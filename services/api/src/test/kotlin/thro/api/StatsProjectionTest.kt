package thro.api

import java.io.File
import java.sql.Connection
import java.sql.DriverManager
import java.util.UUID
import kotlin.math.abs
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * The projection turns an event log into the records the statistics layer consumes. Its figures are
 * checked here against values computed by hand from the leg below, because a projection that
 * derives plausible-looking but wrong records would put a wrong number on a player's profile and
 * nothing downstream would notice.
 *
 * Skipped cleanly when no database is configured, rather than passing silently.
 */
class StatsProjectionTest {

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

    @Test
    fun `projected figures match the leg they were derived from`() {
        if (!configured) {
            println("no database configured (set PGHOST) — projection test skipped")
            return
        }
        val c = migrated()
        val h = CommandHandler(c)
        val match = UUID.randomUUID()
        val device = UUID.randomUUID()
        var seq = 0L
        Matches(c).open(
            match, UUID.randomUUID(), UUID.randomUUID(), "Home", "Away",
            playtestFormat(thro.engine.PlayerId("Home")),
        )

        // Home: 501 -180-> 321 -180-> 141 -101-> 40 -20-> 20 -20-> 0
        //   141, 40 and 20 are all checkout numbers, so all three visits began on a finish.
        //   The first two missed (1 and 2 darts at a double); the third checked out with one dart.
        // Away: four visits of 60, never on a finish.
        fun visit(player: String, total: Int, darts: Int?, atDouble: Int?) {
            seq += 1
            val r = h.handle(
                VisitCommand(
                    commandId = UUID.randomUUID(), matchId = match, deviceId = device,
                    deviceSeq = seq, actorId = UUID.randomUUID(), actorRole = "participant",
                    correlationId = UUID.randomUUID(), player = player, visitTotal = total,
                    dartsUsed = darts, dartsAtDouble = atDouble,
                    occurredAt = "2026-09-04T19:00:00+01:00", occurredTz = "Europe/London",
                ),
                "Home", "Away",
            )
            assertTrue(r is CommandResult.Applied, "visit $seq ($player $total) was not applied: $r")
        }

        visit("Home", 180, null, null); visit("Away", 60, null, null)
        visit("Home", 180, null, null); visit("Away", 60, null, null)
        visit("Home", 101, null, 1);    visit("Away", 60, null, null)
        visit("Home", 20, null, 2);     visit("Away", 60, null, null)
        visit("Home", 20, 1, 1)

        val proj = StatsProjection(c)
        val all = proj.visitsFor(match, device, "Home", "Away")
        val home = all.filter { it.player == "Home" }.map { it.record }

        assertEquals(9, all.size, "every accepted visit should project a record")
        assertEquals(5, home.size)

        // Ordinals are per player per leg — not a counter shared across both competitors, and not
        // reset by the visit that wins the leg.
        assertEquals(listOf(1, 2, 3, 4, 5), home.map { it.visitOrdinal })
        assertEquals(listOf(1, 1, 1, 1, 1), home.map { it.legOrdinal })

        // Remainings are derived by replay, never stored.
        assertEquals(listOf(501, 321, 141, 40, 20), home.map { it.remainingBefore })
        assertEquals(listOf(321, 141, 40, 20, 0), home.map { it.remainingAfter })
        assertEquals(listOf(false, false, false, false, true), home.map { it.wonLeg })

        val checkable = thro.engine.RuleTables.checkouts(thro.engine.OutRule.DOUBLE)
        fun near(actual: Double?, expected: Double, what: String) =
            assertTrue(actual != null && abs(actual - expected) < 0.01, "$what was $actual, expected $expected")

        // 501 scored from 3+3+3+3+1 = 13 darts
        near(thro.stats.Statistics.threeDartAverage(home).value, 501.0 * 3 / 13, "3-dart average")
        // first three visits of the leg: 180 + 180 + 101 = 461 over nine darts
        near(thro.stats.Statistics.firstNineAverage(home).value, 461.0 * 3 / 9, "first 9")
        // one double hit from 1 + 2 + 1 = 4 thrown at
        near(thro.stats.Statistics.checkoutPercentage(home, checkable).value, 25.0, "checkout %")
        near(thro.stats.Statistics.doublesAttempted(home, checkable).value, 4.0, "doubles attempted")
        // three visits began on a finish (141, 40, 20); one of them won the leg
        near(
            thro.stats.Statistics.finishRateFromCheckablePosition(home, checkable).value,
            100.0 / 3, "finish rate",
        )
        near(thro.stats.Statistics.maximums(home).value, 2.0, "180s")
        near(thro.stats.Statistics.highestCheckout(home).value, 20.0, "highest checkout")

        // Away threw four visits of 60 and never stood on a finish, so the figure that needs a
        // double attempt must report itself unavailable rather than defaulting to zero.
        val away = all.filter { it.player == "Away" }.map { it.record }
        val awayCheckout = thro.stats.Statistics.checkoutPercentage(away, checkable)
        assertEquals(thro.stats.Basis.UNAVAILABLE, awayCheckout.basis)
        assertTrue(awayCheckout.note!!.isNotBlank(), "an unavailable figure must explain itself")

        println("  projection verified against a hand-computed leg")
    }
}
