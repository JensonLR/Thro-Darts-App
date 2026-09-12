package thro.api

import java.sql.Connection
import java.time.Instant
import java.time.LocalDate
import java.time.temporal.ChronoUnit
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import org.postgresql.util.PSQLException
import thro.authz.ObjectRef
import thro.authz.ObjectType

/**
 * A league's table, against a real PostgreSQL (PD-054, V041).
 *
 * The arithmetic is the easy half. What these hold is the half that would be wrong quietly: a team that only
 * *says* it plays in the league appearing as a row, an award inventing legs it never won, a corrected result
 * counted twice, a table ordered by THRØ's rules while looking like the league's, and the same table coming
 * out in a different order on the second read.
 */
class StandingsTest {

    private val configured = TestDatabase.configured
    private fun migrated(): Connection = TestDatabase.migrated()

    private val t0: Instant = Instant.parse("2026-09-01T19:00:00Z")
    private val now: Instant = Instant.parse("2026-11-01T21:00:00Z")

    /** A league with one division, three accepted teams, and the ids to play them against each other. */
    private class Season(val seasonId: UUID, val leagueId: UUID, val division: UUID,
                         val a: UUID, val b: UUID, val c: UUID)

    private fun season(orgs: Organisations, admin: UUID): Season {
        val league = orgs.createLeague("Teesside Thursday", "Teesside", by = admin)
        val seasonId = orgs.openSeason(league, "2026/27", LocalDate.of(2026, 9, 1), LocalDate.of(2027, 5, 31))
        val division = orgs.createDivision(seasonId, "Division One", 1)
        val teams = listOf("Grange A", "Riverside A", "Feathers A").map { orgs.createTeam(it, "Stockton", by = admin) }
        for (t in teams) orgs.acceptAffiliation(orgs.affiliate(t, seasonId, division, from = t0, by = admin), at = t0)
        return Season(seasonId, league, division, teams[0], teams[1], teams[2])
    }

    /** A fixture played, with a match behind it — which V014 insists on for any played outcome. */
    private fun played(
        c: Connection, orgs: Organisations, s: Season, home: UUID, away: UUID, legsHome: Int, legsAway: Int,
        admin: UUID, at: Instant = t0.plus(7, ChronoUnit.DAYS),
    ): UUID {
        val fixture = orgs.scheduleFixture(s.seasonId, s.division, home, away, at = at, by = admin)
        val match = UUID.randomUUID()
        val one = orgs.createPlayer()
        val two = orgs.createPlayer()
        // The columns as V018 left them: seats, not names. MigrationTest inserts `home_name` and `away_name`
        // deliberately, because it is testing the world as it was before V018 rewrote it — and copying that
        // insert into a test against a fully migrated database is exactly how this first failed.
        c.prepareStatement(
            """INSERT INTO evidence.match (match_id, home_id, away_id, starting_score,
                                           in_rule, out_rule, legs_mode, legs_target, throw_first)
               VALUES (?, ?, ?, 501, 'straight', 'double', 'first_to', 5, ?)""",
        ).use { ps ->
            ps.setObject(1, match); ps.setObject(2, one); ps.setObject(3, two); ps.setObject(4, one)
            ps.executeUpdate()
        }
        orgs.citeMatch(fixture, match)
        orgs.recordPlayedResult(fixture, legsHome, legsAway, by = admin)
        return fixture
    }

    private fun table(c: Connection, s: Season) = LeagueTable(c).of(s.seasonId, null, now)

    @Test
    fun `a season nobody has is not a table`() {
        if (!configured) return
        migrated().use { c ->
            val refused = assertFailsWith<LeagueTable.Refused> { LeagueTable(c).of(UUID.randomUUID(), null, now) }
            assertEquals(404, refused.status)
        }
    }

