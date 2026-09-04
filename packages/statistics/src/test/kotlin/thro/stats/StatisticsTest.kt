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
    ) = VisitRecord(leg, ord, total, darts, bust, before, after, won)

    /** A 501 leg won in 15 darts: 180, 180, 141 with the last visit using all three darts. */
    private fun nineDartLeg(darts: Int? = 3) = listOf(
        v(1, 1, 180, 3, 501, 321),
        v(1, 2, 180, 3, 321, 141),
        v(1, 3, 141, darts, 141, 0, won = true),
    )

    @Test
    fun `checkout percentage is never fabricated from visit totals`() {
        val s = Statistics.checkoutPercentage(EvidenceLevel.VISIT_TOTAL)
        assertEquals(Basis.UNAVAILABLE, s.basis)
        assertNull(s.value)
        assertNotNull(s.note)
        // the explanation must be usable by a player, not a code
        assertTrue(s.note!!.contains("darts were thrown at a double"))
    }

    @Test
    fun `doubles hit rate is never fabricated either`() {
        assertEquals(Basis.UNAVAILABLE, Statistics.doublesHitRate(EvidenceLevel.VISIT_TOTAL).basis)
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
        // and it must remain a different quantity from the thing it replaces
        assertEquals(Basis.UNAVAILABLE, Statistics.checkoutPercentage(EvidenceLevel.VISIT_TOTAL).basis)
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
            Statistics.checkoutPercentage(EvidenceLevel.VISIT_TOTAL),
            Statistics.doublesHitRate(EvidenceLevel.VISIT_TOTAL),
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
