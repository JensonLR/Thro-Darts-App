package thro.api

import java.sql.Connection
import java.sql.Timestamp
import java.time.Instant
import java.time.LocalDate
import java.util.UUID
import thro.competition.EntrantKind
import thro.competition.MembershipRole
import thro.competition.RegistrationKind
import thro.competition.Requirement
import thro.competition.TenureKind

/**
 * The organisational graph as the store holds it: teams, venues, leagues and their seasons,
 * tournaments, series, and the dated relationships between them (ADR-017).
 *
 * Three rules every method here obeys, because the schema does:
 *
 * - **Identity is a row; place and belonging are periods.** Moving a team's venue or ending a
 *   membership closes a period and opens another. Nothing is deleted; no application role can.
 * - **Membership is not registration.** [addMember] and [register] write different tables that
 *   share no key. Eligibility is derived from registration under an approved policy, never from
 *   membership and never from payment.
 * - **Tournaments and leagues share nothing.** An event has entries and a draw ([Competitions]);
 *   a league season has affiliations, registrations and fixtures (here).
 *
 * Personal data is not written here. A player is an identifier; the name behind it lives in the
 * identity module and is bound through `identity.player_claim`.
 */
public class Organisations(private val connection: Connection) {

    // --- players ------------------------------------------------------------------------------

    /** A sporting identity. Holds no name; that is the identity module's, reached through a claim. */
    public fun createPlayer(source: String = "self", by: UUID? = null): UUID {
        val id = UUID.randomUUID()
        connection.prepareStatement(
            "INSERT INTO competition.player (player_id, source, created_by) VALUES (?, ?, ?)",
        ).use { ps -> ps.setObject(1, id); ps.setString(2, source); ps.setObject(3, by); ps.executeUpdate() }
        return id
    }

    /**
     * Binds a player to the account that holds its personal data. Appended, never updated in
     * place: a wrong claim is revoked with a reason and both identities stand.
     */
    public fun claim(playerId: UUID, accountId: UUID, method: String, confirmedBy: UUID? = null): UUID {
        val id = UUID.randomUUID()
        connection.prepareStatement(
            """
            INSERT INTO identity.player_claim (claim_id, player_id, account_id, method, confirmed_by)
            VALUES (?, ?, ?, ?, ?)
            """.trimIndent(),
        ).use { ps ->
            ps.setObject(1, id); ps.setObject(2, playerId); ps.setObject(3, accountId)
            ps.setString(4, method); ps.setObject(5, confirmedBy); ps.executeUpdate()
        }
        return id
    }

    public fun revokeClaim(claimId: UUID, by: UUID, reason: String) {
        connection.prepareStatement(
            """
            UPDATE identity.player_claim SET revoked_at = clock_timestamp(), revoked_by = ?, revoked_reason = ?
             WHERE claim_id = ?
            """.trimIndent(),
        ).use { ps -> ps.setObject(1, by); ps.setString(2, reason); ps.setObject(3, claimId); ps.executeUpdate() }
    }

    // --- venues and teams ---------------------------------------------------------------------

    public fun createVenue(name: String, locality: String? = null, by: UUID? = null): UUID {
        val id = UUID.randomUUID()
        connection.prepareStatement(
            "INSERT INTO competition.venue (venue_id, name, locality, created_by) VALUES (?, ?, ?, ?)",
        ).use { ps ->
            ps.setObject(1, id); ps.setString(2, name); ps.setString(3, locality); ps.setObject(4, by)
            ps.executeUpdate()
        }
        return id
    }

    public fun createTeam(name: String, locality: String? = null, by: UUID? = null): UUID {
        val id = UUID.randomUUID()
        connection.prepareStatement(
            "INSERT INTO competition.team (team_id, name, locality, created_by) VALUES (?, ?, ?, ?)",
        ).use { ps ->
            ps.setObject(1, id); ps.setString(2, name); ps.setString(3, locality); ps.setObject(4, by)
            ps.executeUpdate()
        }
        return id
    }

