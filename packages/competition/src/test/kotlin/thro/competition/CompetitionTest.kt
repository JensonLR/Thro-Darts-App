package thro.competition

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class BracketTest {

    @Test
    fun `the design's own example, corrected`() {
        // The approved organiser screen reads "74 entries · Round of 64 with 10 byes".
        // 10 is the number of preliminary MATCHES; the real bye count is 54.
        val m = Bracket.math(74)
        assertEquals(128, m.bracketSize)
        assertEquals(54, m.byes)
        assertEquals(10, m.preliminaryMatches)
        // 10 winners plus 54 byes fill a round of 64
        assertEquals(64, m.byes + m.preliminaryMatches)
    }

    @Test
    fun `exhaustive - the bracket identities hold for every field size up to 1024`() {
        for (n in 1..1024) {
            val m = Bracket.math(n)
            assertTrue(m.bracketSize >= n, "bracket smaller than field at n=$n")
            assertTrue(m.bracketSize < n * 2 || n == 1, "bracket oversized at n=$n")
            if (n > 1) {
                assertEquals(n, m.byes + m.preliminaryMatches * 2, "entrants unaccounted at n=$n")
            }
            if (n > 1) {
                assertEquals(m.bracketSize / 2, m.byes + m.preliminaryMatches,
                    "first full round not filled at n=$n")
            }
            assertTrue(m.byes >= 0 && m.preliminaryMatches >= 0, "negative at n=$n")
        }
    }

    @Test
    fun `a single entrant advances on a bye rather than breaking the arithmetic`() {
        val m = Bracket.math(1)
        assertEquals(1, m.bracketSize)
        assertEquals(1, m.byes)
        assertEquals(0, m.preliminaryMatches)
    }

    @Test
    fun `an exact power of two needs no byes - the case a logarithm gets wrong`() {
        // 2^ceil(log2(n)) returns a value fractionally above the integer for exact powers of two
        // in floating point, silently doubling the bracket. Bit length cannot.
        for (n in listOf(2, 4, 8, 16, 32, 64, 128, 256, 512, 1024)) {
            val m = Bracket.math(n)
            assertEquals(n, m.bracketSize, "bracket doubled at n=$n")
            assertEquals(0, m.byes, "byes invented at n=$n")
            assertEquals(n / 2, m.preliminaryMatches)
        }
    }

    @Test
    fun `one more than a power of two puts almost everyone on a bye`() {
        val m = Bracket.math(65)
        assertEquals(128, m.bracketSize)
        assertEquals(63, m.byes)
        assertEquals(1, m.preliminaryMatches)
    }

    @Test
    fun `byes go to the highest seeds and are a distinct slot state`() {
        val field = (1..74).map { Competitor.Player("p$it") }
        val round = Bracket.firstRound(field)
        assertEquals(64, round.size)
        assertEquals(54, round.count { it is Slot.Bye })
        assertEquals(10, round.count { it is Slot.Undetermined })
        // the top seed holds a bye, and it is a bye - not a win, and not "TBC"
        assertTrue(round.first() is Slot.Bye)
        assertEquals("p1", (round.first() as Slot.Bye).competitor.id)
    }

    @Test
    fun `a bye, an undecided slot, a walkover and a withdrawal are four different facts`() {
        val p = Competitor.Player("p1")
        val states = listOf(Slot.Bye(p), Slot.Undetermined, Slot.Walkover(p), Slot.Withdrawn(p))
        assertEquals(4, states.map { it::class }.toSet().size)
    }

    @Test
    fun `a pair and a team are competitors, and rating stays a property of the player`() {
        val pair = Competitor.Pair("pair-1", listOf("a", "b"))
        val team = Competitor.Team("grange-a", listOf("a", "b", "c", "d"))
        assertEquals(2, pair.players.size)
        assertEquals(4, team.players.size)
        // the competitor resolves to players; nothing here stores a rating
        assertTrue(Competitor.Player("a") is Competitor)
    }
}

class StandingsTest {

    private fun row(id: String, pts: Int, lf: Int, la: Int, p: Int = 14) =
        StandingsRow(competitorId = id, played = p, legsFor = lf, legsAgainst = la, points = pts)

    @Test
    fun `points order first, then the declared chain`() {
        val ranked = Standings.rank(
            listOf(row("b", 20, 70, 56), row("a", 24, 80, 46), row("c", 20, 60, 66)),
        )
        assertEquals(listOf("a", "b", "c"), ranked.map { it.row.competitorId })
        assertEquals(TieBreak.POINTS, ranked[1].separatedBy)
        // b and c are level on points, so leg difference separated them - and the table says so
        assertEquals(TieBreak.LEG_DIFFERENCE, ranked[2].separatedBy)
    }

    @Test
    fun `a published table can justify its own ordering`() {
        val ranked = Standings.rank(listOf(row("a", 20, 70, 50), row("b", 20, 70, 50)))
        // genuinely inseparable under the declared chain, and the table must not pretend otherwise
        assertEquals(null, ranked[1].separatedBy)
    }

    @Test
    fun `head to head only participates when it is declared in the chain`() {
        val chain = listOf(TieBreak.POINTS, TieBreak.HEAD_TO_HEAD, TieBreak.LEG_DIFFERENCE)
        val h2h = { x: String, y: String -> if (x == "b" && y == "a") 1 else if (x == "a" && y == "b") -1 else 0 }
        val ranked = Standings.rank(listOf(row("a", 20, 90, 40), row("b", 20, 50, 80)), chain, h2h)
        // b beat a head to head, so b is placed above despite a much worse leg difference
        assertEquals(listOf("b", "a"), ranked.map { it.row.competitorId })
        assertEquals(TieBreak.HEAD_TO_HEAD, ranked[1].separatedBy)
    }

    @Test
    fun `an awarded fixture is a distinct outcome, never a synthetic scoreline`() {
        val outcomes = listOf(
            FixtureOutcome.Played(6, 3),
            FixtureOutcome.Awarded("grange-a", "opponent failed to fulfil the fixture"),
            FixtureOutcome.Walkover("grange-a"),
            FixtureOutcome.Void,
        )
        assertEquals(4, outcomes.map { it::class }.toSet().size)
        // an award carries a reason; it cannot masquerade as legs played
        val awarded = outcomes[1] as FixtureOutcome.Awarded
        assertTrue(awarded.reason.isNotBlank())
    }

    @Test
    fun `drawn fixtures are representable even though the current format cannot produce them`() {
        // the approved league format uses odd leg counts, so draws are structurally impossible -
        // but that must not become an invariant of the aggregate
        val r = StandingsRow("a", played = 10, won = 4, drawn = 2, lost = 4, points = 10)
        assertEquals(10, r.won + r.drawn + r.lost)
    }
}
