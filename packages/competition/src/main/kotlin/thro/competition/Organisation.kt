package thro.competition

import java.time.Instant

/**
 * The organisational graph, as pure types. ADR-016.
 *
 * `Club` is not here, on purpose. It is a word people use for a [Team] or for a [Venue], and it
 * resolves to one of them every time. Everything below is a persistent identity or a **dated**
 * relationship between two of them; a dated relationship is closed by setting its end, never by
 * removing it, because "who played for whom last season" is the product.
 *
 * These types carry identifiers, not people. Display names and age bands live in the identity
 * module (ADR-005) and are joined at publication.
 */

/** A half-open period `[from, until)`. `until == null` means open. */
public data class Period(val from: Instant, val until: Instant? = null) {
    init {
        require(until == null || until > from) { "a period ends after it begins" }
    }

    public val isOpen: Boolean get() = until == null

    public fun contains(at: Instant): Boolean = !at.isBefore(from) && (until == null || at.isBefore(until))

    public fun overlaps(other: Period): Boolean {
        val thisEnd = until ?: Instant.MAX
        val otherEnd = other.until ?: Instant.MAX
        return from.isBefore(otherEnd) && other.from.isBefore(thisEnd)
    }

    /** Closing is the only permitted change, and only once. */
    public fun closedAt(at: Instant): Period {
        check(isOpen) { "a closed period is history and cannot change" }
        return copy(until = at)
    }
}

/** The competitive organisation, whatever it calls itself. Its venue is a [Tenure], not a field. */
public data class Team(val id: String, val name: String, val dissolvedAt: Instant? = null)

/** The physical place. Hosts many teams and many events; owns none of them. */
public data class Venue(val id: String, val name: String)

/** One sporting identity — THRØ ID. Its binding to an account is a claim elsewhere, never a field here. */
public data class Player(val id: String)

public enum class TenureKind { HOME, TRAINING, REGISTERED }

/** Where a team plays, for a period. A team keeps its identity across any number of these. */
public data class Tenure(val teamId: String, val venueId: String, val kind: TenureKind, val period: Period)

public enum class MembershipRole { PLAYER, CAPTAIN, VICE_CAPTAIN, ADMIN }

/** A player's dated relationship with a team. Says nothing about any league. */
public data class Membership(
    val playerId: String,
    val teamId: String,
    val role: MembershipRole = MembershipRole.PLAYER,
    val period: Period,
)

/** The recurring authority. Seasons, not leagues, hold affiliations, registrations and fixtures. */
public data class League(val id: String, val name: String)

public enum class RegistrationKind { TEAM, INDIVIDUAL }

/** One occurrence of a league: "Teesside Thursday League — 2026/27". */
public data class LeagueSeason(
    val id: String,
    val leagueId: String,
    val label: String,
    val registrationKind: RegistrationKind = RegistrationKind.TEAM,
)

/** A team's dated registration to a league season. About the team, never about a player. */
public data class Affiliation(
    val teamId: String,
    val leagueSeasonId: String,
    val divisionId: String? = null,
    val period: Period,
)

public enum class RegistrationStatus { PENDING, REGISTERED, REFUSED, LAPSED }

/**
 * A player's dated eligibility record in a league season.
 *
 * Shares no field with [Membership] beyond the player. [teamId] is the team the registration was
 * **made for**, as it stood at the time; it is not a reference to a membership and it does not
 * follow the player when they leave. A transfer is a new registration.
 */
public data class Registration(
    val playerId: String,
    val leagueSeasonId: String,
    val teamId: String?,
    val status: RegistrationStatus,
    /** The approved policy version this was assessed under. Required once registered. */
    val policyId: String? = null,
    val period: Period,
) {
    init {
        require(status != RegistrationStatus.REGISTERED || policyId != null) {
            "a registration is made under an approved policy, or it is not a registration"
        }
    }
}

/** The persistent identity of a discrete competition that may recur. Not a league. */
public data class Tournament(val id: String, val name: String)

public enum class EntrantKind { PLAYER, PAIR, TEAM }

public enum class EventAccess { OPEN, INVITATIONAL, QUALIFIED, RESTRICTED, MEMBER_ONLY }

/** One edition of a tournament: the thing with entries, check-in, a draw and boards. */
public data class Event(
    val id: String,
    val tournamentId: String? = null,
    val venueId: String? = null,
    val entrantKind: EntrantKind = EntrantKind.PLAYER,
    val access: EventAccess = EventAccess.OPEN,
)

