package thro.api

import java.sql.Connection
import java.time.Instant
import java.util.UUID
import thro.authz.ObjectRef
import thro.authz.ObjectType
import thro.engine.Command
import thro.engine.Engine
import thro.engine.MatchState
import thro.engine.Outcome
import thro.engine.PlayerId

/**
 * Correcting a recorded visit — the flow the approved organiser dispute screen draws.
 *
 * Two things make this different from every other write in the system.
 *
 * First, it is the one action the conflict-of-interest rule exists for. In darts the same people
 * organise and play, so an official correcting a match they are themselves competing in is the
 * ordinary case, not a hypothetical.
 *
 * Second, **a correction never edits the original.** It appends a new event that supersedes it, so
 * the log still shows what was recorded, what it was changed to, by whom, and under what authority.
 * A dispute six months later is unanswerable if the disputed value was overwritten.
 *
 * Third, **a correction is played before it is kept.** An official's authority is to say what was
 * thrown, not to say something that cannot have been: the visit's stream is replayed through the engine
 * with the correction in its place, and a correction the engine refuses — or one that would leave a
 * later visit impossible — is refused in a sentence. The effect stored is the one the engine gave it.
 */
public class Corrections(private val connection: Connection) {

    public sealed interface Result {
        public data class Corrected(val correctionEventId: UUID, val supersedes: UUID) : Result
        public data class Refused(val why: String, val excludedBy: String? = null) : Result
    }

    public fun correctVisit(
        matchId: UUID,
        eventId: UUID,
        officialId: UUID,
        newTotal: Int,
        deviceId: UUID,
        deviceSeq: Long,
        correlationId: UUID = UUID.randomUUID(),
        occurredAt: Instant = Instant.now(),
    ): Result {
        val match = Matches(connection).load(matchId) ?: return Result.Refused("no such match")

        // One central decision point, before the handler does anything. Deny by default, and the
        // decision is recorded whichever way it goes — a refusal is exactly what an investigator
        // needs to see, and a log of grants alone answers only half of ADR-008's question.
        val decision = Relations(connection).decide(
            officialId, "match.correct", ObjectRef(ObjectType.MATCH, matchId.toString()), correlationId,
        )
        if (!decision.allowed) {
            return Result.Refused(
                why = decision.excludedBy?.let {
                    "you are an official here, but you are also playing in this match"
                } ?: "you do not have authority to correct this match",
                excludedBy = decision.excludedBy,
            )
        }

        val original = loadVisit(matchId, eventId)
            ?: return Result.Refused("that visit is not part of this match")
        if (match.idFor(original.player) == null) {
            return Result.Refused("that visit names someone who is not in this match")
        }
        val effect = when (val played = play(match, original, eventId, newTotal)) {
            is Played.Refused -> return Result.Refused(played.why)
            is Played.Stands -> played.effect
        }

        val correctionId = UUID.randomUUID()
        connection.prepareStatement(
            """
            INSERT INTO evidence.event
              (event_id, match_id, device_id, device_seq, event_type, schema_version,
               correlation_id, actor_id, actor_role, occurred_at, occurred_tz, payload,
               corrects_event_id)
            VALUES (?, ?, ?, ?, 'VisitCorrected', 1, ?, ?, 'official', ?::timestamptz, ?, ?::jsonb, ?)
            """.trimIndent(),
        ).use { ps ->
            ps.setObject(1, correctionId)
            ps.setObject(2, matchId)
            ps.setObject(3, deviceId)
            ps.setLong(4, deviceSeq)
            ps.setObject(5, correlationId)
            ps.setObject(6, officialId)
            ps.setString(7, occurredAt.toString())
            ps.setString(8, "Europe/London")
            ps.setString(
                9,
                """{"player":"${original.player}","visitTotal":$newTotal,""" +
                    """"was":${original.visitTotal},"dartsUsed":null,"dartsAtDouble":null,""" +
                    """"effect":"$effect"}""",
            )
            ps.setObject(10, eventId)
            ps.executeUpdate()
        }
        return Result.Corrected(correctionId, eventId)
    }

    /** The visit being corrected, and the device stream it belongs to. */
    private data class RecordedVisit(val player: String, val visitTotal: Int?, val deviceId: UUID)

