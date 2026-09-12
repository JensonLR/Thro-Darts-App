package thro.trust

import java.time.Instant
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * Trust, provenance and rating eligibility.
 *
 * The point of these tests is that a *label* can never disagree with the facts under it, and that
 * one player's unilateral claim never moves a rating.
 */
class TrustTest {

    private val alice = UUID.randomUUID()
    private val bob = UUID.randomUUID()
    private val organiser = UUID.randomUUID()
    private val now: Instant = Instant.parse("2026-09-04T19:00:00Z")

    private fun prov(
        outcome: OutcomeType = OutcomeType.PLAYED,
        channel: CaptureChannel = CaptureChannel.THRO_LIVE,
        confirmations: List<Confirmation> = emptyList(),
        disputes: List<Dispute> = emptyList(),
        corrections: Int = 0,
        quarantine: Quarantine? = null,
        awaiting: Boolean = false,
    ) = Provenance(
        matchId = UUID.randomUUID(),
        outcomeType = outcome,
        captureChannel = channel,
        enteredBy = alice,
        participants = setOf(alice, bob),
        confirmations = confirmations,
        disputes = disputes,
        corrections = corrections,
        quarantine = quarantine,
        awaitingConfirmation = awaiting,
    )

    private fun bothConfirmed() =
        listOf(Confirmation(alice, now), Confirmation(bob, now))

    // ------------------------------------------------------------------ attestation is counted

    @Test
    fun `a player confirming their own entry is not corroboration`() {
        // Alice entered the result. Alice confirming it adds no independent voice, and counting it
        // would let one player manufacture participant-confirmed status alone — which is exactly
        // the attack PD-002 exists to close.
        val p = prov(confirmations = listOf(Confirmation(alice, now)))
        assertEquals(Attestation.SELF_REPORTED, p.attestation)
        assertEquals(1, p.participantConfirmations, "alice is one backer, not two")
    }

    @Test
    fun `the same player confirming twice is still one voice`() {
        val p = prov(confirmations = listOf(Confirmation(alice, now), Confirmation(alice, now)))
        assertEquals(Attestation.SELF_REPORTED, p.attestation)
    }

    @Test
    fun `a confirmation from someone who did not play does not count`() {
        val stranger = UUID.randomUUID()
        val p = prov(confirmations = listOf(Confirmation(alice, now), Confirmation(stranger, now)))
        assertEquals(Attestation.SELF_REPORTED, p.attestation)
    }

    @Test
    fun `both competitors agreeing is participant-confirmed`() {
        assertEquals(Attestation.PARTICIPANT_CONFIRMED, prov(confirmations = bothConfirmed()).attestation)
    }

    @Test
    fun `the opponent alone confirming is enough, because entering is asserting`() {
        // The ordinary flow: alice scores the whole match, bob confirms. Two distinct people stand
        // behind the result, and asking alice to also agree with what she typed adds nothing.
        val p = prov(confirmations = listOf(Confirmation(bob, now)))
        assertEquals(Attestation.PARTICIPANT_CONFIRMED, p.attestation)
        assertEquals(setOf(alice, bob), p.backers)
    }

    @Test
    fun `an organiser outranks the participants`() {
        val p = prov(confirmations = listOf(Confirmation(organiser, now, isOrganiser = true)))
        assertEquals(Attestation.ORGANISER_CONFIRMED, p.attestation)
    }

    // ------------------------------------------------------------- B2: what may move a rating

    @Test
    fun `a unilateral self-reported result never moves a rating`() {
        val e = eligibilityOf(prov(), opponentIsEstablished = true)
        assertFalse(e.eligible, "self-reported must not inform the model")
        assertFalse(e.qualifying)
        assertTrue(IneligibilityReason.ATTESTATION_BELOW_MINIMUM in e.reasons)
    }

