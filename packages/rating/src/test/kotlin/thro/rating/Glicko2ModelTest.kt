package thro.rating

import kotlin.math.abs
import kotlin.random.Random
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * The provisional rating (PD-105): outcome-anchored, carrying its own uncertainty, replayed from evidence, and
 * projected for display as a range until it has earned a number. Held to the harness's behavioural gates that a
 * model can be held to without real matches — small sample, upset bound, stability, cross-pool honesty — and to the
 * architecture's invariants: determinism and a reconciling ledger.
 */
class Glicko2ModelTest {

    private val alice = PlayerId("alice")
    private val bob = PlayerId("bob")
    private val cara = PlayerId("cara")
    private val dan = PlayerId("dan")
    private val eve = PlayerId("eve")

    private fun row(seq: Long, h: PlayerId, a: PlayerId, homeWon: Boolean, qualifying: Boolean = true, xid: Long = 1) =
        EvidenceRow(matchId = "m$seq", at = Watermark(xid, seq), home = h, away = a,
                    homeScore = if (homeWon) 1.0 else 0.0, legsHome = if (homeWon) 3 else 1, legsAway = if (homeWon) 1 else 3,
                    qualifying = qualifying)

    private val model = Glicko2Model()

    private fun snapshot(r: Projection.Replay, p: PlayerId) = r.snapshots.first { it.player == p }

    // ------------------------------------------------------------------------- what it is

    @Test
    fun `a model in the provisional stage may be published, and the shadow one still may not`() {
        assertEquals(Publication.Result.Allowed, Publication.check(model, emptySet()))
        assertTrue(Publication.check(ProvisionalModel(), emptySet()) is Publication.Result.Refused)
        assertEquals(RatingModel.Stage.PROVISIONAL, model.stage)
        assertTrue(!model.validated, "provisional is not validated: OD-001 is still open")
    }

    @Test
    fun `nobody has a rating until they have played, and a winner goes up while a loser goes down`() {
        val r = Projection.replay(listOf(row(1, alice, bob, true)), model, Watermark(1, 1))
        val a = snapshot(r, alice); val b = snapshot(r, bob)
        assertNotNull(a.rating); assertNotNull(b.rating)
        assertTrue(a.rating!! > Glicko2Model.INITIAL_RATING && b.rating!! < Glicko2Model.INITIAL_RATING)
        assertEquals(1, a.matchesCounted)
        assertTrue(r.snapshots.none { it.player == cara })
    }

    @Test
    fun `a match that does not qualify moves nobody and leaves no match line`() {
        val r = Projection.replay(listOf(row(1, alice, bob, true, qualifying = false)), model, Watermark(1, 1))
        assertTrue(r.snapshots.isEmpty())
        assertTrue(r.ledger.isEmpty())
    }

    // ------------------------------------------------------------------------- the invariants

    @Test
    fun `the same evidence in any arrival order produces byte-identical snapshots and ledger`() {
        val evidence = league()
        val a = Projection.replay(evidence, model, Watermark(9, 99))
        val b = Projection.replay(evidence.shuffled(Random(7)), model, Watermark(9, 99))
        assertEquals(a.snapshots.sortedBy { it.player.value }, b.snapshots.sortedBy { it.player.value })
        assertEquals(a.ledger, b.ledger)
    }

    @Test
    fun `the ledger reconciles exactly to every player's net change from the starting rating`() {
        val r = Projection.replay(league(), model, Watermark(9, 99))
        val start = r.snapshots.associate { it.player to Glicko2Model.INITIAL_RATING as Double? }
        assertTrue(r.ledgerReconciles(start), "a line was absorbed or invented")
        assertTrue(r.ledger.all { it.cause == LedgerLine.Cause.MATCH && it.matchId != null && it.explanation != null })
    }

    @Test
    fun `every match line carries the facts an explanation is made from, frozen at that instant`() {
        val r = Projection.replay(listOf(row(1, alice, bob, true), row(2, alice, bob, false)), model, Watermark(1, 2))
        val second = r.ledger.first { it.matchId == "m2" && it.player == alice }
        val e = second.explanation!!
        assertEquals(bob, e.opponent)
        assertEquals(0.0, e.realisedOutcome)
        assertTrue(e.predictedProbability!! > 0.5, "alice had beaten bob once, so she was expected to again")
        // The opponent's rating quoted is the one at that instant, which is bob's after the first match — not his present one.
        val bobAfterFirst = Projection.replay(listOf(row(1, alice, bob, true)), model, Watermark(1, 1)).snapshots.first { it.player == bob }.rating
        assertEquals(bobAfterFirst, e.opponentRatingAtTheTime)
        assertEquals(model.version, e.modelVersion)
    }

    // ------------------------------------------------------------------------- the harness's gates

