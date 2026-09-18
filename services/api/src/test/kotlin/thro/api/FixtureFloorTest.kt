package thro.api

import java.io.File
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * The floor code sets on the production-size desk without asking the model anything (PD-158).
 *
 * **This test spends nothing** — no key, no network, no tokens. It measures what a normaliser and a presence check
 * get on their own, which is the floor PD-154 said to publish before buying a question. Until it exists, "the model
 * got 19 of 20" is a number with nothing to be better than.
 *
 * It is two-sided on purpose. A check that rejected every sentence would score the sealed set perfectly, so the
 * count of fixtures correctly *found* is reported beside the count correctly *refused*, and both are asserted.
 */
class FixtureFloorTest {

    private val desk = ProductionDesk.desk

    @Test
    fun `the desk is the size a real division is, and pairs meet twice`() {
        assertEquals(110, ProductionDesk.fixtures.size, "eleven teams, home and away")
        val meetings = ProductionDesk.fixtures.groupBy { setOf(it.home, it.away) }
        assertEquals(55, meetings.size, "fifty-five pairs")
        assertTrue(meetings.values.all { it.size == 2 }, "every pair meets exactly twice — the case the old desk had none of")
    }

    @Test
    fun `the floor a presence check sets on the sealed set, with no model and no tokens`() {
        var rejected = 0
        val survived = mutableListOf<String>()
        for (text in ProductionDesk.noSuchFixture) {
            val named = Understanding.fixturesNamed(desk, text)
            if (named.isEmpty()) rejected++ else survived += "$text → ${named.size}: ${named.first().home} v ${named.first().away}"
        }
        var found = 0
        val missed = mutableListOf<String>()
        val asked = ProductionDesk.realFixture.count { it.second.isNotEmpty() }
        for ((text, pair) in ProductionDesk.realFixture) {
            if (pair.isEmpty()) continue
            if (Understanding.fixturesNamed(desk, text).any { setOf(it.home, it.away) == pair }) found++ else missed += text
        }

        val out = StringBuilder()
        out.appendLine("# The floor, measured (PD-158)"); out.appendLine()
        out.appendLine("Desk: ${ProductionDesk.teams.size} teams, ${ProductionDesk.fixtures.size} fixtures, every pair meeting twice.")
        out.appendLine("No model, no key, no tokens — this is what a normaliser and a presence check do on their own.")
        out.appendLine()
        out.appendLine("| | Count |")
        out.appendLine("|---|---|")
        out.appendLine("| Sealed \"no fixture\" sentences refused | **$rejected of ${ProductionDesk.noSuchFixture.size}** |")
        out.appendLine("| Real fixtures found (the half that stops a reject-everything check scoring well) | **$found of $asked** |")
        out.appendLine()
        if (survived.isNotEmpty()) { out.appendLine("Survived the floor — what a question would have to earn its keep on:"); out.appendLine(); survived.forEach { out.appendLine("- $it") } }
        if (missed.isNotEmpty()) { out.appendLine("Missed by the floor:"); out.appendLine(); missed.forEach { out.appendLine("- $it") } }
        out.appendLine()
        out.appendLine("**What this means for the two Nouls PD-154 proposed.** `names_two_teams` and `fixture_is_listed` were")
        out.appendLine("meant to stop the desk naming a fixture for a sentence about one the season has not got. Code does that,")
        out.appendLine("here, for nothing, on the board where the case is hardest. They are not worth building.")
        File("build").mkdirs(); File("build/fixture-floor.md").writeText(out.toString())
        println(out)

        assertEquals(ProductionDesk.noSuchFixture.size, rejected,
                     "the floor: every sealed sentence about a fixture the season has not got is refused by code alone")
        assertEquals(asked, found,
                     "and the floor still finds the fixtures that are really named — without this the line above is worthless")
    }

    @Test
    fun `a sentence about a pair that meets twice names both meetings, and the floor cannot tell them apart`() {
        // The honest limit of the floor, written down rather than discovered later: presence finds the pair and says
        // nothing about WHICH of their two meetings is meant. That is what a date, or a person, is for — and it is
        // the one job on this desk a question might genuinely be worth asking.
        val both = Understanding.fixturesNamed(desk, "Grange A beat Dolphin 5-3")
        assertEquals(2, both.size, "a pair plays home and away, and the sentence names neither leg")
        assertEquals(setOf(setOf("Grange A", "Dolphin")), both.map { setOf(it.home, it.away) }.toSet())
    }

    @Test
    fun `a side letter in the sentence keeps the two sides of a club apart`() {
        val b = Understanding.fixturesNamed(desk, "riverside b 5 crown 1")
        assertTrue(b.isNotEmpty(), "the sentence names a real pair")
        assertTrue(b.all { it.home == "Riverside B" || it.away == "Riverside B" },
                   "and never Riverside A, which is a different team in the same division")
    }
}
