package thro.stats

import kotlin.math.abs
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * The point of these tests is not that the arithmetic is right — it is that a statistic which
 * cannot be honestly computed **says so**, and that one which is only approximate never presents
 * itself as a fact.
 */
class StatisticsTest {

    private fun v(
        leg: Int, ord: Int, total: Int, darts: Int? = 3,
        before: Int, after: Int, won: Boolean = false, bust: Boolean = false,
        atDouble: Int? = null,
    ) = VisitRecord(leg, ord, total, darts, bust, before, after, won, atDouble)

    /** Double-out checkout numbers: everything to 170 except the seven bogeys. */
    private val checkable = (2..170).toSet() - setOf(159, 162, 163, 165, 166, 168, 169)

    /** A 501 leg won in 15 darts: 180, 180, 141 with the last visit using all three darts. */
    private fun nineDartLeg(darts: Int? = 3) = listOf(
        v(1, 1, 180, 3, 501, 321),
        v(1, 2, 180, 3, 321, 141),
        v(1, 3, 141, darts, 141, 0, won = true),
    )

    @Test
    fun `never standing on a finish is reported differently from not having said`() {
        // A player who was never on a finish threw no darts at a double. Telling them their
        // attempts "were not recorded" describes missing evidence that does not exist.
        val neverOnAFinish = listOf(v(1, 1, 60, 3, 501, 441), v(1, 2, 60, 3, 441, 381))
        val a = Statistics.doublesAttempted(neverOnAFinish, checkable)
        assertEquals(Basis.UNAVAILABLE, a.basis)
        assertTrue(a.note!!.contains("finishable"), "wrong reason given: ${a.note}")

        val onAFinishButSilent = listOf(v(1, 1, 20, 3, 40, 20))
        val b = Statistics.doublesAttempted(onAFinishButSilent, checkable)
        assertEquals(Basis.UNAVAILABLE, b.basis)
        assertTrue(b.note!!.contains("recorded"), "wrong reason given: ${b.note}")
    }

    @Test
    fun `doubles attempted does not report a partial count as a match total`() {
        // Two visits stood on a finish; only one said how many darts it threw at a double. The
        // recorded sum is 2, but the match total is not 2 — reporting it as exact would state a
        // partial count as a fact.
        val visits = listOf(
            v(1, 1, 20, 3, 40, 20, atDouble = 2),               // recorded
            v(1, 2, 20, 2, 20, 0, won = true, atDouble = null), // on a finish, did not say
        )
        val s = Statistics.doublesAttempted(visits, checkable)
        assertEquals(Basis.BOUNDED, s.basis)
        assertEquals(3.0, s.lower)   // the winning visit threw at least one
        assertEquals(5.0, s.upper)   // and at most three
        assertNull(s.value, "a bounded figure must not also carry a point value")
    }

    @Test
    fun `a bounded checkout percentage can never exceed 100 percent`() {
        // A leg-winning visit whose attempts went unrecorded still counts as a hit. If the bound
        // ignores that it also threw at least one dart at a double, the numerator grows while the
        // denominator does not, and the upper bound climbs past 100% — a figure the quantity
        // cannot take. Under double-out the winning dart IS a double, so that attempt is known to
        // have happened even when its count was not recorded.
        val visits = listOf(
            v(1, 1, 20, 3, 40, 20, atDouble = 1),              // recorded miss
            v(1, 2, 20, 2, 20, 0, won = true, atDouble = null), // won, attempts unrecorded
            v(2, 1, 40, 2, 40, 0, won = true, atDouble = null), // won, attempts unrecorded
        )
        val s = Statistics.checkoutPercentage(visits, checkable)
        assertEquals(Basis.BOUNDED, s.basis)
        assertNotNull(s.upper)
        assertTrue(s.upper!! <= 100.0, "upper bound was ${s.upper}%")
        assertTrue(s.lower!! <= s.upper!!, "bounds inverted")
    }