    @Test
    fun `but it still stands as a result`() {
        // PD-002 withholds rating effect, not existence. Nothing here voids the result, removes it
        // from the bracket, or hides it — those would be a different and much larger decision.
        val p = prov()
        assertEquals(OutcomeType.PLAYED, p.outcomeType)
        assertFalse(p.isQuarantined)
        assertEquals(VerificationState.SELF_REPORTED, VerificationState.of(p))
    }

    @Test
    fun `a participant-confirmed played result against an established opponent qualifies`() {
        val e = eligibilityOf(prov(confirmations = bothConfirmed()), opponentIsEstablished = true)
        assertTrue(e.eligible)
        assertTrue(e.qualifying)
        assertTrue(e.reasons.isEmpty())
    }

    @Test
    fun `an unestablished opponent makes it eligible but not qualifying`() {
        val e = eligibilityOf(prov(confirmations = bothConfirmed()), opponentIsEstablished = false)
        assertTrue(e.eligible, "the match is still real")
        assertFalse(e.qualifying, "there is nothing solid to measure against")
    }

    @Test
    fun `qualifying is always strictly narrower than eligible`() {
        // Exhaustive over the whole space, because the invariant is the point: no combination of
        // inputs may produce a result that establishes a rating without being allowed to inform it.
        var checked = 0
        for (outcome in OutcomeType.entries) {
            for (confirms in listOf(emptyList(), bothConfirmed())) {
                for (quarantined in listOf(false, true)) {
                    for (disputed in listOf(false, true)) {
                        for (established in listOf(false, true)) {
                            val p = prov(
                                outcome = outcome,
                                confirmations = confirms,
                                quarantine = if (quarantined) Quarantine("review", now) else null,
                                disputes = if (disputed) listOf(Dispute(bob, now, 3)) else emptyList(),
                            )
                            val e = eligibilityOf(p, established)
                            assertTrue(
                                !e.qualifying || e.eligible,
                                "qualifying without eligible: $outcome q=$quarantined d=$disputed",
                            )
                            assertEquals(
                                e.eligible, e.reasons.isEmpty(),
                                "eligibility must agree with the reasons given",
                            )
                            checked++
                        }
                    }
                }
            }
        }
        assertEquals(7 * 2 * 2 * 2 * 2, checked)
    }

    @Test
    fun `a walkover is not evidence about how good anybody is`() {
        val e = eligibilityOf(
            prov(outcome = OutcomeType.WALKOVER, confirmations = bothConfirmed()),
            opponentIsEstablished = true,
        )
        assertFalse(e.eligible)
        assertTrue(IneligibilityReason.OUTCOME_TYPE_HAS_NO_PERFORMANCE in e.reasons)
    }

    @Test
    fun `a retirement does not rate under PD-002, and that is a policy value`() {
        // PD-002 says outcome_type must be `played`. A retirement is the arguable case — darts
        // were thrown but the match did not finish — and the decision does not name it, so it is
        // excluded rather than admitted (OD-013). Admitting it must be a policy change, visible.
        val p = prov(outcome = OutcomeType.RETIRED, confirmations = bothConfirmed())
        assertFalse(eligibilityOf(p, true).eligible)
        assertTrue(IneligibilityReason.OUTCOME_TYPE_HAS_NO_PERFORMANCE in eligibilityOf(p, true).reasons)

        val admitting = EligibilityPolicy(informing = setOf(OutcomeType.PLAYED, OutcomeType.RETIRED))
        assertTrue(eligibilityOf(p, true, admitting).eligible)
        assertFalse(eligibilityOf(p, true, admitting).qualifying, "it still cannot establish one")
    }

    @Test
    fun `a policy cannot establish what it may not inform`() {
        val e = kotlin.runCatching {
            EligibilityPolicy(
                informing = setOf(OutcomeType.PLAYED),
                establishing = setOf(OutcomeType.PLAYED, OutcomeType.WALKOVER),
            )
        }.exceptionOrNull()
        assertTrue(e is IllegalArgumentException, "an incoherent policy must be refused, got $e")
    }