    @Test
    fun `THRO's standard orders a league that has said nothing, and the table says whose rules those are`() {
        if (!configured) return
        migrated().use { c ->
            val orgs = Organisations(c)
            val admin = orgs.createPlayer()
            val s = season(orgs, admin)
            played(c, orgs, s, s.a, s.b, 5, 2, admin)
            played(c, orgs, s, s.b, s.c, 3, 3, admin)

            val t = table(c, s)
            val rows = t.divisions.single().rows
            assertFalse(t.rules.mine, "the league approved no points policy, so these are not its rules")
            assertEquals(null, t.rules.policyId)
            assertTrue(t.rules.says.contains("THRØ's standard"), t.rules.says)
            assertEquals(listOf("points", "leg_difference", "legs_for"), t.rules.orderedBy)
            // Grange A won. Riverside A and Feathers A are level on a point each, so leg difference
            // separates them: Feathers only drew, Riverside drew and lost 2-5. The first version of this
            // test expected Riverside second — that was my arithmetic being wrong, not the table's, and it
            // is why the assertion below now names the step that separated each row rather than just the
            // order it produced.
            assertEquals(listOf("Grange A", "Feathers A", "Riverside A"), rows.map { it.name })
            assertEquals(2, rows[0].points, "two for the win")
            assertEquals(1, rows[1].points, "one for the draw")
            assertEquals(1, rows[2].points)
            assertEquals(3, rows[0].legDifference)
            assertEquals(0, rows[1].legDifference)
            assertEquals(-3, rows[2].legDifference)
            assertEquals(null, rows[0].separatedBy, "nothing is above the top of a table")
            assertEquals("points", rows[1].separatedBy, "the win is what put Grange A above them")
            assertEquals("leg_difference", rows[2].separatedBy, "and these two are told apart by their legs")
        }
    }

    @Test
    fun `a team that only says it plays in the league is in nobody's table`() {
        if (!configured) return
        migrated().use { c ->
            val orgs = Organisations(c)
            val admin = orgs.createPlayer()
            val s = season(orgs, admin)
            played(c, orgs, s, s.a, s.b, 5, 1, admin)

            // PD-049: a claim is a team speaking about itself. It reaches the league's public front as its
            // own say and must never become a place in the league's table.
            val sayer = orgs.createTeam("Anchor A", "Stockton", by = admin)
            c.prepareStatement(
                "INSERT INTO competition.team_league_claim (team_id, league_id, said_by) VALUES (?, ?, ?)",
            ).use { ps -> ps.setObject(1, sayer); ps.setObject(2, s.leagueId); ps.setObject(3, admin); ps.executeUpdate() }

            val names = table(c, s).divisions.single().rows.map { it.name }
            assertEquals(3, names.size, "the three the league accepted, and not the one that said so: $names")
            assertFalse(names.contains("Anchor A"))
        }
    }

    @Test
    fun `an award moves the points and never the legs`() {
        if (!configured) return
        migrated().use { c ->
            val orgs = Organisations(c)
            val admin = orgs.createPlayer()
            val s = season(orgs, admin)
            val fixture = orgs.scheduleFixture(s.seasonId, s.division, s.a, s.b, at = t0.plus(7, ChronoUnit.DAYS), by = admin)
            orgs.awardFixture(fixture, s.a, "the away side did not raise a team", by = admin)

            val rows = table(c, s).divisions.single().rows.associateBy { it.name }
            val won = rows.getValue("Grange A")
            val lost = rows.getValue("Riverside A")
            assertEquals(2, won.points, "a walkover is worth a win under THRØ's standard")
            assertEquals(0, won.legsFor, "a scoreline nobody threw would pollute every leg difference below it")
            assertEquals(0, won.legsAgainst)
            assertEquals(1, won.awardedFor)
            assertEquals(1, won.played, "the fixture still happened to the table")
            assertEquals(0, lost.points)
            assertEquals(1, lost.awardedAgainst)
            assertEquals(0, won.evidenced, "and nothing about it was scored on THRØ")
        }
    }

