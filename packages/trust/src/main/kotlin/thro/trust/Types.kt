package thro.trust

import java.time.Instant
import java.util.UUID

/**
 * How a match concluded. First-class, because a walkover stored as a scoreline is
 * indistinguishable from a played one forever.
 */
public enum class OutcomeType {
    /** Both competitors played it out. */
    PLAYED,

    /** Advancement because the opponent did not play. A progression, never a scoreline. */
    WALKOVER,

    /** A competitor withdrew before or during play without completing. */
    FORFEIT,

    /** A competitor retired mid-match. Darts were thrown; the match did not finish. */
    RETIRED,

    /** An official awarded the result. */
    AWARDED,

    /** The result does not stand. */
    VOID,

    /** Superseded by a replay. */
    REPLAYED,
}

/**
 * How the result was captured. This is a **different axis** from who attested it, and the two are
 * routinely confused because the approved design collapses them into one enum: `thro-recorded`
 * describes the capture channel while `participant-confirmed` describes attestation. A match can be
 * scored live in THRØ by one player and never confirmed by the other.
 */
public enum class CaptureChannel {
    /** Scored live in THRØ, visit by visit. */
    THRO_LIVE,

    /** A final result typed into THRØ after the fact. */
    THRO_ENTERED,

    /** Entered by the competition organiser. */
    ORGANISER_ENTERED,

    /** Brought in from outside THRØ. */
    IMPORTED,
}

/**
 * Who stood behind the result, as a ladder. This is the axis B2 turns on.
 *
 * Kept separate from [CaptureChannel] deliberately. Rating eligibility is a question about
 * attestation — how many independent people are willing to be recorded as saying this happened —
 * and not about which text field the number was typed into.
 */
public enum class Attestation {
    /** One participant's unilateral claim. */
    SELF_REPORTED,

    /** Both participants are recorded as agreeing. */
    PARTICIPANT_CONFIRMED,

    /** An accredited organiser confirmed it. */
    ORGANISER_CONFIRMED,
    // Declaration order IS the ladder: enums compare by ordinal, so `>=` reads as "at least".
}

/**
 * The eight labels the approved design defines, with its own wording.
 *
 * **Derived from provenance, never stored beside it.** A stored label can disagree with the facts
 * underneath it; a derived one cannot. See [VerificationState.of].
 */
public enum class VerificationState {
    SELF_REPORTED,
    PARTICIPANT_CONFIRMED,
    THRO_RECORDED,
    ORGANISER_CONFIRMED,
    THRO_VERIFIED,
    PENDING,
    DISPUTED,
    CORRECTED,
    ;

    /** The design's own wording. Verification expresses evidence quality, never prestige. */
    public val label: String
        get() = when (this) {
            SELF_REPORTED -> "Entered by a player. Not independently confirmed."
            PARTICIPANT_CONFIRMED -> "Both players confirmed this result."
            THRO_RECORDED -> "Scored live in the THRØ app."
            ORGANISER_CONFIRMED -> "Confirmed by the competition organiser."
            THRO_VERIFIED -> "Recorded in THRØ and confirmed by the organiser."
            PENDING -> "Waiting for confirmation."
            DISPUTED -> "A player has disputed this result."
            CORRECTED -> "This result was corrected."
        }

    public companion object {
        /**
         * Derives the design's label from provenance.
         *
         * Order matters, and it is not the ladder. The first three answers are about the result's
         * *state* and outrank its quality: a disputed result is disputed however well it was
         * captured, and showing "Recorded in THRØ and confirmed by the organiser" on a result a
         * player is actively contesting would be true and useless.
         */
        public fun of(p: Provenance): VerificationState = when {
            p.hasOpenDispute -> DISPUTED
            p.corrections > 0 -> CORRECTED
            p.awaitingConfirmation -> PENDING
            p.organiserConfirmed && p.captureChannel == CaptureChannel.THRO_LIVE -> THRO_VERIFIED
            p.organiserConfirmed -> ORGANISER_CONFIRMED
            p.captureChannel == CaptureChannel.THRO_LIVE &&
                p.attestation >= Attestation.PARTICIPANT_CONFIRMED -> THRO_RECORDED
            p.attestation >= Attestation.PARTICIPANT_CONFIRMED -> PARTICIPANT_CONFIRMED
            else -> SELF_REPORTED
        }
    }
}

