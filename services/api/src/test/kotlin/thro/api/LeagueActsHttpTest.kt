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

            // PD-120: who changed what, for the season's administrators and nobody else.
            check("the season's history is the administrator's", get("/v1/seasons/$season/history", ade).status.value == 403)
            val history = get("/v1/seasons/$season/history", lee)
            check("and it says, in words, what was done and by whom",
                history.status.value == 200 && history.bodyAsText().contains("\"what\":\"Set the points rules (version 2)\"")
                    && history.bodyAsText().contains("\"who\":\"Lee Organiser\"") && history.bodyAsText().contains("Registered Sam Wilson with Grange A"))

            // PD-119: a server with no System One model cannot read a sentence, and says so rather than guessing.
            val unread = post("/v1/seasons/$season/understand", """{"text":"Riverside beat Grange 5-3"}""", lee)
            check("without a model, Tell THRØ answers 503 in words", unread.status.value == 503 && unread.bodyAsText().contains("cannot read"))
            check("and so does a captain's sentence, so the form is used instead",
                post("/v1/fixtures/$fixture/proposals/read", """{"teamId":"$riverside","text":"the 22nd instead"}""", ade).let { it.status.value == 503 && it.bodyAsText().contains("cannot read") })
        }

        // PD-119: Tell THRØ over the wire, with a stand-in model that picks by the words in the options it is offered.
        val model = object : SystemOne {
            override fun answers(state: String, questions: String): Map<String, Any?>? {
                val q = Json.parseObject(questions)
                @Suppress("UNCHECKED_CAST")
                fun options(id: String) = (q[id] as Map<String, Any?>)["criteria"] as Map<String, Any?>
                fun pick(id: String, vararg words: String) = options(id).entries.first { (_, v) -> words.all { w -> (v?.toString() ?: "").contains(w) } }.key
                fun choice(option: String, p: Double) = mapOf("type" to "choice", "choice" to option, "probabilities" to mapOf(option to p), "confidence" to p)
                if (q.containsKey("asks_move")) {
                    // PD-129: a captain's sentence about one fixture.
                    return mapOf("asks_move" to choice("yes", 0.92), "date_mode" to choice("absolute", 0.9), "month" to choice("October", 0.9), "day" to choice("22", 0.94), "time" to choice("none", 0.9))
                }
                if (q.containsKey("is_fixture")) {
                    // PD-122: one line of a pasted list. Teams by name, in the order the line names them.
                    val line = Json.parseObject(state)["line"] as String
                    val named = options("home_team").filterKeys { it != "none" }.mapNotNull { (k, v) -> line.indexOf(v.toString()).takeIf { it >= 0 }?.let { k to it } }.sortedBy { it.second }.map { it.first }
                    return mapOf("is_fixture" to mapOf("type" to "noul", "noul" to if (line.contains(" v ")) 0.96 else 0.05),
                                 "home_team" to choice(named.getOrNull(0) ?: "none", 0.9), "away_team" to choice(named.getOrNull(1) ?: "none", 0.9),
                                 "month" to choice(if (line.contains("Nov")) "November" else "none", 0.9), "day" to choice(if (line.contains("12")) "12" else "none", 0.9),
                                 "time" to choice(options("time").keys.firstOrNull { it != "none" } ?: "none", 0.9))
                }
                return mapOf("act" to choice("result", 0.95), "fixture" to choice(pick("fixture", "Riverside A", "Grange A"), 0.9),
                             "score" to choice(pick("score", "5-3"), 0.96), "first_number_team" to choice(pick("first_number_team", "Riverside A"), 0.9), "winner_team" to choice(pick("winner_team", "Riverside A"), 0.9))
            }
        }
        testApplication {
            application { thro(Deps(connect = { TestDatabase.connect() }, authenticator = Authenticator.Dev(), now = { Instant.parse("2026-09-16T12:00:00Z") }, systemOne = model)) }
            suspend fun post(path: String, body: String, subject: UUID?): HttpResponse = client.post(path) {
                subject?.let { header(Authenticator.Dev.HEADER, it.toString()) }; header("X-Thro-Device", device.toString()); setBody(body)
            }
            suspend fun get(path: String, subject: UUID?): HttpResponse = client.get(path) { subject?.let { header(Authenticator.Dev.HEADER, it.toString()) } }
            check("Tell THRØ is the administrator's", post("/v1/seasons/$season/understand", """{"text":"Riverside beat Grange 5-3"}""", ade).status.value == 403)
            check("a sentence with nothing in it is a 400", post("/v1/seasons/$season/understand", """{"text":"  "}""", lee).status.value == 400)
            val read = post("/v1/seasons/$season/understand", """{"text":"Riverside beat Grange 5-3 on Thursday"}""", lee)
            val body = read.bodyAsText()
            check("the sentence is read as a result for the fixture, with the numbers on the right sides",
                read.status.value == 200 && body.contains("\"act\":\"result\"") && body.contains("\"fixtureId\":\"$fixture\"")
                    && body.contains("\"legsHome\":5,\"legsAway\":3") && body.contains("\"ready\":true") && body.contains("Riverside A 5–3 Grange A, Thu 8 Oct"))
            // PD-122: the league's list, pasted.
            check("reading a list is the administrator's", post("/v1/seasons/$season/fixtures/read", """{"text":"12 Nov Grange A v Riverside A 8pm"}""", ade).status.value == 403)
            check("nothing pasted is a 400", post("/v1/seasons/$season/fixtures/read", """{"text":"  "}""", lee).status.value == 400)
            val list = post("/v1/seasons/$season/fixtures/read", """{"text":"DIVISION A\nThursday 12 November\nGrange A v Riverside A 8pm"}""", lee)
            val listed = list.bodyAsText()
            check("a pasted list comes back as rows to confirm, the heading's date carried down",
                list.status.value == 200 && listed.contains("\"home\":\"Grange A\"") && listed.contains("\"away\":\"Riverside A\"")
                    && listed.contains("\"on\":\"2026-11-12\",\"time\":\"20:00\",\"scheduledAt\":\"2026-11-12T20:00:00Z\"") && listed.contains("\"doubt\":null")
                    && listed.contains("\"why\":\"a date, carried down\"") && listed.contains("\"why\":\"not a fixture\""))
            // PD-129: the captain says it, on the fixture's own screen. Whoever may propose may have a sentence read.
            val sentence = """{"teamId":"$riverside","text":"can we do the 22nd of October instead, the pub is shut"}"""
            check("a sentence is read for whoever runs the team", post("/v1/fixtures/$fixture/proposals/read", sentence, sam).status.value == 403)
            check("and only for a team in the fixture", post("/v1/fixtures/$fixture/proposals/read", """{"teamId":"$dolphin","text":"the 22nd"}""", gil).status.value == 403)
            check("a sentence with nothing in it is a 400", post("/v1/fixtures/$fixture/proposals/read", """{"teamId":"$riverside","text":" "}""", ade).status.value == 400)
            val moved = post("/v1/fixtures/$fixture/proposals/read", sentence, ade)
            check("the captain's sentence comes back as a day and the time the fixture already had, to confirm",
                moved.status.value == 200 && moved.bodyAsText().contains("\"to\":\"2026-10-22T19:30:00Z\"") && moved.bodyAsText().contains("\"ready\":true")
                    && moved.bodyAsText().contains("\"say\":\"Thu 22 Oct, 8:30 pm\""))
            check("reading proposes nothing", get("/v1/fixtures/$fixture/proposals", ade).bodyAsText() == """{"proposals":[]}""")
            check("and the server tells the web it can read", client.get("/v1/auth/providers").bodyAsText().contains("\"reads\":true"))
        }
        println("league acts over HTTP: $passed checks passed")
    }
}
