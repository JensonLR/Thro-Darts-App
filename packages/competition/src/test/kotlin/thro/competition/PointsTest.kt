package thro.competition

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue

/**
 * What a result is worth (PD-054). THRØ has a standard and a league may replace it, so both halves are held
 * here — and so is the part that makes the standard safe: a rule THRØ cannot compute is refused by name
 * rather than quietly dropped out of somebody's table.
 */
class PointsPolicyTest {

    @Test
    fun `THRO's standard is two a win, one a draw, and it says so`() {
        val p = PointsPolicy.STANDARD
        assertEquals(2, p.win)
        assertEquals(1, p.draw)
        assertEquals(0, p.loss)
        assertEquals(0, p.perLegWon, "the standard awards nothing per leg; a league that does writes its own")
        assertEquals(listOf(TieBreak.POINTS, TieBreak.LEG_DIFFERENCE, TieBreak.LEGS_FOR), p.chain)
        assertTrue(PointsPolicy.STANDARD_SAYS.contains("THRØ's standard"),
                   "the standard names itself wherever it is used: ${PointsPolicy.STANDARD_SAYS}")
        assertTrue(PointsPolicy.STANDARD_SAYS.contains("not this league's own rules"))
    }

    @Test
    fun `a row is the arithmetic of what was played`() {
        val row = PointsPolicy.STANDARD.row("a", playedWon = 9, playedDrawn = 2, playedLost = 3,
                                           legsFor = 70, legsAgainst = 48)
        assertEquals(14, row.played)
        assertEquals(20, row.points, "nine wins at two and two draws at one")
        assertEquals(22, row.legDifference)
    }

    @Test
    fun `an award moves the points and never the legs`() {
        val row = PointsPolicy.STANDARD.row("a", playedWon = 4, playedDrawn = 0, playedLost = 1,
                                            legsFor = 30, legsAgainst = 20, awardedFor = 1, awardedAgainst = 1)
        assertEquals(7, row.played, "a fixture nobody played still happened to the table")
        assertEquals(5, row.won, "the side that was awarded it won it")
        assertEquals(2, row.lost)
        assertEquals(10, row.points, "four wins and one award, at two each")
        assertEquals(30, row.legsFor, "an invented scoreline would pollute every leg difference beneath it")
        assertEquals(20, row.legsAgainst)
    }

    @Test
    fun `a league may score by the leg`() {
        val p = PointsPolicy.parse(mapOf("win" to 2, "draw" to 1, "points_per_leg_won" to 1))
        val row = p.row("a", playedWon = 5, playedDrawn = 0, playedLost = 5, legsFor = 40, legsAgainst = 38)
        assertEquals(50, row.points, "ten points for five wins, and one for each of forty legs")
    }

    @Test
    fun `a league may declare its own order, and THRO's is replaced not merged`() {
        val p = PointsPolicy.parse(mapOf("tie_break" to listOf("points", "head_to_head", "legs_for")))
        assertEquals(listOf(TieBreak.POINTS, TieBreak.HEAD_TO_HEAD, TieBreak.LEGS_FOR), p.chain)
    }

    @Test
    fun `a bonus on a fixture's own scoreline is refused by name`() {
        val why = assertFailsWith<IllegalArgumentException> {
            PointsPolicy.parse(mapOf("win" to 2, "bonus" to listOf(mapOf("legs_for_at_least" to 5))))
        }.message.orEmpty()
        assertTrue(why.contains("cannot yet count"), why)
        assertTrue(why.contains("points_per_leg_won"), "it names what THRØ can do instead: $why")
    }

    @Test
    fun `an order THRO cannot apply is refused, and lists what it knows`() {
        val why = assertFailsWith<IllegalArgumentException> {
            PointsPolicy.parse(mapOf("tie_break" to listOf("points", "coin_toss")))
        }.message.orEmpty()
        assertTrue(why.contains("coin_toss"), why)
        assertTrue(why.contains("head_to_head"), "a refusal that does not say what is possible is a dead end: $why")
    }

    @Test
    fun `a key THRO cannot execute is refused rather than ignored`() {
        val why = assertFailsWith<IllegalArgumentException> {
            PointsPolicy.parse(mapOf("win" to 2, "promotion_places" to 2))
        }.message.orEmpty()
        assertTrue(why.contains("promotion_places"), why)
    }

    @Test
    fun `taking points away is not a rule about a result`() {
        val why = assertFailsWith<IllegalArgumentException> {
            PointsPolicy.parse(mapOf("loss" to -1))
        }.message.orEmpty()
        assertTrue(why.contains("deduction is a decision about a team"), why)
    }

    @Test
    fun `an empty or repeated order says nothing and is refused`() {
        assertFailsWith<IllegalArgumentException> { PointsPolicy.parse(mapOf("tie_break" to emptyList<String>())) }
        assertFailsWith<IllegalArgumentException> {
            PointsPolicy.parse(mapOf("tie_break" to listOf("points", "points")))
        }
    }

    @Test
    fun `a league may say a walkover is not a fixture played`() {
        val p = PointsPolicy.parse(mapOf("awards_count_as_played" to false))
        val row = p.row("a", playedWon = 3, playedDrawn = 0, playedLost = 0, legsFor = 18, legsAgainst = 6,
                        awardedFor = 2)
        assertEquals(3, row.played, "the league counts only what was thrown")
        assertEquals(5, row.won, "and still credits the award")
        assertEquals(10, row.points)
    }

    @Test
    fun `an awarded fixture may be worth something other than a win`() {
        val p = PointsPolicy.parse(mapOf("win" to 3, "awarded" to 1))
        assertEquals(3, p.win)
        assertEquals(1, p.awarded)
        assertEquals(4, p.row("a", playedWon = 1, playedDrawn = 0, playedLost = 0, legsFor = 6, legsAgainst = 2,
                              awardedFor = 1).points)
    }

    @Test
    fun `an awarded fixture is worth a win unless the league says otherwise`() {
        val p = PointsPolicy.parse(mapOf("win" to 3))
        assertEquals(3, p.awarded, "a walkover is a win until somebody says it is not")
    }
}
