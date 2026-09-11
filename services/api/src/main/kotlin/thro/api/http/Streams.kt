package thro.api.http

import io.ktor.http.ContentType
import io.ktor.http.HttpStatusCode
import io.ktor.server.response.respondBytesWriter
import io.ktor.server.response.respondText
import io.ktor.server.routing.Route
import io.ktor.server.routing.get
import io.ktor.utils.io.writeStringUtf8
import java.sql.Connection
import java.time.Duration
import java.util.UUID
import kotlinx.coroutines.delay
import kotlinx.coroutines.withTimeoutOrNull
import thro.api.Grants
import thro.api.MatchRecords
import thro.api.Matches
import thro.api.Relations
import thro.authz.ObjectRef
import thro.authz.ObjectType

/**
 * `match:{id}` (ADR-007), the first stream. Every event of a match in commit order, then each new
 * one as it commits, over server-sent events.
 *
 * Three things the record fixes and this keeps:
 *  - **Replay, not hope.** The event id is `match:{id}:{commitXid}-{globalSeq}`; a client that
 *    reconnects with `Last-Event-ID` gets everything after it from the log. Order is the pair
 *    `(commit_xid, global_seq)` the schema indexes, never `global_seq` alone, and a row is only
 *    served once every transaction older than it has finished (`commit_xid` below the snapshot's
 *    `xmin`), so a reader above a high-water mark cannot skip a row that committed late.
 *  - **Heartbeat.** A comment every fifteen seconds; the client's own clock decides staleness.
 *  - **A slow consumer never slows a writer.** The stream reads the log; it holds no lock and no
 *    queue a writer could fill. It is woken when an event for its match commits (V036, through
 *    [MatchNotifier]) and still polls the log, because the notification is a hint to re-read and
 *    never the transport of truth.
 *
 * Every event carries its own `eventId`, so a correction's `correctsEventId` names a row the reader
 * already holds — without it, a watcher could not tell which visit a retraction struck.
 *
 * Who may watch: the match's participants — including a player who took their seat with a code
 * (PD-043) — the holder of a scoring grant IN FORCE for it, and
 * officials of its event — asked again once a minute while the stream is open, so a grant revoked or
 * a session ended closes the door on a watcher already inside (ADR-007: re-authorise). There is no
 * spectator stream yet, so nothing here is filtered for a least-privileged reader.
 */
internal object MatchStream {

    /** A position in the log: the pair the schema orders by. */
    data class Position(val commitXid: Long, val seq: Long) {
        fun id(matchId: UUID): String = "match:$matchId:$commitXid-$seq"
        companion object {
            fun parse(lastEventId: String?, matchId: UUID): Position? {
                val prefix = "match:$matchId:"
                val tail = lastEventId?.takeIf { it.startsWith(prefix) }?.removePrefix(prefix) ?: return null
                val (x, s) = tail.split("-").takeIf { it.size == 2 } ?: return null
                return Position(x.toLongOrNull() ?: return null, s.toLongOrNull() ?: return null)
            }
        }
    }

    class Event(val position: Position, val type: String, val json: String)

    /** How often an open stream asks again whether its watcher may still watch. */
    val reauthoriseEvery: Duration = Duration.ofSeconds(60)

    /** Committed events after [after], oldest first, only from transactions every older one has finished. */
    fun after(c: Connection, matchId: UUID, after: Position?, limit: Int = 500): List<Event> {
        val out = mutableListOf<Event>()
        c.prepareStatement(
            """
            SELECT commit_xid::text::bigint, global_seq, event_type,
                   jsonb_build_object('eventId', event_id, 'deviceId', device_id, 'deviceSeq', device_seq, 'type', event_type,
                                      'occurredAt', occurred_at, 'actorRole', actor_role, 'correctsEventId', corrects_event_id,
                                      'payload', payload)::text
              FROM evidence.event
             WHERE match_id = ?
               AND commit_xid < pg_snapshot_xmin(pg_current_snapshot())
               AND (commit_xid::text::bigint, global_seq) > (?, ?)
             ORDER BY commit_xid, global_seq
             LIMIT ?
            """.trimIndent(),
        ).use { ps ->
            ps.setObject(1, matchId); ps.setLong(2, after?.commitXid ?: 0); ps.setLong(3, after?.seq ?: 0); ps.setInt(4, limit)
            ps.executeQuery().use { rs -> while (rs.next()) out += Event(Position(rs.getLong(1), rs.getLong(2)), rs.getString(3), rs.getString(4)) }
        }
        return out
    }

