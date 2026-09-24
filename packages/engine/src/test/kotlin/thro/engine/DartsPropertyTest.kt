package thro.engine

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertIs
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * The dart (OD-023), held to the rest of the engine rather than to itself.
 *
 * Three independent statements of the rules meet here: the visit transition (value-based, older,
 * proved exhaustively elsewhere), the dart walk (ring-based, new), and plain enumeration of every
 * hand a player can throw. Each is checked against the others, so a wrong answer has to be wrong in
 * two unrelated ways at once to survive.
 */
class DartsPropertyTest {

    private val a = PlayerId("A")
    private val b = PlayerId("B")

    /** Every dart on the board: miss, 20 singles, 20 doubles, 20 trebles, the outer bull and the bull. */
    private val board: List<Dart> = buildList {
        add(Dart.MISS)
        for (ring in listOf(Ring.SINGLE, Ring.DOUBLE, Ring.TREBLE)) for (n in 1..20) add(Dart(n, ring))
        add(Dart.OUTER_BULL)
        add(Dart.BULL)
    }

    private fun format(out: OutRule, bust: BustRule = BustRule.RESTORE_VISIT) = MatchFormat(
        startingScore = 501, inRule = InRule.STRAIGHT, outRule = out,
        legs = Structure(StructureMode.FIRST_TO, 5), throwFirst = a, bustRule = bust,
    )

    private fun stateAt(remaining: Int, out: OutRule, bust: BustRule = BustRule.RESTORE_VISIT): MatchState {
        val s = MatchState.start(format(out, bust), a, b)
        return s.copy(remaining = s.remaining + (a to remaining))
    }

    private fun hands(maxLength: Int): Sequence<List<Dart>> = sequence {
        var layer = listOf(emptyList<Dart>())
        repeat(maxLength) {
            layer = layer.flatMap { h -> board.map { h + it } }
            yieldAll(layer)
        }
    }

    @Test
    fun `every dart on the board is named and read back as itself`() {
        assertEquals(63, board.toSet().size)
        for (d in board) {
            assertTrue(d.isOnTheBoard, "$d")
            assertEquals(d, Dart.parse(d.name), "round trip of ${d.name}")
        }
        assertEquals(setOf(0) + (1..20) + (1..20).map { 2 * it } + (1..20).map { 3 * it } + setOf(25, 50),
                     board.map { it.value }.toSet())
        // Parsed but not on the board: refused by the engine with a reason, never an exception.
        for (text in listOf("T25", "D0", "T0", "21", "D21")) {
            val d = Dart.parse(text)
            assertTrue(d != null && !d.isOnTheBoard, text)
        }
        for (text in listOf("", "X20", "D", "T+5", "twenty")) assertNull(Dart.parse(text), text)
    }

    /**
     * The heart of it. Under the standard rule, a hand recorded as darts and the same hand recorded
     * as its total must come out the same — EXCEPT where the hand reaches zero on a dart that may not
     * finish, which is precisely what a total cannot see. There, the darts must say bust.
     */
    @Test
    fun `darts and totals agree everywhere the darts do not know more`() {
        var checked = 0
        for (out in OutRule.entries) {
            val from = if (out == OutRule.DOUBLE) 2 else 1
            val threeDartRemainders = listOf(2, 3, 20, 21, 32, 40, 41, 50, 60, 61, 100, 101, 141, 159, 170, 171)
            val cases = (from..182).asSequence().flatMap { rem -> hands(2).map { rem to it } } +
                threeDartRemainders.asSequence().flatMap { rem -> hands(3).filter { it.size == 3 }.map { rem to it } }
            for ((rem, hand) in cases) {
                val byDarts = Engine.apply(stateAt(rem, out), Command.RecordDarts(a, hand))
                if (byDarts !is Outcome.Accepted) continue
                checked++
                val reading = byDarts.reading!!
                val byTotal = Engine.apply(stateAt(rem, out), Command.RecordVisit(a, reading.visitTotal))
                val zeroOnANonFinisher = rem - reading.visitTotal == 0 && !hand.last().mayFinish(out)
                if (zeroOnANonFinisher) {
                    assertEquals(Effect.BUST, byDarts.effect, "$out $rem $hand")
                    assertEquals(BustReason.NOT_A_FINISHING_DART, byDarts.bustReason, "$out $rem $hand")
                    assertEquals(rem, byDarts.state.remaining.getValue(a), "$out $rem $hand")
                } else {
                    assertIs<Outcome.Accepted>(byTotal, "$out $rem $hand total ${reading.visitTotal}")
                    assertEquals(byTotal.effect, byDarts.effect, "$out $rem $hand")
                    assertEquals(byTotal.bustReason, byDarts.bustReason, "$out $rem $hand")
                    assertEquals(byTotal.state.remaining, byDarts.state.remaining, "$out $rem $hand")
                }
            }
        }
        println("darts against totals: $checked hands")
        assertTrue(checked > 1_000_000)
    }