    /** Renames a team. The previous name is kept, by trigger, with the period it applied to. */
    public fun renameTeam(teamId: UUID, to: String, expectedVersion: Int) {
        val n = connection.prepareStatement(
            "UPDATE competition.team SET name = ?, row_version = ? WHERE team_id = ? AND row_version = ?",
        ).use { ps ->
            ps.setString(1, to); ps.setInt(2, expectedVersion + 1); ps.setObject(3, teamId)
            ps.setInt(4, expectedVersion); ps.executeUpdate()
        }
        require(n == 1) { "stale write: team $teamId is not at version $expectedVersion" }
    }

    public fun openTenure(
        teamId: UUID, venueId: UUID, kind: TenureKind = TenureKind.HOME, from: Instant, by: UUID? = null,
    ): UUID {
        val id = UUID.randomUUID()
        connection.prepareStatement(
            """
            INSERT INTO competition.team_venue_tenure (tenure_id, team_id, venue_id, kind, valid_from, recorded_by)
            VALUES (?, ?, ?, ?, ?, ?)
            """.trimIndent(),
        ).use { ps ->
            ps.setObject(1, id); ps.setObject(2, teamId); ps.setObject(3, venueId)
            ps.setString(4, kind.name.lowercase()); ps.setObject(5, Timestamp.from(from)); ps.setObject(6, by)
            ps.executeUpdate()
        }
        return id
    }

    /**
     * Moves a team's home venue. The team row is not touched: the open home tenure is closed at
     * [at] and a new one opened, so the history reads "played at X until [at], at Y since".
     */
    public fun moveHome(teamId: UUID, toVenue: UUID, at: Instant, by: UUID? = null): UUID {
        connection.prepareStatement(
            """
            UPDATE competition.team_venue_tenure SET valid_until = ?
             WHERE team_id = ? AND kind = 'home' AND valid_until IS NULL
            """.trimIndent(),
        ).use { ps -> ps.setObject(1, Timestamp.from(at)); ps.setObject(2, teamId); ps.executeUpdate() }
        return openTenure(teamId, toVenue, TenureKind.HOME, at, by)
    }

    public data class TenureRow(val venueId: UUID, val kind: String, val from: Instant, val until: Instant?)

    public fun tenuresOf(teamId: UUID): List<TenureRow> {
        val out = mutableListOf<TenureRow>()
        connection.prepareStatement(
            "SELECT venue_id, kind, valid_from, valid_until FROM competition.team_venue_tenure WHERE team_id = ? ORDER BY valid_from",
        ).use { ps ->
            ps.setObject(1, teamId)
            ps.executeQuery().use { rs ->
                while (rs.next()) out += TenureRow(
                    rs.getObject(1) as UUID, rs.getString(2), rs.getTimestamp(3).toInstant(),
                    rs.getTimestamp(4)?.toInstant(),
                )
            }
        }
        return out
    }

    // --- membership ---------------------------------------------------------------------------

    public fun addMember(
        teamId: UUID, playerId: UUID, role: MembershipRole = MembershipRole.PLAYER, from: Instant, by: UUID? = null,
    ): UUID {
        val id = UUID.randomUUID()
        connection.prepareStatement(
            """
            INSERT INTO competition.team_membership (membership_id, team_id, player_id, role, valid_from, recorded_by)
            VALUES (?, ?, ?, ?, ?, ?)
            """.trimIndent(),
        ).use { ps ->
            ps.setObject(1, id); ps.setObject(2, teamId); ps.setObject(3, playerId)
            ps.setString(4, role.name.lowercase()); ps.setObject(5, Timestamp.from(from)); ps.setObject(6, by)
            ps.executeUpdate()
        }
        return id
    }

    /** Ends a membership. The row stays; it is what "played for them until March" is made of. */
    public fun endMembership(membershipId: UUID, at: Instant, reason: String? = null) {
        connection.prepareStatement(
            "UPDATE competition.team_membership SET valid_until = ?, ended_reason = ? WHERE membership_id = ?",
        ).use { ps ->
            ps.setObject(1, Timestamp.from(at)); ps.setString(2, reason); ps.setObject(3, membershipId)
            ps.executeUpdate()
        }
    }

    public data class MembershipRow(val membershipId: UUID, val teamId: UUID, val role: String, val from: Instant, val until: Instant?)

