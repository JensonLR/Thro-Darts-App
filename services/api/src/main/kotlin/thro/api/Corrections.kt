package thro.api

import java.sql.Connection
import java.time.Instant
import java.util.UUID
import thro.authz.ObjectRef
import thro.authz.ObjectType

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
                    """"effect":"scored"}""",
            )
            ps.setObject(10, eventId)
            ps.executeUpdate()
        }
        return Result.Corrected(correctionId, eventId)
    }

    private data class RecordedVisit(val player: String, val visitTotal: Int)

    private fun loadVisit(matchId: UUID, eventId: UUID): RecordedVisit? {
        connection.prepareStatement(
            """
            SELECT payload->>'player' AS player, (payload->>'visitTotal')::int AS total
              FROM evidence.event
             WHERE event_id = ? AND match_id = ? AND event_type = 'VisitRecorded'
            """.trimIndent(),
        ).use { ps ->
            ps.setObject(1, eventId)
            ps.setObject(2, matchId)
            ps.executeQuery().use { rs ->
                return if (rs.next()) RecordedVisit(rs.getString("player"), rs.getInt("total")) else null
            }
        }
    }
}