    @Test
    fun `bounds hold across every mixture of recorded and unrecorded attempts`() {
        // Exhaustive over small shapes: whatever the unrecorded visits actually threw, the true
        // percentage must lie inside the reported interval, and the interval must stay in range.
        var checked = 0
        for (wins in 0..3) for (misses in 0..3) for (unrecordedWins in 0..wins) {
            val recordedWins = wins - unrecordedWins
            val visits = buildList {
                repeat(recordedWins) { add(v(it + 1, 1, 40, 2, 40, 0, won = true, atDouble = 1)) }
                repeat(unrecordedWins) { add(v(100 + it, 1, 40, 2, 40, 0, won = true)) }
                repeat(misses) { add(v(200 + it, 1, 20, 3, 40, 20, atDouble = 1)) }
            }
            val s = Statistics.checkoutPercentage(visits, checkable)
            if (s.basis == Basis.UNAVAILABLE) continue
            checked++
            val lo = s.lower ?: s.value!!
            val hi = s.upper ?: s.value!!
            assertTrue(hi <= 100.0 + 1e-9, "upper $hi% out of range for w=$wins m=$misses u=$unrecordedWins")
            assertTrue(lo >= 0.0, "lower $lo% out of range")
            assertTrue(lo <= hi + 1e-9, "bounds inverted for w=$wins m=$misses u=$unrecordedWins")
            // the truth, for every attempt count the unrecorded visits could have had
            val known = recordedWins + misses
            for (extra in unrecordedWins..(unrecordedWins * 3)) {
                val truth = wins.toDouble() * 100 / (known + extra)
                assertTrue(
                    truth in (lo - 1e-9)..(hi + 1e-9),
                    "true $truth% escapes [$lo, $hi] for w=$wins m=$misses u=$unrecordedWins extra=$extra",
                )
            }
        }
        assertTrue(checked > 20, "only $checked shapes exercised")
    }

    @Test
    fun `checkout percentage counts attempts from visits that did NOT finish`() {
        // This is the correction that makes the figure computable at all. A player on 40 who throws
        // a single 20 and misses has attempted a double; asking only on a successful checkout would
        // never record it, and the percentage would be silently inflated.
        val visits = listOf(
            v(1, 1, 180, 3, 501, 321),
            v(1, 2, 180, 3, 321, 141),
            v(1, 3, 101, 3, 141, 40, atDouble = 0),   // 141 is itself a finish; set up instead
            v(1, 4, 20, 3, 40, 20, atDouble = 1),      // on a finish, missed
            v(1, 5, 20, 2, 20, 0, won = true, atDouble = 2),  // on a finish, hit on the second
        )
        val s = Statistics.checkoutPercentage(visits, checkable)
        assertEquals(Basis.EXACT, s.basis)
        assertEquals(EvidenceLevel.DART_LEVEL, s.evidenceLevel)
        // one leg won from three darts thrown at a double
        assertTrue(abs(s.value!! - 100.0 / 3) < 0.001, "got ${s.value}")
        assertEquals(3, s.sampleSize)
    }

    @Test
    fun `asking only on a successful checkout would overstate the percentage`() {
        val full = listOf(
            v(1, 1, 180, 3, 501, 321), v(1, 2, 180, 3, 321, 141),
            v(1, 3, 101, 3, 141, 40, atDouble = 0),
            v(1, 4, 20, 3, 40, 20, atDouble = 1),
            v(1, 5, 20, 2, 20, 0, won = true, atDouble = 1),
        )
        // the same match, if the missed attempt had never been asked about
        val winnerOnly = full.map { if (it.wonLeg) it else it.copy(dartsAtDouble = null) }
        val honest = Statistics.checkoutPercentage(full, checkable).value!!
        val inflated = Statistics.checkoutPercentage(winnerOnly, checkable)
        // the incomplete version cannot report a point value at all — it is bounded
        assertEquals(Basis.BOUNDED, inflated.basis)
        assertNull(inflated.value)
        // and its upper bound is exactly the overstatement the old rule would have published
        assertTrue(inflated.upper!! > honest, "${inflated.upper} should exceed $honest")
        assertTrue(honest >= inflated.lower!! && honest <= inflated.upper!!)
    }