    public fun membershipsOf(playerId: UUID): List<MembershipRow> {
        val out = mutableListOf<MembershipRow>()
        connection.prepareStatement(
            """
            SELECT membership_id, team_id, role, valid_from, valid_until FROM competition.team_membership
             WHERE player_id = ? ORDER BY valid_from
            """.trimIndent(),
        ).use { ps ->
            ps.setObject(1, playerId)
            ps.executeQuery().use { rs ->
                while (rs.next()) out += MembershipRow(
                    rs.getObject(1) as UUID, rs.getObject(2) as UUID, rs.getString(3),
                    rs.getTimestamp(4).toInstant(), rs.getTimestamp(5)?.toInstant(),
                )
            }
        }
        return out
    }

    // --- leagues ------------------------------------------------------------------------------

    public fun createLeague(name: String, locality: String? = null, by: UUID? = null): UUID {
        val id = UUID.randomUUID()
        connection.prepareStatement(
            "INSERT INTO competition.league (league_id, name, locality, created_by) VALUES (?, ?, ?, ?)",
        ).use { ps ->
            ps.setObject(1, id); ps.setString(2, name); ps.setString(3, locality); ps.setObject(4, by)
            ps.executeUpdate()
        }
        return id
    }

    public fun openSeason(
        leagueId: UUID, label: String, startsOn: LocalDate, endsOn: LocalDate,
        registrationKind: RegistrationKind = RegistrationKind.TEAM,
    ): UUID {
        val id = UUID.randomUUID()
        connection.prepareStatement(
            """
            INSERT INTO competition.league_season
              (league_season_id, league_id, label, starts_on, ends_on, registration_kind)
            VALUES (?, ?, ?, ?, ?, ?)
            """.trimIndent(),
        ).use { ps ->
            ps.setObject(1, id); ps.setObject(2, leagueId); ps.setString(3, label)
            ps.setObject(4, startsOn); ps.setObject(5, endsOn)
            ps.setString(6, registrationKind.name.lowercase())
            ps.executeUpdate()
        }
        return id
    }

    public fun createDivision(leagueSeasonId: UUID, name: String, ordinal: Int): UUID {
        val id = UUID.randomUUID()
        connection.prepareStatement(
            "INSERT INTO competition.division (division_id, league_season_id, name, ordinal) VALUES (?, ?, ?, ?)",
        ).use { ps ->
            ps.setObject(1, id); ps.setObject(2, leagueSeasonId); ps.setString(3, name); ps.setInt(4, ordinal)
            ps.executeUpdate()
        }
        return id
    }

    public fun affiliate(teamId: UUID, leagueSeasonId: UUID, divisionId: UUID? = null, from: Instant, by: UUID? = null): UUID {
        val id = UUID.randomUUID()
        connection.prepareStatement(
            """
            INSERT INTO competition.team_affiliation
              (affiliation_id, team_id, league_season_id, division_id, valid_from, recorded_by)
            VALUES (?, ?, ?, ?, ?, ?)
            """.trimIndent(),
        ).use { ps ->
            ps.setObject(1, id); ps.setObject(2, teamId); ps.setObject(3, leagueSeasonId)
            ps.setObject(4, divisionId); ps.setObject(5, Timestamp.from(from)); ps.setObject(6, by)
            ps.executeUpdate()
        }
        return id
    }

    // --- policy -------------------------------------------------------------------------------

    /** A draft policy: it decides nothing until [approvePolicy]. */
    public fun draftPolicy(
        authorityKind: String, authorityId: UUID, kind: String, version: Int,
        effectiveFrom: LocalDate, body: String, provenance: String = "manual", sourceRef: String? = null,
        by: UUID? = null,
    ): UUID {
        val id = UUID.randomUUID()
        val column = when (authorityKind) {
            "league" -> "league_id"
            "league_season" -> "league_season_id"
            "event" -> "event_id"
            "series" -> "series_id"
            "series_season" -> "series_season_id"
            else -> throw IllegalArgumentException("no such authority kind: $authorityKind")
        }
        connection.prepareStatement(
            """
            INSERT INTO competition.policy
              (policy_id, authority_kind, $column, kind, version, effective_from, provenance, source_ref, body, created_by)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?::jsonb, ?)
            """.trimIndent(),
        ).use { ps ->
            ps.setObject(1, id); ps.setString(2, authorityKind); ps.setObject(3, authorityId)
            ps.setString(4, kind); ps.setInt(5, version); ps.setObject(6, effectiveFrom)
            ps.setString(7, provenance); ps.setString(8, sourceRef); ps.setString(9, body); ps.setObject(10, by)
            ps.executeUpdate()
        }
        return id
    }