    @Test
    fun `keep-scored darts keeps exactly the darts before the bust and nothing else changes`() {
        for (out in OutRule.entries) {
            for (rem in (if (out == OutRule.DOUBLE) 2 else 1)..182) {
                for (hand in hands(2)) {
                    val restore = Engine.apply(stateAt(rem, out), Command.RecordDarts(a, hand))
                    val keep = Engine.apply(stateAt(rem, out, BustRule.KEEP_SCORED_DARTS), Command.RecordDarts(a, hand))
                    if (restore !is Outcome.Accepted) {
                        assertEquals(restore, keep, "a refusal does not depend on the bust rule")
                        continue
                    }
                    keep as Outcome.Accepted
                    assertEquals(restore.effect, keep.effect)
                    val left = keep.state.remaining.getValue(a)
                    if (restore.effect == Effect.BUST) {
                        val before = hand.take(restore.reading!!.bustAt!!).sumOf { it.value }
                        assertEquals(rem - before, left, "$out $rem $hand")
                        assertEquals(before, keep.reading!!.scored)
                        assertTrue(left > 0 && !(out == OutRule.DOUBLE && left == 1), "$out $rem $hand kept $left")
                    } else {
                        assertEquals(restore.state.remaining, keep.state.remaining, "$out $rem $hand")
                    }
                }
            }
        }
    }

    /**
     * Whether a finish exists with the darts in hand, against brute force: every hand of up to that
     * many darts, walked by the engine. The route table is not consulted by the brute force at all.
     */
    @Test
    fun `a checkout is possible exactly when some hand of that many darts finishes`() {
        for (out in OutRule.entries) {
            val finishableIn = IntArray(3) { 0 }
            for (rem in 1..200) {
                val bruteForce = BooleanArray(4)
                for (hand in hands(3)) {
                    val r = Darts.read(rem, hand, out)
                    if (r.settled == Darts.Settled.LEG_WON && r.thrown == hand.size) {
                        for (n in hand.size..3) bruteForce[n] = true
                    }
                }
                for (n in 1..3) {
                    assertEquals(bruteForce[n], Checkout.isPossible(rem, n, out), "$out $rem with $n darts")
                    if (bruteForce[n]) finishableIn[n - 1]++
                    val route = Checkout.route(rem, n, out)
                    if (route == null) {
                        assertTrue(!bruteForce[n], "$out $rem has a finish in $n and no route")
                        continue
                    }
                    // The route is a real hand: named darts, no longer than the hand, and the engine
                    // itself says it wins the leg on the last one.
                    val darts = route.map { Dart.parse(it) ?: error("route dart '$it' is not a dart") }
                    assertTrue(darts.size <= n)
                    val walked = Darts.read(rem, darts, out)
                    assertEquals(Darts.Settled.LEG_WON, walked.settled, "$out $rem route $route")
                    assertEquals(darts.size, walked.thrown, "$out $rem route $route finishes early")
                }
            }
            println("$out finishable from 1..200 in one/two/three darts: ${finishableIn.toList()}")
        }
    }

