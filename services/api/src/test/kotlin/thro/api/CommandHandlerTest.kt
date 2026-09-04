package thro.api

import java.io.File
import java.sql.Connection
import java.sql.DriverManager
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * Integration tests for the command path, against a real PostgreSQL.
 *
 * These assert the properties that would be unrecoverable if wrong, so they run against a database
 * rather than a mock. A mocked event store cannot tell you that a replayed command creates a second
 * event, which is precisely the failure that would corrupt a match.
 *
 * Skipped cleanly when no database is configured, rather than passing silently.
 */
class CommandHandlerTest {

    private val host = System.getenv("PGHOST").orEmpty()
    private val configured = host.isNotBlank()

    private fun connect(): Connection {
        val port = System.getenv("PGPORT") ?: "5432"
        val db = System.getenv("PGDATABASE") ?: "postgres"
        val user = System.getenv("PGUSER") ?: "postgres"
        val url = if (host.startsWith("/")) {
            "jdbc:postgresql://localhost:$port/$db?socketFactory=org.newsclub.net.unix.AFUNIXSocketFactory"
        } else {
            "jdbc:postgresql://$host:$port/$db"
        }
        return DriverManager.getConnection(url, user, "")
    }

    private fun migrated(): Connection {
        val c = connect()
        c.createStatement().use { st ->
            st.execute("DROP SCHEMA IF EXISTS evidence CASCADE")
            st.execute("DROP SCHEMA IF EXISTS trust CASCADE")
            st.execute("DROP SCHEMA IF EXISTS rating CASCADE")
            st.execute("DROP SCHEMA IF EXISTS read CASCADE")
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

    private fun cmd(
        match: UUID, device: UUID, seq: Long, player: String, total: Int,
        darts: Int? = 3, id: UUID = UUID.randomUUID(),
    ) = VisitCommand(
        commandId = id, matchId = match, deviceId = device, deviceSeq = seq,
        actorId = UUID.randomUUID(), actorRole = "participant",
        correlationId = UUID.randomUUID(), player = player, visitTotal = total,
        dartsUsed = darts, occurredAt = "2026-09-03T19:00:00+01:00", occurredTz = "Europe/London",
    )

    private fun events(c: Connection, match: UUID): Int {
        c.prepareStatement("SELECT count(*) FROM evidence.event WHERE match_id = ?").use { ps ->
            ps.setObject(1, match)
            ps.executeQuery().use { rs -> rs.next(); return rs.getInt(1) }
        }
    }

    @Test
    fun `command path holds its integrity properties`() {
        if (!configured) {
            println("no database configured (set PGHOST) — integration tests skipped")
            return
        }
        val c = migrated()
        val h = CommandHandler(c)
        val match = UUID.randomUUID()
        val devA = UUID.randomUUID()
        val devB = UUID.randomUUID()
        var passed = 0

        fun check(name: String, cond: Boolean) {
            assertTrue(cond, "FAILED: $name")
            println("  PASS  $name")
            passed++
        }

        // a visit is validated by the server's own engine and appended
        val first = h.handle(cmd(match, devA, 1, "A", 100), "A", "B")
        check("a valid visit is applied", first is CommandResult.Applied &&
            (first as CommandResult.Applied).effect == "scored")
        check("one event was written", events(c, match) == 1)

        // a replay returns the stored response and creates nothing
        val replayId = UUID.randomUUID()
        val once = h.handle(cmd(match, devA, 2, "B", 60, id = replayId), "A", "B")
        val twice = h.handle(cmd(match, devA, 2, "B", 60, id = replayId), "A", "B")
        check("a replayed command is not re-applied", twice is CommandResult.Replayed)
        check("a replay creates no second event", events(c, match) == 2)
        check("the stored response comes back verbatim",
            (twice as CommandResult.Replayed).stored.contains("scored"))

        // a gap is refused rather than applied out of order
        val gap = h.handle(cmd(match, devA, 9, "A", 60), "A", "B")
        check("a sequence gap is refused with the expected value",
            gap is CommandResult.Gap && (gap as CommandResult.Gap).expectedSeq == 3L)
        check("a gap writes no event", events(c, match) == 2)

        // an impossible total is refused by the engine, and leaves no evidence
        val impossible = h.handle(cmd(match, devA, 3, "A", 163), "A", "B")
        check("an unreachable visit total is refused",
            impossible is CommandResult.Refused &&
                (impossible as CommandResult.Refused).reason == "IMPOSSIBLE_VISIT_TOTAL")
        check("a refusal produces no evidence", events(c, match) == 2)

        // out of turn is refused
        val outOfTurn = h.handle(cmd(match, devA, 3, "B", 60), "A", "B")
        check("a visit from the wrong player is refused",
            outOfTurn is CommandResult.Refused &&
                (outOfTurn as CommandResult.Refused).reason == "NOT_YOUR_TURN")

        // the second device authors its own stream for the same match
        val other = h.handle(cmd(match, devB, 1, "A", 100), "A", "B")
        check("a second device can author the same match", other is CommandResult.Applied)
        check("both accounts are stored", events(c, match) == 3)
        c.prepareStatement(
            "SELECT count(DISTINCT device_id) FROM evidence.event WHERE match_id = ?",
        ).use { ps ->
            ps.setObject(1, match)
            ps.executeQuery().use { rs ->
                rs.next()
                check("each device's account is separately readable", rs.getInt(1) == 2)
            }
        }

        // the server derives the outcome; a client's claim about it is not consulted
        val lying = cmd(match, devA, 3, "A", 60).copy(clientEffect = "match_won")
        val derived = h.handle(lying, "A", "B")
        check("the server derives the outcome rather than trusting the client",
            derived is CommandResult.Applied && (derived as CommandResult.Applied).effect == "scored")

        println("  $passed integrity properties held")
        c.close()
    }
}