    /**
     * Whether [principal] may watch [matchId] now: a participant, the holder of a grant in force, or an
     * official of its event. A grant counts only while it is in force and only on its own event's
     * matches (`Grants.liveRoleFor`); asking what was ever issued let a revoked scorer in.
     */
    fun mayWatch(c: Connection, principal: Principal, matchId: UUID, deviceId: UUID?): Boolean {
        val match = Matches(c).load(matchId) ?: return false
        if (principal.subject in match.participants) return true
        // A player who took their seat with a code (PD-043) is one of the two, and follows the match
        // as one: the match still names the competitor it was sent with, so the claim is asked too.
        if (MatchRecords(c).seatOf(matchId, principal.subject) != null) return true
        if (deviceId != null && Grants(c).liveRoleFor(principal.subject, deviceId, matchId) != null) return true
        return Relations(c).decide(principal.subject, "match.adjudicate", ObjectRef(ObjectType.MATCH, matchId.toString())).allowed
    }
}

/**
 * Mounts the match stream on a plain route, writing the frames itself rather than through the SSE
 * helper: the helper answers 200 before the handler runs, and a stream must be able to say 401,
 * 403 or 404 before it says anything else.
 */
internal fun Route.matchStream(path: String, deps: Deps, notifier: MatchNotifier? = null) {
    get(path) {
        val matchId = call.parameters["matchId"]?.let { runCatching { UUID.fromString(it) }.getOrNull() }
            ?: return@get call.respondText("""{"error":"matchId must be a UUID"}""", ContentType.Application.Json, HttpStatusCode.BadRequest)
        val deviceId = call.request.headers["X-Thro-Device"]?.let { runCatching { UUID.fromString(it) }.getOrNull() }
        val lastId: String? = call.request.headers["Last-Event-ID"]
        // The stream holds one connection for its life, narrowed like any request; it is closed
        // when the client goes, whatever happened.
        deps.connect().use { c ->
            fun narrow(role: DbRole) = c.createStatement().use { it.execute("SET ROLE " + role.sql) }

            /**
             * Who is asking. That lives in the identity schema, which the match role cannot read — and
             * the first version stood as the match role and THEN asked the token table, so every
             * signed-in watcher was refused by a grant rather than admitted. Only the development
             * principal, which reads nothing, ever got in, and it was the only one the test used.
             * Identity first, as every other request does; then the match role for what the stream reads.
             */
            fun caller(): Principal? {
                narrow(DbRole.COMPETITION)
                val who = deps.authenticator.authenticate({ name -> call.request.headers[name] }) { c }
                narrow(DbRole.MATCH)
                return who
            }

            val principal = caller()
                ?: return@use call.respondText("""{"error":"no principal"}""", ContentType.Application.Json, HttpStatusCode.Unauthorized)
            Matches(c).load(matchId)
                ?: return@use call.respondText("""{"error":"no such match"}""", ContentType.Application.Json, HttpStatusCode.NotFound)
            if (!MatchStream.mayWatch(c, principal, matchId, deviceId)) {
                return@use call.respondText("""{"error":"not in this match"}""", ContentType.Application.Json, HttpStatusCode.Forbidden)
            }
            var position = MatchStream.Position.parse(lastId, matchId)
            call.response.headers.append("Cache-Control", "no-cache")
            call.response.headers.append("X-Accel-Buffering", "no")
            // Registered before the first read, so an event that commits between that read and the
            // first wait still wakes it: the line is conflated, and holds the wake until it is taken.
            val wake = notifier?.watch(matchId)
            try {
                call.respondBytesWriter(ContentType.Text.EventStream, HttpStatusCode.OK) {
                    suspend fun frame(text: String) { writeStringUtf8(text); flush() }
                    frame("retry: 3000\n: match $matchId; replaying from ${position?.let { "${it.commitXid}-${it.seq}" } ?: "the start"}\n\n")
                    var sinceHeartbeat = Duration.ZERO
                    var sinceCheck = Duration.ZERO
                    while (!isClosedForWrite) {
                        val batch = MatchStream.after(c, matchId, position)
                        for (e in batch) {
                            frame("id: ${e.position.id(matchId)}\nevent: ${e.type}\ndata: ${e.json}\n\n")
                            position = e.position
                            sinceHeartbeat = Duration.ZERO
                        }
                        if (batch.size < 500) {
                            val started = System.nanoTime()
                            if (wake != null) withTimeoutOrNull(deps.streamPoll.toMillis()) { wake.receive() }
                            else delay(deps.streamPoll.toMillis())
                            val waited = Duration.ofNanos(System.nanoTime() - started)
                            sinceHeartbeat = sinceHeartbeat.plus(waited)
                            sinceCheck = sinceCheck.plus(waited)
                            if (sinceHeartbeat >= deps.streamHeartbeat) { frame(": ping\n\n"); sinceHeartbeat = Duration.ZERO }
                            if (sinceCheck >= MatchStream.reauthoriseEvery) {
                                sinceCheck = Duration.ZERO
                                val still = caller()
                                if (still == null || still.subject != principal.subject || !MatchStream.mayWatch(c, still, matchId, deviceId)) {
                                    frame(": no longer allowed to watch this match\n\n")
                                    break
                                }
                            }
                        }
                    }
                }
            } finally {
                if (wake != null) notifier?.unwatch(matchId, wake)
            }
        }
    }
}