    /** Approval is what makes a policy executable, and it names who did it. */
    public fun approvePolicy(policyId: UUID, by: UUID) {
        connection.prepareStatement(
            """
            UPDATE competition.policy
               SET approval_state = 'approved', approved_by = ?, approved_at = clock_timestamp()
             WHERE policy_id = ? AND approval_state = 'draft'
            """.trimIndent(),
        ).use { ps -> ps.setObject(1, by); ps.setObject(2, policyId); ps.executeUpdate() }
    }

    /** Closes the period of an approved policy so a successor can take over from [effectiveTo] + 1. */
    public fun supersedePolicy(policyId: UUID, effectiveTo: LocalDate) {
        connection.prepareStatement(
            "UPDATE competition.policy SET approval_state = 'superseded', effective_to = ? WHERE policy_id = ?",
        ).use { ps -> ps.setObject(1, effectiveTo); ps.setObject(2, policyId); ps.executeUpdate() }
    }

    // --- registration -------------------------------------------------------------------------

    /**
     * Registers a player for a league season under an approved policy. Deliberately takes no
     * membership: whether the player is a member of [teamId] is a different fact, and the league's
     * policy — not THRØ — says whether it matters.
     */
    public fun register(
        playerId: UUID, leagueSeasonId: UUID, teamId: UUID?, policyId: UUID, from: Instant,
        kind: RegistrationKind = RegistrationKind.TEAM, source: String = "thro", by: UUID? = null,
        supersedes: UUID? = null,
    ): UUID {
        val id = UUID.randomUUID()
        connection.prepareStatement(
            """
            INSERT INTO competition.player_registration
              (registration_id, player_id, league_season_id, registration_kind, team_id, status, policy_id,
               source, valid_from, recorded_by, supersedes_registration_id)
            VALUES (?, ?, ?, ?, ?, 'registered', ?, ?, ?, ?, ?)
            """.trimIndent(),
        ).use { ps ->
            ps.setObject(1, id); ps.setObject(2, playerId); ps.setObject(3, leagueSeasonId)
            ps.setString(4, kind.name.lowercase()); ps.setObject(5, teamId); ps.setObject(6, policyId)
            ps.setString(7, source); ps.setObject(8, Timestamp.from(from)); ps.setObject(9, by)
            ps.setObject(10, supersedes)
            ps.executeUpdate()
        }
        return id
    }

    public fun endRegistration(registrationId: UUID, at: Instant, reason: String? = null) {
        connection.prepareStatement(
            "UPDATE competition.player_registration SET valid_until = ?, ended_reason = ? WHERE registration_id = ?",
        ).use { ps ->
            ps.setObject(1, Timestamp.from(at)); ps.setString(2, reason); ps.setObject(3, registrationId)
            ps.executeUpdate()
        }
    }

    public fun isRegistered(playerId: UUID, leagueSeasonId: UUID, at: Instant): Boolean {
        connection.prepareStatement(
            """
            SELECT count(*) FROM competition.player_registration
             WHERE player_id = ? AND league_season_id = ? AND status = 'registered'
               AND valid_from <= ? AND (valid_until IS NULL OR valid_until > ?)
            """.trimIndent(),
        ).use { ps ->
            ps.setObject(1, playerId); ps.setObject(2, leagueSeasonId)
            ps.setObject(3, Timestamp.from(at)); ps.setObject(4, Timestamp.from(at))
            ps.executeQuery().use { rs -> rs.next(); return rs.getInt(1) > 0 }
        }
    }

    // --- tournaments, pairs, series -----------------------------------------------------------

