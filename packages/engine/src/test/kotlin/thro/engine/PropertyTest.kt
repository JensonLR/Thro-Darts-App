package thro.engine

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlin.test.fail

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

    /**
     * Double-in, and the capture rule that makes it scorable at visit granularity (PD-008).
     *
     * The founder asked for it because leagues and tournaments play it. The engine works on visits,
     * not darts, so before this it refused the format rather than score it as straight-in and be
     * silently wrong (OD-015). PD-008 settled the rule: a visit thrown while the player has not
     * opened records the score FROM the opening dart onward, and zero means they did not open. That
     * is what the scorer calls at the oche and it costs no statistic, because a visit is three darts
     * whether it opened or not.
     *
     * Everything below is derived from the generated table, never listed here — the table is
     * enumerated from the dartboard, and enumeration corrected two guesses that seemed obvious: the
     * bull opens (so the largest opening total is D25 + T20 + T20 = 170, not 160), and 41 IS
     * openable (D1 then 19 and 20).
     */
    @Test
    fun `under double-in nothing scores until a player opens, and only an opening total can`() {
        val format = MatchFormat(
            startingScore = 501, inRule = InRule.DOUBLE, outRule = OutRule.DOUBLE,
            legs = Structure(StructureMode.FIRST_TO, 2), throwFirst = PlayerId("A"),
        )
        val a = PlayerId("A")
        val b = PlayerId("B")
        val start = MatchState.start(format, a, b)
        assertEquals(false, start.opened.getValue(a), "double-in starts closed")
        assertEquals(false, start.opened.getValue(b))
        assertTrue(InRule.DOUBLE.requiresOpening)
        assertTrue(InRule.MASTER.requiresOpening)
        assertFalse(InRule.STRAIGHT.requiresOpening)

        // Straight-in is open from the first dart, and every total three darts can make is an
        // opening total, so nothing about it changes.
        val open = MatchState.start(format.copy(inRule = InRule.STRAIGHT), a, b)
        assertEquals(true, open.opened.getValue(a))
        assertEquals(
            RuleTables.openingTotals(InRule.STRAIGHT),
            (1..180).filter { it !in RuleTables.IMPOSSIBLE_VISIT_TOTALS }.toSet(),
        )

        // A visit that does not open scores nothing and does not open the player.
        val missed = Engine.apply(start, Command.RecordVisit(a, 0))
        val afterMiss = assertIs<Outcome.Accepted>(missed)
        assertEquals(Effect.SCORED, afterMiss.effect)
        assertEquals(501, afterMiss.state.remaining.getValue(a), "nothing counts before the double")
        assertEquals(false, afterMiss.state.opened.getValue(a), "and they are still not in")
        assertEquals(b, afterMiss.state.thrower, "the turn still rotates")

        // A total no opening sequence can make is refused — and it is a DIFFERENT refusal from a
        // total three darts cannot make, because 180 is perfectly possible once you are in.
        assertTrue(180 in (0..180).filterNot { it in RuleTables.IMPOSSIBLE_VISIT_TOTALS })
        assertEquals(
            Outcome.Rejected(RejectionReason.IMPOSSIBLE_OPENING_TOTAL),
            Engine.apply(start, Command.RecordVisit(a, 180)),
            "three trebles cannot open a double-in leg",
        )
        assertEquals(
            Outcome.Rejected(RejectionReason.IMPOSSIBLE_VISIT_TOTAL),
            Engine.apply(start, Command.RecordVisit(a, 179)),
            "and a total no three darts can make is still that, not an opening problem",
        )
        // Every unopenable total is refused, and every opening total is accepted. Both directions,
        // over the whole range, so neither the table nor the guard can be trimmed unnoticed.
        for (total in 0..180) {
            val outcome = Engine.apply(start, Command.RecordVisit(a, total))
            val openable = total == 0 || total in RuleTables.openingTotals(InRule.DOUBLE)
            if (openable) {
                assertIs<Outcome.Accepted>(outcome, "$total can open a double-in leg")
            } else {
                assertIs<Outcome.Rejected>(outcome, "$total cannot open a double-in leg")
            }
        }
        assertEquals(170, RuleTables.openingTotals(InRule.DOUBLE).max(), "the bull opens: D25+T20+T20")
        assertTrue(41 in RuleTables.openingTotals(InRule.DOUBLE), "D1 then 19 and 20")
        assertFalse(1 in RuleTables.openingTotals(InRule.DOUBLE), "the smallest double is 2")
        assertEquals(180, RuleTables.openingTotals(InRule.MASTER).max(), "master-in admits trebles")

        // Opening scores from the opening dart onward, and the player stays open for the leg.
        val opened = assertIs<Outcome.Accepted>(Engine.apply(afterMiss.state, Command.RecordVisit(b, 40)))
        assertEquals(461, opened.state.remaining.getValue(b))
        assertEquals(true, opened.state.opened.getValue(b))
        // A is still closed, so 180 is still refused for A even though B is in: opening is per player.
        assertEquals(
            Outcome.Rejected(RejectionReason.IMPOSSIBLE_OPENING_TOTAL),
            Engine.apply(opened.state, Command.RecordVisit(a, 180)),
            "one player opening does not open the other",
        )
        val aIn = assertIs<Outcome.Accepted>(Engine.apply(opened.state, Command.RecordVisit(a, 40)))
        assertEquals(461, aIn.state.remaining.getValue(a))
        assertEquals(true, aIn.state.opened.getValue(a))
        val again = assertIs<Outcome.Accepted>(Engine.apply(aIn.state, Command.RecordVisit(b, 180)))
        assertEquals(281, again.state.remaining.getValue(b), "180 is fine once you are in")

        // A new leg closes the door again, for both players.
        var s = MatchState.start(format.copy(startingScore = 40), a, b)
        val won = assertIs<Outcome.Accepted>(Engine.apply(s, Command.RecordVisit(a, 40, dartsUsed = 1, dartsAtDouble = 1)))
        assertEquals(Effect.LEG_WON, won.effect)
        assertEquals(false, won.state.opened.getValue(a), "a new leg is a new opening")
        assertEquals(false, won.state.opened.getValue(b))

        // A bust reverts the score, never the opening: the double was thrown and it landed.
        s = MatchState.start(format.copy(startingScore = 30), a, b)
        val bust = assertIs<Outcome.Accepted>(Engine.apply(s, Command.RecordVisit(a, 40)))
        assertEquals(Effect.BUST, bust.effect)
        assertEquals(30, bust.state.remaining.getValue(a))
        assertEquals(true, bust.state.opened.getValue(a), "opening survives the bust that follows it")
    }

    /**
     * The checkout routes THRØ shows (PD-013).
     *
     * Which route is best is a preference and the app takes a position on it. Whether a route is a
     * LEGAL FINISH is not a preference, and that is what this holds — arithmetically, for every
     * route in every rule, rather than against a chart somebody typed. It also proves the encoded
     * table survived being parsed, which is the one thing the generator cannot check for us.
     */
    @Test
    fun `every route THRO shows is a legal finish of exactly that remaining`() {
        val throwScore = buildMap {
            for (n in 1..20) { put("$n", n); put("D$n", 2 * n); put("T$n", 3 * n) }
            put("25", 25); put("Bull", 50)
        }
        val finishers = mapOf(
            OutRule.DOUBLE to (2..40 step 2).toSet() + 50,
            OutRule.MASTER to (2..40 step 2).toSet() + 50 + (3..60 step 3).toSet(),
            OutRule.STRAIGHT to (1..20).toSet() + (2..40 step 2).toSet() + (3..60 step 3).toSet() + 25 + 50,
        )
        for (rule in OutRule.entries) {
            val checkouts = RuleTables.checkouts(rule)
            for (remaining in checkouts) {
                val route = RuleTables.route(remaining, rule)
                assertNotNull(route, "$rule $remaining has no route")
                assertTrue(route.size in 1..3, "$rule $remaining is ${route.size} darts: $route")
                val scores = route.map { throwScore[it] ?: fail("$rule $remaining: '$it' is not a throw") }
                assertEquals(remaining, scores.sum(), "$rule $remaining: $route does not sum to it")
                assertTrue(scores.last() in finishers.getValue(rule),
                           "$rule $remaining: $route does not finish on a legal segment")
                for (i in 0 until scores.size - 1) {
                    assertTrue(scores.take(i + 1).sum() < remaining,
                               "$rule $remaining: $route finishes before its last dart")
                }
            }
            // A number with no finish is offered no route, rather than a route that cannot be thrown.
            for (bogey in 1..180) {
                if (bogey !in checkouts) assertNull(RuleTables.route(bogey, rule), "$rule $bogey is a bogey")
            }
        }
    }

    /** A handful anyone who plays darts can check by eye. If the rule stops producing them, look. */
    @Test
    fun `the conventional finishes are the conventional finishes`() {
        val known = mapOf(
            170 to "T20 T20 Bull", 167 to "T20 T19 Bull", 164 to "T20 T18 Bull", 161 to "T20 T17 Bull",
            160 to "T20 T20 D20", 158 to "T20 T20 D19", 141 to "T20 T19 D12", 110 to "T20 Bull",
            100 to "T20 D20", 96 to "T20 D18", 90 to "T18 D18", 81 to "T19 D12", 60 to "20 D20",
            50 to "Bull", 41 to "9 D16", 40 to "D20", 32 to "D16", 2 to "D1",
        )
        for ((remaining, want) in known) {
            assertEquals(want, RuleTables.route(remaining, OutRule.DOUBLE)?.joinToString(" "), "$remaining")
        }
    }
}
