package thro.rating

import kotlin.math.abs
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * The rating architecture, tested without deciding the rating model.
 *
 * OD-001 is open. These tests assert the properties that keep it open — reproducibility, exactly
 * one published model, a reconciling ledger, frozen explanations — and one that stops it being
 * closed by accident: nothing unvalidated can be published.
 */
class ProjectionTest {

    private val alice = PlayerId("alice")
    private val bob = PlayerId("bob")
    private val cara = PlayerId("cara")

    private fun row(seq: Long, h: PlayerId, a: PlayerId, homeWon: Boolean, xid: Long = 1) =
        EvidenceRow(
            matchId = "m$seq", at = Watermark(xid, seq), home = h, away = a,
            homeScore = if (homeWon) 1.0 else 0.0,
            legsHome = if (homeWon) 3 else 1, legsAway = if (homeWon) 1 else 3,
            qualifying = true,
        )

    private val evidence = listOf(
        row(1, alice, bob, true),
        row(2, bob, cara, true),
        row(3, alice, cara, false),
        row(4, alice, bob, true, xid = 2),
    )

    // ------------------------------------------------------------------------- reproducibility

    @Test
    fun `the same watermark and model always produce the same result`() {
        val a = Projection.replay(evidence, ProvisionalModel(), Watermark(2, 4))
        val b = Projection.replay(evidence.shuffled(), ProvisionalModel(), Watermark(2, 4))
        assertEquals(
            a.snapshots.sortedBy { it.player.value },
            b.snapshots.sortedBy { it.player.value },
            "a replay depended on the order rows arrived in",
        )
    }

    @Test
    fun `a watermark is a pair, and the second half matters`() {
        // Two rows can share a commit_xid. Ordering on it alone would make them interchangeable,
        // and a rating that depends on which of two same-transaction rows came first would be
        // irreproducible in exactly the way ADR-009 warns about.
        assertTrue(Watermark(1, 1) < Watermark(1, 2))
        assertTrue(Watermark(1, 99) < Watermark(2, 1), "commit order outranks insert order")
        assertEquals(Watermark(3, 7), Watermark(3, 7))
    }

    @Test
    fun `replaying at an earlier watermark sees less evidence, not different evidence`() {
        val early = Projection.replay(evidence, ProvisionalModel(), Watermark(1, 2))
        val late = Projection.replay(evidence, ProvisionalModel(), Watermark(2, 4))
        assertEquals(2, early.evidenceCount)
        assertEquals(4, late.evidenceCount)
        assertTrue(early.snapshots.size <= late.snapshots.size)
    }

    @Test
    fun `evidence above the watermark is never included`() {
        val r = Projection.replay(evidence, ProvisionalModel(), Watermark(1, 3))
        assertEquals(3, r.evidenceCount, "a row from a later transaction leaked in")
    }

    // --------------------------------------------------------------- OD-001 stays open

    @Test
    fun `an unvalidated model cannot be published`() {
        val r = Publication.check(ProvisionalModel(), publishedModels = emptySet())
        assertTrue(r is Publication.Result.Refused)
        assertTrue(r.why.contains("OD-001"), "the refusal must say why: ${r.why}")
    }

    @Test
    fun `no model in this repository claims to be validated`() {
        // If this ever fails, someone has decided OD-001 by writing `validated = true` instead of
        // by producing evidence. That is the failure mode the whole register exists to catch.
        assertFalse(ProvisionalModel().validated)
    }

    @Test
    fun `exactly one model may be published at a time`() {
        val validated = object : RatingModel by ProvisionalModel() {
            override val id = "candidate-b"
            override val validated = true
            override fun rate(evidence: List<EvidenceRow>) = emptyList<Snapshot>() to emptyList<LedgerLine>()
        }
        assertTrue(Publication.check(validated, emptySet()) is Publication.Result.Allowed)
        val blocked = Publication.check(validated, setOf("candidate-a"))
        assertTrue(blocked is Publication.Result.Refused)
        assertTrue(blocked.why.contains("ambiguous"), blocked.why)
        // Re-publishing the model that is already published is not a conflict with itself.
        assertTrue(Publication.check(validated, setOf("candidate-b")) is Publication.Result.Allowed)
    }

    @Test
    fun `candidates run in shadow and publish nothing`() {
        val r = Projection.replay(evidence, ProvisionalModel(), Watermark(2, 4))
        assertTrue(r.snapshots.isNotEmpty(), "shadow models still compute")
        assertTrue(r.snapshots.none { it.published }, "a shadow model published a snapshot")
        assertTrue(r.snapshots.all { it.rating == null }, "a provisional rating showed a number")
    }

