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
import thro.competition.MembershipRole
import thro.engine.InRule
import thro.engine.MatchFormat
import thro.engine.OutRule
import thro.engine.Structure
import thro.engine.StructureMode

/**
 * A fixture as one team lives it (PD-106): who is available, who is picked, and which match on THRØ it was played
 * in — so the captain's week and the organiser's table meet on one fixture, and a scoreline in a league table can
 * say it was scored on THRØ because it was.
 */
class TeamFixtureTest {

    @Test
    fun `a team reads its fixture, says who can play, names its side, and cites the match it played`() {
        if (!TestDatabase.configured) {
            println("no database configured (set PGHOST) — team fixture tests skipped")
            return
        }
        val c = TestDatabase.migrated()
        val orgs = Organisations(c)
        val rel = Relations(c)
        var passed = 0
        fun check(name: String, cond: Boolean) {
            assertTrue(cond, "FAILED: $name")
            println("  PASS  $name")
            passed++
        }
        val t0 = Instant.parse("2026-09-01T18:00:00Z")
        val lee = UUID.randomUUID()                              // runs the league
        val ade = orgs.createPlayer(); val sam = orgs.createPlayer()   // Riverside: captain and a member
        val gil = orgs.createPlayer()                             // Grange: captain
        val zed = orgs.createPlayer()                             // nobody's
        val league = orgs.createLeague("Teesside Thursday League")
        val season = orgs.openSeason(league, "2026/27", LocalDate.of(2026, 9, 1), LocalDate.of(2027, 5, 31))
        rel.grant(lee, "admin", ObjectRef(ObjectType.LEAGUE_SEASON, season.toString()))
        val riverside = orgs.createTeam("Riverside A", by = ade); val grange = orgs.createTeam("Grange A", by = gil)
        orgs.addMember(riverside, ade, MembershipRole.ADMIN, from = t0); orgs.addMember(riverside, sam, MembershipRole.PLAYER, from = t0)
        orgs.addMember(grange, gil, MembershipRole.ADMIN, from = t0)
        rel.grant(ade, "admin", ObjectRef(ObjectType.TEAM, riverside.toString())); rel.grant(gil, "admin", ObjectRef(ObjectType.TEAM, grange.toString()))
        for (t in listOf(riverside, grange)) orgs.acceptAffiliation(orgs.affiliate(t, season, from = t0), t0)
        val fixture = orgs.scheduleFixture(season, null, riverside, grange, Instant.parse("2026-09-17T19:30:00Z"))
        val oneLeg = MatchFormat(startingScore = 501, inRule = InRule.STRAIGHT, outRule = OutRule.DOUBLE, legs = Structure(StructureMode.FIRST_TO, 1), throwFirst = Seat.home)
        val phone = UUID.randomUUID()

        testApplication {
            application { thro(Deps(connect = { TestDatabase.connect() }, authenticator = Authenticator.Dev(), now = { Instant.parse("2026-09-16T12:00:00Z") })) }
            suspend fun get(path: String, subject: UUID?): HttpResponse = client.get(path) { subject?.let { header(Authenticator.Dev.HEADER, it.toString()) } }
            suspend fun post(path: String, body: String, subject: UUID): HttpResponse = client.post(path) {
                header(Authenticator.Dev.HEADER, subject.toString()); header("X-Thro-Device", phone.toString()); setBody(body)
            }
            val mine = "/v1/fixtures/$fixture/team/$riverside"

            // --- reading it ------------------------------------------------------------------------------------
            check("a team's fixture needs a principal", get(mine, null).status.value == 401)
            check("and is for the team's own members", get(mine, zed).status.value == 403 && get(mine, gil).status.value == 403)
            check("a fixture nobody has is a 404", get("/v1/fixtures/${UUID.randomUUID()}/team/$riverside", ade).status.value == 404)
            check("a team not in this fixture is a 404 too", get("/v1/fixtures/$fixture/team/${orgs.createTeam("Elsewhere")}", ade).status.value == 404)
            val first = get(mine, sam).bodyAsText()
            check("a member reads the fixture: who, when, the version, and no match yet",
                first.contains("\"fixtureId\":\"$fixture\"") && first.contains("\"opponent\":\"Grange A\"") && first.contains("\"version\":1") && first.contains("\"matchId\":null"))
            check("every member of the side is listed with their availability, none yet",
                first.contains("\"playerId\":\"$ade\"") && first.contains("\"playerId\":\"$sam\"") && Regex("\"availability\":null").findAll(first).count() == 2)
            check("a member sees they do not pick the side; the admin sees they do",
                first.contains("\"yourRole\":\"player\"") && first.contains("\"mayNameLineup\":false") && get(mine, ade).bodyAsText().contains("\"mayNameLineup\":true"))

            // --- who can play -----------------------------------------------------------------------------------
            val said = post("/v1/commands", """{"type":"SetAvailability","commandId":"${UUID.randomUUID()}","fixtureId":"$fixture","playerId":"$sam","teamId":"$riverside","status":"available","expectedVersion":0}""", sam)
            check("a member says they can play", said.status.value == 200 && said.bodyAsText().contains("\"outcome\":\"applied\""))
            val after = get(mine, ade).bodyAsText()
            check("and the side sees it, with the version the next change must name",
                after.contains("\"playerId\":\"$sam\",\"name\":null,\"availability\":\"available\",\"availabilityVersion\":1"))

            // --- naming the side --------------------------------------------------------------------------------
            val picked = post("/v1/commands", """{"type":"NameLineup","commandId":"${UUID.randomUUID()}","fixtureId":"$fixture","teamId":"$riverside","players":["$sam","$ade"],"expectedVersion":0}""", ade)
            check("the admin names the side", picked.status.value == 200 && picked.bodyAsText().contains("\"outcome\":\"applied\""))
            val lined = get(mine, sam).bodyAsText()
            check("and everybody on the team reads it, in order", lined.contains("\"lineup\":{\"version\":1,\"players\":[\"$sam\",\"$ade\"]}"))

            // --- the match it was played in ------------------------------------------------------------------------
            val match = UUID.randomUUID()
            Matches(c).open(match, ade, gil, oneLeg)
            var seq = 0L
            for ((seat, total) in listOf("home" to 180, "away" to 60, "home" to 180, "away" to 60, "home" to 141)) {
                val r = post("/v1/commands", """{"type":"RecordVisit","commandId":"${UUID.randomUUID()}","matchId":"$match","deviceSeq":${++seq},"player":"$seat","visitTotal":$total,"occurredAt":"2026-09-17T19:${30 + seq}:00Z"}""", ade)
                check("visit $seq is applied", r.status.value == 200)
            }
            check("citing needs a principal", client.post("/v1/fixtures/$fixture/match") { setBody("""{"matchId":"$match"}""") }.status.value == 401)
            check("a member who was not in the match cannot cite it", post("/v1/fixtures/$fixture/match", """{"matchId":"$match"}""", sam).status.value == 403)
            check("nor can a stranger", post("/v1/fixtures/$fixture/match", """{"matchId":"$match"}""", zed).status.value == 403)
            check("a match nobody has is a 404", post("/v1/fixtures/$fixture/match", """{"matchId":"${UUID.randomUUID()}"}""", ade).status.value == 404)
            // A match the captain played against somebody who is not in the other team is not this fixture's match.
            val elsewhere = UUID.randomUUID()
            Matches(c).open(elsewhere, ade, zed, oneLeg)
            val aside = post("/v1/fixtures/$fixture/match", """{"matchId":"$elsewhere"}""", ade)
            check("a match against somebody outside the opposing team cannot be cited", aside.status.value == 409 && aside.bodyAsText().contains("other team"))
            val cited = post("/v1/fixtures/$fixture/match", """{"matchId":"$match"}""", ade)
            check("the captain who played it cites the match to the fixture", cited.status.value == 200 && cited.bodyAsText().contains("\"matchId\":\"$match\""))
            check("once: a fixture's match is not a field to point elsewhere", post("/v1/fixtures/$fixture/match", """{"matchId":"$match"}""", gil).status.value == 409)
            check("the side sees the match on its fixture", get(mine, sam).bodyAsText().contains("\"matchId\":\"$match\""))

            // --- so the league's result is a played one ---------------------------------------------------------
            val result = post("/v1/fixtures/$fixture/result", """{"legsHome":1,"legsAway":0}""", lee)
            check("the organiser's result is now played — scored on THRØ — rather than the league's word",
                result.status.value == 200 && result.bodyAsText().contains("\"kind\":\"played\""))
        }
        println("team fixture: $passed checks passed")
    }
}