/** A participant's assertion that the recorded result is wrong. Localises to a leg. */
public data class Dispute(
    val raisedBy: UUID,
    val raisedAt: Instant,
    val legOrdinal: Int?,
    val resolvedAt: Instant? = null,
) {
    public val isOpen: Boolean get() = resolvedAt == null
}

/** A recorded confirmation by a participant or an official. */
public data class Confirmation(
    val actorId: UUID,
    val at: Instant,
    val isOrganiser: Boolean = false,
)

/**
 * Suspension of a result's *eligibility* pending review, without accusation.
 *
 * An **orthogonal axis, not a ninth verification state**: overloading the enum would destroy the
 * provenance underneath, and a device fault triggers this as readily as fraud. It retains the
 * result, its provenance, its place in the bracket and its visibility; it suspends rating
 * eligibility, form contribution, rank denominators and cohort averages. It is reversible.
 */
public data class Quarantine(
    val reason: String,
    val at: Instant,
    val liftedAt: Instant? = null,
) {
    public val isActive: Boolean get() = liftedAt == null
}

/**
 * The composite record of how a result came to exist.
 *
 * Everything a trust label or an eligibility answer needs is here, so that both can be *computed*
 * rather than stored. Storing either beside the provenance is what lets a displayed badge drift
 * away from the facts it claims to summarise.
 */
public data class Provenance(
    val matchId: UUID,
    val outcomeType: OutcomeType,
    val captureChannel: CaptureChannel,
    val enteredBy: UUID,
    /** The two competitors. Attestation asks how many of these are recorded as agreeing. */
    val participants: Set<UUID>,
    val confirmations: List<Confirmation> = emptyList(),
    val disputes: List<Dispute> = emptyList(),
    val corrections: Int = 0,
    val quarantine: Quarantine? = null,
    /** True while THRØ is still waiting for a confirmation it expects. */
    val awaitingConfirmation: Boolean = false,
) {
    /**
     * The distinct competitors who stand behind this result.
     *
     * The player who **entered** it is one of them: entering a result is asserting it, which is
     * precisely what `self-reported` means. Counting them again when they tap confirm would let
     * one player manufacture corroboration alone, so this is a set and not a tally.
     *
     * In the ordinary flow one player scores the match and the other confirms — two distinct
     * backers, and the result is participant-confirmed without the scorer being asked to agree
     * with themselves.
     */
    public val backers: Set<UUID>
        get() = (setOf(enteredBy) + confirmations.filter { !it.isOrganiser }.map { it.actorId })
            .filter { it in participants }.toSet()

    /** How many of the competitors stand behind it. */
    public val participantConfirmations: Int get() = backers.size

    public val organiserConfirmed: Boolean
        get() = confirmations.any { it.isOrganiser }

    public val hasOpenDispute: Boolean get() = disputes.any { it.isOpen }

    public val isQuarantined: Boolean get() = quarantine?.isActive == true

    /**
     * The attestation ladder, derived.
     *
     * An organiser confirmation outranks a participant one because an accredited official is
     * independent of the result. A single participant confirming their own entry adds nothing:
     * the entering player already claimed it, so attestation counts *distinct* competitors.
     */
    public val attestation: Attestation
        get() = when {
            organiserConfirmed -> Attestation.ORGANISER_CONFIRMED
            participants.isNotEmpty() && backers.containsAll(participants) ->
                Attestation.PARTICIPANT_CONFIRMED
            else -> Attestation.SELF_REPORTED
        }
}
