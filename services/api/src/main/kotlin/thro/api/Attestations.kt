package thro.api

import java.sql.Connection
import java.time.Instant
import java.util.UUID
import thro.trust.Attestation
import thro.trust.CaptureChannel
import thro.trust.Confirmation
import thro.trust.OutcomeType
import thro.trust.Provenance
import thro.trust.eligibilityOf

/**
 * Per-leg participant attestation — ADR-006's third scoring-authority mechanism, and the thing
 * PD-002 depends on.
 *
 * A single writer is not enough on its own, because the approved dispute screen shows a per-leg
 * `Confirmed` column authored by the participant who scored nothing. This is what that column
 * reads from, and it is what raises a result from self-reported to participant-confirmed.
 *
 * Attestations are `trust`'s stream, not `match`'s. The database enforces that: appending a
 * `LegAttested` event as the match role is refused, so the match module cannot confirm a result on
 * a participant's behalf.
 */
public class Attestations(private val connection: Connection) {

    public sealed interface Result {
        public data class Recorded(val legOrdinal: Int, val attested: Boolean) : Result
        public data class Refused(val why: String) : Result
    }

    /**
     * Records one participant's confirmation, or refusal, of one leg.
     *
     * The attesting player must be in the match — the same store-backed check that closes
     * cross-match injection — because an attestation from an outsider is not weak evidence, it is
     * evidence of nothing.
     */
    public fun attest(
        matchId: UUID,
        legOrdinal: Int,
        participantId: UUID,
        attested: Boolean,
        deviceId: UUID,
        deviceSeq: Long,
        occurredAt: Instant = Instant.now(),
    ): Result {
        val match = Matches(connection).load(matchId) ?: return Result.Refused("no such match")
        if (participantId !in match.participants) {
            return Result.Refused("that player is not in this match")
        }
        val eventId = UUID.randomUUID()
        connection.prepareStatement(
            """
            INSERT INTO evidence.event
              (event_id, match_id, device_id, device_seq, event_type, schema_version,
               correlation_id, actor_id, actor_role, occurred_at, occurred_tz, payload)
            VALUES (?, ?, ?, ?, 'LegAttested', 1, ?, ?, 'participant', ?::timestamptz, ?, ?::jsonb)
            """.trimIndent(),
        ).use { ps ->
            ps.setObject(1, eventId)
            ps.setObject(2, matchId)
            ps.setObject(3, deviceId)
            ps.setLong(4, deviceSeq)
            ps.setObject(5, UUID.randomUUID())
            ps.setObject(6, participantId)
            ps.setString(7, occurredAt.toString())
            ps.setString(8, "Europe/London")
            ps.setString(9, """{"legOrdinal":$legOrdinal,"attested":$attested}""")
            ps.executeUpdate()
        }
        connection.prepareStatement(
            """
            INSERT INTO trust.leg_attestation
              (leg_id, match_id, participant_id, attested, event_id, attested_at)
            VALUES (?, ?, ?, ?, ?, ?::timestamptz)
            ON CONFLICT (leg_id, participant_id) DO NOTHING
            """.trimIndent(),
        ).use { ps ->
            // A leg is identified within its match; the projection keys on it.
            ps.setObject(1, legIdFor(matchId, legOrdinal))
            ps.setObject(2, matchId)
            ps.setObject(3, participantId)
            ps.setBoolean(4, attested)
            ps.setObject(5, eventId)
            ps.setString(6, occurredAt.toString())
            ps.executeUpdate()
        }
        return Result.Recorded(legOrdinal, attested)
    }

    /** Deterministic, so the same leg always projects to the same row rather than accumulating. */
    private fun legIdFor(matchId: UUID, legOrdinal: Int): UUID =
        UUID.nameUUIDFromBytes("$matchId:$legOrdinal".toByteArray())

    /**
     * Assembles the match's provenance from the log.
     *
     * Derived, never stored: a stored trust label can disagree with the evidence under it. The
     * verification label and the eligibility answer both fall out of this.
     */
    public fun provenanceOf(matchId: UUID, outcome: OutcomeType = OutcomeType.PLAYED): Provenance? {
        val match = Matches(connection).load(matchId) ?: return null
        val confirmations = mutableListOf<Confirmation>()
        connection.prepareStatement(
            """
            SELECT participant_id, attested, attested_at FROM trust.leg_attestation
             WHERE match_id = ? AND attested
            """.trimIndent(),
        ).use { ps ->
            ps.setObject(1, matchId)
            ps.executeQuery().use { rs ->
                while (rs.next()) {
                    confirmations += Confirmation(
                        actorId = rs.getObject("participant_id") as UUID,
                        at = rs.getTimestamp("attested_at").toInstant(),
                    )
                }
            }
        }
        val legsPlayed = legsIn(matchId)
        // A participant has confirmed the MATCH only when they have confirmed every leg of it.
        // Confirming one leg of a nine-leg match is not agreement about the result.
        val complete = confirmations.groupBy { it.actorId }
            .filterValues { it.size >= legsPlayed && legsPlayed > 0 }
            .map { (actor, list) -> Confirmation(actor, list.maxOf { it.at }) }

        return Provenance(
            matchId = matchId,
            outcomeType = outcome,
            captureChannel = CaptureChannel.THRO_LIVE,
            enteredBy = match.homeId,
            participants = match.participants,
            confirmations = complete,
        )
    }

    private fun legsIn(matchId: UUID): Int {
        connection.prepareStatement(
            """
            SELECT count(*) FROM evidence.event
             WHERE match_id = ? AND event_type = 'VisitRecorded'
               AND payload->>'effect' IN ('leg_won','set_won','match_won')
            """.trimIndent(),
        ).use { ps ->
            ps.setObject(1, matchId)
            ps.executeQuery().use { rs -> rs.next(); return rs.getInt(1) }
        }
    }

    /** Whether this match may inform a rating, and why not when it may not. */
    public fun eligibility(matchId: UUID, opponentIsEstablished: Boolean = true): String {
        val p = provenanceOf(matchId) ?: return """{"error":"no such match"}"""
        val e = eligibilityOf(p, opponentIsEstablished)
        val label = thro.trust.VerificationState.of(p)
        return """{"attestation":"${p.attestation.name}","verification":"${label.name}",""" +
            """"verificationLabel":${quoteJson(label.label)},""" +
            """"eligible":${e.eligible},"qualifying":${e.qualifying},""" +
            """"reasons":[${e.reasons.joinToString(",") { "\"${it.name}\"" }}]}"""
    }

    private fun quoteJson(s: String): String =
        "\"" + s.replace("\\", "\\\\").replace("\"", "\\\"") + "\""
}