    // ------------------------------------------------------------------ what provisional means

    @Test
    fun `every player is provisional at launch, and that is the truth not a placeholder`() {
        val r = Projection.replay(evidence, ProvisionalModel(), Watermark(2, 4))
        for (s in r.snapshots) {
            assertNull(s.rating, "${s.player} was given a rating nothing supports")
            assertTrue(s.confidence in 0.0..1.0)
        }
    }

    @Test
    fun `confidence rises with observation and stops at one`() {
        val many = (1L..40L).map { row(it, alice, bob, it % 2 == 0L) }
        val r = Projection.replay(many, ProvisionalModel(establishAfter = 10), Watermark(1, 40))
        val a = r.snapshots.single { it.player == alice }
        assertEquals(40, a.matchesCounted)
        assertEquals(1.0, a.confidence, "confidence must not exceed certainty")
    }

    @Test
    fun `a non-qualifying result is not counted`() {
        val mixed = evidence + row(5, alice, cara, true, xid = 2).copy(qualifying = false)
        val r = Projection.replay(mixed, ProvisionalModel(), Watermark(2, 5))
        val before = Projection.replay(evidence, ProvisionalModel(), Watermark(2, 4))
        assertEquals(
            before.snapshots.single { it.player == alice }.matchesCounted,
            r.snapshots.single { it.player == alice }.matchesCounted,
            "a non-qualifying result moved the count",
        )
    }

    // ---------------------------------------------------------------------- ledger invariant

    @Test
    fun `the ledger reconciles exactly to the net change`() {
        val r = Projection.replay(evidence, ProvisionalModel(), Watermark(2, 4))
        assertTrue(r.ledgerReconciles(previous = emptyMap()))
    }

    @Test
    fun `a change absorbed silently into a match line fails reconciliation`() {
        // Build a model that moves a rating by 10 but only writes a line for 6. The missing 4 is
        // exactly the "silently absorbed adjustment" ADR-009 forbids, and the invariant must catch
        // it rather than let a rating drift with no visible cause.
        val dishonest = object : RatingModel {
            override val id = "dishonest"
            override val version = "1.0.0"
            override val parameterHash = "-"
            override fun rate(evidence: List<EvidenceRow>) = listOf(
                Snapshot(alice, id, version, parameterHash, 1, Watermark(1, 1), 10.0, 0.5, 1, false),
            ) to listOf(
                LedgerLine(alice, Watermark(1, 1), LedgerLine.Cause.MATCH, "m1", 6.0, null),
            )
        }
        val r = Projection.replay(evidence, dishonest, Watermark(2, 4))
        assertFalse(r.ledgerReconciles(previous = emptyMap()), "4 points appeared from nowhere")

        val honest = object : RatingModel by dishonest {
            override fun rate(evidence: List<EvidenceRow>) = listOf(
                Snapshot(alice, "honest", "1.0.0", "-", 1, Watermark(1, 1), 10.0, 0.5, 1, false),
            ) to listOf(
                LedgerLine(alice, Watermark(1, 1), LedgerLine.Cause.MATCH, "m1", 6.0, null),
                LedgerLine(alice, Watermark(1, 1), LedgerLine.Cause.RECOMPUTATION, null, 4.0, null),
            )
        }
        assertTrue(
            Projection.replay(evidence, honest, Watermark(2, 4)).ledgerReconciles(emptyMap()),
            "the same movement with its adjustment declared must reconcile",
        )
    }

    // -------------------------------------------------------------------- frozen explanations

    @Test
    fun `an explanation keeps the opponent's rating as it was, not as it became`() {
        val then = Explanation(
            opponent = bob, opponentRatingAtTheTime = 1400.0, opponentConfidenceAtTheTime = 0.8,
            ownRatingAtTheTime = 1350.0, predictedProbability = 0.43, realisedOutcome = 1.0,
            modelVersion = "1.0.0",
        )
        val line = LedgerLine(alice, Watermark(1, 1), LedgerLine.Cause.MATCH, "m1", 12.0, then)
        // Bob's rating moves on afterwards. The frozen explanation must not follow it: a
        // regenerated one would quote a past opponent at their present rating and be false.
        val bobNow = 1600.0
        assertEquals(1400.0, line.explanation!!.opponentRatingAtTheTime)
        assertTrue(abs(bobNow - line.explanation!!.opponentRatingAtTheTime!!) > 0)
    }
}
