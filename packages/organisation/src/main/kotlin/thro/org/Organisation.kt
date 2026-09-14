package thro.org

/**
 * Teams, leagues and tournaments — the bodies a player belongs to.
 *
 * The founder asked for these to hold their own data, carry their own branding, and be a place where
 * a club can reach its members and arrange things. This package is the part of that engineering can
 * build without inventing product: the model, the membership, the branding rule that keeps the app
 * legible whatever a club chooses, and the boundary a communications feature cannot cross until the
 * safeguarding question is answered.
 *
 * What is deliberately NOT here is recorded in `docs/product/OPEN_DECISIONS.md` under OD-016 to
 * OD-019, and the screens are B3: the design export draws no club, league or profile screen, and
 * `docs/design/DESIGN_UNSPECIFIED.md` says none of these may be invented by engineering.
 */

@JvmInline
public value class OrganisationId(public val value: String) {
    init { require(value.isNotBlank()) { "an organisation id cannot be blank" } }
}

@JvmInline
public value class PersonId(public val value: String) {
    init { require(value.isNotBlank()) { "a person id cannot be blank" } }
}

/**
 * What kind of body this is.
 *
 * All three hold members, carry branding and arrange fixtures, so they are one type with a kind
 * rather than three near-identical types. The kind is what the thing is CALLED to its members and
 * what its lifetime is: a team is standing, a league runs a season, a tournament runs once. Nothing
 * in this package branches on it — anything that needs to is a product rule, not a structural one,
 * and would be wrong to invent here.
 *
 * `TEAM` was `CLUB` until the founder's instruction of 2026-09-09 (ADR-017, PD-028): the standing
 * competitive organisation is the Team whatever it calls itself — darts team, darts club, pub team,
 * side — and THRØ carries no separate club concept. The kind is renamed; nothing else about it
 * changed, and this package has no persistence for a rename to disturb.
 */
public enum class OrganisationKind { TEAM, LEAGUE, TOURNAMENT }

/**
 * What a person may do inside an organisation.
 *
 * Three levels, because that is what the actions below actually distinguish and no more. A role is
 * not a permission: `Permissions` says what each role may do, in one place, so a new action cannot
 * quietly acquire an authority nobody granted it.
 */
public enum class OrgRole { MEMBER, OFFICIAL, ADMIN }

/** An action a person may want to take inside an organisation. */
public enum class OrgAction {
    /**
     * Read the organisation's own page: its name, badge, kind and published fixtures.
     *
     * Public, by PD-009 — a league advertising a new season needs a page a stranger can open. It is
     * the only public action, and everything below it needs a membership.
     */
    VIEW,
    /** See who else is a member. */
    VIEW_MEMBERS,
    /** Send an announcement to the membership. */
    ANNOUNCE,
    /** Create, move or cancel a fixture. */
    MANAGE_FIXTURES,
    /** Change the name, the branding, or the kind. */
    MANAGE_BRANDING,
    /** Admit, remove, or change the role of a member. */
    MANAGE_MEMBERS,
}

public object Permissions {
    /**
     * Who may do what. Stated as data rather than as branches, so the whole authority surface of an
     * organisation is nine lines you can read at once and an action cannot be added without a
     * deliberate decision about who it belongs to.
     */
    private val allowed: Map<OrgRole, Set<OrgAction>> = mapOf(
        OrgRole.MEMBER to setOf(OrgAction.VIEW, OrgAction.VIEW_MEMBERS),
        OrgRole.OFFICIAL to setOf(
            OrgAction.VIEW, OrgAction.VIEW_MEMBERS, OrgAction.ANNOUNCE, OrgAction.MANAGE_FIXTURES,
        ),
        OrgRole.ADMIN to OrgAction.entries.toSet(),
    )

    /** The one action a stranger may take (PD-009): the front of a club is public. */
    private val public: Set<OrgAction> = setOf(OrgAction.VIEW)

    public fun may(role: OrgRole, action: OrgAction): Boolean = action in allowed.getValue(role)

    /**
     * A public front and a private inside (PD-009). A person with no membership may open the page
     * and see nothing else; everything past the front door needs one.
     */
    public fun may(membership: Membership?, action: OrgAction): Boolean =
        if (membership == null) action in public else may(membership.role, action)

    /**
     * Who a viewer may see on the membership list.
     *
     * A member recorded as a MINOR — or whose age is not established, which is treated the same way
     * for the same reason as everywhere else — is listed **only to an admin**. That is the one case
     * where getting the visibility rule wrong matters, so it is a function rather than a convention:
     * a caller cannot render the list without going through it.
     */
    public fun visibleMembers(to: Membership?, members: List<Membership>): List<Membership> {
        if (!may(to, OrgAction.VIEW_MEMBERS)) return emptyList()
        if (to?.role == OrgRole.ADMIN) return members
        return members.filter { it.ageBand == AgeBand.ADULT }
    }
}

/**
 * One person's place in one organisation.
 *
 * The age band travels with the membership because every safeguarding decision needs it at the
 * moment of the decision, and a lookup inside the decision is a lookup that gets skipped. It is the
 * same reasoning ADR-008 gives for carrying it into `Authorizer.check`.
 */
public data class Membership(
    val organisation: OrganisationId,
    val person: PersonId,
    val role: OrgRole,
    val ageBand: AgeBand = AgeBand.UNKNOWN,
)

/**
 * The age dimension, as `packages/authz` defines it and for the same reason: unknown is a value and
 * is treated as the most restrictive case, because the thing you do not know is whether you are
 * dealing with a child. Duplicated rather than depended on because these packages are independent
 * builds; `AuthzAgeBand` in the API layer is where the two meet.
 */
public enum class AgeBand { UNKNOWN, MINOR, ADULT }

public data class Organisation(
    val id: OrganisationId,
    val kind: OrganisationKind,
    val name: String,
    val branding: Branding = Branding.default,
) {
    init {
        require(name.isNotBlank()) { "an organisation must have a name" }
        require(name.length <= 120) { "an organisation name must be 120 characters or fewer" }
    }
}
