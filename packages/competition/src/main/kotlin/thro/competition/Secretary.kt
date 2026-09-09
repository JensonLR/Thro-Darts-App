package thro.competition

import java.time.Instant
import java.time.LocalDate

/**
 * THRØ Secretary, the pure half: what a league's approved registration policy requires, what is
 * missing, and how a submission moves — with the evidence each move demands.
 *
 * The one rule the whole module exists to keep: **THRØ is never the sporting authority.** It can
 * say a submission was prepared, sent and delivered because it did those things and holds the
 * evidence. It cannot say a submission was acknowledged or accepted; only a named person who
 * administers the receiving side can, and the transition records who. A green tick that THRØ
 * awarded itself would be the lie this product exists to remove from grassroots administration.
 */

// --- Requirements ---------------------------------------------------------------------------------

/**
 * A fact a league may require of a player before registering them, limited to facts THRØ can
 * actually check. A requirement THRØ cannot check is not silently passed: it is a **manual
 * requirement**, satisfied only by a named person confirming it with a note, and rendered as a
 * manual step rather than a tick THRØ awarded.
 */
public enum class RegistrationFact { NAME, AGE_BAND, ACCOUNT_CLAIMED, CONSENT }

/** How a season's registration deadline is expressed. */
public sealed interface RegistrationDeadline {
    public data class On(val date: LocalDate) : RegistrationDeadline
    /** Relative to the team's first fixture in the season. Recomputed when that fixture moves, and the change logged. */
    public data class DaysBeforeFirstFixture(val days: Int) : RegistrationDeadline {
        init { require(days >= 0) { "a deadline is before the fixture, not after" } }
    }
    public data object None : RegistrationDeadline

    /** The rule as the task stores it, so it can be recomputed later. */
    public val rule: String? get() = when (this) {
        is On -> "on:$date"
        is DaysBeforeFirstFixture -> "days_before_first_fixture:$days"
        None -> null
    }
}

/** An approved registration policy, parsed into the facts THRØ can check plus the ones it cannot. */
public data class RegistrationPolicy(
    val requires: Set<RegistrationFact>,
    val deadline: RegistrationDeadline,
    /** Requirements THRØ cannot check — "passport photo" — each satisfied only by a named confirmation. */
    val manualRequirements: List<String> = emptyList(),
    /** Whether a player may hold registrations for two teams in this season. False unless the league says so. */
    val dualRegistrationPermitted: Boolean = false,
) {
    public companion object {
        private val knownKeys = setOf(
            "requires", "manual_requirements", "registration_closes_on", "deadline_days_before_first_fixture",
            "dual_registration_permitted",
        )

        /**
         * Parses the JSON body of a `registration` policy. Deliberately a small, strict reader:
         * an unknown key or an unknown checkable requirement is refused, because a rule THRØ
         * silently ignored is a rule THRØ silently broke. A league that needs something THRØ
         * cannot check lists it under `manual_requirements`, where it is a manual step by name.
         */
        public fun parse(fields: Map<String, Any?>): RegistrationPolicy {
            val unknown = fields.keys - knownKeys
            require(unknown.isEmpty()) { "registration policy has keys THRØ cannot execute: $unknown" }
            val requires = (fields["requires"] as? List<*>).orEmpty().map { key ->
                when (val k = key.toString()) {
                    "name" -> RegistrationFact.NAME
                    "age_band" -> RegistrationFact.AGE_BAND
                    "account_claim" -> RegistrationFact.ACCOUNT_CLAIMED
                    "consent" -> RegistrationFact.CONSENT
                    else -> throw IllegalArgumentException(
                        "registration policy requires '$k', which THRØ cannot check; list it under manual_requirements",
                    )
                }
            }.toSet()
            val manual = (fields["manual_requirements"] as? List<*>).orEmpty().map { it.toString() }
            require(manual.all { it.isNotBlank() } && manual.toSet().size == manual.size) { "manual requirements are distinct and named" }
            val closes = fields["registration_closes_on"]?.toString()
            val days = (fields["deadline_days_before_first_fixture"] as? Number)?.toInt()
            require(closes == null || days == null) { "a policy states one deadline, not two" }
            val deadline = when {
                closes != null -> RegistrationDeadline.On(LocalDate.parse(closes))
                days != null -> RegistrationDeadline.DaysBeforeFirstFixture(days)
                else -> RegistrationDeadline.None
            }
            return RegistrationPolicy(requires, deadline, manual, fields["dual_registration_permitted"] == true)
        }
    }
}