    @Test
    fun `a match that recorded no double attempts says so rather than guessing`() {
        val visits = listOf(
            v(1, 1, 180, 3, 501, 321),
            v(1, 2, 101, 3, 321, 220),
            v(1, 3, 180, 3, 220, 40),
            v(1, 4, 40, 1, 40, 0, won = true),   // finished, but attempts never recorded
        )
        val s = Statistics.checkoutPercentage(visits, checkable)
        assertEquals(Basis.UNAVAILABLE, s.basis)
        assertNull(s.value)
        assertTrue(s.note!!.contains("darts were thrown at a double"))
    }

    @Test
    fun `doubles attempted is exact over the visits that recorded it`() {
        val visits = listOf(
            v(1, 1, 20, 3, 40, 20, atDouble = 1),
            v(1, 2, 20, 2, 20, 0, won = true, atDouble = 2),
        )
        assertEquals(3.0, Statistics.doublesAttempted(visits, checkable).value)
        assertEquals(Basis.EXACT, Statistics.doublesAttempted(visits, checkable).basis)
    }

    @Test
    fun `three dart average is exact when the winning visit recorded its darts`() {
        val s = Statistics.threeDartAverage(nineDartLeg(darts = 3))
        assertEquals(Basis.EXACT, s.basis)
        // 501 scored across 9 darts = 167.0
        assertTrue(abs(s.value!! - 167.0) < 0.001, "got ${s.value}")
    }

    @Test
    fun `three dart average is bounded, not a point value, when darts used is unknown`() {
        val s = Statistics.threeDartAverage(nineDartLeg(darts = null))
        assertEquals(Basis.BOUNDED, s.basis)
        assertNull(s.value)          // must NOT present a single number
        assertNotNull(s.lower)
        assertNotNull(s.upper)
        // 501 over 9 darts (all three used) up to 501 over 7 darts (one used)
        assertTrue(abs(s.lower!! - 167.0) < 0.001, "lower ${s.lower}")
        assertTrue(abs(s.upper!! - 501.0 * 3 / 7) < 0.001, "upper ${s.upper}")
        assertTrue(s.upper!! > s.lower!!)
        assertTrue(s.note!!.contains("did not record"))
    }

    @Test
    fun `the unknown-darts interval brackets the truth`() {
        // the same leg, computed exactly, must fall inside the bounded version's range
        val exact = Statistics.threeDartAverage(nineDartLeg(darts = 3)).value!!
        val bounded = Statistics.threeDartAverage(nineDartLeg(darts = null))
        assertTrue(exact >= bounded.lower!! && exact <= bounded.upper!!,
            "$exact outside [${bounded.lower}, ${bounded.upper}]")
    }

    @Test
    fun `assuming three darts understates the average, which is why the field is captured`() {
        // a 501 leg won in 13 darts: 180, 180, 141 with the last visit using one dart
        val visits = listOf(
            v(1, 1, 180, 3, 501, 321),
            v(1, 2, 180, 3, 321, 141),
            v(1, 3, 141, 1, 141, 0, won = true),
        )
        val truth = Statistics.threeDartAverage(visits).value!!            // 501 over 7 darts
        val assumed = Statistics.threeDartAverage(nineDartLeg(3)).value!!  // 501 over 9 darts
        assertTrue(truth > assumed)
        val understatementPct = (truth - assumed) / truth * 100
        assertTrue(understatementPct > 20, "understated by only $understatementPct%")
    }

    @Test
    fun `a bust visit counts its darts but contributes nothing`() {
        val visits = listOf(
            v(1, 1, 180, 3, 501, 321),
            v(1, 2, 100, 3, 321, 321, bust = true),   // busted: remaining unchanged
            v(1, 3, 180, 3, 321, 141),
            v(1, 4, 141, 3, 141, 0, won = true),
        )
        val s = Statistics.threeDartAverage(visits)
        assertEquals(Basis.EXACT, s.basis)
        // 501 scored over 12 darts — the bust drags the average down, correctly
        assertTrue(abs(s.value!! - 501.0 * 3 / 12) < 0.001, "got ${s.value}")
        assertTrue(s.value!! < 167.0, "a bust must lower the average, not be discarded")
    }

