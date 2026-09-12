package thro.api

import java.sql.Connection
import java.time.Instant
import java.util.UUID
import thro.authz.ObjectRef
import thro.authz.ObjectType

/**
 * Disputes, adjudication and quarantine — trust's stream.
 *
 * A dispute is a participant's assertion that the recorded result is wrong, and it localises to a
 * leg. Adjudication carries the same conflict-of-interest exclusion as correction: an official
 * ruling on a match they are competing in is the same problem wearing a different verb.
 *
 * Nothing here deletes. A resolution is recorded, never applied by overwriting the thing disputed,
 * and a quarantine is lifted rather than removed — that a match was reviewed and cleared is itself
 * worth knowing.
 */
public class Disputes(private val connection: Connection) {

    public sealed interface Result {
        public data class Raised(val disputeId: UUID) : Result
        public data class Resolved(val disputeId: UUID, val resolution: String) : Result
        public data class Quarantined(val quarantineId: UUID) : Result
        public data class Lifted(val quarantineId: UUID) : Result
        public data class Refused(val why: String, val excludedBy: String? = null) : Result
    }

    /** A participant says the recorded result is wrong. Only a participant may. */
    public fun raise(
        matchId: UUID,
        raisedBy: UUID,
        legOrdinal: Int?,
        reason: String,
        deviceId: UUID,
        deviceSeq: Long,
        occurredAt: Instant = Instant.now(),
    ): Result {
        val match = Matches(connection).load(matchId) ?: return Result.Refused("no such match")
        if (raisedBy !in match.participants) {
            return Result.Refused("only a participant can dispute a result")
        }
        val eventId = appendTrustEvent(
            matchId, deviceId, deviceSeq, "DisputeRaised", raisedBy, occurredAt,
            """{"legOrdinal":${legOrdinal ?: "null"},"reason":${json(reason)}}""",
        )
        val id = UUID.randomUUID()
        connection.prepareStatement(
            """
            INSERT INTO trust.dispute
              (dispute_id, match_id, raised_by, leg_ordinal, reason, raised_event)
            VALUES (?, ?, ?, ?, ?, ?)
            """.trimIndent(),
        ).use { ps ->
            ps.setObject(1, id); ps.setObject(2, matchId); ps.setObject(3, raisedBy)
            if (legOrdinal == null) ps.setNull(4, java.sql.Types.INTEGER) else ps.setInt(4, legOrdinal)
            ps.setString(5, reason); ps.setObject(6, eventId)
            ps.executeUpdate()
        }
        return Result.Raised(id)
    }

    /**
     * An official rules on a dispute.
     *
     * Routed through the same decision point as a correction, so the conflict-of-interest exclusion
     * applies without being restated — restating a security rule is how the two copies drift apart.
     */
    public fun adjudicate(
        disputeId: UUID,
        officialId: UUID,
        resolution: String,
        deviceId: UUID,
        deviceSeq: Long,
        occurredAt: Instant = Instant.now(),
    ): Result {
        require(resolution in setOf("upheld", "rejected", "withdrawn")) { "unknown resolution" }
        val matchId = matchOf(disputeId) ?: return Result.Refused("no such dispute")

        val decision = Relations(connection).decide(
            officialId, "match.adjudicate", ObjectRef(ObjectType.MATCH, matchId.toString()),
        )
        if (!decision.allowed) {
            return Result.Refused(
                why = decision.excludedBy?.let {
                    "you are an official here, but you are also playing in this match"
                } ?: "you do not have authority to adjudicate this match",
                excludedBy = decision.excludedBy,
            )
        }

        val eventId = appendTrustEvent(
            matchId, deviceId, deviceSeq, "DisputeResolved", officialId, occurredAt,
            """{"disputeId":"$disputeId","resolution":"$resolution"}""",
        )
        val updated = connection.prepareStatement(
            """
            UPDATE trust.dispute
               SET resolved_at = clock_timestamp(), resolved_by = ?, resolution = ?, resolved_event = ?
             WHERE dispute_id = ? AND resolved_at IS NULL
            """.trimIndent(),
        ).use { ps ->
            ps.setObject(1, officialId); ps.setString(2, resolution)
            ps.setObject(3, eventId); ps.setObject(4, disputeId)
            ps.executeUpdate()
        }
        return if (updated == 1) Result.Resolved(disputeId, resolution)
        else Result.Refused("that dispute is already resolved")
    }