/** What THRØ knows about a player at assessment time. Absence of knowledge is a missing fact. */
public data class RegistrationFacts(
    val hasName: Boolean,
    val ageBandKnown: Boolean,
    val accountClaimed: Boolean,
    val consentRecorded: Boolean,
) {
    public fun missing(policy: RegistrationPolicy): Set<RegistrationFact> =
        policy.requires.filterNot {
            when (it) {
                RegistrationFact.NAME -> hasName
                RegistrationFact.AGE_BAND -> ageBandKnown
                RegistrationFact.ACCOUNT_CLAIMED -> accountClaimed
                RegistrationFact.CONSENT -> consentRecorded
            }
        }.toSet()

    /** Manual requirements not yet confirmed by a named person. */
    public fun manualOutstanding(policy: RegistrationPolicy, confirmed: Set<String>): List<String> =
        policy.manualRequirements.filterNot { it in confirmed }
}

// --- Tasks ------------------------------------------------------------------------------------------

public enum class TaskState { OPEN, WAITING_PLAYER, WAITING_OPPONENT, WAITING_LEAGUE, DONE, CANCELLED }

public enum class TaskKind { REGISTRATION_REQUIRED, CONSENT_REQUIRED, RESULT_SUBMISSION_DUE, REARRANGEMENT_ANSWER_DUE, MANUAL }

/** The captain's inbox headings, derived from state and deadline — never stored. */
public enum class InboxSection { ACTION_REQUIRED, DUE_TODAY, UPCOMING, WAITING_FOR_PLAYER, WAITING_FOR_OPPONENT, WAITING_FOR_LEAGUE, COMPLETED }

public object Inbox {
    public fun sectionOf(state: TaskState, dueAt: Instant?, now: Instant, endOfToday: Instant): InboxSection = when (state) {
        TaskState.DONE, TaskState.CANCELLED -> InboxSection.COMPLETED
        TaskState.WAITING_PLAYER -> InboxSection.WAITING_FOR_PLAYER
        TaskState.WAITING_OPPONENT -> InboxSection.WAITING_FOR_OPPONENT
        TaskState.WAITING_LEAGUE -> InboxSection.WAITING_FOR_LEAGUE
        TaskState.OPEN -> when {
            dueAt == null -> InboxSection.UPCOMING
            !dueAt.isAfter(now) -> InboxSection.ACTION_REQUIRED
            !dueAt.isAfter(endOfToday) -> InboxSection.DUE_TODAY
            else -> InboxSection.UPCOMING
        }
    }
}

// --- Submissions ------------------------------------------------------------------------------------

public enum class SubmissionState {
    DRAFT, READY, SUBMITTED, DELIVERED, DELIVERY_FAILED, ACKNOWLEDGED, ACCEPTED, ACCEPTED_CONDITIONAL,
    REJECTED, ACTION_REQUIRED, WITHDRAWN, SUPERSEDED,
    ;

    public val isTerminal: Boolean get() = this in setOf(ACCEPTED, REJECTED, WITHDRAWN, SUPERSEDED)
}

public enum class SubmissionKind { PLAYER_REGISTRATION, RESULT, FIXTURE_REARRANGEMENT }

/** How a delivery attempt travels. Ordered by the adapter priority the founder set; provenance, not prestige. */
public enum class Transport { API, STRUCTURED, EXPORT, DOCUMENT, EMAIL, MANUAL }

/**
 * What stands behind a transition. `DELIVERY` is an attempt row the transport code wrote;
 * `ARTEFACT` is retained inbound material from the counterparty; `HUMAN_CONFIRMATION` is a named
 * person saying so with a note — the honest manual step, shown as a manual step, never dressed as
 * a receipt.
 */
public enum class EvidenceKind { DELIVERY, ARTEFACT, HUMAN_CONFIRMATION }

/** Who may make a transition. */
public enum class Mover { THRO, SUBMITTER, RECIPIENT }

public data class TransitionRule(
    val from: SubmissionState,
    val to: SubmissionState,
    val mover: Mover,
    /** Evidence kinds that satisfy this move. Empty means none is needed. */
    val evidence: Set<EvidenceKind>,
    /** Whether a named actor is required. THRØ acting alone never counts as a person. */
    val actorRequired: Boolean,
)

/**
 * The transition table. It is data so that the database trigger and this type can be checked
 * against each other, and so a reviewer can read the whole rule on one screen.
 */
public object SubmissionTransitions {
    private val delivery = setOf(EvidenceKind.DELIVERY, EvidenceKind.HUMAN_CONFIRMATION)
    private val recipient = setOf(EvidenceKind.ARTEFACT, EvidenceKind.HUMAN_CONFIRMATION)

