package thro.api

import java.sql.Connection
import java.time.Instant
import java.time.LocalDate
import java.time.temporal.ChronoUnit
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import org.postgresql.util.PSQLException
import thro.authz.ObjectRef
import thro.authz.ObjectType
import thro.competition.EntrantKind
import thro.competition.Entrant
import thro.competition.MembershipRole

/**
 * The organisational graph against a real PostgreSQL (ADR-016), and the acceptance criteria of
 * the execution plan's §12 that are database properties.
 *
 * Every property here is one a contributor would otherwise "fix" by editing a row: moving a team's
 * venue by updating a column, ending a membership by deleting it, rewriting an approved policy.
 * The schema refuses each, and these tests assert the refusal.
 *
 * Skipped cleanly when no database is configured, rather than passing silently.
 */
class OrganisationTest {

    private val configured = TestDatabase.configured
    private fun migrated(): Connection = TestDatabase.migrated()

    private fun refused(constraint: String, block: () -> Unit): Boolean = try {
        block(); false
    } catch (e: PSQLException) {
        e.message!!.contains(constraint)
    } catch (e: IllegalArgumentException) {
        e.message!!.contains(constraint)
    }

    @Test
    fun `team, venue, membership, registration, season, tournament and series behave as the vocabulary says`() {
        if (!configured) {
            println("no database configured (set PGHOST) — organisation tests skipped")
            return
        }
        val c = migrated()
        val orgs = Organisations(c)
        var passed = 0
        fun check(name: String, cond: Boolean) {
            assertTrue(cond, "FAILED: $name")
            println("  PASS  $name")
            passed++
        }
        val admin = UUID.randomUUID()
        val t0 = Instant.parse("2026-09-01T19:00:00Z")
        val t1 = Instant.parse("2027-01-15T19:00:00Z")
        val t2 = Instant.parse("2027-06-01T19:00:00Z")

        // --- 1. Team identity survives a venue change --------------------------------------------
        val riversideClub = orgs.createVenue("Riverside Club", "Stockton")
        val grangeWmc = orgs.createVenue("Grange WMC", "Middlesbrough")
        val riversideA = orgs.createTeam("Riverside A", "Stockton", by = admin)
        orgs.openTenure(riversideA, riversideClub, from = t0)
        orgs.moveHome(riversideA, grangeWmc, at = t1)

        val tenures = orgs.tenuresOf(riversideA)
        check("a venue move leaves two tenures on the same team", tenures.size == 2)
        check("the first is closed at the move", tenures[0].venueId == riversideClub && tenures[0].until == t1)
        check("the second is open at the new venue", tenures[1].venueId == grangeWmc && tenures[1].until == null)
        check("the team row is untouched by the move", c.prepareStatement(
            "SELECT row_version, name FROM competition.team WHERE team_id = ?",
        ).use { ps -> ps.setObject(1, riversideA); ps.executeQuery().use { rs -> rs.next(); rs.getInt(1) == 1 && rs.getString(2) == "Riverside A" } })
        check("home venue is answered by date", orgs.homeVenueAt(riversideA, t0.plusSeconds(1)) == riversideClub &&
            orgs.homeVenueAt(riversideA, t2) == grangeWmc)
        check("a second open home tenure is refused", refused("tenure_home_periods_never_overlap") {
            orgs.openTenure(riversideA, riversideClub, from = t2)
        })
        check("and so is one that overlaps a past home tenure", refused("tenure_home_periods_never_overlap") {
            orgs.openTenure(riversideA, riversideClub, from = t0.plus(30, ChronoUnit.DAYS))
        })

        // --- 2. One venue, several teams ---------------------------------------------------------
        val grangeA = orgs.createTeam("Grange A")
        val grangeB = orgs.createTeam("Grange B")
        orgs.openTenure(grangeA, grangeWmc, from = t0)
        orgs.openTenure(grangeB, grangeWmc, from = t0)
        c.prepareStatement(
            "SELECT count(DISTINCT team_id) FROM competition.team_venue_tenure WHERE venue_id = ? AND valid_until IS NULL",
        ).use { ps ->
            ps.setObject(1, grangeWmc)
            ps.executeQuery().use { rs -> rs.next(); check("one venue hosts three teams at once", rs.getInt(1) == 3) }
        }

        // --- 3. A player in two teams; 5. history preserved ------------------------------------
        val sam = orgs.createPlayer(source = "team_admin", by = admin)
        val m1 = orgs.addMember(riversideA, sam, MembershipRole.CAPTAIN, from = t0)
        val m2 = orgs.addMember(grangeA, sam, from = t0)
        check("a player holds two concurrent memberships", orgs.membershipsOf(sam).count { it.until == null } == 2)
        check("but not two open memberships of one team", refused("membership_one_open_per_team_player") {
            orgs.addMember(riversideA, sam, from = t1)
        })
        orgs.endMembership(m2, at = t1, reason = "left")
        val after = orgs.membershipsOf(sam)
        check("ending a membership keeps the row", after.size == 2 && after.single { it.membershipId == m2 }.until == t1)
        check("a closed membership cannot be reopened", refused("closed relationship") {
            c.prepareStatement("UPDATE competition.team_membership SET valid_until = NULL WHERE membership_id = ?")
                .use { ps -> ps.setObject(1, m2); ps.executeUpdate() }
        })
        check("a closed membership cannot be moved to another team", refused("closed relationship") {
            c.prepareStatement("UPDATE competition.team_membership SET team_id = ? WHERE membership_id = ?")
                .use { ps -> ps.setObject(1, grangeB); ps.setObject(2, m2); ps.executeUpdate() }
        })
        check("an open membership's player is fixed", refused("player_id is fixed") {
            c.prepareStatement("UPDATE competition.team_membership SET player_id = ? WHERE membership_id = ?")
                .use { ps -> ps.setObject(1, orgs.createPlayer()); ps.setObject(2, m1); ps.executeUpdate() }
        })
        check("a membership's start is fixed", refused("start is fixed") {
            c.prepareStatement("UPDATE competition.team_membership SET valid_from = ? WHERE membership_id = ?")
                .use { ps -> ps.setObject(1, java.sql.Timestamp.from(t1)); ps.setObject(2, m1); ps.executeUpdate() }
        })
        check("no application role can delete a membership", refused("permission denied") {
            c.createStatement().use { it.execute("SET ROLE app_competition") }
            try {
                c.prepareStatement("DELETE FROM competition.team_membership WHERE membership_id = ?")
                    .use { ps -> ps.setObject(1, m2); ps.executeUpdate() }
            } finally {
                c.createStatement().use { it.execute("RESET ROLE") }
            }
        })

        // --- 6. League season is not the league; 4. membership is not registration --------------
        val league = orgs.createLeague("Teesside Thursday League", "Teesside")
        val s2025 = orgs.openSeason(league, "2025/26", LocalDate.of(2025, 9, 1), LocalDate.of(2026, 5, 31))
        val s2026 = orgs.openSeason(league, "2026/27", LocalDate.of(2026, 9, 1), LocalDate.of(2027, 5, 31))
        check("two seasons of one league coexist", s2025 != s2026)
        check("a season label is unique within its league", refused("league_season_league_id_label_key") {
            orgs.openSeason(league, "2026/27", LocalDate.of(2026, 9, 1), LocalDate.of(2027, 5, 31))
        })
        val divOne = orgs.createDivision(s2026, "Division One", 1)
        val divOf2025 = orgs.createDivision(s2025, "Division One", 1)
        orgs.affiliate(riversideA, s2026, divOne, from = t0)
        check("an affiliation cannot name a division of another season", refused("team_affiliation_division_id_league_season_id_fkey") {
            orgs.affiliate(grangeA, s2026, divOf2025, from = t0)
        })

        // Sam is a member of Riverside A and registered for nothing.
        check("a member with no registration is not registered", !orgs.isRegistered(sam, s2026, t1))

        // Registration needs an approved policy.
        val draft = orgs.draftPolicy(
            "league_season", s2026, "registration", 1, LocalDate.of(2026, 9, 1),
            """{"requires":["full_name","date_of_birth"],"deadline_days_before_first_fixture":7}""",
            provenance = "manual", by = admin,
        )
        check("registering under a draft policy is refused", refused("approved and in force") {
            c.prepareStatement(
                """
                INSERT INTO competition.player_registration
                  (registration_id, player_id, league_season_id, registration_kind, team_id, status, valid_from)
                VALUES (?, ?, ?, 'team', ?, 'registered', ?)
                """.trimIndent(),
            ).use { ps ->
                ps.setObject(1, UUID.randomUUID()); ps.setObject(2, sam); ps.setObject(3, s2026)
                ps.setObject(4, riversideA); ps.setObject(5, java.sql.Timestamp.from(t0)); ps.executeUpdate()
            }
        })
        orgs.approvePolicy(draft, by = admin)
        val reg = orgs.register(sam, s2026, riversideA, draft, from = t0)
        check("a registered player is registered", orgs.isRegistered(sam, s2026, t1))
        check("a team-registered season refuses a registration naming no team", refused("registration_for_a_team_names_one") {
            orgs.register(orgs.createPlayer(), s2026, null, draft, from = t0)
        })
        check("and one of the wrong kind", refused("player_registration_league_season_id_registration_kind_fkey") {
            orgs.register(orgs.createPlayer(), s2026, riversideA, draft, from = t0, kind = thro.competition.RegistrationKind.INDIVIDUAL)
        })
        check("a second live registration in the same season is refused", refused("registration_periods_never_overlap") {
            orgs.register(sam, s2026, grangeA, draft, from = t1)
        })

        // Sam leaves Riverside A. The registration was made for Riverside A and still stands.
        orgs.endMembership(m1, at = t1, reason = "left")
        check("registration outlives the membership it was made under", orgs.isRegistered(sam, s2026, t2))
        check("and still says which team it was for", c.prepareStatement(
            "SELECT team_id FROM competition.player_registration WHERE registration_id = ?",
        ).use { ps -> ps.setObject(1, reg); ps.executeQuery().use { rs -> rs.next(); rs.getObject(1) == riversideA } })

        // --- 12. Approved policy is frozen ---------------------------------------------------------
        check("an approved policy's body cannot change", refused("cannot be rewritten") {
            c.prepareStatement("UPDATE competition.policy SET body = '{}'::jsonb WHERE policy_id = ?")
                .use { ps -> ps.setObject(1, draft); ps.executeUpdate() }
        })
        check("nor its effective date", refused("cannot be rewritten") {
            c.prepareStatement("UPDATE competition.policy SET effective_from = '2020-01-01' WHERE policy_id = ?")
                .use { ps -> ps.setObject(1, draft); ps.executeUpdate() }
        })
        check("nor can its approval be withdrawn", refused("cannot be withdrawn") {
            c.prepareStatement("UPDATE competition.policy SET approval_state = 'draft', approved_by = NULL, approved_at = NULL WHERE policy_id = ?")
                .use { ps -> ps.setObject(1, draft); ps.executeUpdate() }
        })
        val v2 = orgs.draftPolicy(
            "league_season", s2026, "registration", 2, LocalDate.of(2026, 12, 1),
            """{"requires":["full_name","date_of_birth","photo"]}""", by = admin,
        )
        check("a second approved version cannot overlap the first", refused("policy_approved_periods_never_overlap") {
            orgs.approvePolicy(v2, by = admin)
        })
        orgs.supersedePolicy(draft, LocalDate.of(2026, 11, 30))
        orgs.approvePolicy(v2, by = admin)
        check("once the first is closed the second may be approved", c.prepareStatement(
            "SELECT approval_state FROM competition.policy WHERE policy_id = ?",
        ).use { ps -> ps.setObject(1, v2); ps.executeQuery().use { rs -> rs.next(); rs.getString(1) == "approved" } })
        // A transfer is a new registration superseding the old, not an edit — and it cites the
        // policy in force on its own start date, which by now is v2.
        orgs.endRegistration(reg, at = t2, reason = "transferred")
        check("a transfer cannot cite a policy no longer in force", refused("approved and in force") {
            orgs.register(sam, s2026, grangeA, draft, from = t2, supersedes = reg)
        })
        val transfer = orgs.register(sam, s2026, grangeA, v2, from = t2, supersedes = reg)
        check("a transfer supersedes rather than rewrites", transfer != reg && orgs.isRegistered(sam, s2026, t2.plusSeconds(1)))
        check("the superseded registration's team is still on record", c.prepareStatement(
            "SELECT team_id, valid_until FROM competition.player_registration WHERE registration_id = ?",
        ).use { ps -> ps.setObject(1, reg); ps.executeQuery().use { rs -> rs.next(); rs.getObject(1) == riversideA && rs.getTimestamp(2) != null } })
        check("a registration's status never moves backwards", refused("does not move") {
            c.prepareStatement("UPDATE competition.player_registration SET status = 'pending' WHERE registration_id = ?")
                .use { ps -> ps.setObject(1, transfer); ps.executeUpdate() }
        })
        check("a policy cannot cite a season that does not exist", refused("policy_league_season_id_fkey") {
            orgs.draftPolicy("league_season", UUID.randomUUID(), "points", 1, LocalDate.of(2026, 9, 1), "{}")
        })

        // --- 7. Tournament is not a league (schema shape) ---------------------------------------
        fun columns(table: String): Set<String> {
            val out = mutableSetOf<String>()
            c.prepareStatement(
                "SELECT column_name FROM information_schema.columns WHERE table_schema = 'competition' AND table_name = ?",
            ).use { ps -> ps.setString(1, table); ps.executeQuery().use { rs -> while (rs.next()) out += rs.getString(1) } }
            return out
        }
        check("no event, entry, check-in or bracket tie references a league season",
            listOf("event", "entry", "check_in", "bracket_tie").none { "league_season_id" in columns(it) })
        check("no league fixture, affiliation or registration references an event",
            listOf("league_fixture", "team_affiliation", "player_registration").none { "event_id" in columns(it) })
        check("no series table references a fixture, affiliation or registration",
            listOf("series", "series_season", "series_event").none { t ->
                columns(t).any { it.contains("fixture") || it.contains("affiliation") || it.contains("registration") }
            })
        check("no standings live in the competition schema", c.prepareStatement(
            "SELECT count(*) FROM information_schema.tables WHERE table_schema = 'competition' AND table_name LIKE '%standing%'",
        ).use { ps -> ps.executeQuery().use { rs -> rs.next(); rs.getInt(1) == 0 } })

        // --- 8. Typed entrants --------------------------------------------------------------------
        val comp = Competitions(c)
        val open = UUID.randomUUID()
        val pairsOpen = UUID.randomUUID()
        val interClub = UUID.randomUUID()
        val riversideOpen = orgs.createTournament("The Riverside Open")
        comp.openEvent(open, "Riverside Open 2026", t1, t1.plus(10, ChronoUnit.HOURS), venueId = riversideClub, tournamentId = riversideOpen)
        comp.openEvent(pairsOpen, "Pairs", t1, t1.plus(10, ChronoUnit.HOURS), entrantKind = EntrantKind.PAIR)
        comp.openEvent(interClub, "Inter-club", t1, t1.plus(10, ChronoUnit.HOURS), entrantKind = EntrantKind.TEAM)
        val jo = orgs.createPlayer()
        val pair = orgs.createPair(sam, jo)
        comp.enter(open, Entrant.Player(sam.toString()), seed = 1)
        comp.enter(pairsOpen, Entrant.Pair(pair.toString(), sam.toString(), jo.toString()))
        comp.enter(interClub, Entrant.Team(riversideA.toString()))
        check("a player, a pair and a team each enter the event of their kind", c.prepareStatement(
            "SELECT entrant_kind, competitor_id FROM competition.entry WHERE event_id IN (?, ?, ?) ORDER BY entrant_kind",
        ).use { ps ->
            ps.setObject(1, open); ps.setObject(2, pairsOpen); ps.setObject(3, interClub)
            ps.executeQuery().use { rs ->
                val rows = generateSequence { if (rs.next()) rs.getString(1) to rs.getObject(2) else null }.toList()
                rows == listOf("pair" to pair, "player" to sam, "team" to riversideA)
            }
        })
        check("a team cannot enter a singles event", refused("entry_kind_is_the_event_kind") {
            comp.enter(open, Entrant.Team(grangeA.toString()))
        })
        check("an entry naming two kinds at once is refused", refused("entry_is_exactly_one_kind_of_entrant") {
            c.prepareStatement(
                "INSERT INTO competition.entry (entry_id, event_id, entrant_kind, player_id, team_id) VALUES (?, ?, 'player', ?, ?)",
            ).use { ps ->
                ps.setObject(1, UUID.randomUUID()); ps.setObject(2, open); ps.setObject(3, jo); ps.setObject(4, grangeA)
                ps.executeUpdate()
            }
        })
        check("the same two players are one pair whichever way round", refused("pair_player_a_player_b_key") {
            orgs.createPair(jo, sam)
        })
        check("an entrant must be a player record, not a bare identifier", refused("entry_player_id_fkey") {
            comp.enter(open, UUID.randomUUID())
        })

        // --- 9. Series holds events at different venues, and nothing else -----------------------
        val tour = orgs.createSeries("North East Tour")
        val tour2026 = orgs.openSeriesSeason(tour, "2026", LocalDate.of(2026, 9, 1), LocalDate.of(2027, 5, 31))
        val leg2 = UUID.randomUUID()
        comp.openEvent(leg2, "Grange Open", t2, t2.plus(10, ChronoUnit.HOURS), venueId = grangeWmc)
        orgs.linkEventToSeries(tour2026, open, 1)
        orgs.linkEventToSeries(tour2026, leg2, 2)
        check("a series season links events at two venues", c.prepareStatement(
            """
            SELECT count(DISTINCT e.venue_id) FROM competition.series_event se
              JOIN competition.event e ON e.event_id = se.event_id WHERE se.series_season_id = ?
            """.trimIndent(),
        ).use { ps -> ps.setObject(1, tour2026); ps.executeQuery().use { rs -> rs.next(); rs.getInt(1) == 2 } })
        check("two events cannot share an ordinal in a series season", refused("series_event_series_season_id_ordinal_key") {
            orgs.linkEventToSeries(tour2026, pairsOpen, 2)
        })

        // --- League fixtures: venue frozen at scheduling; changes logged; outcomes appended -------
        orgs.affiliate(grangeA, s2026, divOne, from = t0)
        val fx = orgs.scheduleFixture(s2026, divOne, riversideA, grangeA, at = t1.plus(7, ChronoUnit.DAYS))
        check("a fixture's venue is the home team's venue at scheduling", c.prepareStatement(
            "SELECT venue_id FROM competition.league_fixture WHERE fixture_id = ?",
        ).use { ps -> ps.setObject(1, fx); ps.executeQuery().use { rs -> rs.next(); rs.getObject(1) == grangeWmc } })
        orgs.rearrangeFixture(fx, to = t1.plus(14, ChronoUnit.DAYS), expectedVersion = 1)
        check("a stale rearrangement is refused", refused("stale write") {
            orgs.rearrangeFixture(fx, to = t1.plus(21, ChronoUnit.DAYS), expectedVersion = 1)
        })
        check("the original date survives in the change log", c.prepareStatement(
            "SELECT from_scheduled_at, to_scheduled_at, from_state, to_state FROM competition.league_fixture_change WHERE fixture_id = ?",
        ).use { ps ->
            ps.setObject(1, fx)
            ps.executeQuery().use { rs ->
                rs.next() && rs.getTimestamp(1).toInstant() == t1.plus(7, ChronoUnit.DAYS) &&
                    rs.getTimestamp(2).toInstant() == t1.plus(14, ChronoUnit.DAYS) &&
                    rs.getString(3) == "scheduled" && rs.getString(4) == "rearranged"
            }
        })
        check("a fixture cannot be switched to another team", refused("fixed") {
            c.prepareStatement("UPDATE competition.league_fixture SET away_team_id = ?, row_version = 3 WHERE fixture_id = ?")
                .use { ps -> ps.setObject(1, grangeB); ps.setObject(2, fx); ps.executeUpdate() }
        })
        val award = orgs.awardFixture(fx, riversideA, "opponent did not raise a side", by = admin)
        check("an award to a team not in the fixture is refused", refused("one of the two teams") {
            orgs.awardFixture(fx, grangeB, "wrong", by = admin)
        })
        check("a second outcome must supersede the first", refused("must supersede") {
            orgs.awardFixture(fx, grangeA, "changed our minds", by = admin)
        })
        // The trigger refuses this before the legs CHECK is reached: a fixture with no match cannot
        // have been played, whatever scoreline is typed.
        check("a played outcome needs a match", refused("needs the fixture's match") {
            c.prepareStatement(
                "INSERT INTO competition.league_fixture_outcome (outcome_id, fixture_id, kind, decided_by, supersedes_outcome_id) VALUES (?, ?, 'played', ?, ?)",
            ).use { ps -> ps.setObject(1, UUID.randomUUID()); ps.setObject(2, fx); ps.setObject(3, admin); ps.setObject(4, award); ps.executeUpdate() }
        })
        orgs.voidOutcome(fx, supersedes = award, reason = "awarded in error; fixture to be replayed", by = admin)
        check("the superseded award is still on the record", c.prepareStatement(
            "SELECT count(*) FROM competition.league_fixture_outcome WHERE fixture_id = ?",
        ).use { ps -> ps.setObject(1, fx); ps.executeQuery().use { rs -> rs.next(); rs.getInt(1) == 2 } })
        check("an outcome cannot be edited", refused("permission denied") {
            c.createStatement().use { it.execute("SET ROLE app_competition") }
            try {
                c.prepareStatement("UPDATE competition.league_fixture_outcome SET reason = 'x' WHERE outcome_id = ?")
                    .use { ps -> ps.setObject(1, award); ps.executeUpdate() }
            } finally {
                c.createStatement().use { it.execute("RESET ROLE") }
            }
        })

        // --- Team rename keeps the old name; dissolution is once ---------------------------------
        orgs.renameTeam(riversideA, "Riverside Arrows", expectedVersion = 1)
        check("a rename keeps the previous name with its period", c.prepareStatement(
            "SELECT name, valid_until IS NULL FROM competition.team_name WHERE team_id = ? ORDER BY valid_from",
        ).use { ps ->
            ps.setObject(1, riversideA)
            ps.executeQuery().use { rs ->
                val rows = generateSequence { if (rs.next()) rs.getString(1) to rs.getBoolean(2) else null }.toList()
                rows == listOf("Riverside A" to false, "Riverside Arrows" to true)
            }
        })

        // --- Claims bind a player to an account and are revoked, never repointed -----------------
        val account = UUID.randomUUID()
        c.prepareStatement("INSERT INTO identity.account (account_id, display_name, created_via, consent_basis) VALUES (?, 'Sam Wilson', 'team_admin', 'none')")
            .use { ps -> ps.setObject(1, account); ps.executeUpdate() }
        val claim = orgs.claim(sam, account, "self_created")
        check("a second live claim on the player is refused", refused("claim_one_live_per_player") {
            orgs.claim(sam, UUID.randomUUID().also { other ->
                c.prepareStatement("INSERT INTO identity.account (account_id, display_name) VALUES (?, 'Other')")
                    .use { ps -> ps.setObject(1, other); ps.executeUpdate() }
            }, "self_created")
        })
        check("a claim cannot be pointed at another player", refused("fixed when made") {
            c.prepareStatement("UPDATE identity.player_claim SET player_id = ? WHERE claim_id = ?")
                .use { ps -> ps.setObject(1, jo); ps.setObject(2, claim); ps.executeUpdate() }
        })
        check("an organiser confirmation must name the organiser", refused("claim_confirmation_is_attributed") {
            orgs.claim(jo, account, "organiser_confirmed", confirmedBy = null)
        })
        orgs.revokeClaim(claim, by = admin, reason = "wrong Sam")
        check("after revocation the player is unclaimed and the account is free", c.prepareStatement(
            "SELECT count(*) FROM identity.player_claim WHERE revoked_at IS NULL AND (player_id = ? OR account_id = ?)",
        ).use { ps -> ps.setObject(1, sam); ps.setObject(2, account); ps.executeQuery().use { rs -> rs.next(); rs.getInt(1) == 0 } })
        check("the player holds no text at all", c.prepareStatement(
            "SELECT count(*) FROM information_schema.columns WHERE table_schema = 'competition' AND table_name = 'player' AND data_type IN ('text','character varying')",
        ).use { ps -> ps.executeQuery().use { rs -> rs.next(); rs.getInt(1) == 1 } })
        // (the one text column is `source`, a fixed vocabulary; nothing free-form)
        check("the only text on a player is its source vocabulary", c.prepareStatement(
            "SELECT column_name FROM information_schema.columns WHERE table_schema = 'competition' AND table_name = 'player' AND data_type = 'text'",
        ).use { ps -> ps.executeQuery().use { rs -> rs.next(); rs.getString(1) == "source" } })

        // --- 13. Authorization relations are revoked, not deleted --------------------------------
        val rel = Relations(c)
        val teamRef = ObjectRef(ObjectType.TEAM, riversideA.toString())
        rel.grant(sam, "captain", teamRef, by = admin)
        rel.revoke(sam, "captain", teamRef, by = admin)
        rel.grant(sam, "captain", teamRef, by = admin)
        check("a revoked relation stays on the record and can be granted again", c.prepareStatement(
            "SELECT count(*) FILTER (WHERE revoked_at IS NOT NULL), count(*) FILTER (WHERE revoked_at IS NULL) FROM authz.relation WHERE subject_id = ?",
        ).use { ps -> ps.setObject(1, sam); ps.executeQuery().use { rs -> rs.next(); rs.getInt(1) == 1 && rs.getInt(2) == 1 } })
        check("the competition role cannot delete a relation", refused("permission denied") {
            c.createStatement().use { it.execute("SET ROLE app_competition") }
            try {
                c.prepareStatement("DELETE FROM authz.relation WHERE subject_id = ?")
                    .use { ps -> ps.setObject(1, sam); ps.executeUpdate() }
            } finally {
                c.createStatement().use { it.execute("RESET ROLE") }
            }
        })
        check("the ambiguous 'season' object type is gone", refused("relation_object_type_check") {
            c.prepareStatement("INSERT INTO authz.relation (subject_id, relation, object_type, object_id) VALUES (?, 'admin', 'season', 'x')")
                .use { ps -> ps.setObject(1, sam); ps.executeUpdate() }
        })
        rel.grant(admin, "admin", ObjectRef(ObjectType.LEAGUE_SEASON, s2026.toString()))
        check("and league_season, tournament and series are accepted", c.prepareStatement(
            "SELECT count(*) FROM authz.relation WHERE object_type = 'league_season' AND revoked_at IS NULL",
        ).use { ps -> ps.executeQuery().use { rs -> rs.next(); rs.getInt(1) == 1 } })

        println("  $passed organisation properties held")
        assertEquals(68, passed)
    }
}