    public fun createTournament(name: String, locality: String? = null, by: UUID? = null): UUID {
        val id = UUID.randomUUID()
        connection.prepareStatement(
            "INSERT INTO competition.tournament (tournament_id, name, locality, created_by) VALUES (?, ?, ?, ?)",
        ).use { ps ->
            ps.setObject(1, id); ps.setString(2, name); ps.setString(3, locality); ps.setObject(4, by)
            ps.executeUpdate()
        }
        return id
    }

    /** A pair is normalised so that (a, b) and (b, a) are the same row. */
    public fun createPair(playerA: UUID, playerB: UUID): UUID {
        require(playerA != playerB) { "a pair is two distinct players" }
        val (a, b) = if (playerA.toString() < playerB.toString()) playerA to playerB else playerB to playerA
        val id = UUID.randomUUID()
        connection.prepareStatement(
            "INSERT INTO competition.pair (pair_id, player_a, player_b) VALUES (?, ?, ?)",
        ).use { ps -> ps.setObject(1, id); ps.setObject(2, a); ps.setObject(3, b); ps.executeUpdate() }
        return id
    }

    public fun createSeries(name: String, by: UUID? = null): UUID {
        val id = UUID.randomUUID()
        connection.prepareStatement(
            "INSERT INTO competition.series (series_id, name, created_by) VALUES (?, ?, ?)",
        ).use { ps -> ps.setObject(1, id); ps.setString(2, name); ps.setObject(3, by); ps.executeUpdate() }
        return id
    }

    public fun openSeriesSeason(seriesId: UUID, label: String, startsOn: LocalDate, endsOn: LocalDate): UUID {
        val id = UUID.randomUUID()
        connection.prepareStatement(
            """
            INSERT INTO competition.series_season (series_season_id, series_id, label, starts_on, ends_on)
            VALUES (?, ?, ?, ?, ?)
            """.trimIndent(),
        ).use { ps ->
            ps.setObject(1, id); ps.setObject(2, seriesId); ps.setString(3, label)
            ps.setObject(4, startsOn); ps.setObject(5, endsOn); ps.executeUpdate()
        }
        return id
    }

    public fun linkEventToSeries(seriesSeasonId: UUID, eventId: UUID, ordinal: Int) {
        connection.prepareStatement(
            "INSERT INTO competition.series_event (series_season_id, event_id, ordinal) VALUES (?, ?, ?)",
        ).use { ps ->
            ps.setObject(1, seriesSeasonId); ps.setObject(2, eventId); ps.setInt(3, ordinal); ps.executeUpdate()
        }
    }

    // --- league fixtures ----------------------------------------------------------------------

    /**
     * Schedules a league fixture. The venue is copied from the home team's tenure at [at] and
     * frozen on the fixture, so a later venue move does not relocate it.
     */
    public fun scheduleFixture(
        leagueSeasonId: UUID, divisionId: UUID?, homeTeamId: UUID, awayTeamId: UUID, at: Instant,
        venueId: UUID? = homeVenueAt(homeTeamId, at), by: UUID? = null,
    ): UUID {
        val id = UUID.randomUUID()
        connection.prepareStatement(
            """
            INSERT INTO competition.league_fixture
              (fixture_id, league_season_id, division_id, home_team_id, away_team_id, scheduled_at, venue_id, created_by)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """.trimIndent(),
        ).use { ps ->
            ps.setObject(1, id); ps.setObject(2, leagueSeasonId); ps.setObject(3, divisionId)
            ps.setObject(4, homeTeamId); ps.setObject(5, awayTeamId); ps.setObject(6, Timestamp.from(at))
            ps.setObject(7, venueId); ps.setObject(8, by)
            ps.executeUpdate()
        }
        return id
    }

    public fun homeVenueAt(teamId: UUID, at: Instant): UUID? {
        connection.prepareStatement(
            """
            SELECT venue_id FROM competition.team_venue_tenure
             WHERE team_id = ? AND kind = 'home' AND valid_from <= ? AND (valid_until IS NULL OR valid_until > ?)
            """.trimIndent(),
        ).use { ps ->
            ps.setObject(1, teamId); ps.setObject(2, Timestamp.from(at)); ps.setObject(3, Timestamp.from(at))
            ps.executeQuery().use { rs -> return if (rs.next()) rs.getObject(1) as UUID else null }
        }
    }

