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

/**
 * A league started on THRØ is run by whoever starts it (PD-100), as a team started on THRØ is — and a
 * league THRØ lists from somewhere else is still run only by the person named for it (PD-053). The difference is
 * who could be pretending: nobody can steal a league they made themselves.
 */
class LeagueStartingTest {

    @Test
    fun `whoever starts a league runs it, adds its teams and plays its fixtures, and nobody takes over a listed one`() {
        if (!TestDatabase.configured) {
            println("no database configured (set PGHOST) — league starting tests skipped")
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
        val jen = UUID.randomUUID()   // starts a league
        val zed = UUID.randomUUID()   // anybody else
        // A league THRØ lists from the directory: nobody made it here, so nobody here may run it by starting things.
        val listed = orgs.createLeague("Stockton and District Thursday Night Darts League", "Stockton-on-Tees")

        testApplication {
            application { thro(Deps(connect = { TestDatabase.connect() }, authenticator = Authenticator.Dev(), now = { Instant.parse("2026-09-14T12:00:00Z") })) }
            suspend fun post(path: String, body: String, subject: UUID? = jen): HttpResponse = client.post(path) {
                subject?.let { header(Authenticator.Dev.HEADER, it.toString()) }
                setBody(body)
            }
            suspend fun get(path: String, subject: UUID? = jen): HttpResponse = client.get(path) {
                subject?.let { header(Authenticator.Dev.HEADER, it.toString()) }
            }
            fun idOf(text: String, key: String) = Regex("\"$key\":\"([0-9a-f-]{36})\"").find(text)!!.groupValues[1]

            val start = """{"name":"THRØ Test League","locality":"Stockton-on-Tees","season":{"label":"2026-27","startsOn":"2026-09-01","endsOn":"2027-05-31","divisions":["Premier","First"]}}"""

            // --- starting one ---------------------------------------------------------------------------
            check("starting a league needs a principal", post("/v1/leagues", start, subject = null).status.value == 401)
            check("a league needs a name", post("/v1/leagues", """{"name":"X","season":{"label":"2026-27","startsOn":"2026-09-01","endsOn":"2027-05-31"}}""").status.value == 400)
            check("and a first season", post("/v1/leagues", """{"name":"THRØ Test League"}""").status.value == 400)
            check("a season that ends before it starts is a 400",
                post("/v1/leagues", """{"name":"THRØ Test League","season":{"label":"2026-27","startsOn":"2027-05-31","endsOn":"2026-09-01"}}""").status.value == 400)
            check("a season longer than two years is a 400",
                post("/v1/leagues", """{"name":"THRØ Test League","season":{"label":"forever","startsOn":"2026-09-01","endsOn":"2029-09-01"}}""").status.value == 400)
            check("two divisions with one name is a 400",
                post("/v1/leagues", """{"name":"THRØ Test League","season":{"label":"2026-27","startsOn":"2026-09-01","endsOn":"2027-05-31","divisions":["Premier","premier"]}}""").status.value == 400)

            val started = post("/v1/leagues", start)
            val startedText = started.bodyAsText()
            check("the league starts, with its first season and its divisions", started.status.value == 200
                && startedText.contains("\"leagueId\"") && startedText.contains("\"leagueSeasonId\"") && startedText.contains("Premier") && startedText.contains("First"))
            val league = idOf(startedText, "leagueId")
            val season = idOf(startedText, "leagueSeasonId")
            val premier = Regex("\"divisionId\":\"([0-9a-f-]{36})\",\"name\":\"Premier\"").find(startedText)!!.groupValues[1]

            // --- whoever starts it runs it, and nobody else ----------------------------------------------------
            check("the starter runs the season", get("/v1/seasons/$season/teams").status.value == 200)
            check("nobody else does", get("/v1/seasons/$season/teams", subject = zed).status.value == 403)
            val mine = get("/v1/me/seasons").bodyAsText()
            check("the seasons a person runs are theirs to find again, with the league's name",
                mine.contains(season) && mine.contains("THRØ Test League") && mine.contains("2026-27"))
            check("and a stranger runs none", get("/v1/me/seasons", subject = zed).bodyAsText() == """{"seasons":[]}""")
            check("the league is listed publicly, like any other", get("/v1/leagues", subject = null).bodyAsText().contains("THRØ Test League"))

            // --- its teams ------------------------------------------------------------------------------------
            check("adding a team is the season's administrator's",
                post("/v1/seasons/$season/teams", """{"name":"Anchor A","divisionId":"$premier"}""", subject = zed).status.value == 403)
            check("a team needs a name", post("/v1/seasons/$season/teams", """{"name":" ","divisionId":"$premier"}""").status.value == 400)
            check("a division from another season is refused",
                post("/v1/seasons/$season/teams", """{"name":"Anchor A","divisionId":"${UUID.randomUUID()}"}""").status.value == 422)
            val anchor = post("/v1/seasons/$season/teams", """{"name":"Anchor A","divisionId":"$premier"}""")
            val anchorText = anchor.bodyAsText()
            check("a team the league adds is in the season at once — the league is the one letting it in",
                anchor.status.value == 200 && anchorText.contains("\"status\":\"accepted\"") && anchorText.contains("\"teamId\""))
            check("a second team with the same name in the season is a 409",
                post("/v1/seasons/$season/teams", """{"name":"anchor a","divisionId":"$premier"}""").status.value == 409)
            val bell = post("/v1/seasons/$season/teams", """{"name":"Bell A","divisionId":"$premier"}""").bodyAsText()

            // --- and the loop closes: fixtures, a result, a table -----------------------------------------------
            val fixtures = post("/v1/seasons/$season/fixtures",
                """{"fixtures":[{"homeTeamId":"${idOf(anchorText, "teamId")}","awayTeamId":"${idOf(bell, "teamId")}","scheduledAt":"2026-09-17T19:30:00Z"}]}""")
            check("the starter schedules a fixture between the teams they added", fixtures.status.value == 200)
            val result = post("/v1/fixtures/${idOf(fixtures.bodyAsText(), "fixtureId")}/result", """{"legsHome":7,"legsAway":5}""")
            check("enters its result", result.status.value == 200)
            val table = get("/v1/seasons/$season/standings", subject = null).bodyAsText()
            check("and the table has both teams in it", table.contains("Anchor A") && table.contains("Bell A"))

            // --- the next season ------------------------------------------------------------------------------
            val next = """{"label":"2027-28","startsOn":"2027-09-01","endsOn":"2028-05-31","divisions":["Premier"]}"""
            check("the next season of a league is its starter's to open", post("/v1/leagues/$league/seasons", next, subject = zed).status.value == 403)
            val opened = post("/v1/leagues/$league/seasons", next)
            check("and they open it, and run it", opened.status.value == 200
                && get("/v1/seasons/${idOf(opened.bodyAsText(), "leagueSeasonId")}/teams").status.value == 200)
            check("the same season label twice in one league is a 409", post("/v1/leagues/$league/seasons", next).status.value == 409)
            check("a league nobody has is a 404", post("/v1/leagues/${UUID.randomUUID()}/seasons", next).status.value == 404)

            // --- a listed league is not anybody's to start seasons in ----------------------------------------------
            val taken = post("/v1/leagues/$listed/seasons", next)
            check("a league THRØ lists from elsewhere cannot have seasons opened in it by whoever asks, and says why",
                taken.status.value == 403 && taken.bodyAsText().contains("named"))
        }
        println("league starting: $passed checks passed")
    }
}
