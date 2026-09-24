package thro.api

import java.sql.Connection
import java.time.Instant
import java.util.UUID
import thro.engine.Command
import thro.engine.Dart
import thro.engine.Engine
import thro.engine.InRule
import thro.engine.MatchFormat
import thro.engine.MatchState
import thro.engine.OutRule
import thro.engine.Outcome
import thro.engine.PlayerId
import thro.engine.Structure
import thro.engine.StructureMode

/**
 * The command handler: the one path by which competitive evidence enters the system.
 *
 * Everything the architecture claims about integrity converges here. The client's assertion of an
 * outcome is never trusted — the server rehydrates the match from its own event log, revalidates
 * through the same engine the client ran, and appends **its** result. The command receipt is
 * written in the same transaction as the event, because a crash between two transactions would
 * either double-apply a visit or lose the receipt, and both corrupt a match.
 */
public data class VisitCommand(
    val commandId: UUID,
    val matchId: UUID,
    val deviceId: UUID,
    val deviceSeq: Long,
    val actorId: UUID,
    val actorRole: String,
    val correlationId: UUID,
    val player: String,
    /** The visit's total. Null only on a visit given as [darts], whose total the engine derives. */
    val visitTotal: Int?,
    val dartsUsed: Int?,
    /** Darts thrown at a double. Recorded on every visit that began on a finish, not only one that
     *  ended in one — see PD-001. Null means unknown, never zero. */
    val dartsAtDouble: Int? = null,
    val occurredAt: String,
    val occurredTz: String,
    /** What the client's engine computed. Cross-checked, never trusted. */
    val clientEffect: String? = null,
    val engineVersion: String = "unknown",
    /**
     * The darts thrown, in order (OD-023). When present the visit is a `RecordDarts` and [visitTotal], [dartsUsed]
     * and [dartsAtDouble] are not read: the engine derives every one of them from the darts, so a client cannot
     * send a total that contradicts its own darts.
     */
    val darts: List<Dart>? = null,
) {
    /** The engine command this is. */
    public fun command(): Command = if (darts != null) {
        Command.RecordDarts(PlayerId(player), darts)
    } else {
        Command.RecordVisit(
            PlayerId(player),
            requireNotNull(visitTotal) { "a visit is recorded as a total or as its darts, and this was neither" },
            dartsUsed, dartsAtDouble,
        )
    }
}

public sealed interface CommandResult {
    public data class Applied(val effect: String, val reason: String?, val deviceSeq: Long) : CommandResult
    public data class Refused(val reason: String) : CommandResult
    /** A replay. The stored response is returned verbatim, including a stored refusal. */
    public data class Replayed(val stored: String) : CommandResult
    public data class Gap(val expectedSeq: Long) : CommandResult

    /** The match does not exist, or the command names someone who is not playing in it. */
    public data class NotThisMatch(val reason: String) : CommandResult
}

/**
 * Fixed for now; a real deployment pins the ruleset onto the match when it is opened.
 *
 * Defined once and shared with the statistics projection: a projection that replayed the log under
 * a different format would derive different remainings from the same events, and the figures would
 * disagree with the scoreboard that produced them.
 */
public fun playtestFormat(home: PlayerId = Seat.home): MatchFormat = MatchFormat(
    startingScore = 501,
    inRule = InRule.STRAIGHT,
    outRule = OutRule.DOUBLE,
    legs = Structure(StructureMode.FIRST_TO, 5),
    throwFirst = home,
)

public class CommandHandler(private val connection: Connection) {

    /** Kept for callers that still pass labels; the participant set comes from the store. */
    public fun handle(cmd: VisitCommand, home: String, away: String): CommandResult = handle(cmd)

