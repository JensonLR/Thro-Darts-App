package thro.api

import io.ktor.client.request.get
import io.ktor.client.request.header
import io.ktor.client.request.post
import io.ktor.client.request.setBody
import io.ktor.client.statement.HttpResponse
import io.ktor.client.statement.bodyAsText
import io.ktor.server.testing.testApplication
import java.time.Instant
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
 * A friendly between two teams (PD-110), over the wire: whoever runs one team challenges another to a game outside any
 * season; whoever runs the other accepts or declines; either may read it; the challenger may withdraw; and once played
 * on THRØ, somebody who played it and runs one of the teams cites the match, once. Nothing about a friendly reaches a
 * league table, and no rating is touched.
 */
class FriendlyHttpTest {

    @Test
    fun `a team challenges another, the other answers, and the match played is cited once`() {
        if (!TestDatabase.configured) {
            println("no database configured (set PGHOST) — friendly HTTP tests skipped")
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
            return s.playerId!!
        }
        val ade = person("004.ade", "Ade Captain")
        val gil = person("004.gil", "Gil Captain")
        val sam = person("004.sam", "Sam Player")
        val zed = person("004.zed", "Zed Nobody")
        val riverside = orgs.createTeam("Riverside A", by = ade); val grange = orgs.createTeam("Grange A", by = gil)
        orgs.addMember(riverside, ade, MembershipRole.ADMIN, from = t0); orgs.addMember(riverside, sam, MembershipRole.PLAYER, from = t0)
        orgs.addMember(grange, gil, MembershipRole.ADMIN, from = t0)
        rel.grant(ade, "admin", ObjectRef(ObjectType.TEAM, riverside.toString())); rel.grant(gil, "admin", ObjectRef(ObjectType.TEAM, grange.toString()))

        testApplication {
            application { thro(Deps(connect = { TestDatabase.connect() }, authenticator = Authenticator.Dev(), now = { Instant.parse("2026-09-16T12:00:00Z") })) }
            suspend fun get(path: String, subject: UUID?): HttpResponse = client.get(path) { subject?.let { header(Authenticator.Dev.HEADER, it.toString()) } }
            suspend fun post(path: String, body: String, subject: UUID?): HttpResponse = client.post(path) {
                subject?.let { header(Authenticator.Dev.HEADER, it.toString()) }; header("X-Thro-Device", device.toString()); setBody(body)
            }
            fun idOf(text: String, key: String) = Regex("\"$key\":\"([0-9a-f-]{36})\"").find(text)?.groupValues?.get(1)

            // --- a challenge is the team's, by whoever runs it -----------------------------------------------------
            val challenge = """{"toTeamId":"$grange","playAt":"2026-09-25T19:30:00Z","message":"Friday, our board, first to five?"}"""
            check("a challenge needs a principal", post("/v1/teams/$riverside/friendlies", challenge, null).status.value == 401)
            check("and is for whoever runs the team", post("/v1/teams/$riverside/friendlies", challenge, sam).status.value == 403 && post("/v1/teams/$riverside/friendlies", challenge, zed).status.value == 403)
            check("a team cannot challenge itself", post("/v1/teams/$riverside/friendlies", """{"toTeamId":"$riverside","playAt":"2026-09-25T19:30:00Z"}""", ade).status.value == 400)
            check("a date in the past is refused", post("/v1/teams/$riverside/friendlies", """{"toTeamId":"$grange","playAt":"2026-09-01T19:30:00Z"}""", ade).status.value == 400)
            check("a team THRØ does not have is a 404", post("/v1/teams/$riverside/friendlies", """{"toTeamId":"${UUID.randomUUID()}","playAt":"2026-09-25T19:30:00Z"}""", ade).status.value == 404)
            val made = post("/v1/teams/$riverside/friendlies", challenge, ade)
            val id = idOf(made.bodyAsText(), "friendlyId")
            check("the captain challenges, and it is proposed", made.status.value == 200 && id != null && made.bodyAsText().contains("\"state\":\"proposed\"") && made.bodyAsText().contains("Grange A"))
            check("a second open challenge between the same two teams is a 409, from either side",
                post("/v1/teams/$riverside/friendlies", challenge, ade).status.value == 409 && post("/v1/teams/$grange/friendlies", """{"toTeamId":"$riverside","playAt":"2026-09-26T19:30:00Z"}""", gil).status.value == 409)

            // --- both teams read it; nobody else --------------------------------------------------------------------
            check("a stranger cannot read a team's friendlies", get("/v1/teams/$grange/friendlies", zed).status.value == 403)
            val theirs = get("/v1/teams/$grange/friendlies", gil).bodyAsText()
            check("the challenged team reads who, when and the message", theirs.contains("\"friendlyId\":\"$id\"") && theirs.contains("Riverside A") && theirs.contains("first to five") && theirs.contains("\"direction\":\"received\""))
            check("the challenger's members read it as sent", get("/v1/teams/$riverside/friendlies", sam).bodyAsText().contains("\"direction\":\"sent\""))

            // --- the answer is the challenged team's ---------------------------------------------------------------
            check("the challenger cannot answer its own challenge", post("/v1/friendlies/$id/answer", """{"answer":"accepted"}""", ade).status.value == 403)
            check("a member who does not run the team cannot answer", post("/v1/friendlies/$id/answer", """{"answer":"accepted"}""", zed).status.value == 403)
            check("an answer THRØ does not know is a 400", post("/v1/friendlies/$id/answer", """{"answer":"maybe"}""", gil).status.value == 400)
            check("a refusal says why", post("/v1/friendlies/$id/answer", """{"answer":"declined"}""", gil).status.value == 400)
            val accepted = post("/v1/friendlies/$id/answer", """{"answer":"accepted","note":"see you Friday"}""", gil)
            check("the other captain accepts", accepted.status.value == 200 && accepted.bodyAsText().contains("\"state\":\"accepted\""))
            check("answering again is a 409", post("/v1/friendlies/$id/answer", """{"answer":"declined","note":"no"}""", gil).status.value == 409)
            check("withdrawing an accepted friendly is a 409", post("/v1/friendlies/$id/withdraw", "{}", ade).status.value == 409)

            // --- the match it was played in ----------------------------------------------------------------------
            check("citing a match THRØ does not have is a 404", post("/v1/friendlies/$id/match", """{"matchId":"${UUID.randomUUID()}"}""", ade).status.value == 404)
            // A finished leg on THRØ between the two captains, recorded the way a phone records one.
            val matchId = UUID.randomUUID()
            Matches(c).open(matchId, ade, gil, MatchFormat(startingScore = 501, inRule = InRule.STRAIGHT, outRule = OutRule.DOUBLE, legs = Structure(StructureMode.FIRST_TO, 1), throwFirst = Seat.home))
            var seq = 0L
            for ((seat, total) in listOf("home" to 180, "away" to 60, "home" to 180, "away" to 60, "home" to 141)) {
                val r = post("/v1/commands", """{"type":"RecordVisit","commandId":"${UUID.randomUUID()}","matchId":"$matchId","deviceSeq":${++seq},"player":"$seat","visitTotal":$total,"occurredAt":"2026-09-25T19:${30 + seq}:00Z"}""", ade)
                check("visit $seq is applied", r.status.value == 200)
            }
            check("citing is for somebody who played it and runs a team in it", post("/v1/friendlies/$id/match", """{"matchId":"$matchId"}""", sam).status.value == 403)
            check("the captain who played cites it", post("/v1/friendlies/$id/match", """{"matchId":"$matchId"}""", ade).status.value == 200 && get("/v1/teams/$riverside/friendlies", ade).bodyAsText().contains("\"matchId\":\"$matchId\""))
            check("a friendly names its match once", post("/v1/friendlies/$id/match", """{"matchId":"$matchId"}""", gil).status.value == 409)

            // --- declining, and withdrawing ---------------------------------------------------------------------------
            val second = idOf(post("/v1/teams/$grange/friendlies", """{"toTeamId":"$riverside","playAt":"2026-10-02T19:30:00Z"}""", gil).bodyAsText(), "friendlyId")!!
            check("the challenged captain declines with a reason", post("/v1/friendlies/$second/answer", """{"answer":"declined","note":"cup night"}""", ade).bodyAsText().contains("\"state\":\"declined\""))
            val third = idOf(post("/v1/teams/$grange/friendlies", """{"toTeamId":"$riverside","playAt":"2026-10-09T19:30:00Z"}""", gil).bodyAsText(), "friendlyId")!!
            check("withdrawing is the challenger's", post("/v1/friendlies/$third/withdraw", "{}", ade).status.value == 403)
            check("the challenger withdraws", post("/v1/friendlies/$third/withdraw", "{}", gil).bodyAsText().contains("\"state\":\"withdrawn\""))
            check("a withdrawn challenge cannot be answered", post("/v1/friendlies/$third/answer", """{"answer":"accepted"}""", ade).status.value == 409)
            check("no league table knows any of this", get("/v1/leagues", null).bodyAsText().let { !it.contains("Riverside A") })
        }
        println("friendlies over HTTP: $passed checks passed")
    }
}
