package thro.engine

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Property tests over the whole transition space.
 *
 * The X01 transition table is small enough to enumerate exhaustively — every reachable remaining
 * against every achievable visit total — so these are closer to proofs than to samples. That
 * matters because the rule implementations most often drop accounts for eight cases in eighty-six
 * thousand, which no hand-written test would ever stumble on.
 */
class PropertyTest {

    private val a = PlayerId("A")
    private val b = PlayerId("B")

    private fun format(out: OutRule = OutRule.DOUBLE, start: Int = 501) = MatchFormat(
        startingScore = start,
        inRule = InRule.STRAIGHT,
        outRule = out,
        legs = Structure(StructureMode.FIRST_TO, 5),
        throwFirst = a,
    )

    private fun stateAt(remaining: Int, out: OutRule = OutRule.DOUBLE): MatchState {
        val s = MatchState.start(format(out), a, b)
        return s.copy(remaining = s.remaining + (a to remaining))
    }

    private val achievable: List<Int> =
        (0..RuleTables.MAX_VISIT_TOTAL).filter { it !in RuleTables.IMPOSSIBLE_VISIT_TOTALS }

    @Test
    fun `exhaustive - a scored visit never leaves a negative remaining or one`() {
        var scored = 0
        for (rem in 2..501) {
            for (vt in achievable) {
                val r = Engine.apply(stateAt(rem), Command.RecordVisit(a, vt))
                if (r is Outcome.Accepted && r.effect == Effect.SCORED) {
                    val left = r.state.remaining.getValue(a)
                    assertTrue(left > 0, "remaining $left after scoring $vt from $rem")
                    assertTrue(left != 1, "remaining 1 is unreachable under double-out ($vt from $rem)")
                    scored++
                }
            }
        }
        println("exhaustive scored transitions checked: $scored")
    }

    @Test
    fun `exhaustive - a bust always restores the pre-visit remaining exactly`() {
        var busts = 0
        for (rem in 2..501) {
            for (vt in achievable) {
                val r = Engine.apply(stateAt(rem), Command.RecordVisit(a, vt))
                if (r is Outcome.Accepted && r.effect == Effect.BUST) {
                    assertEquals(rem, r.state.remaining.getValue(a), "bust did not restore $rem")
                    assertNotNull(r.bustReason)
                    busts++
                }
            }
        }
        println("exhaustive bust transitions checked: $busts")
    }

    @Test
    fun `exhaustive - bust is impossible at or above the stated threshold`() {
        for (rem in RuleTables.BUST_IMPOSSIBLE_AT_OR_ABOVE..501) {
            for (vt in achievable) {
                val r = Engine.apply(stateAt(rem), Command.RecordVisit(a, vt))
                assertTrue(
                    r !is Outcome.Accepted || r.effect != Effect.BUST,
                    "bust occurred at remaining $rem with visit $vt",
                )
            }
        }
    }

    @Test
    fun `the exact-zero bust set is precisely the eight known values`() {
        val found = (2..501).filter { rem ->
            val r = Engine.apply(stateAt(rem), Command.RecordVisit(a, rem))
            r is Outcome.Accepted && r.bustReason == BustReason.NOT_CHECKOUT_POSSIBLE
        }
        assertEquals(listOf(159, 162, 165, 168, 171, 174, 177, 180), found)
    }

    @Test
    fun `a leg is won only from a finishable remaining`() {
        val checkouts = RuleTables.checkouts(OutRule.DOUBLE)
        for (rem in 2..501) {
            val r = Engine.apply(stateAt(rem), Command.RecordVisit(a, rem))
            val won = r is Outcome.Accepted &&
                (r.effect == Effect.LEG_WON || r.effect == Effect.MATCH_WON)
            assertEquals(rem in checkouts, won, "leg-won disagreement at remaining $rem")
        }
    }

    @Test
    fun `master out reaches 180 where double out stops at 170`() {
        assertTrue(Engine.apply(stateAt(180, OutRule.MASTER), Command.RecordVisit(a, 180))
            .let { it is Outcome.Accepted && it.effect != Effect.BUST })
        assertTrue(Engine.apply(stateAt(180, OutRule.DOUBLE), Command.RecordVisit(a, 180))
            .let { it is Outcome.Accepted && it.effect == Effect.BUST })
    }

    @Test
    fun `the engine is deterministic`() {
        for (rem in 2..501 step 7) {
            for (vt in achievable) {
                val one = Engine.apply(stateAt(rem), Command.RecordVisit(a, vt))
                val two = Engine.apply(stateAt(rem), Command.RecordVisit(a, vt))
                assertEquals(one, two)
            }
        }
    }

    @Test
    fun `darts used may be fewer than three only on a leg-winning visit`() {
        // 40 finishes; one dart is legitimate
        assertTrue(Engine.apply(stateAt(40), Command.RecordVisit(a, 40, dartsUsed = 1))
            is Outcome.Accepted)
        // a visit that does not finish cannot have used one dart
        val r = Engine.apply(stateAt(200), Command.RecordVisit(a, 60, dartsUsed = 1))
        assertEquals(RejectionReason.DARTS_USED_INVALID, (r as Outcome.Rejected).reason)
        // unknown is always permitted; it is never inferred
        assertTrue(Engine.apply(stateAt(200), Command.RecordVisit(a, 60, dartsUsed = null))
            is Outcome.Accepted)
        // zero darts is not a visit
        assertEquals(
            RejectionReason.DARTS_USED_INVALID,
            (Engine.apply(stateAt(40), Command.RecordVisit(a, 40, dartsUsed = 0)) as Outcome.Rejected).reason,
        )
    }

    @Test
    fun `turn passes to the opponent after every resolved visit including a bust`() {
        for (vt in listOf(60, 180, 0)) {
            val r = Engine.apply(stateAt(200), Command.RecordVisit(a, vt)) as Outcome.Accepted
            assertEquals(b, r.state.thrower)
        }
        val bust = Engine.apply(stateAt(50), Command.RecordVisit(a, 60)) as Outcome.Accepted
        assertEquals(Effect.BUST, bust.effect)
        assertEquals(b, bust.state.thrower)
    }

    @Test
    fun `leg start alternates so the opener of leg one also opens the decider`() {
        var s = MatchState.start(format(), a, b)
        val starters = mutableListOf(s.legStarter)
        repeat(4) {
            // whoever is due to throw wins the leg outright
            val p = s.thrower!!
            s = (Engine.apply(s.copy(remaining = s.remaining + (p to 40)),
                Command.RecordVisit(p, 40, 2)) as Outcome.Accepted).state
            if (!s.isComplete) starters += s.legStarter
        }
        assertEquals(listOf(a, b, a, b, a), starters)
    }

    @Test
    fun `a completed match rejects further visits`() {
        var s = MatchState.start(format().copy(legs = Structure(StructureMode.FIRST_TO, 1)), a, b)
        s = (Engine.apply(s.copy(remaining = s.remaining + (a to 40)),
            Command.RecordVisit(a, 40, 2)) as Outcome.Accepted).state
        assertTrue(s.isComplete)
        assertNull(s.thrower)
        assertEquals(
            RejectionReason.MATCH_COMPLETE,
            (Engine.apply(s, Command.RecordVisit(a, 60)) as Outcome.Rejected).reason,
        )
    }

    @Test
    fun `best of nine requires five legs`() {
        assertEquals(5, Structure(StructureMode.BEST_OF, 9).winsRequired)
        assertEquals(5, Structure(StructureMode.FIRST_TO, 5).winsRequired)
        assertEquals(2, Structure(StructureMode.BEST_OF, 3).winsRequired)
    }
}
