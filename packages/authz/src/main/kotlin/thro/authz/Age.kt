package thro.authz

/**
 * The age dimension.
 *
 * ADR-008 makes this a first-class authorization attribute from the first account, because
 * visibility rules written without it mean re-auditing every endpoint and every public page later.
 *
 * **This is a dimension, not a policy.** Only the minor/adult distinction is modelled, because that
 * is the one every safeguarding regime shares. The thresholds, what evidence establishes them, and
 * what each unlocks are OD-010 — to be researched against primary sources, not invented here.
 * Nothing in this file is a legal conclusion.
 */
public enum class AgeBand {
    /**
     * Not established. A value, never an absence.
     *
     * A nullable band is a band that gets forgotten in a condition. An explicit unknown has to be
     * handled, and it is handled as **the most restrictive case** — the safe direction when the
     * thing you do not know is whether you are dealing with a child.
     */
    UNKNOWN,
    MINOR,
    ADULT,
}

/** How the band came to be believed. Evidence quality, never permission. */
public enum class AgeAssurance { NONE, SELF_DECLARED, GUARDIAN_DECLARED, VERIFIED }

/** What is known about the subject at the moment of a decision. */
public data class SubjectAttributes(
    val ageBand: AgeBand = AgeBand.UNKNOWN,
    val assurance: AgeAssurance = AgeAssurance.NONE,
)

/**
 * An age requirement on an action.
 *
 * Configurable, and empty by default: an action carries no age requirement unless one is
 * deliberately attached. That default is the honest one while OD-010 is open — inventing
 * restrictions would be as wrong as omitting the dimension, in the opposite direction.
 */
public data class AgeRequirement(
    /** Bands permitted to take this action. */
    val permitted: Set<AgeBand>,
    /** The weakest assurance that counts. `NONE` means a self-declared band is enough. */
    val minimumAssurance: AgeAssurance = AgeAssurance.NONE,
) {
    public fun isSatisfiedBy(attrs: SubjectAttributes): Boolean =
        attrs.ageBand in permitted && attrs.assurance.ordinal >= minimumAssurance.ordinal

    public companion object {
        /**
         * The shape a safeguarding rule takes once OD-010 answers: adults only, and a
         * self-declaration is not enough to establish it.
         *
         * Provided as a *constructor*, not applied to any action here. Which actions carry it is
         * the founder's decision and a legal question, and this repository does not answer it.
         */
        public fun adultsOnly(minimumAssurance: AgeAssurance = AgeAssurance.VERIFIED): AgeRequirement =
            AgeRequirement(permitted = setOf(AgeBand.ADULT), minimumAssurance = minimumAssurance)
    }
}
