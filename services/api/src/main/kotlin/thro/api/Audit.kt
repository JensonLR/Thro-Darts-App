package thro.api

import java.sql.Connection
import java.util.UUID
import thro.authz.Decision
import thro.authz.ObjectRef
import thro.authz.Subject

/** A break in the chain: which entry, and how it fails. */
public data class BrokenLink(val seq: Long, val why: String)

/**
 * The authorization audit log.
 *
 * ADR-008 requires that when a fraud allegation arrives fourteen months later, "who could have done
 * this, and who did?" is answerable. That means recording the decision *and the reason for it* —
 * the relation that granted it and the policy version in force — because a log of outcomes without
 * the rule that produced them cannot answer the first half of the question.
 *
 * The hash chain is computed by the database, never here. An application that computed its own
 * hashes could write a self-consistent chain of lies that verifies perfectly while being false.
 */
public class Audit(private val connection: Connection) {

    public companion object {
        /** Bumped whenever the rule set changes, so an old decision can be read against its rules. */
        public const val POLICY_VERSION: String = "1.0.0"
    }

    public fun record(
        subject: Subject,
        action: String,
        obj: ObjectRef,
        decision: Decision,
        correlationId: UUID? = null,
    ) {
        connection.prepareStatement(
            """
            INSERT INTO audit.decision
              (subject_id, action, object_type, object_id, allowed, granted_by, excluded_by,
               policy_version, correlation_id)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """.trimIndent(),
        ).use { ps ->
            ps.setObject(1, UUID.fromString(subject.id))
            ps.setString(2, action)
            ps.setString(3, obj.type.name.lowercase())
            ps.setString(4, obj.id)
            ps.setBoolean(5, decision.allowed)
            ps.setString(6, decision.grantedBy)
            ps.setString(7, decision.excludedBy)
            ps.setString(8, POLICY_VERSION)
            ps.setObject(9, correlationId)
            ps.executeUpdate()
        }
    }

    /** The first entry that does not verify, or null if the chain is intact. */
    public fun firstBrokenLink(): BrokenLink? {
        connection.prepareStatement("SELECT broken_seq, why FROM audit.first_broken_link()").use { ps ->
            ps.executeQuery().use { rs ->
                return if (rs.next()) BrokenLink(rs.getLong(1), rs.getString(2)) else null
            }
        }
    }
}
