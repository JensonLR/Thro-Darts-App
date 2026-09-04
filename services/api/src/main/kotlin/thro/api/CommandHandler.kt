package thro.api

import java.sql.Connection
import java.util.UUID
import thro.engine.Command
import thro.engine.Effect
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
    val visitTotal: Int,
    val dartsUsed: Int?,
    /** Darts thrown at a double. Recorded on every visit that began on a finish, not only one that
     *  ended in one — see PD-001. Null means unknown, never zero. */
    val dartsAtDouble: Int? = null,
    val occurredAt: String,
    val occurredTz: String,
    /** What the client's engine computed. Cross-checked, never trusted. */
    val clientEffect: String? = null,
    val engineVersion: String = "unknown",
)

public sealed interface CommandResult {
    public data class Applied(val effect: String, val reason: String?, val deviceSeq: Long) : CommandResult
    public data class Refused(val reason: String) : CommandResult
    /** A replay. The stored response is returned verbatim, including a stored refusal. */
    public data class Replayed(val stored: String) : CommandResult
    public data class Gap(val expectedSeq: Long) : CommandResult
}

/**
 * Fixed for now; a real deployment pins the ruleset onto the match when it is opened.
 *
 * Defined once and shared with the statistics projection: a projection that replayed the log under
 * a different format would derive different remainings from the same events, and the figures would
 * disagree with the scoreboard that produced them.
 */
internal fun playtestFormat(home: PlayerId): MatchFormat = MatchFormat(
    startingScore = 501,
    inRule = InRule.STRAIGHT,
    outRule = OutRule.DOUBLE,
    legs = Structure(StructureMode.FIRST_TO, 5),
    throwFirst = home,
)

public class CommandHandler(private val connection: Connection) {

    private fun formatFor(home: PlayerId): MatchFormat = playtestFormat(home)

    public fun handle(cmd: VisitCommand, home: String, away: String): CommandResult {
        val previousAutoCommit = connection.autoCommit
        connection.autoCommit = false
        try {
            // 1. Idempotency first. A replay must never re-apply, and must return what it returned
            //    the first time — including a refusal.
            storedReceipt(cmd)?.let {
                connection.commit()
                return CommandResult.Replayed(it)
            }

            // 2. Gapless per-device sequence. A gap means the device is missing events, so the
            //    server refuses rather than applying past it and silently reordering evidence.
            val expected = nextSeqFor(cmd.matchId, cmd.deviceId)
            if (cmd.deviceSeq != expected) {
                connection.commit()
                return CommandResult.Gap(expected)
            }

            // 3. Rehydrate from the server's own log. The client's view is not consulted.
            val state = rehydrate(cmd.matchId, cmd.deviceId, PlayerId(home), PlayerId(away))

            // 4. Revalidate through the same engine the client ran.
            val outcome = Engine.apply(
                state,
                Command.RecordVisit(
                    PlayerId(cmd.player), cmd.visitTotal, cmd.dartsUsed, cmd.dartsAtDouble,
                ),
            )

            val result = when (outcome) {
                is Outcome.Rejected -> CommandResult.Refused(outcome.reason.name)
                is Outcome.Accepted -> CommandResult.Applied(
                    effect = effectName(outcome.effect),
                    reason = outcome.bustReason?.name,
                    deviceSeq = cmd.deviceSeq,
                )
            }

            // 5. A refusal is recorded as a receipt but produces no evidence: it did not happen.
            if (result is CommandResult.Applied) {
                appendEvent(cmd, result)
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
    public fun replayFor(matchId: UUID, deviceId: UUID, home: String, away: String): MatchState =
        rehydrate(matchId, deviceId, PlayerId(home), PlayerId(away))

    /**
     * Rehydrates by folding this device's own stream. Each device's account is separate — the
     * difference between two accounts of one match is the signal a dispute is built on, so they are
     * never merged here.
     */
    private fun rehydrate(matchId: UUID, deviceId: UUID, home: PlayerId, away: PlayerId): MatchState {
        var state = MatchState.start(formatFor(home), home, away)
        connection.prepareStatement(
            """
            SELECT payload->>'player' AS player,
                   (payload->>'visitTotal')::int AS visit_total,
                   payload->>'dartsUsed' AS darts_used,
                   payload->>'dartsAtDouble' AS darts_at_double
            FROM evidence.event
            WHERE match_id = ? AND device_id = ? AND event_type = 'VisitRecorded'
            ORDER BY device_seq
            """.trimIndent(),
        ).use { ps ->
            ps.setObject(1, matchId)
            ps.setObject(2, deviceId)
            ps.executeQuery().use { rs ->
                while (rs.next()) {
                    val outcome = Engine.apply(
                        state,
                        Command.RecordVisit(
                            PlayerId(rs.getString("player")),
                            rs.getInt("visit_total"),
                            rs.getString("darts_used")?.toIntOrNull(),
                            rs.getString("darts_at_double")?.toIntOrNull(),
                        ),
                    )
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

    private fun appendEvent(cmd: VisitCommand, applied: CommandResult.Applied) {
        val payload = buildString {
            append("{")
            append("\"player\":\"").append(cmd.player).append("\",")
            append("\"visitTotal\":").append(cmd.visitTotal).append(",")
            append("\"dartsUsed\":").append(cmd.dartsUsed?.toString() ?: "null").append(",")
            append("\"dartsAtDouble\":").append(cmd.dartsAtDouble?.toString() ?: "null").append(",")
            append("\"effect\":\"").append(applied.effect).append("\"")
            append("}")
        }
        connection.prepareStatement(
            """
            INSERT INTO evidence.event
              (event_id, match_id, device_id, device_seq, event_type, schema_version,
               engine_version, correlation_id, actor_id, actor_role, occurred_at, occurred_tz, payload)
            VALUES (?, ?, ?, ?, 'VisitRecorded', 1, ?, ?, ?, ?, ?::timestamptz, ?, ?::jsonb)
            """.trimIndent(),
        ).use { ps ->
            ps.setObject(1, UUID.randomUUID())
            ps.setObject(2, cmd.matchId)
            ps.setObject(3, cmd.deviceId)
            ps.setLong(4, cmd.deviceSeq)
            ps.setString(5, cmd.engineVersion)
            ps.setObject(6, cmd.correlationId)
            ps.setObject(7, cmd.actorId)
            ps.setString(8, cmd.actorRole)
            ps.setString(9, cmd.occurredAt)
            ps.setString(10, cmd.occurredTz)
            ps.setString(11, payload)
            ps.executeUpdate()
        }
    }

    private fun writeReceipt(cmd: VisitCommand, result: CommandResult) {
        val (outcome, reason, body) = when (result) {
            is CommandResult.Applied ->
                Triple("accepted", result.reason,
                    "{\"effect\":\"${result.effect}\",\"deviceSeq\":${result.deviceSeq}}")
            is CommandResult.Refused -> Triple("rejected", result.reason, "{\"reason\":\"${result.reason}\"}")
            else -> Triple("rejected", "UNEXPECTED", "{}")
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

    private fun effectName(e: Effect): String = when (e) {
        Effect.SCORED -> "scored"
        Effect.BUST -> "bust"
        Effect.LEG_WON -> "leg_won"
        Effect.SET_WON -> "set_won"
        Effect.MATCH_WON -> "match_won"
    }
}