    /**
     * ADR-006's server algorithm, with ADR-008's participant check ahead of it.
     *
     * Nothing about who is playing is taken from the caller. The highest-value attack in the
     * product is posting an event that carries a stranger's match id, and the only defence that
     * actually works is loading the aggregate and asking it.
     */
    public fun handle(cmd: VisitCommand): CommandResult {
        val previousAutoCommit = connection.autoCommit
        connection.autoCommit = false
        try {
            // 1. Idempotency first. A replay must never re-apply, and must return what it returned
            //    the first time — including a refusal.
            storedReceipt(cmd)?.let {
                connection.commit()
                return CommandResult.Replayed(it)
            }

            // 1b. The aggregate decides who is playing. A command naming anyone else is not a
            //     rules violation to be recorded — it is evidence aimed at a match its author is
            //     not in, so it produces no evidence at all.
            val match = Matches(connection).load(cmd.matchId)
            if (match == null) {
                val r = CommandResult.NotThisMatch("no such match")
                writeReceipt(cmd, r)
                connection.commit()
                return r
            }
            if (match.idFor(cmd.player) == null) {
                val r = CommandResult.NotThisMatch("that is not a seat in this match")
                writeReceipt(cmd, r)
                connection.commit()
                return r
            }

            // 2. Authority (ADR-006 step 2). This ANNOTATES the evidence; it never gates it. A
            //    revoked or expired grant still records — evidence is not destroyed for an
            //    authorization reason, because the dispute that needs it is the one in which
            //    someone's authority was contested. Unsound authority is routed to review instead.
            val (authority, grantId) = Grants(connection).authorityFor(
                cmd.matchId, cmd.actorId, cmd.deviceId, Instant.parse(cmd.occurredAt),
            )

            // 2b. But an author who is neither in the match nor was ever granted anything for it
            //     is not a scorer whose authority lapsed — they are a stranger, and this is the
            //     cross-match injection ADR-008 names as the highest-value attack. Refused before
            //     any evidence exists, and receipted so a retry is answered the same way. (Hostile
            //     review of the HTTP layer found the seat check alone let a stranger through.)
            if (cmd.actorId !in match.participants && authority == Authority.UNGRANTED) {
                val r = CommandResult.NotThisMatch("you are not in this match and hold no grant for it")
                writeReceipt(cmd, r)
                connection.commit()
                return r
            }

            // 3. Gapless per-device sequence. A gap means the device is missing events, so the
            //    server refuses rather than applying past it and silently reordering evidence.
            val expected = nextSeqFor(cmd.matchId, cmd.deviceId)
            if (cmd.deviceSeq != expected) {
                connection.commit()
                return CommandResult.Gap(expected)
            }

            // 4. Rehydrate from the server's own log. The client's view is not consulted.
            val state = rehydrate(cmd.matchId, cmd.deviceId, match)

            // 5. Revalidate through the same engine the client ran. A visit given as darts is
            //    revalidated as darts: the engine decides what they scored, where they bust and how
            //    many were thrown at a double, and that is what is stored.
            val command = cmd.command()
            val outcome = Engine.apply(state, command)

            val result = when (outcome) {
                is Outcome.Rejected -> CommandResult.Refused(outcome.reason.name)
                is Outcome.Accepted -> CommandResult.Applied(
                    effect = Visits.effectName(outcome.effect),
                    reason = outcome.bustReason?.name,
                    deviceSeq = cmd.deviceSeq,
                )
            }

            // 6. A refusal is recorded as a receipt but produces no evidence: it did not happen.
            if (result is CommandResult.Applied) {
                appendEvent(cmd, command, (outcome as Outcome.Accepted).reading, result, authority, grantId)
            }
            writeReceipt(cmd, result)
            connection.commit()
            return result
        } catch (e: Exception) {
            connection.rollback()
            throw e
        } finally {
            connection.autoCommit = previousAutoCommit
        }
    }

    /** Read-only replay, for surfaces that need current state without submitting a command. */
    public fun replayFor(matchId: UUID, deviceId: UUID): MatchState =
        rehydrate(matchId, deviceId, requireNotNull(Matches(connection).load(matchId)) { "no such match" })

    /** Kept for callers that still pass labels; the seats come from the aggregate. */
    public fun replayFor(matchId: UUID, deviceId: UUID, home: String, away: String): MatchState = replayFor(matchId, deviceId)

    /**
     * Rehydrates by folding this device's own stream. Each device's account is separate — the
     * difference between two accounts of one match is the signal a dispute is built on, so they are
     * never merged here.
     */
    private fun rehydrate(matchId: UUID, deviceId: UUID, match: MatchAggregate): MatchState {
        var state = MatchState.start(match.format, Seat.home, Seat.away)
        connection.prepareStatement(
            """
            SELECT payload::text
            FROM evidence.event
            WHERE match_id = ? AND device_id = ? AND event_type = 'VisitRecorded'
            ORDER BY device_seq
            """.trimIndent(),
        ).use { ps ->
            ps.setObject(1, matchId)
            ps.setObject(2, deviceId)
            ps.executeQuery().use { rs ->
                while (rs.next()) {
                    // Each visit replays as what it was entered as — its darts, or its total — because
                    // under the keep rule, or a dart that reaches zero on a treble, the two differ.
                    val visit = Visits.commandOf(rs.getString(1)) ?: continue
                    val outcome = Engine.apply(state, visit)
                    if (outcome is Outcome.Accepted) state = outcome.state
                }
            }
        }
        return state
    }