    /** Rearranges a fixture. The original date is kept by the change log the trigger writes. */
    public fun rearrangeFixture(fixtureId: UUID, to: Instant, expectedVersion: Int, venueId: UUID? = null) {
        val n = connection.prepareStatement(
            """
            UPDATE competition.league_fixture
               SET scheduled_at = ?, venue_id = coalesce(?, venue_id), schedule_state = 'rearranged', row_version = ?
             WHERE fixture_id = ? AND row_version = ?
            """.trimIndent(),
        ).use { ps ->
            ps.setObject(1, Timestamp.from(to)); ps.setObject(2, venueId); ps.setInt(3, expectedVersion + 1)
            ps.setObject(4, fixtureId); ps.setInt(5, expectedVersion)
            ps.executeUpdate()
        }
        require(n == 1) { "stale write: fixture $fixtureId is not at version $expectedVersion" }
    }

    /** Awards a fixture unplayed: a decision with an actor and a reason, never a scoreline. */
    public fun awardFixture(fixtureId: UUID, toTeamId: UUID, reason: String, by: UUID, policyId: UUID? = null): UUID {
        val id = UUID.randomUUID()
        connection.prepareStatement(
            """
            INSERT INTO competition.league_fixture_outcome
              (outcome_id, fixture_id, kind, to_team_id, reason, decided_by, policy_id)
            VALUES (?, ?, 'awarded', ?, ?, ?, ?)
            """.trimIndent(),
        ).use { ps ->
            ps.setObject(1, id); ps.setObject(2, fixtureId); ps.setObject(3, toTeamId)
            ps.setString(4, reason); ps.setObject(5, by); ps.setObject(6, policyId)
            ps.executeUpdate()
        }
        return id
    }

    /** Voids an earlier outcome by superseding it. The earlier decision stays on the record. */
    public fun voidOutcome(fixtureId: UUID, supersedes: UUID, reason: String, by: UUID): UUID {
        val id = UUID.randomUUID()
        connection.prepareStatement(
            """
            INSERT INTO competition.league_fixture_outcome
              (outcome_id, fixture_id, kind, reason, decided_by, supersedes_outcome_id)
            VALUES (?, ?, 'void', ?, ?, ?)
            """.trimIndent(),
        ).use { ps ->
            ps.setObject(1, id); ps.setObject(2, fixtureId); ps.setString(3, reason)
            ps.setObject(4, by); ps.setObject(5, supersedes)
            ps.executeUpdate()
        }
        return id
    }

    // --- what an event requires of an entrant (V019) -----------------------------------------------

    /**
     * States one requirement of [eventId] in [group]. Rows in one group are alternatives; every
     * group must hold. Refused by the store on an open event, because "open" means open.
     */
    public fun requireForEntry(eventId: UUID, group: Int, requirement: Requirement, by: UUID): UUID {
        val id = UUID.randomUUID()
        val (kind, team, season, qualifier, band, player) = when (requirement) {
            is Requirement.TeamMember -> Sextuple("team_member", UUID.fromString(requirement.teamId), null, null, null, null)
            is Requirement.LeagueRegistered -> Sextuple("league_registered", null, UUID.fromString(requirement.leagueSeasonId), null, null, null)
            is Requirement.EnteredEvent -> Sextuple("entered_event", null, null, UUID.fromString(requirement.qualifierEventId), null, null)
            is Requirement.AgeBand -> Sextuple("age_band", null, null, null, requirement.band, null)
            is Requirement.Invited -> Sextuple("invited", null, null, null, null, UUID.fromString(requirement.playerId))
        }
        connection.prepareStatement(
            """
            INSERT INTO competition.event_eligibility
              (requirement_id, event_id, requirement_group, kind, team_id, league_season_id, qualifier_event_id, age_band, player_id, stated_by)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """.trimIndent(),
        ).use { ps ->
            ps.setObject(1, id); ps.setObject(2, eventId); ps.setInt(3, group); ps.setString(4, kind)
            ps.setObject(5, team); ps.setObject(6, season); ps.setObject(7, qualifier); ps.setString(8, band); ps.setObject(9, player)
            ps.setObject(10, by)
            ps.executeUpdate()
        }
        return id
    }