    private fun loadVisit(matchId: UUID, eventId: UUID): RecordedVisit? {
        connection.prepareStatement(
            """
            SELECT payload->>'player' AS player, (payload->>'visitTotal')::int AS total, device_id
              FROM evidence.event
             WHERE event_id = ? AND match_id = ? AND event_type = 'VisitRecorded'
            """.trimIndent(),
        ).use { ps ->
            ps.setObject(1, eventId)
            ps.setObject(2, matchId)
            ps.executeQuery().use { rs ->
                return if (rs.next()) {
                    RecordedVisit(rs.getString("player"), rs.getObject("total") as Int?, rs.getObject("device_id") as UUID)
                } else {
                    null
                }
            }
        }
    }

    private sealed interface Played {
        class Stands(val effect: String) : Played
        class Refused(val why: String) : Played
    }

    /**
     * Replays the stream [original] belongs to — its device's visits, less any its scorer struck, with every earlier
     * correction in place — twice: as it stands, and with this correction too. The correction has to be a visit the
     * engine accepts from where it was thrown, and every visit that stood before it has to stand after it; a
     * correction that turned a later checkout into a turn out of order is not a correction of one visit, it is a
     * rewrite of the leg.
     */
    private fun play(match: MatchAggregate, original: RecordedVisit, eventId: UUID, newTotal: Int): Played {
        class Visit(val id: UUID, val command: Command)
        val corrected = HashMap<UUID, Command>()
        connection.prepareStatement(
            """
            SELECT corrects_event_id, payload::text FROM evidence.event
             WHERE match_id = ? AND event_type = 'VisitCorrected' AND corrects_event_id IS NOT NULL
             ORDER BY commit_xid, global_seq
            """.trimIndent(),
        ).use { ps ->
            ps.setObject(1, match.matchId)
            ps.executeQuery().use { rs ->
                // The latest correction of a visit is the one that stands.
                while (rs.next()) Visits.commandOf(rs.getString(2))?.let { corrected[rs.getObject(1) as UUID] = it }
            }
        }
        val struck = HashSet<UUID>()
        val stream = mutableListOf<Visit>()
        connection.prepareStatement(
            """
            SELECT event_id, event_type, payload::text, corrects_event_id FROM evidence.event
             WHERE match_id = ? AND device_id = ? AND event_type IN ('VisitRecorded', 'VisitRetracted')
             ORDER BY device_seq
            """.trimIndent(),
        ).use { ps ->
            ps.setObject(1, match.matchId)
            ps.setObject(2, original.deviceId)
            ps.executeQuery().use { rs ->
                while (rs.next()) {
                    val id = rs.getObject(1) as UUID
                    if (rs.getString(2) == "VisitRetracted") {
                        (rs.getObject(4) as UUID?)?.let(struck::add)
                    } else {
                        Visits.commandOf(rs.getString(3))?.let { stream += Visit(id, it) }
                    }
                }
            }
        }
        if (eventId in struck) {
            return Played.Refused("that visit was struck by its scorer, so it is not part of the record to correct")
        }
        val standing = stream.filter { it.id !in struck }

        fun replay(swap: Map<UUID, Command>): Map<UUID, Outcome> {
            var state = MatchState.start(match.format, Seat.home, Seat.away)
            val out = LinkedHashMap<UUID, Outcome>()
            for (v in standing) {
                val outcome = Engine.apply(state, swap[v.id] ?: v.command)
                if (outcome is Outcome.Accepted) state = outcome.state
                out[v.id] = outcome
            }
            return out
        }
        val correction = Command.RecordVisit(PlayerId(original.player), newTotal)
        val before = replay(corrected)
        val after = replay(corrected + (eventId to correction))

        when (val mine = after[eventId]) {
            is Outcome.Rejected -> return Played.Refused("that correction cannot stand: ${Visits.sentence(mine.reason, correction)}")
            is Outcome.Accepted -> {
                for ((id, was) in before) {
                    val now = after[id]
                    if (was is Outcome.Accepted && now is Outcome.Rejected) {
                        val later = standing.first { it.id == id }.command
                        return Played.Refused(
                            "that correction would leave a later visit (${Visits.describe(later)}) impossible: " +
                                Visits.sentence(now.reason, later),
                        )
                    }
                }
                return Played.Stands(Visits.effectName(mine.effect))
            }
            null -> return Played.Refused("that visit is not part of this match")
        }
    }
}
