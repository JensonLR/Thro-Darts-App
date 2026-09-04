package thro.api

import java.sql.Connection
import java.util.UUID
import thro.authz.Authorizer
import thro.authz.Hierarchy
import thro.authz.ObjectRef
import thro.authz.ObjectType
import thro.authz.Rules
import thro.authz.Subject
import thro.authz.TupleSource

/**
 * The relation store, and the one decision point built over it.
 *
 * ADR-008 resolves permissions **per request**, never from a token: a removed organiser who kept
 * their power until a token expired is a live authority the system believes it has revoked.
 */
public class Relations(private val connection: Connection) {

    public fun grant(subject: UUID, relation: String, obj: ObjectRef, by: UUID? = null) {
        connection.prepareStatement(
            """
            INSERT INTO authz.relation (subject_id, relation, object_type, object_id, granted_by)
            VALUES (?, ?, ?, ?, ?) ON CONFLICT DO NOTHING
            """.trimIndent(),
        ).use { ps ->
            ps.setObject(1, subject)
            ps.setString(2, relation)
            ps.setString(3, obj.type.name.lowercase())
            ps.setString(4, obj.id)
            ps.setObject(5, by)
            ps.executeUpdate()
        }
    }

    /** Revocation is a delete, and it takes effect on the very next request. */
    public fun revoke(subject: UUID, relation: String, obj: ObjectRef) {
        connection.prepareStatement(
            """
            DELETE FROM authz.relation
             WHERE subject_id = ? AND relation = ? AND object_type = ? AND object_id = ?
            """.trimIndent(),
        ).use { ps ->
            ps.setObject(1, subject)
            ps.setString(2, relation)
            ps.setString(3, obj.type.name.lowercase())
            ps.setString(4, obj.id)
            ps.executeUpdate()
        }
    }

    public fun link(child: ObjectRef, parent: ObjectRef) {
        connection.prepareStatement(
            """
            INSERT INTO authz.hierarchy (child_type, child_id, parent_type, parent_id)
            VALUES (?, ?, ?, ?) ON CONFLICT DO NOTHING
            """.trimIndent(),
        ).use { ps ->
            ps.setString(1, child.type.name.lowercase())
            ps.setString(2, child.id)
            ps.setString(3, parent.type.name.lowercase())
            ps.setString(4, parent.id)
            ps.executeUpdate()
        }
    }

    private fun tupleSource(): TupleSource = TupleSource { relation, obj ->
        val out = mutableSetOf<Subject>()
        connection.prepareStatement(
            """
            SELECT subject_id FROM authz.relation
             WHERE relation = ? AND object_type = ? AND object_id = ?
            """.trimIndent(),
        ).use { ps ->
            ps.setString(1, relation)
            ps.setString(2, obj.type.name.lowercase())
            ps.setString(3, obj.id)
            ps.executeQuery().use { rs ->
                while (rs.next()) out += Subject(rs.getString(1))
            }
        }
        out
    }

    private fun hierarchy(): Hierarchy {
        val map = mutableMapOf<ObjectRef, MutableSet<ObjectRef>>()
        connection.prepareStatement(
            "SELECT child_type, child_id, parent_type, parent_id FROM authz.hierarchy",
        ).use { ps ->
            ps.executeQuery().use { rs ->
                while (rs.next()) {
                    val child = ObjectRef(ObjectType.valueOf(rs.getString(1).uppercase()), rs.getString(2))
                    val parent = ObjectRef(ObjectType.valueOf(rs.getString(3).uppercase()), rs.getString(4))
                    map.getOrPut(child) { mutableSetOf() } += parent
                }
            }
        }
        return Hierarchy(map.mapValues { it.value.toSet() })
    }

    /**
     * Resolves and **records** one decision.
     *
     * The audit write is not optional and not a caller's responsibility. ADR-008 requires every
     * granting decision on a mutating action to be recorded with the relation that granted it, and
     * a decision point that leaves logging to its callers is one that will be called without it.
     */
    public fun decide(subject: UUID, action: String, obj: ObjectRef, correlationId: UUID? = null): thro.authz.Decision {
        val authorizer = Authorizer(tupleSource(), hierarchy(), Rules.DEFAULT)
        val decision = authorizer.check(Subject(subject.toString()), action, obj)
        Audit(connection).record(Subject(subject.toString()), action, obj, decision, correlationId)
        return decision
    }
}
