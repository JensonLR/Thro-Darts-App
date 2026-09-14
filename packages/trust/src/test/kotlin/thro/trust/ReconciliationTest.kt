package thro.trust

import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotEquals
import kotlin.test.assertTrue
import thro.engine.InRule
import thro.engine.MatchFormat
import thro.engine.OutRule
import thro.engine.PlayerId
import thro.engine.Structure
import thro.engine.StructureMode

/**
 * Reconciling two independent accounts of one offline match.
 *
 * The load-bearing test is [a corrected mis-key does not manufacture a dispute]: it is the exact
 * case ADR-006 names as the reason reconciliation happens at outcome level rather than by digest
 * equality, and it is asserted here *against* a digest so the distinction is demonstrated rather
 * than asserted.
 */
class ReconciliationTest {

    private val home = PlayerId("Home")
    private val away = PlayerId("Away")
    private val format = MatchFormat(
        startingScore = 501,
        inRule = InRule.STRAIGHT,
        outRule = OutRule.DOUBLE,
        legs = Structure(StructureMode.FIRST_TO, 1),
        throwFirst = home,
    )

    /** A leg: Home 180, 180, 141 out. Away throws 60s and never finishes. */
    private fun agreedLeg(startSeq: Long = 1): List<AccountedVisit> = listOf(
        AccountedVisit(startSeq + 0, home, 180),
        AccountedVisit(startSeq + 1, away, 60),
        AccountedVisit(startSeq + 2, home, 180),
        AccountedVisit(startSeq + 3, away, 60),
        AccountedVisit(startSeq + 4, home, 141, dartsUsed = 3, dartsAtDouble = 1),
    )

    @Test
    fun `two accounts that agree are corroborated`() {
        val a = DeviceAccount(UUID.randomUUID(), agreedLeg())
        val b = DeviceAccount(UUID.randomUUID(), agreedLeg())
        val r = Reconcile.reconcile(listOf(a, b), format, home, away)
        assertTrue(r is Reconciliation.Corroborated, "got $r")
        assertEquals(home, r.outcome.winner)
        assertEquals(1, r.outcome.legsWon[home])
    }

    @Test
    fun `a corrected mis-key does not manufacture a dispute`() {
        // Both scorers watched the same match. One of them typed 100 instead of 180 on the second
        // visit and corrected it. The devices agree completely about what happened.
        val clean = DeviceAccount(UUID.randomUUID(), agreedLeg())
        val fumbled = DeviceAccount(
            UUID.randomUUID(),
            listOf(
                AccountedVisit(1, home, 180),
                AccountedVisit(2, away, 60),
                AccountedVisit(3, home, 100),                       // mis-keyed
                AccountedVisit(4, home, 180, correctsSeq = 3),      // corrected
                AccountedVisit(5, away, 60),
                AccountedVisit(6, home, 141, dartsUsed = 3, dartsAtDouble = 1),
            ),
        )

        // A digest over the raw journals disagrees — this is precisely the false dispute that
        // digest equality would raise, and the reason ADR-006 forbids it as the comparison.
        assertNotEquals(
            clean.journalDigest, fumbled.journalDigest,
            "the journals really do differ; if they did not, this test would prove nothing",
        )

        val r = Reconcile.reconcile(listOf(clean, fumbled), format, home, away)
        assertTrue(r is Reconciliation.Corroborated, "a corrected mis-key was treated as a dispute: $r")
        assertEquals(home, r.outcome.winner)
    }

    @Test
    fun `a genuine disagreement is contested and explains itself`() {
        val a = DeviceAccount(UUID.randomUUID(), agreedLeg())
        // The second scorer has Away winning the leg instead.
        val b = DeviceAccount(
            UUID.randomUUID(),
            listOf(
                AccountedVisit(1, home, 180),
                AccountedVisit(2, away, 180),
                AccountedVisit(3, home, 100),
                AccountedVisit(4, away, 180),
                AccountedVisit(5, home, 60),
                AccountedVisit(6, away, 141, dartsUsed = 3, dartsAtDouble = 1),
            ),
        )
        val r = Reconcile.reconcile(listOf(a, b), format, home, away)
        assertTrue(r is Reconciliation.Contested, "got $r")
        assertEquals(2, r.outcomes.size)
        assertTrue(r.explanation.isNotEmpty(), "a contested match must say where the stories parted")
        // The accounts are kept apart, never merged into a third story.
        assertNotEquals(
            r.outcomes[a.deviceId], r.outcomes[b.deviceId],
            "the two accounts must remain distinguishable",
        )
    }

    @Test
    fun `the explanation points at the first visit that differs`() {
        val a = DeviceAccount(UUID.randomUUID(), agreedLeg())
        val b = DeviceAccount(
            UUID.randomUUID(),
            agreedLeg().map { if (it.seq == 3L) it.copy(visitTotal = 140) else it },
        )
        val diffs = Reconcile.explain(a, b)
        assertEquals(1, diffs.size, "only one visit differs")
        assertEquals(3, diffs.first().ordinal)
        assertEquals(180, diffs.first().left?.visitTotal)
        assertEquals(140, diffs.first().right?.visitTotal)
    }

    @Test
    fun `one device alone is uncorroborated, not corroborated and not contested`() {
        val a = DeviceAccount(UUID.randomUUID(), agreedLeg())
        val r = Reconcile.reconcile(listOf(a), format, home, away)
        assertTrue(r is Reconciliation.Uncorroborated, "got $r")
        assertEquals(home, r.outcome.winner)
    }

    @Test
    fun `an account of different length can still corroborate`() {
        // One device recorded a rejected visit that never happened; the engine drops it on replay,
        // so the outcomes still agree. Length is not the comparison.
        val a = DeviceAccount(UUID.randomUUID(), agreedLeg())
        val b = DeviceAccount(
            UUID.randomUUID(),
            listOf(AccountedVisit(0, away, 60)) + agreedLeg(startSeq = 1),
        )
        // Guard against this passing vacuously: the extra visit really is in b's effective list,
        // so it really is being replayed and really is being refused by the engine as out of turn.
        assertEquals(a.effective.size + 1, b.effective.size, "the extra visit must be replayed")
        assertEquals(
            thro.engine.RejectionReason.NOT_YOUR_TURN,
            (thro.engine.Engine.apply(
                thro.engine.MatchState.start(format, home, away),
                thro.engine.Command.RecordVisit(away, 60),
            ) as thro.engine.Outcome.Rejected).reason,
            "the premise of this test is that the engine refuses it",
        )

        val r = Reconcile.reconcile(listOf(a, b), format, home, away)
        assertTrue(r is Reconciliation.Corroborated, "got $r")
    }

    @Test
    fun `corrections are dropped from the outcome but kept in the account`() {
        val fumbled = DeviceAccount(
            UUID.randomUUID(),
            listOf(
                AccountedVisit(1, home, 100),
                AccountedVisit(2, home, 180, correctsSeq = 1),
            ),
        )
        assertEquals(2, fumbled.visits.size, "the superseded row is evidence and stays")
        assertEquals(1, fumbled.effective.size, "but it is not counted twice")
        assertEquals(180, fumbled.effective.single().visitTotal)
    }
}
