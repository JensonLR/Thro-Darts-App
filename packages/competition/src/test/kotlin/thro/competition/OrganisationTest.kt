package thro.competition

import java.time.Instant
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * The organisational vocabulary (ADR-016) as pure types. These are the properties a contributor
 * would otherwise "fix" by adding a venue column to Team or a team column to Registration, so
 * each one fails the moment somebody does.
 */
class OrganisationTest {

    private val t0 = Instant.parse("2026-09-01T19:00:00Z")
    private val t1 = Instant.parse("2027-01-15T19:00:00Z")
    private val t2 = Instant.parse("2027-06-01T19:00:00Z")

    @Test
    fun `a team keeps its identity when it moves venue, and the history keeps both venues`() {
        val team = Team("riverside-a", "Riverside A")
        val old = Venue("riverside-club", "Riverside Club")
        val new = Venue("grange-wmc", "Grange WMC")
        val before = listOf(Tenure(team.id, old.id, TenureKind.HOME, Period(t0)))

        val after = TeamHistory.moveHome(team, before, new, t1)

        assertEquals(2, after.size)
        assertEquals(old.id, TeamHistory.homeVenueAt(after, t0.plusSeconds(1)))
        assertEquals(new.id, TeamHistory.homeVenueAt(after, t2))
        // The team is the same team: nothing about it was touched by the move.
        assertTrue(after.all { it.teamId == team.id })
        // The old tenure is closed at the move, not deleted, and its start is unchanged.
        val closed = after.single { it.venueId == old.id }
        assertEquals(Period(t0, t1), closed.period)
    }

    @Test
    fun `one venue hosts several teams at once`() {
        val venue = Venue("grange-wmc", "Grange WMC")
        val a = Tenure("grange-a", venue.id, TenureKind.HOME, Period(t0))
        val b = Tenure("grange-b", venue.id, TenureKind.HOME, Period(t0))
        // Nothing in the model relates the two: each team's tenure is its own fact.
        assertEquals(venue.id, TeamHistory.homeVenueAt(listOf(a), t1))
        assertEquals(venue.id, TeamHistory.homeVenueAt(listOf(b), t1))
    }

    @Test
    fun `a player may belong to several teams where the policy permits`() {
        val sam = "sam"
        val memberships = listOf(
            Membership(sam, "riverside-a", period = Period(t0)),
            Membership(sam, "county-side", period = Period(t0)),
        )
        assertTrue(TeamHistory.mayJoin(sam, memberships, maxConcurrentTeams = null, at = t1))
        assertTrue(TeamHistory.mayJoin(sam, memberships, maxConcurrentTeams = 3, at = t1))
        assertFalse(TeamHistory.mayJoin(sam, memberships, maxConcurrentTeams = 2, at = t1))
        // A cap counts concurrent memberships, so an ended one no longer counts against it.
        val ended = memberships.map { if (it.teamId == "county-side") it.copy(period = it.period.closedAt(t1)) else it }
        assertTrue(TeamHistory.mayJoin(sam, ended, maxConcurrentTeams = 2, at = t2))
    }

    @Test
    fun `membership is not registration`() {
        val sam = "sam"
        val season = LeagueSeason("tt-2026", "teesside-thursday", "2026/27")
        val member = Membership(sam, "riverside-a", period = Period(t0))

        // A member of a team with no registration is not registered for anything.
        assertFalse(Eligibility.isRegistered(emptyList(), sam, season.id, t1))

        // A registration made for the team stands after the player has left the team.
        val registration = Registration(sam, season.id, "riverside-a", RegistrationStatus.REGISTERED, "pol-1", Period(t0))
        val left = member.copy(period = member.period.closedAt(t1))
        assertFalse(left.period.contains(t2))
        assertTrue(Eligibility.isRegistered(listOf(registration), sam, season.id, t2))

        // And a registration is not a membership: it says which team it was made for, not that the
        // player belongs to it now.
        assertEquals("riverside-a", registration.teamId)
    }

    @Test
    fun `a registration is made under an approved policy or it is not one`() {
        assertFailsWith<IllegalArgumentException> {
            Registration("sam", "tt-2026", "riverside-a", RegistrationStatus.REGISTERED, policyId = null, period = Period(t0))
        }
        // Pending needs no policy yet: it is the state before assessment.
        Registration("sam", "tt-2026", "riverside-a", RegistrationStatus.PENDING, period = Period(t0))
    }