    @Test
    fun `maximums and score bands are exact`() {
        val visits = nineDartLeg()
        assertEquals(2.0, Statistics.maximums(visits).value)
        assertEquals(Basis.EXACT, Statistics.maximums(visits).basis)
        assertEquals(3.0, Statistics.scoresAtLeast(visits, 100).value)
        assertEquals(2.0, Statistics.scoresAtLeast(visits, 180).value)
    }

    @Test
    fun `highest checkout is the remaining finished from`() {
        val s = Statistics.highestCheckout(nineDartLeg())
        assertEquals(Basis.EXACT, s.basis)
        assertEquals(141.0, s.value)
    }

    @Test
    fun `first nine discloses the legs it excluded`() {
        val visits = nineDartLeg() + listOf(
            // a second leg decided in two visits: no first nine
            v(2, 1, 180, 3, 501, 321),
            v(2, 2, 321, 3, 321, 0, won = true),
        )
        val s = Statistics.firstNineAverage(visits)
        assertEquals(Basis.EXACT, s.basis)
        assertEquals(1, s.sampleSize)
        assertNotNull(s.note)
        assertTrue(s.note!!.contains("excluded"), s.note!!)
    }

    @Test
    fun `finish rate from a checkable position is exact and is not checkout percentage`() {
        val checkable = ((2..170).toSet() - setOf(159, 162, 163, 165, 166, 168, 169))
        val visits = listOf(
            v(1, 1, 180, 3, 501, 321),
            v(1, 2, 180, 3, 321, 141),
            v(1, 3, 141, 3, 141, 0, won = true),   // opened checkable, took it
            v(2, 1, 180, 3, 501, 321),
            v(2, 2, 200, 3, 321, 121),
            v(2, 3, 60, 3, 121, 61),               // opened checkable, missed it
        )
        val s = Statistics.finishRateFromCheckablePosition(visits, checkable)
        assertEquals(Basis.EXACT, s.basis)
        assertEquals(2, s.sampleSize)
        assertEquals(50.0, s.value)
        // it remains a DIFFERENT quantity from checkout percentage: this counts visits that opened
        // on a finish, that counts darts thrown at a double. Both are real; they are not the same.
        val withAttempts = visits.map { if (it.remainingBefore in checkable) it.copy(dartsAtDouble = 3) else it }
        val co = Statistics.checkoutPercentage(withAttempts, checkable)
        assertEquals(Basis.EXACT, co.basis)
        assertTrue(abs(co.value!! - s.value!!) > 1.0, "the two measures should not coincide here")
    }

    @Test
    fun `best leg is measured in visits because darts are not always known`() {
        val s = Statistics.bestLegInVisits(nineDartLeg())
        assertEquals(Basis.EXACT, s.basis)
        assertEquals(3.0, s.value)
    }

    @Test
    fun `an empty history reports unavailable rather than zero`() {
        for (s in listOf(
            Statistics.threeDartAverage(emptyList()),
            Statistics.firstNineAverage(emptyList()),
            Statistics.highestCheckout(emptyList()),
            Statistics.bestLegInVisits(emptyList()),
        )) {
            assertEquals(Basis.UNAVAILABLE, s.basis)
            assertNull(s.value)
            assertNotNull(s.note)
        }
    }

    @Test
    fun `every unavailable statistic explains itself in words a player can act on`() {
        val unavailable = listOf(
            Statistics.checkoutPercentage(emptyList(), checkable),
            Statistics.doublesAttempted(emptyList(), checkable),
            Statistics.threeDartAverage(emptyList()),
        )
        for (s in unavailable) {
            assertNotNull(s.note, "an unavailable statistic with no explanation is a dead end")
            // a proxy for "this is a sentence a player can act on", not an arbitrary bar:
            // a three-word fragment tells someone nothing about what to do next
            assertTrue(s.note!!.split(" ").size >= 6, "explanation too terse: ${s.note}")
            assertTrue(s.note!!.first().isUpperCase() && s.note!!.endsWith("."),
                "explanations are sentences, not codes: ${s.note}")
        }
    }
}