    @Test
    fun `a corrected result is counted once, and a voided one not at all`() {
        if (!configured) return
        migrated().use { c ->
            val orgs = Organisations(c)
            val admin = orgs.createPlayer()
            val s = season(orgs, admin)
            val fixture = played(c, orgs, s, s.a, s.b, 5, 0, admin)
            val live = c.prepareStatement(
                "SELECT outcome_id FROM competition.league_fixture_outcome WHERE fixture_id = ?",
            ).use { ps ->
                ps.setObject(1, fixture)
                ps.executeQuery().use { rs -> rs.next(); rs.getObject(1) as UUID }
            }
            // A second look is a second decision (V014): the first stays on the record and must not be added
            // to the second, or one fixture would be worth two results.
            orgs.recordPlayedResult(fixture, 2, 3, by = admin, supersedes = live)

            val corrected = table(c, s).divisions.single().rows.associateBy { it.name }
            assertEquals(1, corrected.getValue("Grange A").played, "one fixture, however often it was decided")
            assertEquals(0, corrected.getValue("Grange A").points, "and the answer that stands is the second one")
            assertEquals(2, corrected.getValue("Riverside A").points)
            assertEquals(2, corrected.getValue("Grange A").legsFor)

            val second = c.prepareStatement(
                "SELECT outcome_id FROM competition.league_fixture_outcome WHERE fixture_id = ? AND supersedes_outcome_id IS NOT NULL",
            ).use { ps ->
                ps.setObject(1, fixture)
                ps.executeQuery().use { rs -> rs.next(); rs.getObject(1) as UUID }
            }
            orgs.voidOutcome(fixture, second, "played under protest, to be replayed", by = admin)
            val voided = table(c, s).divisions.single().rows.associateBy { it.name }
            assertEquals(0, voided.getValue("Grange A").played, "a voided fixture is not a result")
            assertEquals(0, voided.getValue("Riverside A").points)
        }
    }

    @Test
    fun `a team that has played nothing is a row of zeroes rather than a team missing`() {
        if (!configured) return
        migrated().use { c ->
            val orgs = Organisations(c)
            val admin = orgs.createPlayer()
            val s = season(orgs, admin)
            played(c, orgs, s, s.a, s.b, 5, 4, admin)

            val feathers = table(c, s).divisions.single().rows.single { it.name == "Feathers A" }
            assertEquals(0, feathers.played)
            assertEquals(0, feathers.points)
            assertEquals(0, feathers.legsFor)
        }
    }

    @Test
    fun `a league's own rules replace THRO's, and the table says they are the league's`() {
        if (!configured) return
        migrated().use { c ->
            val orgs = Organisations(c)
            val admin = orgs.createPlayer()
            val s = season(orgs, admin)
            played(c, orgs, s, s.a, s.b, 5, 2, admin)
            played(c, orgs, s, s.b, s.c, 3, 3, admin)

            // Three a win and a point a leg: a shape THRØ's standard does not have, so a table ordered by it
            // cannot be mistaken for one ordered by the default.
            val policy = orgs.draftPolicy(
                "league_season", s.seasonId, "points", 1, LocalDate.of(2026, 9, 1),
                body = """{"win":3,"draw":1,"points_per_leg_won":1}""", by = admin,
            )
            orgs.approvePolicy(policy, by = admin)

            val t = table(c, s)
            val rows = t.divisions.single().rows.associateBy { it.name }
            assertTrue(t.rules.mine, "the league approved these")
            assertEquals(policy, t.rules.policyId)
            assertTrue(t.rules.says.contains("This league's own rules"), t.rules.says)
            assertEquals(8, rows.getValue("Grange A").points, "three for the win and five legs")
            assertEquals(6, rows.getValue("Riverside A").points, "one for the draw, two legs and three legs")
            assertEquals(4, rows.getValue("Feathers A").points, "one for the draw and three legs")
        }
    }

    @Test
    fun `rules THRO cannot apply refuse the table rather than quietly ordering it another way`() {
        if (!configured) return
        migrated().use { c ->
            val orgs = Organisations(c)
            val admin = orgs.createPlayer()
            val s = season(orgs, admin)
            played(c, orgs, s, s.a, s.b, 5, 2, admin)

            val policy = orgs.draftPolicy(
                "league_season", s.seasonId, "points", 1, LocalDate.of(2026, 9, 1),
                body = """{"win":2,"promotion_places":2}""", by = admin,
            )
            orgs.approvePolicy(policy, by = admin)

            val refused = assertFailsWith<LeagueTable.Refused> { table(c, s) }
            assertEquals(409, refused.status)
            assertTrue(refused.why.contains("promotion_places"),
                       "the league is told which of its own words THRØ could not execute: ${refused.why}")
        }
    }