    @Test
    fun `historical membership is preserved - closing is the only change and it happens once`() {
        val p = Period(t0)
        val closed = p.closedAt(t1)
        assertEquals(t0, closed.from)
        assertEquals(t1, closed.until)
        assertFailsWith<IllegalStateException> { closed.closedAt(t2) }
        assertFailsWith<IllegalArgumentException> { Period(t1, t0) }
        // Membership at an instant reads the closed row too.
        val m = Membership("sam", "riverside-a", period = closed)
        assertEquals(setOf("sam"), TeamHistory.membersAt(listOf(m), t0.plusSeconds(1)))
        assertEquals(emptySet(), TeamHistory.membersAt(listOf(m), t2))
    }

    @Test
    fun `a league season is distinct from the league`() {
        val league = League("teesside-thursday", "Teesside Thursday League")
        val s1 = LeagueSeason("tt-2025", league.id, "2025/26")
        val s2 = LeagueSeason("tt-2026", league.id, "2026/27")
        assertEquals(s1.leagueId, s2.leagueId)
        assertTrue(s1 != s2)
        // Affiliation and registration name the season, never the league.
        val aff = Affiliation("riverside-a", s2.id, period = Period(t0))
        assertEquals(s2.id, aff.leagueSeasonId)
    }

    @Test
    fun `a tournament is not a league - the two structures share no shape`() {
        val event = Event("riverside-open-2026", tournamentId = "riverside-open")
        val season = LeagueSeason("tt-2026", "teesside-thursday", "2026/27")
        // An exhaustive when: the compiler requires both arms, so no code path can treat one as
        // the other by falling through a default.
        fun describe(c: Competition): String = when (c) {
            is Competition.OfLeague -> "season ${c.season.label} of ${c.season.leagueId}"
            is Competition.OfTournament -> "edition ${c.event.id} of ${c.event.tournamentId}"
        }
        assertEquals("season 2026/27 of teesside-thursday", describe(Competition.OfLeague(season)))
        assertEquals("edition riverside-open-2026 of riverside-open", describe(Competition.OfTournament(event)))
    }

    @Test
    fun `an entry is exactly one kind of entrant, and the event decides which`() {
        val singles = Event("open", entrantKind = EntrantKind.PLAYER)
        val pairs = Event("pairs", entrantKind = EntrantKind.PAIR)
        val teams = Event("inter-club", entrantKind = EntrantKind.TEAM)

        Entry(singles, Entrant.Player("sam"))
        Entry(pairs, Entrant.Pair("sam-and-jo", "sam", "jo"))
        Entry(teams, Entrant.Team("riverside-a"))

        assertFailsWith<IllegalArgumentException> { Entry(pairs, Entrant.Player("sam")) }
        assertFailsWith<IllegalArgumentException> { Entry(singles, Entrant.Team("riverside-a")) }
        assertFailsWith<IllegalArgumentException> { Entrant.Pair("x", "sam", "sam") }
        assertFailsWith<IllegalArgumentException> { Entry(singles, Entrant.Player("sam"), seed = 0) }

        // The resolved competitor is the typed identifier, whichever kind it is.
        assertEquals("riverside-a", Entrant.Team("riverside-a").competitorId)
        assertEquals("sam-and-jo", Entrant.Pair("sam-and-jo", "sam", "jo").competitorId)
    }

    @Test
    fun `a series contains events at different venues and holds nothing a league has`() {
        val e1 = Event("open-1", venueId = "riverside-club")
        val e2 = Event("open-2", venueId = "grange-wmc")
        val season = SeriesSeason("tour-2026", "north-east-tour", "2026", listOf(e1.id, e2.id))
        assertEquals(listOf("open-1", "open-2"), season.eventIds)
        assertFailsWith<IllegalArgumentException> {
            SeriesSeason("tour-2026", "north-east-tour", "2026", listOf(e1.id, e1.id))
        }
        // There is no affiliation, registration or fixture type that names a series season. This
        // is a compile-time fact; the assertion below is the closest a runtime test can come to it.
        assertNull(Affiliation::class.java.declaredFields.firstOrNull { it.name.contains("series", ignoreCase = true) })
        assertNull(Registration::class.java.declaredFields.firstOrNull { it.name.contains("series", ignoreCase = true) })
    }

    @Test
    fun `the match-time Competitor Team is a lineup, not the organisation`() {
        // ADR-016 keeps both. The lineup names the players who contested one match; the
        // organisation is a Team with a name and a history, and knows nothing of who played tonight.
        val lineup = Competitor.Team("riverside-a", listOf("sam", "jo", "ade", "kim"))
        val organisation = Team("riverside-a", "Riverside A")
        assertEquals(organisation.id, lineup.id)
        assertEquals(4, lineup.players.size)
    }
}