    /**
     * Suspends eligibility pending review, without accusation.
     *
     * A device fault triggers this as readily as fraud, so nothing here implies wrongdoing and
     * nothing is hidden: the result keeps its place in the bracket and its visibility.
     */
    public fun quarantine(
        matchId: UUID,
        appliedBy: UUID,
        reasonCode: String,
        reason: String,
        deviceId: UUID,
        deviceSeq: Long,
        occurredAt: Instant = Instant.now(),
    ): Result {
        Matches(connection).load(matchId) ?: return Result.Refused("no such match")
        val eventId = appendTrustEvent(
            matchId, deviceId, deviceSeq, "Quarantined", appliedBy, occurredAt,
            """{"reasonCode":${json(reasonCode)},"reason":${json(reason)}}""",
        )
        val id = UUID.randomUUID()
        connection.prepareStatement(
            """
            INSERT INTO trust.quarantine
              (quarantine_id, match_id, reason_code, reason, applied_by, applied_event)
            VALUES (?, ?, ?, ?, ?, ?)
            """.trimIndent(),
        ).use { ps ->
            ps.setObject(1, id); ps.setObject(2, matchId); ps.setString(3, reasonCode)
            ps.setString(4, reason); ps.setObject(5, appliedBy); ps.setObject(6, eventId)
            ps.executeUpdate()
        }
        return Result.Quarantined(id)
    }

    public fun lift(
        quarantineId: UUID,
        liftedBy: UUID,
        deviceId: UUID,
        deviceSeq: Long,
        occurredAt: Instant = Instant.now(),
    ): Result {
        val matchId = matchOfQuarantine(quarantineId) ?: return Result.Refused("no such quarantine")
        val eventId = appendTrustEvent(
            matchId, deviceId, deviceSeq, "QuarantineLifted", liftedBy, occurredAt,
            """{"quarantineId":"$quarantineId"}""",
        )
        val updated = connection.prepareStatement(
            """
            UPDATE trust.quarantine
               SET lifted_at = clock_timestamp(), lifted_by = ?, lifted_event = ?
             WHERE quarantine_id = ? AND lifted_at IS NULL
            """.trimIndent(),
        ).use { ps ->
            ps.setObject(1, liftedBy); ps.setObject(2, eventId); ps.setObject(3, quarantineId)
            ps.executeUpdate()
        }
        return if (updated == 1) Result.Lifted(quarantineId)
        else Result.Refused("that quarantine is already lifted")
    }

    public fun openDisputeCount(matchId: UUID): Int = count(
        "SELECT count(*) FROM trust.dispute WHERE match_id = ? AND resolved_at IS NULL", matchId,
    )

    public fun isQuarantined(matchId: UUID): Boolean = count(
        "SELECT count(*) FROM trust.quarantine WHERE match_id = ? AND lifted_at IS NULL", matchId,
    ) > 0

    private fun count(sql: String, matchId: UUID): Int {
        connection.prepareStatement(sql).use { ps ->
            ps.setObject(1, matchId)
            ps.executeQuery().use { rs -> rs.next(); return rs.getInt(1) }
        }
    }

    private fun matchOf(disputeId: UUID): UUID? = lookup(
        "SELECT match_id FROM trust.dispute WHERE dispute_id = ?", disputeId,
    )

    private fun matchOfQuarantine(id: UUID): UUID? = lookup(
        "SELECT match_id FROM trust.quarantine WHERE quarantine_id = ?", id,
    )

    private fun lookup(sql: String, id: UUID): UUID? {
        connection.prepareStatement(sql).use { ps ->
            ps.setObject(1, id)
            ps.executeQuery().use { rs -> return if (rs.next()) rs.getObject(1) as UUID else null }
        }
    }

    private fun appendTrustEvent(
        matchId: UUID, deviceId: UUID, deviceSeq: Long, type: String,
        actorId: UUID, occurredAt: Instant, payload: String,
    ): UUID {
        val id = UUID.randomUUID()
        connection.prepareStatement(
            """
            INSERT INTO evidence.event
              (event_id, match_id, device_id, device_seq, event_type, schema_version,
               correlation_id, actor_id, actor_role, occurred_at, occurred_tz, payload)
            VALUES (?, ?, ?, ?, ?, 1, ?, ?, 'participant', ?::timestamptz, ?, ?::jsonb)
            """.trimIndent(),
        ).use { ps ->
            ps.setObject(1, id); ps.setObject(2, matchId); ps.setObject(3, deviceId)
            ps.setLong(4, deviceSeq); ps.setString(5, type); ps.setObject(6, UUID.randomUUID())
            ps.setObject(7, actorId); ps.setString(8, occurredAt.toString())
            ps.setString(9, "Europe/London"); ps.setString(10, payload)
            ps.executeUpdate()
        }
        return id
    }

    private fun json(s: String): String =
        "\"" + s.replace("\\", "\\\\").replace("\"", "\\\"") + "\""
}