    /**
     * After any darts of a visit, the route shown for what is left, with the darts left, is still a
     * finish — including after a dart that makes a different route possible, or none at all.
     */
    @Test
    fun `mid-visit routes are always throwable from where the darts left the player`() {
        val out = OutRule.DOUBLE
        for (rem in 2..170) {
            for (hand in hands(2)) {
                val r = Darts.read(rem, hand, out)
                if (r.settled != null || r.thrown != hand.size) continue
                val route = Checkout.route(r.left, r.dartsLeft, out) ?: continue
                val finish = Darts.read(r.left, route.map { Dart.parse(it)!! }, out)
                assertEquals(Darts.Settled.LEG_WON, finish.settled, "$rem after $hand: ${r.left} via $route")
                assertTrue(route.size <= r.dartsLeft)
            }
        }
        // The cases a player would name. 100: T20 leaves 40, D20 in one. 100: 20 leaves 80, which
        // needs two darts and has two. 100: T20 T20 is below zero — a bust, not a route.
        assertEquals(listOf("D20"), Checkout.route(Darts.read(100, listOf(Dart(20, Ring.TREBLE)), out).left, 2, out))
        assertEquals(listOf("T16", "D16"), Checkout.route(80, 2, out))
        assertNull(Checkout.route(80, 1, out), "80 cannot be finished with one dart")
        assertNull(Checkout.route(159, 3, out), "159 is a bogey")
        assertEquals(listOf("Bull"), Checkout.route(50, 1, out))
    }

    /** A match's rules are its own: two matches, two bust rules, the same darts, no leakage. */
    @Test
    fun `a bust rule belongs to its match`() {
        val bust = listOf(Dart(20, Ring.SINGLE), Dart(15, Ring.DOUBLE))
        val s1 = Engine.apply(stateAt(40, OutRule.DOUBLE), Command.RecordDarts(a, bust)) as Outcome.Accepted
        val l1 = Engine.apply(stateAt(40, OutRule.DOUBLE, BustRule.KEEP_SCORED_DARTS), Command.RecordDarts(a, bust))
            as Outcome.Accepted
        assertEquals(40, s1.state.remaining.getValue(a), "standard: back to where the visit began")
        assertEquals(20, l1.state.remaining.getValue(a), "local: the 20 stands")
        val s2 = (Engine.apply(s1.state, Command.RecordVisit(b, 0)) as Outcome.Accepted).state
        val l2 = (Engine.apply(l1.state, Command.RecordVisit(b, 0)) as Outcome.Accepted).state
        // The same first dart, D10, means different things only because the scores differ: from 20 it
        // is the whole visit, and from 40 it is the first of three.
        val d10 = Dart(10, Ring.DOUBLE)
        val s3 = Engine.apply(s2, Command.RecordDarts(a, listOf(d10, Dart.MISS, Dart.MISS)))
        val l3 = Engine.apply(l2, Command.RecordDarts(a, listOf(d10)))
        assertIs<Outcome.Accepted>(s3)
        assertIs<Outcome.Accepted>(l3)
        assertEquals(Effect.SCORED, s3.effect)
        assertEquals(20, s3.state.remaining.getValue(a), "standard: 40, D10, 20 left")
        assertEquals(Effect.LEG_WON, l3.effect, "local: 20, D10, checked out")
    }

    /** Opening under double-in, from the darts: nothing before the opening double counts. */
    @Test
    fun `under double-in the darts before the opening double score nothing`() {
        val f = format(OutRule.DOUBLE).copy(inRule = InRule.DOUBLE)
        val s = MatchState.start(f, a, b)
        val opened = Engine.apply(s, Command.RecordDarts(a, listOf(Dart(20, Ring.SINGLE), Dart(20, Ring.DOUBLE), Dart(20, Ring.SINGLE))))
        opened as Outcome.Accepted
        assertEquals(441, opened.state.remaining.getValue(a), "20 does not count, D20 and 20 do")
        assertEquals(60, opened.reading!!.visitTotal)
        assertEquals(true, opened.state.opened[a])
        val notIn = Engine.apply(opened.state, Command.RecordDarts(b, List(3) { Dart(20, Ring.TREBLE) }))
        notIn as Outcome.Accepted
        assertEquals(501, notIn.state.remaining.getValue(b), "three trebles do not open a double-in leg")
        assertEquals(false, notIn.state.opened[b])
    }
}