    /** Withdraws a stated requirement with a reason. The row stays; it is what the entrant was told. */
    public fun withdrawRequirement(requirementId: UUID, by: UUID, reason: String) {
        connection.prepareStatement(
            "UPDATE competition.event_eligibility SET withdrawn_at = clock_timestamp(), withdrawn_by = ?, withdrawn_reason = ? WHERE requirement_id = ?",
        ).use { ps -> ps.setObject(1, by); ps.setString(2, reason); ps.setObject(3, requirementId); ps.executeUpdate() }
    }

    /**
     * The store's answer: does the player satisfy every live group of the event's requirement at
     * [at]? `null` when the event states none, and the caller must not read that as yes.
     */
    public fun satisfiesEvent(playerId: UUID, eventId: UUID, at: Instant): Boolean? =
        connection.prepareStatement("SELECT competition.player_satisfies_event(?, ?, ?)").use { ps ->
            ps.setObject(1, playerId); ps.setObject(2, eventId); ps.setObject(3, Timestamp.from(at))
            ps.executeQuery().use { rs -> rs.next(); val b = rs.getBoolean(1); if (rs.wasNull()) null else b }
        }

    private data class Sextuple<A, B, C, D, E, F>(val a: A, val b: B, val c: C, val d: D, val e: E, val f: F)

    // --- match night (V021): availability and lineups, at the store level -------------------------
    // Authorization and the version the author saw live in OrganisationCommands; these write rows.

    public enum class Availability { AVAILABLE, UNAVAILABLE, MAYBE }

    public data class AvailabilityRow(val playerId: UUID, val teamId: UUID, val status: Availability, val recordedBy: UUID, val version: Int)

    /**
     * Records [playerId]'s availability for [fixtureId] as [by] says it. [expectedVersion] is 0 when
     * no row exists yet. Returns the new version, or null when the row was not at the expected
     * version — the store's own refusal (a non-member, a team not in the fixture) is thrown.
     */
    public fun recordAvailability(fixtureId: UUID, playerId: UUID, teamId: UUID, status: Availability, by: UUID, expectedVersion: Int): Int? {
        val n = if (expectedVersion == 0) {
            connection.prepareStatement(
                """
                INSERT INTO competition.availability (fixture_id, player_id, team_id, status, recorded_by)
                VALUES (?, ?, ?, ?, ?) ON CONFLICT DO NOTHING
                """.trimIndent(),
            ).use { ps ->
                ps.setObject(1, fixtureId); ps.setObject(2, playerId); ps.setObject(3, teamId)
                ps.setString(4, status.name.lowercase()); ps.setObject(5, by); ps.executeUpdate()
            }
        } else {
            connection.prepareStatement(
                """
                UPDATE competition.availability
                   SET status = ?, team_id = ?, recorded_by = ?, recorded_at = clock_timestamp(), row_version = ?
                 WHERE fixture_id = ? AND player_id = ? AND row_version = ?
                """.trimIndent(),
            ).use { ps ->
                ps.setString(1, status.name.lowercase()); ps.setObject(2, teamId); ps.setObject(3, by); ps.setInt(4, expectedVersion + 1)
                ps.setObject(5, fixtureId); ps.setObject(6, playerId); ps.setInt(7, expectedVersion); ps.executeUpdate()
            }
        }
        return if (n == 1) expectedVersion + 1 else null
    }

    public fun availabilityOf(fixtureId: UUID, playerId: UUID): AvailabilityRow? =
        connection.prepareStatement("SELECT team_id, status, recorded_by, row_version FROM competition.availability WHERE fixture_id = ? AND player_id = ?").use { ps ->
            ps.setObject(1, fixtureId); ps.setObject(2, playerId)
            ps.executeQuery().use { rs ->
                if (rs.next()) AvailabilityRow(playerId, rs.getObject(1) as UUID, Availability.valueOf(rs.getString(2).uppercase()), rs.getObject(3) as UUID, rs.getInt(4)) else null
            }
        }

