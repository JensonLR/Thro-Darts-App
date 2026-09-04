package thro.api

import java.sql.Connection
import java.time.Instant
import java.util.UUID

/**
 * How sound the recording actor's authority was at the moment evidence was recorded.
 *
 * This is an annotation on evidence, never a gate in front of it. ADR-006 is explicit that a
 * revoked scorer keeps the ability to *record* on a device that has not reached the network, and
 * that the mitigation is not rejection but review: recording is not the same as being believed.
 * Evidence is never destroyed for an authorization reason, because the dispute that needs it is
 * exactly the dispute in which someone's authority was contested.
 *
 * ADR-006's failure table lists grant expiry as the prevention for "a stale journal replayed weeks
 * later". It does not do that alone, and it should not: a player whose grant lapsed because an
 * organiser mis-set the session end still threw real darts. What actually stops an old command
 * landing on a settled match is the engine's finalised-match rejection, which refuses on the rules
 * rather than on authority. Expiry marks the evidence; the rules decide whether it can apply.
 */
public enum class Authority {
    /** A live, unexpired grant covering this match. */
    GRANTED,

    /** A grant existed and covered this match, but had passed its expiry when the visit occurred. */
    EXPIRED,

    /** A grant existed and was withdrawn before the visit occurred. */
    REVOKED,

    /** No grant was ever issued to this actor and device for this match. */
    UNGRANTED,
    ;

    /** Anything but [GRANTED] is recorded and routed to an organiser, never silently trusted. */
    public val needsReview: Boolean get() = this != GRANTED
}

public data class Grant(
    val grantId: UUID,
    val eventId: UUID,
    val matchId: UUID?,
    val actorId: UUID,
    val deviceId: UUID,
    val actorRole: String,
    val expiresAt: Instant,
    val revokedAt: Instant?,
)

/**
 * Issues, revokes and evaluates scoring grants.
 *
 * Grants are issued at check-in for a player's whole event, because check-in is the last moment the
 * product can rely on having a network. Their lifetime is the competition session plus 24 hours: a
 * tournament day runs ten hours or more, and a grant that expires mid-event fails the one case the
 * mechanism exists for.
 */
public class Grants(private val connection: Connection) {

    public companion object {
        /** The competition session plus 24 hours (ADR-006). */
        public const val LIFETIME_HOURS: Long = 24
    }

    /**
     * Issues a grant, superseding any live grant for the same scope in the same transaction.
     *
     * Reassignment revokes rather than adds: an actor holding two grants for one scope would make
     * "which authority was this recorded under" unanswerable, which is the question a dispute asks.
     */
    public fun issue(
        eventId: UUID,
        actorId: UUID,
        deviceId: UUID,
        actorRole: String,
        matchId: UUID? = null,
        sessionEndsAt: Instant,
        issuedBy: UUID,
    ): UUID {
        revokeScope(eventId, actorId, deviceId, matchId, issuedBy, "superseded")
        val id = UUID.randomUUID()
        connection.prepareStatement(
            """
            INSERT INTO trust.scoring_grant
              (grant_id, event_id, match_id, actor_id, device_id, actor_role, expires_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """.trimIndent(),
        ).use { ps ->
            ps.setObject(1, id)
            ps.setObject(2, eventId)
            ps.setObject(3, matchId)
            ps.setObject(4, actorId)
            ps.setObject(5, deviceId)
            ps.setString(6, actorRole)
            ps.setObject(7, java.sql.Timestamp.from(sessionEndsAt.plusSeconds(LIFETIME_HOURS * 3600)))
            ps.executeUpdate()
        }
        return id
    }

    /** Withdraws a grant. The row is kept: what authority existed and when is itself evidence. */
    public fun revoke(grantId: UUID, revokedBy: UUID, reason: String) {
        connection.prepareStatement(
            """
            UPDATE trust.scoring_grant
               SET revoked_at = clock_timestamp(), revoked_by = ?, revoked_reason = ?
             WHERE grant_id = ? AND revoked_at IS NULL
            """.trimIndent(),
        ).use { ps ->
            ps.setObject(1, revokedBy)
            ps.setString(2, reason)
            ps.setObject(3, grantId)
            ps.executeUpdate()
        }
    }

