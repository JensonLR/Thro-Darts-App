package thro.api

import io.ktor.client.request.get
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
 * What THRØ knows about a league, said on the public list (PD-126). Most of the list is a directory: leagues placed
 * where they say they are, run somewhere else, with nothing of theirs on THRØ. A few are run here — started here, or
 * run by the person named to run them — and only those can have fixtures and a table. A reader cannot tell the two
 * apart unless the list says so, and a list that does not say so reads as three hundred leagues on THRØ, which is false.
 */
class LeagueStandingTest {

    @Test
    fun `the list says which leagues are run on THRØ, and how many fixtures and results each season holds`() {
        if (!TestDatabase.configured) {
            println("no database configured (set PGHOST) — league standing tests skipped")
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
        val t0 = Instant.parse("2026-09-01T18:00:00Z")
        val jen = UUID.randomUUID(); val lee = UUID.randomUUID()

        // Listed from the directory, nothing of its own here.
        orgs.createLeague("Aardvark Listed League", "Salisbury")
        // Listed from the directory with its teams imported, and nobody running it here.
        val filled = orgs.createLeague("Badger Imported League", "Stockton-on-Tees")
        val filledSeason = orgs.openSeason(filled, "2026", LocalDate.of(2026, 1, 1), LocalDate.of(2026, 12, 31))
        val filledDivision = orgs.createDivision(filledSeason, "Premier", 1)
        orgs.acceptAffiliation(orgs.affiliate(orgs.createTeam("Blue Bell"), filledSeason, divisionId = filledDivision, from = t0), t0)
        // Listed from the directory, and the person named to run it runs it here.
        val named = orgs.createLeague("Cormorant Named League", "Redcar")
        val namedSeason = orgs.openSeason(named, "2026", LocalDate.of(2026, 1, 1), LocalDate.of(2026, 12, 31))
        Relations(c).grant(lee, "admin", ObjectRef(ObjectType.LEAGUE_SEASON, namedSeason.toString()))
        // Started here, with two fixtures and one of them decided.
        val started = SeasonPlanning(c).startLeague(jen, "Dolphin Started League", "Yarm",
            SeasonPlanning.Opening("2026-27", LocalDate.of(2026, 9, 1), LocalDate.of(2027, 5, 31), listOf("One")))
        val season = started.season.leagueSeasonId
        val one = started.season.divisions.first().divisionId
        val a = orgs.createTeam("Anchor"); val b = orgs.createTeam("Buck"); val d = orgs.createTeam("Drovers")
        for (t in listOf(a, b, d)) orgs.acceptAffiliation(orgs.affiliate(t, season, divisionId = one, from = t0), t0)
        val first = orgs.scheduleFixture(season, one, a, b, Instant.parse("2026-09-10T19:30:00Z"))
        orgs.scheduleFixture(season, one, b, d, Instant.parse("2026-09-17T19:30:00Z"))
        val voided = orgs.scheduleFixture(season, one, d, a, Instant.parse("2026-09-24T19:30:00Z"))
        orgs.awardFixture(first, a, "Buck did not travel.", by = jen)
        // A result that was voided is not a result: the table ignores it, and so does the count.
        orgs.voidOutcome(voided, orgs.awardFixture(voided, d, "Entered in error.", by = jen), "Entered against the wrong fixture.", by = jen)

        testApplication {
            application { thro(Deps(connect = { TestDatabase.connect() }, authenticator = Authenticator.Dev(), now = { Instant.parse("2026-09-18T12:00:00Z") })) }
            val body = client.get("/v1/leagues").bodyAsText()
            fun league(name: String) = body.substring(body.indexOf("\"name\":\"$name\"")).substringBefore("\"saidTeams\"")

            check("a league from the directory is listed, not run here", league("Aardvark Listed League").contains("\"standing\":\"listed\""))
            check("and stays listed when its teams were imported with it", league("Badger Imported League").contains("\"standing\":\"listed\""))
            check("an imported season holds no fixtures and no results", league("Badger Imported League").contains("\"fixtures\":0,\"results\":0"))
            check("a listed league run here by the person named to run it is run here", league("Cormorant Named League").contains("\"standing\":\"run_here\""))
            check("a league started here is run here", league("Dolphin Started League").contains("\"standing\":\"run_here\""))
            check("its season counts its fixtures, and only the results that stand", league("Dolphin Started League").contains("\"fixtures\":3,\"results\":1"))
            check("and nothing on the list names who runs anything", !body.contains(jen.toString()) && !body.contains(lee.toString()))
        }
        println("league standing: $passed checks passed")
    }
}