/**
 * What enters an event. Exactly one shape per kind, so an entry cannot be a player and a team at
 * once, and the resolved [competitorId] is the identifier the draw, check-in and bracket tie key on.
 */
public sealed interface Entrant {
    public val kind: EntrantKind
    public val competitorId: String

    public data class Player(val playerId: String) : Entrant {
        override val kind: EntrantKind get() = EntrantKind.PLAYER
        override val competitorId: String get() = playerId
    }

    public data class Pair(val pairId: String, val playerA: String, val playerB: String) : Entrant {
        init {
            require(playerA != playerB) { "a pair is two distinct players" }
        }
        override val kind: EntrantKind get() = EntrantKind.PAIR
        override val competitorId: String get() = pairId
    }

    public data class Team(val teamId: String) : Entrant {
        override val kind: EntrantKind get() = EntrantKind.TEAM
        override val competitorId: String get() = teamId
    }
}

/** An entry in an event. Refuses an entrant of the wrong kind at construction, as the database does. */
public data class Entry(val event: Event, val entrant: Entrant, val seed: Int? = null) {
    init {
        require(entrant.kind == event.entrantKind) {
            "a ${event.entrantKind.name.lowercase()} event cannot accept a ${entrant.kind.name.lowercase()} entry"
        }
        require(seed == null || seed > 0) { "a seed is positive" }
    }
}

/** A linked collection of tournaments. Not a league: it holds events and nothing else. */
public data class Series(val id: String, val name: String)

/** A dated occurrence of a series, linking specific events in order. */
public data class SeriesSeason(val id: String, val seriesId: String, val label: String, val eventIds: List<String>) {
    init {
        require(eventIds.toSet().size == eventIds.size) { "an event appears once in a series season" }
    }
}

/**
 * The structures that produce matches. Exhaustive: a `when` over this must name both, which is how
 * the compiler stops a league behaviour being applied to a tournament by accident.
 */
public sealed interface Competition {
    public data class OfLeague(val season: LeagueSeason) : Competition
    public data class OfTournament(val event: Event) : Competition
}

/**
 * Pure operations over a team's dated relationships. Nothing here changes an identity; every
 * operation returns the old rows closed and the new row opened.
 */
public object TeamHistory {

    /**
     * Moves a team's home venue at [at]. The team is untouched; the open home tenure is closed at
     * [at] and a new one opened. Every earlier tenure is returned unchanged, which is the history.
     */
    public fun moveHome(team: Team, tenures: List<Tenure>, toVenue: Venue, at: Instant): List<Tenure> {
        require(tenures.all { it.teamId == team.id }) { "tenures belong to the team" }
        val open = tenures.filter { it.kind == TenureKind.HOME && it.period.isOpen }
        check(open.size <= 1) { "a team has at most one open home tenure" }
        val closed = open.map { it.copy(period = it.period.closedAt(at)) }
        val kept = tenures - open.toSet()
        return kept + closed + Tenure(team.id, toVenue.id, TenureKind.HOME, Period(at))
    }

    public fun homeVenueAt(tenures: List<Tenure>, at: Instant): String? =
        tenures.singleOrNull { it.kind == TenureKind.HOME && it.period.contains(at) }?.venueId

    /** Members at an instant, including anyone whose membership was later closed. */
    public fun membersAt(memberships: List<Membership>, at: Instant): Set<String> =
        memberships.filter { it.period.contains(at) }.map { it.playerId }.toSet()

    /**
     * Whether a player may hold one more membership under a policy that caps concurrent teams.
     * `null` means the policy sets no cap — which is the default, because that is a competition's
     * rule to make and not THRØ's.
     */
    public fun mayJoin(playerId: String, memberships: List<Membership>, maxConcurrentTeams: Int?, at: Instant): Boolean {
        if (maxConcurrentTeams == null) return true
        val current = memberships.count { it.playerId == playerId && it.period.contains(at) }
        return current < maxConcurrentTeams
    }
}

/**
 * The one question the registration model exists to answer honestly: is this player registered
 * for this season at this instant? Membership is not an input. Neither is payment.
 */
public object Eligibility {
    public fun isRegistered(registrations: List<Registration>, playerId: String, leagueSeasonId: String, at: Instant): Boolean =
        registrations.any {
            it.playerId == playerId && it.leagueSeasonId == leagueSeasonId &&
                it.status == RegistrationStatus.REGISTERED && it.period.contains(at)
        }
}