    @Test
    fun `the same results come out in the same order twice`() {
        if (!configured) return
        migrated().use { c ->
            val orgs = Organisations(c)
            val admin = orgs.createPlayer()
            val s = season(orgs, admin)
            // Three teams level on everything the standard can separate them by: the order must still be the
            // same on the second read, or a published table reorders itself between two people looking at it.
            played(c, orgs, s, s.a, s.b, 3, 3, admin)
            played(c, orgs, s, s.b, s.c, 3, 3, admin)
            played(c, orgs, s, s.c, s.a, 3, 3, admin)

            val first = table(c, s).divisions.single().rows
            val again = table(c, s).divisions.single().rows
            assertEquals(first.map { it.name }, again.map { it.name })
            assertEquals(listOf(null, null, null), first.map { it.separatedBy },
                         "nothing in the chain separated them, and the table does not pretend otherwise")
        }
    }

    @Test
    fun `a fixture whose date has gone by with no result is counted and said`() {
        if (!configured) return
        migrated().use { c ->
            val orgs = Organisations(c)
            val admin = orgs.createPlayer()
            val s = season(orgs, admin)
            played(c, orgs, s, s.a, s.b, 5, 2, admin)
            orgs.scheduleFixture(s.seasonId, s.division, s.b, s.c, at = t0.plus(14, ChronoUnit.DAYS), by = admin)
            orgs.scheduleFixture(s.seasonId, s.division, s.a, s.c, at = now.plus(7, ChronoUnit.DAYS), by = admin)

            val division = table(c, s).divisions.single()
            assertEquals(1, division.awaitingResults,
                         "the one whose night has been and gone, and not the one still to come")
        }
    }

    @Test
    fun `a fixture's match is named once`() {
        if (!configured) return
        migrated().use { c ->
            val orgs = Organisations(c)
            val admin = orgs.createPlayer()
            val s = season(orgs, admin)
            val fixture = played(c, orgs, s, s.a, s.b, 5, 2, admin)
            val why = assertFailsWith<IllegalArgumentException> { orgs.citeMatch(fixture, UUID.randomUUID()) }
            assertTrue(why.message!!.contains("already names a match"), why.message!!)
        }
    }

    @Test
    fun `an official may declare a result nobody scored on THRO, and it is never evidence`() {
        if (!configured) return
        migrated().use { c ->
            val orgs = Organisations(c)
            val admin = orgs.createPlayer()
            val s = season(orgs, admin)
            played(c, orgs, s, s.a, s.b, 5, 2, admin)
            // This one never reached a phone: the secretary has it on a paper card (PD-055).
            val fixture = orgs.scheduleFixture(s.seasonId, s.division, s.b, s.c, at = t0.plus(7, ChronoUnit.DAYS), by = admin)
            orgs.declareResult(fixture, 4, 5, by = admin)

            val rows = table(c, s).divisions.single().rows.associateBy { it.name }
            assertEquals(1, rows.getValue("Feathers A").played, "a declared result is what happened")
            assertEquals(2, rows.getValue("Feathers A").points, "and it is worth a win like any other")
            assertEquals(5, rows.getValue("Feathers A").legsFor)
            assertEquals(0, rows.getValue("Feathers A").evidenced, "but nobody recorded it happening")
            assertEquals(1, rows.getValue("Grange A").evidenced, "where a match was scored on THRØ, the row says so")
        }
    }

    @Test
    fun `a fixture scored on THRO cannot have its result declared over the top`() {
        if (!configured) return
        migrated().use { c ->
            val orgs = Organisations(c)
            val admin = orgs.createPlayer()
            val s = season(orgs, admin)
            val fixture = played(c, orgs, s, s.a, s.b, 5, 2, admin)
            // Correcting a played result is what superseding is for; declaring a different scoreline over
            // the top of a match would be an official overwriting evidence with a recollection.
            val why = assertFailsWith<PSQLException> { orgs.declareResult(fixture, 9, 0, by = admin) }
            assertTrue(why.message!!.contains("read from the match"), why.message!!)
        }
    }

