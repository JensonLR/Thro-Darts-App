package thro.api

import java.io.File
import java.sql.Connection
import java.sql.DriverManager
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import thro.authz.Decision
import thro.authz.ObjectRef
import thro.authz.ObjectType
import thro.authz.Subject

/**
 * The authorization audit log.
 *
 * These tests tamper with the log rather than describing tampering. A chain that has never had
 * anything altered under it is not known to detect alteration.
 *
 * Skipped cleanly when no database is configured, rather than passing silently.
 */
class AuditTest {

    private val configured = TestDatabase.configured

    private fun migrated(): Connection = TestDatabase.migrated()

    @Test
    fun `the audit chain detects every way of rewriting history`() {
        if (!configured) {
            println("no database configured (set PGHOST) — audit tests skipped")
            return
        }
        val c = migrated()
        val audit = Audit(c)
        var passed = 0
        fun check(name: String, cond: Boolean) {
            assertTrue(cond, "FAILED: $name")
            println("  PASS  $name")
            passed++
        }

        val dana = Subject(UUID.randomUUID().toString())
        val theirs = ObjectRef(ObjectType.MATCH, "m1")
        val hers = ObjectRef(ObjectType.MATCH, "m2")

        audit.record(dana, "match.correct", theirs, Decision(true, grantedBy = "event:e#official"))
        audit.record(
            dana, "match.correct", hers,
            Decision(false, grantedBy = "event:e#official", excludedBy = "match:m2#participant"),
        )
        audit.record(dana, "match.score", theirs, Decision(true, grantedBy = "board:b#scorer"))

        check("the chain is intact after honest appends", audit.firstBrokenLink() == null)

        // Both halves of ADR-008's question are answerable.
        c.prepareStatement(
            "SELECT allowed, granted_by, excluded_by, policy_version FROM audit.decision WHERE object_id = 'm2'",
        ).use { ps ->
            ps.executeQuery().use { rs ->
                rs.next()
                check("a refusal records that authority existed", rs.getString("granted_by") == "event:e#official")
                check("and why it did not apply", rs.getString("excluded_by") == "match:m2#participant")
                check("under a named policy version", rs.getString("policy_version") == Audit.POLICY_VERSION)
                check("and the outcome", !rs.getBoolean("allowed"))
            }
        }

        // --- tamper 1: change what a decision said -------------------------------------------
        c.createStatement().use { it.execute("SET ROLE thro_owner; UPDATE audit.decision SET allowed = true WHERE seq = 2; RESET ROLE") }
        val altered = audit.firstBrokenLink()
        check("altering an entry is detected", altered != null && altered.seq == 2L)
        check("and the reason names the entry contents", altered!!.why.contains("hash"))
        c.createStatement().use { it.execute("SET ROLE thro_owner; UPDATE audit.decision SET allowed = false WHERE seq = 2; RESET ROLE") }
        check("restoring it makes the chain verify again", audit.firstBrokenLink() == null)

        // --- tamper 2: remove a decision entirely --------------------------------------------
        c.createStatement().use { it.execute("SET ROLE thro_owner; DELETE FROM audit.decision WHERE seq = 2; RESET ROLE") }
        val deleted = audit.firstBrokenLink()
        check("removing an entry is detected", deleted != null)
        check("by the successor whose predecessor vanished", deleted!!.seq == 3L)
        check("and the reason names the link", deleted.why.contains("previous entry"))

        // --- the application cannot forge a chain --------------------------------------------
        val c2 = migrated()
        val forged = ByteArray(32) { 0x41 }
        c2.prepareStatement(
            """
            INSERT INTO audit.decision
              (subject_id, action, object_type, object_id, allowed, policy_version, prev_hash, entry_hash)
            VALUES (?, 'match.correct', 'match', 'm9', true, '1.0.0', ?, ?)
            """.trimIndent(),
        ).use { ps ->
            ps.setObject(1, UUID.randomUUID())
            ps.setBytes(2, forged)
            ps.setBytes(3, forged)
            ps.executeUpdate()
        }
        c2.prepareStatement("SELECT prev_hash, entry_hash FROM audit.decision WHERE seq = 1").use { ps ->
            ps.executeQuery().use { rs ->
                rs.next()
                check("a supplied prev_hash is discarded", !rs.getBytes(1).contentEquals(forged))
                check("a supplied entry_hash is discarded", !rs.getBytes(2).contentEquals(forged))
            }
        }
        check("so the forged entry still verifies honestly", Audit(c2).firstBrokenLink() == null)

        // --- write-only for application roles -------------------------------------------------
        for (role in listOf("app_match", "app_trust", "app_rating", "app_read")) {
            val denied = try {
                c2.createStatement().use { st ->
                    st.execute("SET ROLE $role")
                    st.executeQuery("SELECT count(*) FROM audit.decision")
                    st.execute("RESET ROLE")
                }
                false
            } catch (e: org.postgresql.util.PSQLException) {
                c2.createStatement().use { it.execute("RESET ROLE") }
                e.message!!.contains("permission denied")
            }
            check("$role cannot read the log it writes to", denied)
        }

        // An empty log is intact, not broken.
        val c3 = migrated()
        check("an empty log verifies", Audit(c3).firstBrokenLink() == null)

        println("  $passed audit properties held")
        assertEquals(19, passed)
        assertNotNull(c)
    }
}