    /**
     * Names [teamId]'s side for [fixtureId], in slot order. [expectedVersion] is 0 when no lineup
     * exists yet. Returns the new version, or null when the lineup was not at the expected version.
     * The store refuses a non-member, a team not in the fixture, and any change once the fixture
     * has a live outcome other than a void. The entries are written in the same transaction as the
     * naming and the store holds them to it (V022), so the side is complete when this commits.
     */
    public fun nameLineup(fixtureId: UUID, teamId: UUID, players: List<UUID>, by: UUID, expectedVersion: Int): Int? {
        require(players.isNotEmpty()) { "a lineup names at least one player" }
        require(players.toSet().size == players.size) { "a player is named once in a lineup" }
        // The naming and its entries are one transaction, whatever the caller's mode: the store
        // holds the entries to the naming's timestamp (V022), so they cannot be two.
        if (!connection.autoCommit) return nameLineupInTransaction(fixtureId, teamId, players, by, expectedVersion)
        connection.autoCommit = false
        try {
            val v = nameLineupInTransaction(fixtureId, teamId, players, by, expectedVersion)
            connection.commit()
            return v
        } catch (e: Exception) {
            connection.rollback()
            throw e
        } finally {
            connection.autoCommit = true
        }
    }

    private fun nameLineupInTransaction(fixtureId: UUID, teamId: UUID, players: List<UUID>, by: UUID, expectedVersion: Int): Int? {
        val n = if (expectedVersion == 0) {
            connection.prepareStatement(
                "INSERT INTO competition.lineup (fixture_id, team_id, named_by) VALUES (?, ?, ?) ON CONFLICT DO NOTHING",
            ).use { ps -> ps.setObject(1, fixtureId); ps.setObject(2, teamId); ps.setObject(3, by); ps.executeUpdate() }
        } else {
            connection.prepareStatement(
                "UPDATE competition.lineup SET named_by = ?, named_at = now(), row_version = ? WHERE fixture_id = ? AND team_id = ? AND row_version = ?",
            ).use { ps -> ps.setObject(1, by); ps.setInt(2, expectedVersion + 1); ps.setObject(3, fixtureId); ps.setObject(4, teamId); ps.setInt(5, expectedVersion); ps.executeUpdate() }
        }
        if (n != 1) return null
        val version = expectedVersion + 1
        connection.prepareStatement(
            "INSERT INTO competition.lineup_entry (fixture_id, team_id, lineup_version, slot, player_id) VALUES (?, ?, ?, ?, ?)",
        ).use { ps ->
            // One statement per entry, not a batch: a batch failure surfaces as BatchUpdateException
            // and the store's refusal — "not a member" — would lose its words on the way out.
            players.forEachIndexed { i, p ->
                ps.setObject(1, fixtureId); ps.setObject(2, teamId); ps.setInt(3, version); ps.setInt(4, i + 1); ps.setObject(5, p); ps.executeUpdate()
            }
        }
        return version
    }

    /** The side as currently named, in slot order; empty when none has been. */
    public fun currentLineup(fixtureId: UUID, teamId: UUID): List<UUID> =
        connection.prepareStatement("SELECT player_id FROM competition.current_lineup(?, ?)").use { ps ->
            ps.setObject(1, fixtureId); ps.setObject(2, teamId)
            ps.executeQuery().use { rs -> generateSequence { if (rs.next()) rs.getObject(1) as UUID else null }.toList() }
        }

    /** The side as named under [version], for history. */
    public fun lineupAt(fixtureId: UUID, teamId: UUID, version: Int): List<UUID> =
        connection.prepareStatement("SELECT player_id FROM competition.lineup_entry WHERE fixture_id = ? AND team_id = ? AND lineup_version = ? ORDER BY slot").use { ps ->
            ps.setObject(1, fixtureId); ps.setObject(2, teamId); ps.setInt(3, version)
            ps.executeQuery().use { rs -> generateSequence { if (rs.next()) rs.getObject(1) as UUID else null }.toList() }
        }

    public fun lineupVersion(fixtureId: UUID, teamId: UUID): Int =
        connection.prepareStatement("SELECT row_version FROM competition.lineup WHERE fixture_id = ? AND team_id = ?").use { ps ->
            ps.setObject(1, fixtureId); ps.setObject(2, teamId); ps.executeQuery().use { rs -> if (rs.next()) rs.getInt(1) else 0 }
        }
}