    private fun revokeScope(
        eventId: UUID,
        actorId: UUID,
        deviceId: UUID,
        matchId: UUID?,
        by: UUID,
        reason: String,
    ) {
        connection.prepareStatement(
            """
            UPDATE trust.scoring_grant
               SET revoked_at = clock_timestamp(), revoked_by = ?, revoked_reason = ?
             WHERE revoked_at IS NULL
               AND event_id = ? AND actor_id = ? AND device_id = ?
               AND coalesce(match_id, '00000000-0000-0000-0000-000000000000'::uuid)
                 = coalesce(?, '00000000-0000-0000-0000-000000000000'::uuid)
            """.trimIndent(),
        ).use { ps ->
            ps.setObject(1, by)
            ps.setString(2, reason)
            ps.setObject(3, eventId)
            ps.setObject(4, actorId)
            ps.setObject(5, deviceId)
            ps.setObject(6, matchId)
            ps.executeUpdate()
        }
    }

    /**
     * Evaluates the authority an actor held for a match *at the moment the visit occurred*.
     *
     * The time compared against is [occurredAt] — the device clock, which ADR-006 treats as
     * evidence only. That is deliberate and it is the honest comparison: the question is whether
     * the actor was authorised when they threw, not whether they are authorised now that a queued
     * batch has finally reached the network. A device clock can be wrong or manipulated, which is
     * why the answer annotates the evidence for review rather than deciding whether to keep it.
     */
    public fun authorityFor(
        matchId: UUID,
        actorId: UUID,
        deviceId: UUID,
        occurredAt: Instant,
    ): Pair<Authority, UUID?> {
        val candidates = mutableListOf<Grant>()
        connection.prepareStatement(
            """
            SELECT grant_id, event_id, match_id, actor_id, device_id, actor_role,
                   expires_at, revoked_at
              FROM trust.scoring_grant
             WHERE actor_id = ? AND device_id = ?
               AND (match_id = ? OR match_id IS NULL)
             ORDER BY issued_at DESC
            """.trimIndent(),
        ).use { ps ->
            ps.setObject(1, actorId)
            ps.setObject(2, deviceId)
            ps.setObject(3, matchId)
            ps.executeQuery().use { rs ->
                while (rs.next()) {
                    candidates += Grant(
                        grantId = rs.getObject("grant_id") as UUID,
                        eventId = rs.getObject("event_id") as UUID,
                        matchId = rs.getObject("match_id") as UUID?,
                        actorId = rs.getObject("actor_id") as UUID,
                        deviceId = rs.getObject("device_id") as UUID,
                        actorRole = rs.getString("actor_role"),
                        expiresAt = rs.getTimestamp("expires_at").toInstant(),
                        revokedAt = rs.getTimestamp("revoked_at")?.toInstant(),
                    )
                }
            }
        }
        if (candidates.isEmpty()) return Authority.UNGRANTED to null

        // A match-scoped grant is more specific than an event-wide one and is preferred.
        val ordered = candidates.sortedBy { if (it.matchId != null) 0 else 1 }
        ordered.firstOrNull { g ->
            (g.revokedAt == null || g.revokedAt > occurredAt) && g.expiresAt > occurredAt
        }?.let { return Authority.GRANTED to it.grantId }

        // Nothing was sound. Say which failure it was, preferring the more serious: a withdrawn
        // authority is a different fact from one that simply ran out.
        ordered.firstOrNull { it.revokedAt != null && it.revokedAt <= occurredAt }
            ?.let { return Authority.REVOKED to it.grantId }
        return Authority.EXPIRED to ordered.first().grantId
    }
}
