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

/**
 * The organiser's remaining acts over a league season (PD-112), over the wire: the points rules a table is ordered
 * by, moving a team between divisions, and transferring a registered player to another team. Each is the season
 * administrator's and nobody else's, each is refused in words where the season's own facts forbid it, and each
 * leaves the record it replaces in place.
 */
class LeagueActsHttpTest {

    @Test
    fun `the administrator sets the points rules, moves a team and transfers a player`() {
        if (!TestDatabase.configured) {
            println("no database configured (set PGHOST) — league acts HTTP tests skipped")
            return
        }
        val c = TestDatabase.migrated()
        val orgs = Organisations(c)
        val rel = Relations(c)
        val accounts = Accounts(c)
        var passed = 0
        fun check(name: String, cond: Boolean) {
            assertTrue(cond, "FAILED: $name")
            println("  PASS  $name")
            passed++
        }
        val t0 = Instant.parse("2026-09-01T18:00:00Z")
        val device = UUID.randomUUID()
        fun person(sub: String, name: String): UUID {
            val s = accounts.signIn("apple", sub, device)
            accounts.setDisplayName(s.accountId, name)
            Friends(c).declareAge(s.accountId, "adult")
            Consent(c).say(s.accountId, Consent.Scope.LISTING, yes = true)
            return s.playerId!!
        }
        val lee = person("005.lee", "Lee Organiser")
        val ade = person("005.ade", "Ade Captain")
        val sam = person("005.sam", "Sam Wilson")
        val gil = person("005.gil", "Gil Captain")
        val league = orgs.createLeague("Teesside Thursday League")
        val season = orgs.openSeason(league, "2026/27", LocalDate.of(2026, 9, 1), LocalDate.of(2027, 5, 31))
        rel.grant(lee, "admin", ObjectRef(ObjectType.LEAGUE_SEASON, season.toString()))
        val a = orgs.createDivision(season, "Division A", 1); val b = orgs.createDivision(season, "Division B", 2)
        val riverside = orgs.createTeam("Riverside A", by = ade); val grange = orgs.createTeam("Grange A", by = gil); val dolphin = orgs.createTeam("Dolphin", by = gil)
        orgs.addMember(riverside, ade, MembershipRole.ADMIN, from = t0); orgs.addMember(riverside, sam, MembershipRole.PLAYER, from = t0)
        orgs.addMember(grange, gil, MembershipRole.ADMIN, from = t0)
        rel.grant(ade, "admin", ObjectRef(ObjectType.TEAM, riverside.toString())); rel.grant(gil, "admin", ObjectRef(ObjectType.TEAM, grange.toString()))
        for ((t, d) in listOf(riverside to a, grange to a, dolphin to b)) orgs.acceptAffiliation(orgs.affiliate(t, season, divisionId = d, from = t0), t0)
        val fixture = orgs.scheduleFixture(season, a, riverside, grange, Instant.parse("2026-10-08T19:30:00Z"))
        // Sam is registered with Riverside under a policy the league approved.
        val policy = orgs.draftPolicy("league_season", season, "registration", 1, LocalDate.of(2026, 9, 1), """{"requires":["name"],"deadline_days_before_first_fixture":7}""", by = lee)
        orgs.approvePolicy(policy, by = lee)
        orgs.register(sam, season, riverside, policy, from = t0, by = lee)

        testApplication {
            application { thro(Deps(connect = { TestDatabase.connect() }, authenticator = Authenticator.Dev(), now = { Instant.parse("2026-09-16T12:00:00Z") })) }
            suspend fun get(path: String, subject: UUID?): HttpResponse = client.get(path) { subject?.let { header(Authenticator.Dev.HEADER, it.toString()) } }
            suspend fun post(path: String, body: String, subject: UUID?): HttpResponse = client.post(path) {
                subject?.let { header(Authenticator.Dev.HEADER, it.toString()) }; header("X-Thro-Device", device.toString()); setBody(body)
            }

            // --- the points rules ------------------------------------------------------------------------------------
            check("before any are set, the table says it is ordered by THRØ's standard", get("/v1/seasons/$season/standings", null).bodyAsText().contains("THRØ's standard"))
            val rules = """{"win":3,"draw":1,"loss":0,"tieBreak":["points","head_to_head","leg_difference"]}"""
            check("setting the points rules needs a principal", post("/v1/seasons/$season/points", rules, null).status.value == 401)
            check("and the season's administrator", post("/v1/seasons/$season/points", rules, ade).status.value == 403)
            check("a tie-break THRØ cannot order by is refused in words", post("/v1/seasons/$season/points", """{"win":3,"tieBreak":["coin toss"]}""", lee).bodyAsText().contains("coin toss"))
            check("a negative loss is refused", post("/v1/seasons/$season/points", """{"win":3,"loss":-1}""", lee).status.value == 400)
            val set = post("/v1/seasons/$season/points", rules, lee)
            check("the administrator sets three for a win, in force from today", set.status.value == 200 && set.bodyAsText().contains("\"win\":3") && set.bodyAsText().contains("\"version\":1"))
            val table = get("/v1/seasons/$season/standings", null).bodyAsText()
            check("the table now says it is ordered by this league's own rules", table.contains("3 points a win") && !table.contains("THRØ's standard"))
            check("a second setting supersedes the first", post("/v1/seasons/$season/points", """{"win":2,"draw":1}""", lee).bodyAsText().contains("\"version\":2"))

            // --- moving a team between divisions ---------------------------------------------------------------------
            check("moving a team is the administrator's", post("/v1/seasons/$season/teams/$dolphin/division", """{"divisionId":"$a"}""", gil).status.value == 403)
            check("a division of another season is refused", post("/v1/seasons/$season/teams/$dolphin/division", """{"divisionId":"${UUID.randomUUID()}"}""", lee).status.value == 400)
            val blocked = post("/v1/seasons/$season/teams/$riverside/division", """{"divisionId":"$b"}""", lee)
            check("a team with an undecided fixture in its division stays until it is rearranged or voided", blocked.status.value == 409 && blocked.bodyAsText().contains("fixture"))
            val moved = post("/v1/seasons/$season/teams/$dolphin/division", """{"divisionId":"$a"}""", lee)
            check("Dolphin moves up to Division A", moved.status.value == 200 && moved.bodyAsText().contains("\"divisionId\":\"$a\""))
            check("and the season's plan says so", get("/v1/seasons/$season/teams", lee).bodyAsText().let { Regex("\"teamId\":\"$dolphin\"[^}]*\"divisionId\":\"$a\"").containsMatchIn(it) })
            check("moving to where it already is is a 409", post("/v1/seasons/$season/teams/$dolphin/division", """{"divisionId":"$a"}""", lee).status.value == 409)

            // --- transferring a registered player ----------------------------------------------------------------------
            val transfer = """{"toTeamId":"$grange","from":"2026-10-01","note":"moved house"}"""
            check("a transfer is the administrator's", post("/v1/seasons/$season/registrations/$sam/transfer", transfer, ade).status.value == 403)
            check("a player who is not registered cannot be transferred", post("/v1/seasons/$season/registrations/$gil/transfer", transfer, lee).status.value == 409)
            check("to a team not in the season is refused", post("/v1/seasons/$season/registrations/$sam/transfer", """{"toTeamId":"${UUID.randomUUID()}","from":"2026-10-01","note":"x"}""", lee).status.value == 404)
            check("a transfer says why", post("/v1/seasons/$season/registrations/$sam/transfer", """{"toTeamId":"$grange","from":"2026-10-01"}""", lee).status.value == 400)
            val done = post("/v1/seasons/$season/registrations/$sam/transfer", transfer, lee)
            check("Sam is transferred to Grange from 1 October", done.status.value == 200 && done.bodyAsText().contains("\"teamId\":\"$grange\"") && done.bodyAsText().contains("\"from\":\"2026-10-01\""))
            check("registered throughout: with Riverside before, with Grange after, never unregistered",
                orgs.isRegistered(sam, season, Instant.parse("2026-09-20T00:00:00Z")) && orgs.isRegistered(sam, season, Instant.parse("2026-10-20T00:00:00Z")))
            val registrations = get("/v1/seasons/$season/registrations", lee).bodyAsText()
            check("the season's registered players list both registrations: Riverside ended, Grange current",
                Regex("\"registered\":\\[.*\"team\":\"Riverside A\"[^}]*\"until\":\"2026-10-01").containsMatchIn(registrations) && Regex("\"team\":\"Grange A\"[^}]*\"until\":null").containsMatchIn(registrations))
            check("transferring again to the same team is a 409", post("/v1/seasons/$season/registrations/$sam/transfer", transfer, lee).status.value == 409)
        }
        println("league acts over HTTP: $passed checks passed")
    }
}
