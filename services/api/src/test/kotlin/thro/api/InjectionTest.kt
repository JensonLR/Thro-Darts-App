package thro.api

import java.io.File
import java.sql.Connection
import java.sql.DriverManager
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import thro.engine.InRule
import thro.engine.MatchFormat
import thro.engine.OutRule
import thro.engine.PlayerId
import thro.engine.Structure
import thro.engine.StructureMode

/**
 * Cross-match evidence injection — ADR-008's highest-value attack.
 *
 * Post a leg event carrying a stranger's match id and you move a stranger's rating. These tests
 * mount the attack rather than describing it, because a control that has never been fired at is
 * not known to work.
 *
 * Skipped cleanly when no database is configured, rather than passing silently.
 */
class InjectionTest {

    private val host = System.getenv("PGHOST").orEmpty()
    private val configured = host.isNotBlank()

    private fun migrated(): Connection {
        val port = System.getenv("PGPORT") ?: "5432"
        val db = System.getenv("PGDATABASE") ?: "postgres"
        val user = System.getenv("PGUSER") ?: "postgres"
        val c = DriverManager.getConnection("jdbc:postgresql://$host:$port/$db", user, "")
        c.createStatement().use { st ->
            for (s in listOf("evidence", "trust", "rating", "read")) {
                st.execute("DROP SCHEMA IF EXISTS $s CASCADE")
            }
            for (r in listOf("thro_owner", "app_match", "app_trust", "app_rating", "app_read")) {
                st.execute("DROP ROLE IF EXISTS $r")
            }
        }
        val dir = generateSequence(File(".").absoluteFile) { it.parentFile }
            .map { File(it, "services/api/migrations") }
            .firstOrNull { it.isDirectory } ?: File("migrations")
        dir.listFiles { f -> f.extension == "sql" }?.sortedBy { it.name }?.forEach { f ->
            c.createStatement().use { it.execute(f.readText()) }
        }
        return c
    }

    private fun format(first: String) = MatchFormat(
        startingScore = 501,
        inRule = InRule.STRAIGHT,
        outRule = OutRule.DOUBLE,
        legs = Structure(StructureMode.FIRST_TO, 3),
        throwFirst = PlayerId(first),
    )

    @Test
    fun `evidence cannot be injected into a match the author is not in`() {
        if (!configured) {
            println("no database configured (set PGHOST) — injection tests skipped")
            return
        }
        val c = migrated()
        val h = CommandHandler(c)
        val matches = Matches(c)
        var passed = 0
        fun check(name: String, cond: Boolean) {
            assertTrue(cond, "FAILED: $name")
            println("  PASS  $name")
            passed++
        }

        fun visit(match: UUID, player: String, seq: Long, total: Int = 60): CommandResult =
            h.handle(
                VisitCommand(
                    commandId = UUID.randomUUID(), matchId = match, deviceId = UUID.randomUUID(),
                    deviceSeq = seq, actorId = UUID.randomUUID(), actorRole = "participant",
                    correlationId = UUID.randomUUID(), player = player, visitTotal = total,
                    dartsUsed = null, occurredAt = "2026-09-04T19:00:00Z", occurredTz = "Europe/London",
                ),
            )

        fun events(match: UUID): Int {
            c.prepareStatement("SELECT count(*) FROM evidence.event WHERE match_id = ?").use { ps ->
                ps.setObject(1, match)
                ps.executeQuery().use { rs -> rs.next(); return rs.getInt(1) }
            }
        }

        // A real match between two strangers.
        val theirMatch = UUID.randomUUID()
        matches.open(
            theirMatch, UUID.randomUUID(), UUID.randomUUID(), "Alice", "Bob", format("Alice"),
        )
        check("a legitimate visit from a real participant is applied", visit(theirMatch, "Alice", 1) is CommandResult.Applied)

        // The attack: an outsider writes into their match.
        val r = visit(theirMatch, "Mallory", 2)
        check("a stranger's visit is refused", r is CommandResult.NotThisMatch)
        check("and produces no evidence", events(theirMatch) == 1)

        // The attack against a match that does not exist at all.
        val invented = UUID.randomUUID()
        val r2 = visit(invented, "Mallory", 1)
        check("a visit into an invented match is refused", r2 is CommandResult.NotThisMatch)
        check("and writes nothing", events(invented) == 0)

        // The refusal is idempotent like every other outcome: a retry returns the stored answer.
        val cmdId = UUID.randomUUID()
        val cmdDevice = UUID.randomUUID()   // one device: receipts key on (device, command)
        fun retry() = h.handle(
            VisitCommand(
                commandId = cmdId, matchId = invented, deviceId = cmdDevice, deviceSeq = 1,
                actorId = UUID.randomUUID(), actorRole = "participant",
                correlationId = UUID.randomUUID(), player = "Mallory", visitTotal = 60,
                dartsUsed = null, occurredAt = "2026-09-04T19:00:00Z", occurredTz = "Europe/London",
            ),
        )
        check("the refusal is recorded", retry() is CommandResult.NotThisMatch)
        check("and a replay returns it rather than re-deciding", retry() is CommandResult.Replayed)

        // The database itself refuses an orphan, so the control does not rest on application code
        // alone. Defence in depth: a bug in the handler must not be enough to plant evidence.
        val orphan = try {
            c.prepareStatement(
                """
                INSERT INTO evidence.event
                  (event_id, match_id, device_id, device_seq, event_type, schema_version,
                   correlation_id, actor_id, actor_role, occurred_at, occurred_tz, payload)
                VALUES (?, ?, ?, 1, 'VisitRecorded', 1, ?, ?, 'participant',
                        now(), 'Europe/London', '{}'::jsonb)
                """.trimIndent(),
            ).use { ps ->
                ps.setObject(1, UUID.randomUUID())
                ps.setObject(2, UUID.randomUUID())   // a match that does not exist
                ps.setObject(3, UUID.randomUUID())
                ps.setObject(4, UUID.randomUUID())
                ps.setObject(5, UUID.randomUUID())
                ps.executeUpdate()
            }
            false
        } catch (e: org.postgresql.util.PSQLException) {
            e.message!!.contains("event_belongs_to_a_real_match")
        }
        check("the database refuses evidence for a match that does not exist", orphan)

        // Who is playing cannot be edited after the fact by any application role.
        for (role in listOf("app_match", "app_trust", "app_rating", "app_read")) {
            val denied = try {
                c.createStatement().use { st ->
                    st.execute("SET ROLE $role")
                    st.execute("UPDATE evidence.match SET away_name = 'Mallory' WHERE match_id = '$theirMatch'")
                    st.execute("RESET ROLE")
                }
                false
            } catch (e: org.postgresql.util.PSQLException) {
                c.createStatement().use { it.execute("RESET ROLE") }
                e.message!!.contains("permission denied")
            }
            check("$role cannot rewrite who is playing", denied)
        }

        println("  $passed injection properties held")
        assertEquals(12, passed)
    }
}
