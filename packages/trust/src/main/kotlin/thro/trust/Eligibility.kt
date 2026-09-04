package thro.trust

/**
 * Derives the design's verification label from provenance.
 *
 * Order matters, and it is not the ladder. The first three answers are about the result's *state*
 * and outrank its quality: a disputed result is disputed however well it was captured, and showing
 * "Recorded in THRØ and confirmed by the organiser" on a result a player is actively contesting
 * would be true and useless.
 */
public fun VerificationState.Companion.of(p: Provenance): VerificationState = when {
    p.hasOpenDispute -> VerificationState.DISPUTED
    p.corrections > 0 -> VerificationState.CORRECTED
    p.awaitingConfirmation -> VerificationState.PENDING
    p.organiserConfirmed && p.captureChannel == CaptureChannel.THRO_LIVE ->
        VerificationState.THRO_VERIFIED
    p.organiserConfirmed -> VerificationState.ORGANISER_CONFIRMED
    p.captureChannel == CaptureChannel.THRO_LIVE &&
        p.attestation >= Attestation.PARTICIPANT_CONFIRMED -> VerificationState.THRO_RECORDED
    p.attestation >= Attestation.PARTICIPANT_CONFIRMED -> VerificationState.PARTICIPANT_CONFIRMED
    else -> VerificationState.SELF_REPORTED
}

/** Kotlin needs a companion to hang [of] on. */
public val VerificationState.Companion.states: List<VerificationState>
    get() = VerificationState.entries

/**
 * Which outcome types may inform the rating model, and which may establish a rating.
 *
 * Configurable rather than hardwired, per ADR-014 and the open-decisions discipline: the rating
 * model itself is undecided (OD-001), so a policy that pins which outcomes feed it would be
 * deciding part of OD-001 by implementation convenience. The defaults below are the conservative
 * reading and are stated so they can be argued with.
 */
public data class EligibilityPolicy(
    /**
     * Outcomes that may inform the rating model. **PD-002: `played` only.** Walkovers, awards,
     * forfeits and voids are recorded but never rate.
     *
     * A retirement is the genuinely arguable case — darts were thrown, but the match did not
     * finish — and PD-002 does not name it. It is excluded here rather than admitted, because
     * admitting it would decide an open question by implementation convenience. Raising it is a
     * policy change (see OD-013).
     */
    val informing: Set<OutcomeType> = setOf(OutcomeType.PLAYED),

    /** Outcomes that may *establish* a rating. Never wider than [informing]. */
    val establishing: Set<OutcomeType> = setOf(OutcomeType.PLAYED),

    /**
     * **PD-002 (B2).** The minimum attestation for rating eligibility.
     *
     * One player's unilateral claim never moves either rating. Self-reported results still
     * progress the bracket and still appear in the record — they are simply not evidence about
     * how good anybody is.
     */
    val minimumAttestation: Attestation = Attestation.PARTICIPANT_CONFIRMED,
) {
    init {
        require(informing.containsAll(establishing)) {
            "a policy cannot let an outcome establish a rating it may not even inform: " +
                "${establishing - informing}"
        }
    }
}

/** Why a result cannot inform the rating model, in terms an organiser can act on. */
public enum class IneligibilityReason {
    OUTCOME_TYPE_HAS_NO_PERFORMANCE,
    ATTESTATION_BELOW_MINIMUM,
    QUARANTINED,
    DISPUTED,
}

public data class Eligibility(
    val eligible: Boolean,
    val qualifying: Boolean,
    val reasons: List<IneligibilityReason> = emptyList(),
) {
    init {
        require(!(qualifying && !eligible)) { "qualifying is strictly narrower than eligible" }
    }
}

/**
 * Decides whether a result may inform the rating model, and whether it may establish a rating.
 *
 * **Eligible** — permitted to inform the model at all.
 * **Qualifying** — counts toward establishing a rating. Strictly narrower.
 *
 * [opponentIsEstablished] is a fact about the other player's rating, not about this match, which is
 * why it is passed in rather than read from provenance. A match against an unrated opponent is
 * still real; it just cannot establish a rating, because there is nothing solid to measure against.
 */
public fun eligibilityOf(
    p: Provenance,
    opponentIsEstablished: Boolean,
    policy: EligibilityPolicy = EligibilityPolicy(),
): Eligibility {
    val reasons = mutableListOf<IneligibilityReason>()
    if (p.outcomeType !in policy.informing) reasons += IneligibilityReason.OUTCOME_TYPE_HAS_NO_PERFORMANCE
    if (p.attestation < policy.minimumAttestation) reasons += IneligibilityReason.ATTESTATION_BELOW_MINIMUM
    if (p.isQuarantined) reasons += IneligibilityReason.QUARANTINED
    if (p.hasOpenDispute) reasons += IneligibilityReason.DISPUTED

    val eligible = reasons.isEmpty()
    val qualifying = eligible && p.outcomeType in policy.establishing && opponentIsEstablished
    return Eligibility(eligible = eligible, qualifying = qualifying, reasons = reasons)
}