    public val RULES: List<TransitionRule> = listOf(
        TransitionRule(SubmissionState.DRAFT, SubmissionState.READY, Mover.THRO, emptySet(), actorRequired = false),
        TransitionRule(SubmissionState.READY, SubmissionState.SUBMITTED, Mover.SUBMITTER, emptySet(), actorRequired = true),
        TransitionRule(SubmissionState.SUBMITTED, SubmissionState.DELIVERED, Mover.THRO, delivery, actorRequired = false),
        TransitionRule(SubmissionState.SUBMITTED, SubmissionState.DELIVERY_FAILED, Mover.THRO, setOf(EvidenceKind.DELIVERY), actorRequired = false),
        TransitionRule(SubmissionState.DELIVERY_FAILED, SubmissionState.READY, Mover.SUBMITTER, emptySet(), actorRequired = true),
        TransitionRule(SubmissionState.DELIVERED, SubmissionState.ACKNOWLEDGED, Mover.RECIPIENT, recipient, actorRequired = true),
        TransitionRule(SubmissionState.ACKNOWLEDGED, SubmissionState.ACCEPTED, Mover.RECIPIENT, recipient, actorRequired = true),
        TransitionRule(SubmissionState.ACKNOWLEDGED, SubmissionState.ACCEPTED_CONDITIONAL, Mover.RECIPIENT, recipient, actorRequired = true),
        TransitionRule(SubmissionState.ACKNOWLEDGED, SubmissionState.REJECTED, Mover.RECIPIENT, recipient, actorRequired = true),
        TransitionRule(SubmissionState.ACKNOWLEDGED, SubmissionState.ACTION_REQUIRED, Mover.RECIPIENT, recipient, actorRequired = true),
        TransitionRule(SubmissionState.ACCEPTED_CONDITIONAL, SubmissionState.ACCEPTED, Mover.RECIPIENT, recipient, actorRequired = true),
        TransitionRule(SubmissionState.ACTION_REQUIRED, SubmissionState.READY, Mover.SUBMITTER, emptySet(), actorRequired = true),
        TransitionRule(SubmissionState.READY, SubmissionState.WITHDRAWN, Mover.SUBMITTER, emptySet(), actorRequired = true),
        TransitionRule(SubmissionState.SUBMITTED, SubmissionState.WITHDRAWN, Mover.SUBMITTER, emptySet(), actorRequired = true),
        TransitionRule(SubmissionState.DELIVERY_FAILED, SubmissionState.WITHDRAWN, Mover.SUBMITTER, emptySet(), actorRequired = true),
        TransitionRule(SubmissionState.ACTION_REQUIRED, SubmissionState.WITHDRAWN, Mover.SUBMITTER, emptySet(), actorRequired = true),
    ) + SubmissionState.entries.filterNot { it.isTerminal }.map {
        // The subject was superseded (a voided result); THRØ closes what carried it.
        TransitionRule(it, SubmissionState.SUPERSEDED, Mover.THRO, emptySet(), actorRequired = false)
    }

    /** The states THRØ, or the team that sent the submission, may never reach on its own. */
    public val NEVER_BY_THRO: Set<SubmissionState> = setOf(
        SubmissionState.ACKNOWLEDGED, SubmissionState.ACCEPTED, SubmissionState.ACCEPTED_CONDITIONAL,
        SubmissionState.REJECTED, SubmissionState.ACTION_REQUIRED,
    )

    public sealed interface Verdict {
        public data object Permitted : Verdict
        public data class Refused(val why: String) : Verdict
    }

    public fun check(from: SubmissionState, to: SubmissionState, evidence: EvidenceKind?, actorNamed: Boolean): Verdict {
        val rule = RULES.firstOrNull { it.from == from && it.to == to }
            ?: return Verdict.Refused("a submission does not move from ${from.name.lowercase()} to ${to.name.lowercase()}")
        if (rule.actorRequired && !actorNamed) {
            return Verdict.Refused("${to.name.lowercase()} needs a named person; THRØ acting alone is not one")
        }
        if (rule.evidence.isNotEmpty() && (evidence == null || evidence !in rule.evidence)) {
            return Verdict.Refused("${to.name.lowercase()} needs evidence of kind ${rule.evidence.joinToString("|") { it.name.lowercase() }}")
        }
        if (evidence == EvidenceKind.HUMAN_CONFIRMATION && !actorNamed) {
            return Verdict.Refused("a human confirmation names the human")
        }
        return Verdict.Permitted
    }
}
