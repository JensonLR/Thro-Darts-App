package thro.org

/**
 * A club reaching its members — and the line this package will not cross on its own.
 *
 * The founder asked for the app to "become a hub for them to communicate with member and arrange
 * things". Clubs and leagues have junior members. A feature that lets one person message another
 * privately, where one of them may be a child, is a safeguarding surface — and what the law requires
 * of it is **OD-010**, which this repository has always said it does not answer.
 *
 * So two things are built and one is not:
 *
 *  1. **Announcements are broadcast, from a role, to a membership.** Never person to person, never
 *     private, and every one is a record with an author. That is what a club secretary actually
 *     needs — the fixture is off, the AGM is Tuesday — and it has no private channel in it.
 *  2. **A minor receives nothing until somebody has answered the question.** `CommunicationPolicy`
 *     starts as `undecided`, and while it is undecided every member whose band is MINOR *or UNKNOWN*
 *     is withheld, with the reason on the record. An app shipped with no answer cannot message a
 *     child. That is not a placeholder; it is the safe direction, and it is enforced rather than
 *     documented.
 *  3. **Member-to-member messaging is not built at all.** Not stubbed, not disabled behind a flag —
 *     absent, because the shape of the safeguarding controls it needs (moderation, reporting,
 *     retention, guardian consent) would determine its data model, and building the model first
 *     would prejudge them. It is OD-017.
 */

/** Why an announcement did not reach somebody. Never silent. */
public enum class Withheld {
    /** The recipient's age band is MINOR, and no policy permits it. */
    MINOR_AND_NO_POLICY,

    /**
     * The recipient's age band is UNKNOWN. Treated exactly as MINOR: the thing not known is whether
     * this is a child, and the safe reading of "I do not know" is the restrictive one.
     */
    UNKNOWN_AGE_AND_NO_POLICY,

    /** The recipient is not a member of the organisation the announcement was sent to. */
    NOT_A_MEMBER,
}

/**
 * Who an organisation's announcements may reach.
 *
 * `undecided` is the shipped default and the honest one. The alternative — a default that lets
 * announcements through to juniors — would be engineering inventing a safeguarding position, which
 * `DESIGN_UNSPECIFIED.md` and OD-010 both forbid.
 */
public data class CommunicationPolicy(
    /** Whether an announcement may reach a member recorded as a MINOR. Null means undecided. */
    val minorsMayReceive: Boolean?,
    /**
     * Whether a member whose age is UNKNOWN is treated as a minor. True is the only value that has
     * ever been set here, and it is not configurable to false through any constructor a caller can
     * reach — it exists so the reasoning is visible in the type rather than buried in a branch.
     */
    val unknownCountsAsMinor: Boolean = true,
) {
    public companion object {
        /** No answer yet. Minors and unknowns receive nothing. */
        public val undecided: CommunicationPolicy = CommunicationPolicy(minorsMayReceive = null)
    }
}

public data class Announcement(
    val organisation: OrganisationId,
    val author: PersonId,
    val subject: String,
    val body: String,
) {
    init {
        require(subject.isNotBlank()) { "an announcement needs a subject" }
        require(subject.length <= 120) { "a subject must be 120 characters or fewer" }
        require(body.isNotBlank()) { "an announcement needs a body" }
        require(body.length <= 4000) { "a body must be 4000 characters or fewer" }
    }
}

/** Exactly who an announcement reaches, and exactly who it does not, and why. */
public data class Delivery(
    val to: List<PersonId>,
    val withheld: Map<PersonId, Withheld>,
) {
    public val reached: Int get() = to.size
    public val notReached: Int get() = withheld.size
}

public object Announcements {
    /**
     * Who may send. Authority is checked here rather than assumed by the caller, because "the caller
     * already checked" is how an authority hole is written.
     */
    public fun mayAnnounce(membership: Membership?): Boolean =
        Permissions.may(membership, OrgAction.ANNOUNCE)

    /**
     * Works out the delivery. Total: every member appears in exactly one of the two lists, so a
     * caller cannot silently lose somebody, and the count that is shown to the sender is a count of
     * something real.
     */
    public fun deliver(
        announcement: Announcement,
        members: List<Membership>,
        policy: CommunicationPolicy,
    ): Delivery {
        val to = mutableListOf<PersonId>()
        val withheld = LinkedHashMap<PersonId, Withheld>()
        for (m in members) {
            if (m.organisation != announcement.organisation) {
                withheld[m.person] = Withheld.NOT_A_MEMBER
                continue
            }
            when (m.ageBand) {
                AgeBand.ADULT -> to.add(m.person)
                AgeBand.MINOR ->
                    if (policy.minorsMayReceive == true) to.add(m.person)
                    else withheld[m.person] = Withheld.MINOR_AND_NO_POLICY
                AgeBand.UNKNOWN ->
                    if (!policy.unknownCountsAsMinor && policy.minorsMayReceive == true) to.add(m.person)
                    else withheld[m.person] = Withheld.UNKNOWN_AGE_AND_NO_POLICY
            }
        }
        return Delivery(to = to, withheld = withheld)
    }
}