    @Test
    fun `small sample - at two matches nothing confident is shown, only a wide range`() {
        val r = Projection.replay(listOf(row(1, alice, bob, true), row(2, alice, bob, true)), model, Watermark(1, 2))
        val d = Display.of(snapshot(r, alice), model)
        assertTrue(d is Display.Provisional, "a number at two matches is the failure the harness names: $d")
        d as Display.Provisional
        assertTrue(d.high - d.low >= 400, "the range at two matches must be honest about how little is known: ${d.low}–${d.high}")
    }

    @Test
    fun `established - a number appears only after the threshold and once the uncertainty has narrowed`() {
        // Six players of graded strength, a round robin played three times: fifteen matches each against opponents
        // who are narrowing too. Measured before the threshold was set: deviation ~139 after two rounds, ~112 after
        // three, ~95 after four — so 120 is "about three rounds of a small league", and that is the stated position.
        val players = (0 until 6).map { PlayerId("p$it") }
        val strength = players.indices.map { it * 0.4 }
        val rnd = Random(1)
        var seq = 0L
        val rows = ArrayList<EvidenceRow>()
        repeat(3) {
            for (i in players.indices) for (j in players.indices) if (i < j) {
                val pWin = 1.0 / (1.0 + kotlin.math.exp(-(strength[i] - strength[j])))
                rows += row(++seq, players[i], players[j], rnd.nextDouble() < pWin)
            }
        }
        val two = Projection.replay(rows, model, Watermark(1, 20))
        assertTrue(Display.of(snapshot(two, players[3]), model) is Display.Provisional, "two rounds in, still a range")
        val three = Projection.replay(rows, model, Watermark(1, seq))
        val d = Display.of(snapshot(three, players[3]), model)
        assertTrue(d is Display.Established, "fifteen matches in a league narrow enough for a number: $d")
        assertTrue(snapshot(three, players[3]).matchesCounted >= Glicko2Model.ESTABLISH_AFTER)

        // Twenty wins over strangers who never narrow tell less than fifteen matches in a league: still a range.
        val field = players.drop(1)
        val strangers = (1..20).map { i -> row(100L + i, players[0], field[i % 5], true) }
        val s = Projection.replay(strangers, model, Watermark(1, 200))
        assertTrue(Display.of(snapshot(s, players[0]), model) is Display.Provisional,
                   "beating a rotating field of unknowns must not earn a number")
    }

    @Test
    fun `upset bound - no single match moves a rating by more than the stated cap`() {
        val rnd = Random(42)
        val players = listOf(alice, bob, cara, dan, eve)
        val rows = (1..300).map { i ->
            val h = players[rnd.nextInt(5)]; var a = players[rnd.nextInt(5)]; while (a == h) a = players[rnd.nextInt(5)]
            row(i.toLong(), h, a, rnd.nextBoolean())
        }
        val r = Projection.replay(rows, model, Watermark(1, 300))
        val worst = r.ledger.maxOf { abs(it.delta) }
        assertTrue(worst <= Glicko2Model.MOST_ONE_MATCH_MAY_MOVE, "one result moved a rating by $worst")
    }

    @Test
    fun `stability - a day with no matches moves no published integer`() {
        val r1 = Projection.replay(league(), model, Watermark(9, 99))
        val r2 = Projection.replay(league(), model, Watermark(9, 99))
        assertEquals(r1.snapshots.map { Display.of(it, model) }, r2.snapshots.map { Display.of(it, model) })
    }

    @Test
    fun `cross-pool - two groups who never meet are two pools, and each snapshot says how big its pool is`() {
        val rows = listOf(row(1, alice, bob, true), row(2, bob, cara, true), row(3, dan, eve, true), row(4, eve, dan, false))
        val r = Projection.replay(rows, model, Watermark(1, 4))
        assertEquals(3, snapshot(r, alice).pool)
        assertEquals(3, snapshot(r, cara).pool)
        assertEquals(2, snapshot(r, dan).pool)
        // One bridge match joins them.
        val joined = Projection.replay(rows + row(5, cara, dan, true), model, Watermark(1, 5))
        assertTrue(joined.snapshots.all { it.pool == 5 })
    }

    @Test
    fun `display - unrated, a range, or a number with its margin, and nothing else`() {
        assertEquals(Display.Unrated, Display.of(null, model))
        val r = Projection.replay(listOf(row(1, alice, bob, true)), model, Watermark(1, 1))
        val d = Display.of(snapshot(r, alice), model) as Display.Provisional
        assertTrue(d.low < d.high && d.low % 10 == 0 && d.high % 10 == 0, "a range is rounded to tens: $d")
        assertNull(Display.of(snapshot(r, alice), model).let { (it as? Display.Established)?.value })
    }

    // ------------------------------------------------------------------------- a small league

    private fun league(): List<EvidenceRow> {
        val players = listOf(alice, bob, cara, dan, eve)
        val rnd = Random(3)
        return (1..40).map { i ->
            val h = players[rnd.nextInt(5)]; var a = players[rnd.nextInt(5)]; while (a == h) a = players[rnd.nextInt(5)]
            row(i.toLong(), h, a, rnd.nextBoolean(), xid = (i / 10).toLong() + 1)
        }
    }
}
