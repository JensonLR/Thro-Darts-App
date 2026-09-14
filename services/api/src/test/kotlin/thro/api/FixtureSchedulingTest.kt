package thro.api

import io.ktor.client.request.get
import io.ktor.client.request.header
import io.ktor.client.request.post
import io.ktor.client.request.setBody
import io.ktor.client.statement.HttpResponse
import io.ktor.client.statement.bodyAsText
import io.ktor.server.testing.testApplication
import java.time.Instant
import java.time.LocalDate
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertTrue
import thro.api.http.Authenticator
import thro.api.http.Deps
import thro.api.http.thro
import thro.authz.ObjectRef
import thro.authz.ObjectType

/**
 * A season gets its fixtures (PD-099). Until this, nothing could create one: a season arrived from the directory
 * with teams waiting to be let in and no fixture to enter a result against, so every surface built on fixtures —
 * results, the table, the live board, the television — had nothing to show.
 *
 * Held here at the HTTP layer, because who may do this is as much the point as what it does.
 */
class FixtureSchedulingTest {

    @Test
    fun `a league's named administrator lets teams in and gives the season its fixtures, all or nothing`() {
        if (!TestDatabase.configured) {
            println("no database configured (set PGHOST) — fixture scheduling tests skipped")
            return
        }
        val c = TestDatabase.migrated()
        val orgs = Organisations(c)
        var passed = 0
        fun check(name: String, cond: Boolean) {
            assertTrue(cond, "FAILED: $name")
            println("  PASS  $name")
            passed++
        }

        // --- the world ------------------------------------------------------------------------------------
        val lee = UUID.randomUUID()   // the league's secretary, named
        val zed = UUID.randomUUID()   // anybody else
        val t0 = Instant.parse("2026-08-01T00:00:00Z")
        val league = orgs.createLeague("Teesside Thursday League")
        val season = orgs.openSeason(league, "2026/27", LocalDate.of(2026, 9, 1), LocalDate.of(2027, 5, 31))
        val premier = orgs.createDivision(season, "Premier", 1)
        val first = orgs.createDivision(season, "First", 2)
        Relations(c).grant(lee, "admin", ObjectRef(ObjectType.LEAGUE_SEASON, season.toString()))
        val anchor = orgs.createTeam("Anchor A")
        val bell = orgs.createTeam("Bell A")
        val crown = orgs.createTeam("Crown A")      // applied, never let in
        val dragon = orgs.createTeam("Dragon A")    // let in, but to the First division
        val pub = orgs.createVenue("The Anchor")
        orgs.openTenure(anchor, pub, from = t0)
        val anchorIn = orgs.affiliate(anchor, season, premier, from = t0)
        val bellIn = orgs.affiliate(bell, season, premier, from = t0)
        orgs.affiliate(crown, season, premier, from = t0)
        val dragonIn = orgs.affiliate(dragon, season, first, from = t0)
        orgs.acceptAffiliation(dragonIn, t0)

        fun fixturesIn(s: UUID) = c.prepareStatement("SELECT count(*) FROM competition.league_fixture WHERE league_season_id = ?")
            .use { ps -> ps.setObject(1, s); ps.executeQuery().use { rs -> rs.next(); rs.getInt(1) } }

        testApplication {
            application { thro(Deps(connect = { TestDatabase.connect() }, authenticator = Authenticator.Dev(), now = { Instant.parse("2026-08-20T18:00:00Z") })) }
            suspend fun post(path: String, body: String, subject: UUID? = lee): HttpResponse = client.post(path) {
                subject?.let { header(Authenticator.Dev.HEADER, it.toString()) }
                setBody(body)
            }
            suspend fun get(path: String, subject: UUID? = lee): HttpResponse = client.get(path) {
                subject?.let { header(Authenticator.Dev.HEADER, it.toString()) }
            }
            fun one(home: UUID, away: UUID, at: String, division: UUID? = null) =
                """{"homeTeamId":"$home","awayTeamId":"$away","scheduledAt":"$at"${division?.let { ",\"divisionId\":\"$it\"" } ?: ""}}"""
            fun batch(vararg f: String) = """{"fixtures":[${f.joinToString(",")}]}"""

            // --- who may look -------------------------------------------------------------------------
            check("a season's teams, for running it, need a principal", get("/v1/seasons/$season/teams", subject = null).status.value == 401)
            check("and refuse anybody who does not administer the season", get("/v1/seasons/$season/teams", subject = zed).status.value == 403)
            check("and a season nobody has is a 404, whoever asks", get("/v1/seasons/${UUID.randomUUID()}/teams").status.value == 404)
            val teams = get("/v1/seasons/$season/teams")
            val listed = teams.bodyAsText()
            check("the administrator sees every team that asked in, waiting or accepted, with the division it asked for",
                teams.status.value == 200 && listed.contains("\"affiliationId\":\"$anchorIn\"") && listed.contains("Crown A")
                    && listed.contains("\"status\":\"applied\"") && listed.contains("\"status\":\"accepted\"")
                    && listed.contains("\"divisionId\":\"$premier\"") && listed.contains("\"name\":\"Premier\""))
            check("and the season's dates, which bound its fixtures", listed.contains("\"startsOn\":\"2026-09-01\"") && listed.contains("\"endsOn\":\"2027-05-31\""))

            // --- letting teams in, through the route that already existed ------------------------------
            check("accepting a team is the administrator's", post("/v1/seasons/$season/affiliations/$anchorIn", "{}", subject = zed).status.value == 403)
            check("the administrator lets Anchor and Bell in",
                post("/v1/seasons/$season/affiliations/$anchorIn", "{}").status.value == 200
                    && post("/v1/seasons/$season/affiliations/$bellIn", "{}").status.value == 200)

            // --- who may schedule ----------------------------------------------------------------------
            val good = batch(one(anchor, bell, "2026-09-10T19:30:00Z"), one(bell, anchor, "2027-01-14T19:30:00Z"))
            check("scheduling needs a principal", post("/v1/seasons/$season/fixtures", good, subject = null).status.value == 401)
            check("scheduling is refused to anybody who does not administer the season", post("/v1/seasons/$season/fixtures", good, subject = zed).status.value == 403)
            check("scheduling into a season nobody has is a 404", post("/v1/seasons/${UUID.randomUUID()}/fixtures", good).status.value == 404)
            check("and nothing was written by any of those", fixturesIn(season) == 0)

            // --- what a fixture has to be ----------------------------------------------------------------
            check("a body that is not a list of fixtures is a 400", post("/v1/seasons/$season/fixtures", """{"fixtures":"soon"}""").status.value == 400)
            check("an empty list is a 400", post("/v1/seasons/$season/fixtures", batch()).status.value == 400)
            check("a date that is not an instant is a 400", post("/v1/seasons/$season/fixtures", batch(one(anchor, bell, "next Thursday"))).status.value == 400)
            check("a team id that is not a UUID is a 400", post("/v1/seasons/$season/fixtures", """{"fixtures":[{"homeTeamId":"anchor","awayTeamId":"$bell","scheduledAt":"2026-09-10T19:30:00Z"}]}""").status.value == 400)
            check("more than a season's worth in one go is a 400",
                post("/v1/seasons/$season/fixtures", batch(*Array(401) { one(anchor, bell, "2026-09-10T19:30:00Z") })).status.value == 400)

            val waiting = post("/v1/seasons/$season/fixtures", batch(one(anchor, crown, "2026-09-10T19:30:00Z")))
            check("a team still waiting to be let in cannot be given a fixture, and the refusal names it",
                waiting.status.value == 422 && waiting.bodyAsText().contains("Crown A"))
            val stranger = post("/v1/seasons/$season/fixtures", batch(one(anchor, orgs.createTeam("Elsewhere A"), "2026-09-10T19:30:00Z")))
            check("nor a team that never asked to be in this season", stranger.status.value == 422)
            check("a team cannot play itself", post("/v1/seasons/$season/fixtures", batch(one(anchor, anchor, "2026-09-10T19:30:00Z"))).status.value == 422)
            check("a fixture before the season starts is refused", post("/v1/seasons/$season/fixtures", batch(one(anchor, bell, "2026-08-31T19:30:00Z"))).status.value == 422)
            check("and one after it ends", post("/v1/seasons/$season/fixtures", batch(one(anchor, bell, "2027-06-01T19:30:00Z"))).status.value == 422)
            check("the season's last day is inside it", post("/v1/seasons/$season/fixtures", batch(one(anchor, bell, "2027-05-31T19:30:00Z"))).status.value == 200)
            check("teams in different divisions cannot be drawn against each other in a league fixture",
                post("/v1/seasons/$season/fixtures", batch(one(anchor, dragon, "2026-09-10T19:30:00Z"))).status.value == 422)
            check("nor put in a division neither of them is in",
                post("/v1/seasons/$season/fixtures", batch(one(anchor, bell, "2026-09-10T19:30:00Z", first))).status.value == 422)
            check("the same fixture twice in one list is refused",
                post("/v1/seasons/$season/fixtures", batch(one(anchor, bell, "2026-09-17T19:30:00Z"), one(anchor, bell, "2026-09-17T19:30:00Z"))).status.value == 422)
            val clash = post("/v1/seasons/$season/fixtures", batch(one(anchor, bell, "2026-09-17T19:30:00Z"), one(bell, anchor, "2026-09-17T19:30:00Z")))
            check("a team cannot be in two fixtures at the same moment", clash.status.value == 422 && clash.bodyAsText().contains("playing twice"))
            val before = fixturesIn(season)
            val mixed = post("/v1/seasons/$season/fixtures", batch(one(anchor, bell, "2026-09-24T19:30:00Z"), one(bell, crown, "2026-10-01T19:30:00Z")))
            check("one bad fixture refuses the whole list, and says which one", mixed.status.value == 422 && mixed.bodyAsText().contains("Fixture 2"))
            check("and none of that list was written", fixturesIn(season) == before)

            // --- the season gets its fixtures ------------------------------------------------------------
            val made = post("/v1/seasons/$season/fixtures", good)
            val madeText = made.bodyAsText()
            check("the administrator schedules a home and an away", made.status.value == 200 && Regex("\"fixtureId\"").findAll(madeText).count() == 2)
            check("both are written", fixturesIn(season) == before + 2)
            val again = post("/v1/seasons/$season/fixtures", good)
            check("sending the same list again is a 409, and plays nothing twice", again.status.value == 409 && fixturesIn(season) == before + 2)
            val ids = Regex("\"fixtureId\":\"([0-9a-f-]{36})\"").findAll(madeText).map { UUID.fromString(it.groupValues[1]) }.toList()
            val public = get("/v1/seasons/$season/fixtures", subject = null).bodyAsText()
            check("they are on the season's public fixture list, in the teams' own division",
                ids.all { public.contains(it.toString()) } && public.contains("Premier"))
            check("and a fixture at home takes the home team's venue", public.contains("The Anchor"))

            // --- and a result can be entered against one, which is the point -----------------------------
            val result = post("/v1/fixtures/${ids.first()}/result", """{"legsHome":6,"legsAway":3}""")
            check("a result goes in against a scheduled fixture", result.status.value == 200 && result.bodyAsText().contains("\"kind\":\"declared\""))
            val table = get("/v1/seasons/$season/standings", subject = null).bodyAsText()
            check("and the season's table has its first row with points in it", table.contains("Anchor A") && table.contains("Bell A"))
        }
        println("fixture scheduling: $passed checks passed")
    }
}