    @Test
    fun `running a league is for whoever was named to run it, and for nobody else`() {
        if (!configured) return
        migrated().use { c ->
            val orgs = Organisations(c)
            val admin = orgs.createPlayer()
            val stranger = orgs.createPlayer()
            val s = season(orgs, admin)
            val obj = ObjectRef(ObjectType.LEAGUE_SEASON, s.seasonId.toString())

            // PD-053: a league administrator is named and never self-appointed, so the default is nobody —
            // including the player who created the league, which is the case worth holding.
            assertFalse(Relations(c).decide(admin, "league_season.administer", obj).allowed,
                        "creating a league does not make you its administrator")
            assertFalse(Relations(c).decide(stranger, "league_season.administer", obj).allowed)

            Relations(c).grant(admin, "admin", obj)
            assertTrue(Relations(c).decide(admin, "league_season.administer", obj).allowed,
                       "and the person named to run it may")
            assertFalse(Relations(c).decide(stranger, "league_season.administer", obj).allowed,
                        "naming one administrator names one, not everybody")
        }
    }
    @Test
    fun `the standing result names itself, so a correction can name what it replaces`() {
        if (!configured) return
        migrated().use { c ->
            val orgs = Organisations(c)
            val admin = orgs.createPlayer()
            val s = season(orgs, admin)
            val fixture = played(c, orgs, s, s.a, s.b, 5, 2, admin)

            val first = Fixtures(c).of(s.seasonId).single().decided!!
            assertEquals(5, first.legsHome)
            // PD-059: without this a reader can see that a fixture has a result and has no way to say which
            // result, so the only correction available is a blind overwrite — which is the thing the
            // database refuses and therefore the thing nobody could do at all.
            orgs.recordPlayedResult(fixture, 4, 5, by = admin, supersedes = first.outcomeId)

            val second = Fixtures(c).of(s.seasonId).single().decided!!
            assertEquals(4, second.legsHome, "the correction is what stands")
            assertFalse(second.outcomeId == first.outcomeId, "and it is a different decision, not an edit")
        }
    }

    @Test
    fun `a correction that names a result somebody already corrected is refused`() {
        if (!configured) return
        migrated().use { c ->
            val orgs = Organisations(c)
            val admin = orgs.createPlayer()
            val s = season(orgs, admin)
            val fixture = played(c, orgs, s, s.a, s.b, 5, 2, admin)
            val first = Fixtures(c).of(s.seasonId).single().decided!!.outcomeId

            // Two officials open the fixture. The first correction lands.
            orgs.recordPlayedResult(fixture, 4, 5, by = admin, supersedes = first)

            // The second still holds the outcome it read, and its correction would silently undo the other's.
            // The database refuses it: superseding a result that is no longer standing leaves the standing
            // one unaccounted for, which is exactly the lost update nobody would have noticed.
            val why = assertFailsWith<PSQLException> {
                orgs.recordPlayedResult(fixture, 3, 5, by = admin, supersedes = first)
            }
            assertTrue(why.message!!.contains("already has an outcome"), why.message!!)

            val stands = Fixtures(c).of(s.seasonId).single().decided!!
            assertEquals(4, stands.legsHome, "the first correction still stands, untouched")
        }
    }

