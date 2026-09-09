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

    private val configured = TestDatabase.configured

    private fun migrated(): Connection = TestDatabase.migrated()

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
        val homePlayer = UUID.randomUUID()
        var seq = 0L
        Matches(c).open(match, homePlayer, UUID.randomUUID(), playtestFormat())

        // Home: 501 -180-> 321 -180-> 141 -101-> 40 -20-> 20 -20-> 0
        //   141, 40 and 20 are all checkout numbers, so all three visits began on a finish.
        //   The first two missed (1 and 2 darts at a double); the third checked out with one dart.
        // Away: four visits of 60, never on a finish.
        fun visit(player: String, total: Int, darts: Int?, atDouble: Int?) {
            seq += 1
            val r = h.handle(
                VisitCommand(
                    commandId = UUID.randomUUID(), matchId = match, deviceId = device,
                    deviceSeq = seq, actorId = homePlayer, actorRole = "participant",
                    correlationId = UUID.randomUUID(), player = player, visitTotal = total,
                    dartsUsed = darts, dartsAtDouble = atDouble,
                    occurredAt = "2026-09-04T19:00:00+01:00", occurredTz = "Europe/London",
                ),
                "home", "away",
            )
            assertTrue(r is CommandResult.Applied, "visit $seq ($player $total) was not applied: $r")
        }

        visit("home", 180, null, null); visit("away", 60, null, null)
        visit("home", 180, null, null); visit("away", 60, null, null)
        visit("home", 101, null, 1);    visit("away", 60, null, null)
        visit("home", 20, null, 2);     visit("away", 60, null, null)
        visit("home", 20, 1, 1)

        val proj = StatsProjection(c)
        val all = proj.visitsFor(match, device, "home", "away", playtestFormat(thro.engine.PlayerId("home")))
        val home = all.filter { it.player == "home" }.map { it.record }

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
        val away = all.filter { it.player == "away" }.map { it.record }
        val awayCheckout = thro.stats.Statistics.checkoutPercentage(away, checkable)
        assertEquals(thro.stats.Basis.UNAVAILABLE, awayCheckout.basis)
        assertTrue(awayCheckout.note!!.isNotBlank(), "an unavailable figure must explain itself")

        println("  projection verified against a hand-computed leg")
    }

    /**
     * The projection must replay under the match's own format, not a fixed one.
     *
     * It used to replay every match under a hardcoded 501 / double-out / first-to-five while the
     * command path rehydrated from the stored format — so a 301 match had every remaining derived
     * two hundred too high, and the figures disagreed with the scoreboard that produced them. That
     * is the precise failure the "shared format" comment was written to prevent, and it was the one
     * happening.
     */
    @Test
    fun `the projection replays under the match's own format, not a fixed one`() {
        if (!configured) {
            println("no database configured (set PGHOST) — projection format test skipped")
            return
        }
        val c = migrated()
        val h = CommandHandler(c)
        val match = UUID.randomUUID()
        val device = UUID.randomUUID()
        val format = thro.engine.MatchFormat(
            startingScore = 301,
            inRule = thro.engine.InRule.STRAIGHT,
            outRule = thro.engine.OutRule.DOUBLE,
            legs = thro.engine.Structure(thro.engine.StructureMode.FIRST_TO, 3),
            throwFirst = thro.engine.PlayerId("home"),
        )
        val homePlayer = UUID.randomUUID()
        Matches(c).open(match, homePlayer, UUID.randomUUID(), format)

        var seq = 0L
        fun visit(player: String, total: Int) {
            seq += 1
            val r = h.handle(
                VisitCommand(
                    commandId = UUID.randomUUID(), matchId = match, deviceId = device,
                    deviceSeq = seq, actorId = homePlayer, actorRole = "participant",
                    correlationId = UUID.randomUUID(), player = player, visitTotal = total,
                    dartsUsed = null, dartsAtDouble = null,
                    occurredAt = "2026-09-07T19:00:00+01:00", occurredTz = "Europe/London",
                ),
                "home", "away",
            )
            assertTrue(r is CommandResult.Applied, "visit $seq ($player $total) was not applied: $r")
        }
        visit("home", 100); visit("away", 60); visit("home", 100)

        val proj = StatsProjection(c)
        val home = proj.visitsFor(match, device, "home", "away", format)
            .filter { it.player == "home" }.map { it.record }
        assertEquals(listOf(301, 201), home.map { it.remainingBefore },
                     "a 301 match starts at 301 — under the old fixed format this read 501 and 401")
        assertEquals(listOf(201, 101), home.map { it.remainingAfter })

        // And the summary's checkable set comes from the match's out-rule for the same reason.
        val summary = proj.summaryFor(match, device, "home", "away", "home", format)
        assertTrue(summary.contains("threeDartAverage"), "summary: $summary")
    }
}