    // --------------------------------------------------------- quarantine is an orthogonal axis

    @Test
    fun `quarantine suspends eligibility without changing the verification label`() {
        val clean = prov(confirmations = bothConfirmed())
        val held = clean.copy(quarantine = Quarantine("device fault under review", now))

        // The label is unchanged: quarantine is not a ninth verification state, and overloading
        // the enum would destroy the provenance underneath.
        assertEquals(VerificationState.of(clean), VerificationState.of(held))
        assertTrue(eligibilityOf(clean, true).eligible)
        assertFalse(eligibilityOf(held, true).eligible)
        assertTrue(IneligibilityReason.QUARANTINED in eligibilityOf(held, true).reasons)
    }

    @Test
    fun `quarantine is reversible`() {
        val held = prov(
            confirmations = bothConfirmed(),
            quarantine = Quarantine("review", now, liftedAt = now.plusSeconds(3600)),
        )
        assertFalse(held.isQuarantined)
        assertTrue(eligibilityOf(held, true).eligible)
    }

    // ------------------------------------------------------------------- the label is derived

    @Test
    fun `an open dispute outranks every quality label`() {
        val p = prov(
            channel = CaptureChannel.THRO_LIVE,
            confirmations = bothConfirmed() + Confirmation(organiser, now, isOrganiser = true),
            disputes = listOf(Dispute(bob, now, 9)),
        )
        // Without the dispute this would be the top of the ladder.
        assertEquals(VerificationState.THRO_VERIFIED, VerificationState.of(p.copy(disputes = emptyList())))
        assertEquals(VerificationState.DISPUTED, VerificationState.of(p))
    }

    @Test
    fun `a resolved dispute stops outranking`() {
        val p = prov(
            confirmations = bothConfirmed(),
            disputes = listOf(Dispute(bob, now, 9, resolvedAt = now.plusSeconds(600))),
        )
        assertEquals(VerificationState.THRO_RECORDED, VerificationState.of(p))
    }

    @Test
    fun `live scoring alone is not participant confirmation`() {
        // The design collapses capture channel and attestation into one enum. A match scored live
        // in THRØ by one player, with the other never confirming, is not corroborated by anyone.
        val p = prov(channel = CaptureChannel.THRO_LIVE)
        assertEquals(VerificationState.SELF_REPORTED, VerificationState.of(p))
        assertFalse(eligibilityOf(p, true).eligible)
    }

    @Test
    fun `organiser confirmation of a live-scored match is thro-verified`() {
        val p = prov(
            channel = CaptureChannel.THRO_LIVE,
            confirmations = listOf(Confirmation(organiser, now, isOrganiser = true)),
        )
        assertEquals(VerificationState.THRO_VERIFIED, VerificationState.of(p))
    }

    @Test
    fun `organiser confirmation of an entered match is organiser-confirmed, not thro-verified`() {
        val p = prov(
            channel = CaptureChannel.ORGANISER_ENTERED,
            confirmations = listOf(Confirmation(organiser, now, isOrganiser = true)),
        )
        assertEquals(VerificationState.ORGANISER_CONFIRMED, VerificationState.of(p))
    }

    @Test
    fun `every verification state carries the design's own wording`() {
        for (s in VerificationState.entries) {
            assertTrue(s.label.isNotBlank(), "$s has no wording")
        }
        assertEquals(8, VerificationState.entries.size, "the design defines exactly eight")
    }

    @Test
    fun `the policy can be argued with rather than being hardwired`() {
        // OD-001 is open, so which outcomes feed the rating model is configuration, not domain.
        // Raising the bar to organiser-confirmed must be a policy change and nothing more.
        val strict = EligibilityPolicy(minimumAttestation = Attestation.ORGANISER_CONFIRMED)
        val p = prov(confirmations = bothConfirmed())
        assertTrue(eligibilityOf(p, true).eligible)
        assertFalse(eligibilityOf(p, true, strict).eligible)
    }
}