    private fun nextSeqFor(matchId: UUID, deviceId: UUID): Long {
        connection.prepareStatement(
            "SELECT coalesce(max(device_seq), 0) + 1 FROM evidence.event WHERE match_id = ? AND device_id = ?",
        ).use { ps ->
            ps.setObject(1, matchId)
            ps.setObject(2, deviceId)
            ps.executeQuery().use { rs -> rs.next(); return rs.getLong(1) }
        }
    }

    private fun storedReceipt(cmd: VisitCommand): String? {
        connection.prepareStatement(
            "SELECT response_body::text FROM evidence.command_receipt WHERE device_id = ? AND client_command_id = ?",
        ).use { ps ->
            ps.setObject(1, cmd.deviceId)
            ps.setObject(2, cmd.commandId)
            ps.executeQuery().use { rs -> return if (rs.next()) rs.getString(1) else null }
        }
    }

    private fun appendEvent(
        cmd: VisitCommand,
        command: Command,
        reading: thro.engine.VisitReading?,
        applied: CommandResult.Applied,
        authority: Authority,
        grantId: UUID?,
    ) {
        // A darts visit keeps its darts, and beside them what the engine derived, so a reader that
        // knows only totals still reads it (schema 2). A total is stored exactly as it always was.
        val payload = Visits.payload(cmd.player, command, reading, applied.effect)
        connection.prepareStatement(
            """
            INSERT INTO evidence.event
              (event_id, match_id, device_id, device_seq, event_type, schema_version,
               engine_version, correlation_id, actor_id, actor_role, occurred_at, occurred_tz,
               payload, authority, grant_id)
            VALUES (?, ?, ?, ?, 'VisitRecorded', ?, ?, ?, ?, ?, ?::timestamptz, ?, ?::jsonb, ?, ?)
            """.trimIndent(),
        ).use { ps ->
            ps.setObject(1, UUID.randomUUID())
            ps.setObject(2, cmd.matchId)
            ps.setObject(3, cmd.deviceId)
            ps.setLong(4, cmd.deviceSeq)
            ps.setInt(5, Visits.schemaOf(command))
            ps.setString(6, cmd.engineVersion)
            ps.setObject(7, cmd.correlationId)
            ps.setObject(8, cmd.actorId)
            ps.setString(9, cmd.actorRole)
            ps.setString(10, cmd.occurredAt)
            ps.setString(11, cmd.occurredTz)
            ps.setString(12, payload)
            ps.setString(13, authority.name.lowercase())
            ps.setObject(14, grantId)
            ps.executeUpdate()
        }
    }

    private fun writeReceipt(cmd: VisitCommand, result: CommandResult) {
        // The stored body names its outcome, so a replay can be answered — over HTTP, with its
        // status — exactly as the first answer was.
        fun j(s: String?): String = if (s == null) "null" else "\"" + s.replace("\\", "\\\\").replace("\"", "\\\"") + "\""
        val (outcome, reason, body) = when (result) {
            is CommandResult.Applied ->
                Triple("accepted", result.reason,
                    "{\"outcome\":\"applied\",\"effect\":${j(result.effect)},\"reason\":${j(result.reason)},\"deviceSeq\":${result.deviceSeq}}")
            is CommandResult.Refused -> Triple("rejected", result.reason, "{\"outcome\":\"refused\",\"why\":${j(result.reason)}}")
            is CommandResult.NotThisMatch ->
                Triple("rejected", "NOT_THIS_MATCH", "{\"outcome\":\"not_this_match\",\"why\":${j(result.reason)}}")
            else -> Triple("rejected", "UNEXPECTED", "{\"outcome\":\"refused\",\"why\":\"unexpected\"}")
        }
        connection.prepareStatement(
            """
            INSERT INTO evidence.command_receipt
              (device_id, client_command_id, match_id, outcome, reason_code, response_body)
            VALUES (?, ?, ?, ?, ?, ?::jsonb)
            """.trimIndent(),
        ).use { ps ->
            ps.setObject(1, cmd.deviceId)
            ps.setObject(2, cmd.commandId)
            ps.setObject(3, cmd.matchId)
            ps.setString(4, outcome)
            ps.setString(5, reason)
            ps.setString(6, body)
            ps.executeUpdate()
        }
    }
}