    @Test
    fun `an annulled fixture says so, and the table counts it as unplayed`() {
        if (!configured) return
        migrated().use { c ->
            val orgs = Organisations(c)
            val admin = orgs.createPlayer()
            val s = season(orgs, admin)
            val fixture = played(c, orgs, s, s.a, s.b, 5, 2, admin)
            val standing = Fixtures(c).of(s.seasonId).single().decided!!.outcomeId
            orgs.voidOutcome(fixture, standing, "played under protest, to be replayed", by = admin)

            val f = Fixtures(c).of(s.seasonId).single()
            // Two facts, and the point of PD-065 is that they are both true at once: there is no result,
            // and the reason there is no result is on the record where a reader can see it. A fixture that
            // simply reappeared under "still to play" would look like one nobody had got round to.
            assertEquals(null, f.decided, "a void is not a result")
            assertEquals("played under protest, to be replayed", f.annulled?.reason)
            assertEquals(0, table(c, s).divisions.single().rows.associateBy { it.name }
                .getValue("Grange A").played, "and the table counts it as unplayed")

            // Deciding it again clears the annulment: the fixture has a result, so it is not open any more.
            orgs.recordPlayedResult(fixture, 3, 5, by = admin)
            val replayed = Fixtures(c).of(s.seasonId).single()
            assertEquals(3, replayed.decided?.legsHome)
            assertEquals(null, replayed.annulled, "a fixture decided again is not still annulled")
        }
    }

    @Test
    fun `a fixture whose result was voided can be decided again`() {
        if (!configured) return
        migrated().use { c ->
            val orgs = Organisations(c)
            val admin = orgs.createPlayer()
            val s = season(orgs, admin)
            val fixture = played(c, orgs, s, s.a, s.b, 5, 2, admin)
            val first = Fixtures(c).of(s.seasonId).single().decided!!.outcomeId
            orgs.voidOutcome(fixture, first, "played under protest, to be replayed", by = admin)

            // Every reader agrees a voided fixture has no result: the table counts it as unplayed and the
            // fixture list shows nothing decided. So entering one must be entering a first result — there is
            // nothing on show to supersede, and an organiser looking at the page cannot name what they
            // cannot see.
            assertEquals(null, Fixtures(c).of(s.seasonId).single().decided, "a void is not a result")
            assertEquals(0, table(c, s).divisions.single().rows.associateBy { it.name }
                .getValue("Grange A").played)

            orgs.recordPlayedResult(fixture, 3, 5, by = admin)
            assertEquals(3, Fixtures(c).of(s.seasonId).single().decided?.legsHome,
                         "the replayed result stands, and the void stays on the record behind it")
        }
    }

    @Test
    fun `a season's fixtures say what is left and what was decided, and never name a private team`() {
        if (!configured) return
        migrated().use { c ->
            val orgs = Organisations(c)
            val admin = orgs.createPlayer()
            val s = season(orgs, admin)
            played(c, orgs, s, s.a, s.b, 5, 2, admin)
            val awarded = orgs.scheduleFixture(s.seasonId, s.division, s.b, s.c, at = t0.plus(7, ChronoUnit.DAYS), by = admin)
            orgs.awardFixture(awarded, s.b, "the away side did not raise a team", by = admin)
            orgs.scheduleFixture(s.seasonId, s.division, s.c, s.a, at = t0.plus(14, ChronoUnit.DAYS), by = admin)

            val all = Fixtures(c).of(s.seasonId)
            assertEquals(3, all.size, "played, awarded and still to play")
            assertEquals(listOf("played", "awarded", null), all.map { it.decided?.kind }, "soonest first")
            assertEquals(5, all[0].decided?.legsHome)
            assertEquals(true, all[1].decided?.awardedToHome, "the home side was given that one")
            assertEquals(null, all[2].decided, "and the last has been decided by nobody")

            // PD-056: a private team is unnamed and its fixtures are still listed — hiding them would leave
            // a hole in the league's own calendar, which is nobody's idea of privacy.
            // row_version advances or the trigger refuses it as a stale write — the same rule every other
            // write to a team obeys, and the reason a test cannot quietly sidestep the store.
            c.prepareStatement(
                "UPDATE competition.team SET visibility = 'private', row_version = row_version + 1 WHERE team_id = ?",
            ).use { ps ->
                ps.setObject(1, s.c); ps.executeUpdate()
            }
            val hidden = Fixtures(c).of(s.seasonId)
            assertEquals(3, hidden.size, "the fixtures are still there")
            assertFalse(hidden.any { it.home == "Feathers A" || it.away == "Feathers A" }, "and it is not named")
            assertTrue(hidden.any { it.home == null || it.away == null }, "the side is simply unnamed")
        }
    }
}
