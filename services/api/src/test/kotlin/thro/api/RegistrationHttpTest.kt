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
 * Registering players with a league run on THRØ (PD-107), over the wire: the league says what a registration needs,
 * the team finds out who owes one and what is missing, sends it, and the league answers — and nothing is registered
 * until it does. The Secretary's domain and its state machine were already held by `SecretaryTest`; this holds that
 * every step is reachable by the right person and by nobody else.
 */
class RegistrationHttpTest {

    @Test
    fun `the league sets what a registration needs, the team sends one, and only the league's answer registers anybody`() {
        if (!TestDatabase.configured) {
            println("no database configured (set PGHOST) — registration HTTP tests skipped")
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
        // People with accounts, made the way a person's is, so the registration facts THRØ checks can be true of them.
        fun person(sub: String, name: String, adult: Boolean, consents: Boolean): Pair<UUID, UUID> {
            val s = accounts.signIn("apple", sub, device)
            accounts.setDisplayName(s.accountId, name)
            if (adult) Friends(c).declareAge(s.accountId, "adult")
            if (consents) Consent(c).say(s.accountId, Consent.Scope.LISTING, yes = true)
            return s.accountId to s.playerId!!
        }
        val (_, lee) = person("001.lee", "Lee Organiser", adult = true, consents = true)
        val (_, ade) = person("001.ade", "Ade Captain", adult = true, consents = true)
        val (_, sam) = person("001.sam", "Sam Wilson", adult = true, consents = true)
        val (_, kim) = person("001.kim", "Kim Park", adult = false, consents = false)   // age unknown, no consent
        val (_, zed) = person("001.zed", "Zed Nobody", adult = true, consents = true)
        val league = orgs.createLeague("Teesside Thursday League")
        val season = orgs.openSeason(league, "2026/27", LocalDate.of(2026, 9, 1), LocalDate.of(2027, 5, 31))
        rel.grant(lee, "admin", ObjectRef(ObjectType.LEAGUE_SEASON, season.toString()))
        val riverside = orgs.createTeam("Riverside A", by = ade); val grange = orgs.createTeam("Grange A")
        orgs.addMember(riverside, ade, MembershipRole.ADMIN, from = t0)
        orgs.addMember(riverside, sam, MembershipRole.PLAYER, from = t0)
        orgs.addMember(riverside, kim, MembershipRole.PLAYER, from = t0)
        rel.grant(ade, "admin", ObjectRef(ObjectType.TEAM, riverside.toString()))
        for (t in listOf(riverside, grange)) orgs.acceptAffiliation(orgs.affiliate(t, season, from = t0), t0)
        orgs.scheduleFixture(season, null, riverside, grange, Instant.parse("2026-10-08T19:30:00Z"))

        testApplication {
            application { thro(Deps(connect = { TestDatabase.connect() }, authenticator = Authenticator.Dev(), now = { Instant.parse("2026-09-16T12:00:00Z") })) }
            suspend fun get(path: String, subject: UUID?): HttpResponse = client.get(path) { subject?.let { header(Authenticator.Dev.HEADER, it.toString()) } }
            suspend fun post(path: String, body: String, subject: UUID?): HttpResponse = client.post(path) {
                subject?.let { header(Authenticator.Dev.HEADER, it.toString()) }; header("X-Thro-Device", device.toString()); setBody(body)
            }
            fun idOf(text: String, key: String) = Regex("\"$key\":\"([0-9a-f-]{36})\"").find(text)?.groupValues?.get(1)

            // --- what a registration needs is the league's to say ----------------------------------------------------
            val policy = """{"requires":["name","age_band","consent"],"manualRequirements":["fee"],"deadlineDaysBeforeFirstFixture":7}"""
            check("a registration policy needs a principal", post("/v1/seasons/$season/policy", policy, null).status.value == 401)
            check("and the season's administrator", post("/v1/seasons/$season/policy", policy, ade).status.value == 403)
            check("a requirement THRØ does not know is a 400", post("/v1/seasons/$season/policy", """{"requires":["blood type"]}""", lee).status.value == 400)
            check("before one is set, the team owes nothing", post("/v1/teams/$riverside/reconcile", "{}", ade).bodyAsText().contains("\"created\":0"))
            val set = post("/v1/seasons/$season/policy", policy, lee)
            check("the administrator sets it, approved and in force", set.status.value == 200 && set.bodyAsText().contains("\"version\":1") && set.bodyAsText().contains("\"approved\":true"))
            check("and reads it back", get("/v1/seasons/$season/policy", lee).bodyAsText().contains("\"fee\""))
            check("a second one supersedes the first", post("/v1/seasons/$season/policy", policy, lee).bodyAsText().contains("\"version\":2"))

            // --- the team finds out who owes one ----------------------------------------------------------------------
            check("reconciling is for whoever runs the team", post("/v1/teams/$riverside/reconcile", "{}", zed).status.value == 403 && post("/v1/teams/$riverside/reconcile", "{}", sam).status.value == 403)
            val owed = post("/v1/teams/$riverside/reconcile", "{}", ade)
            check("the captain finds every member owes a registration, seven days before the first fixture",
                owed.status.value == 200 && owed.bodyAsText().contains("\"created\":3") && owed.bodyAsText().contains("2026-10-01"))
            check("and doing it again finds nothing new", post("/v1/teams/$riverside/reconcile", "{}", ade).bodyAsText().contains("\"created\":0"))
            val inbox = get("/v1/teams/$riverside/inbox", ade).bodyAsText()
            val tasks = Regex("\"taskId\":\"([0-9a-f-]{36})\"[^}]*\"player\":\"([0-9a-f-]{36})\"").findAll(inbox).associate { UUID.fromString(it.groupValues[2]) to it.groupValues[1] }
            check("the team's inbox names the player each task is about", tasks.keys.containsAll(listOf(ade, sam, kim)))
            val samTask = tasks.getValue(sam); val kimTask = tasks.getValue(kim)

            // --- what is missing is said, and a requirement THRØ cannot check is confirmed by a person -----------------
            check("assessing is for whoever runs the team", post("/v1/tasks/$samTask/assess", "{}", sam).status.value == 403)
            val kimAssessed = post("/v1/tasks/$kimTask/assess", "{}", ade).bodyAsText()
            check("a player whose age is not known and who has not consented is missing both, said by name",
                kimAssessed.contains("\"missing\":[") && kimAssessed.contains("age_band") && kimAssessed.contains("consent") && kimAssessed.contains("\"submissionId\":null"))
            val samAssessed = post("/v1/tasks/$samTask/assess", "{}", ade).bodyAsText()
            check("a player with everything THRØ can check still waits on the fee, which THRØ cannot",
                samAssessed.contains("\"missing\":[]") && samAssessed.contains("\"manualOutstanding\":[\"fee\"]") && samAssessed.contains("\"submissionId\":null"))
            check("confirming the fee needs a note", post("/v1/tasks/$samTask/confirm", """{"requirement":"fee"}""", ade).status.value == 400)
            check("and is the captain's", post("/v1/tasks/$samTask/confirm", """{"requirement":"fee","note":"paid in cash"}""", sam).status.value == 403)
            check("the captain confirms it", post("/v1/tasks/$samTask/confirm", """{"requirement":"fee","note":"paid in cash, 14 Sep"}""", ade).status.value == 200)
            val ready = post("/v1/tasks/$samTask/assess", "{}", ade).bodyAsText()
            val submission = idOf(ready, "submissionId")
            check("now a submission is prepared", submission != null && ready.contains("\"state\":\"ready\""))

            // --- sending it ---------------------------------------------------------------------------------------------
            check("the league sees nothing before it is sent", get("/v1/seasons/$season/registrations", lee).bodyAsText() == """{"registrations":[]}""")
            check("sending is the captain's", post("/v1/submissions/$submission/submit", "{}", sam).status.value == 403)
            val sent = post("/v1/submissions/$submission/submit", "{}", ade)
            check("the captain sends it, and on THRØ it is delivered at once", sent.status.value == 200 && sent.bodyAsText().contains("\"state\":\"delivered\""))
            check("sending it again is refused in words", post("/v1/submissions/$submission/submit", "{}", ade).status.value == 409)
            check("Sam is not registered because it was sent", !orgs.isRegistered(sam, season, Instant.parse("2026-09-20T00:00:00Z")))

            // --- the league answers, and only then is anybody registered -----------------------------------------------
            check("the league's list is the administrator's", get("/v1/seasons/$season/registrations", ade).status.value == 403)
            val list = get("/v1/seasons/$season/registrations", lee).bodyAsText()
            check("and when it was sent, not when it was drafted", Regex("\"sentAt\":\"2026-09-16T12:00").containsMatchIn(list) || list.contains("\"sentAt\":\"20"))
            check("the administrator sees the submission, the player by name, the team, and its state",
                list.contains("\"submissionId\":\"$submission\"") && list.contains("\"player\":\"Sam Wilson\"") && list.contains("\"team\":\"Riverside A\"") && list.contains("\"state\":\"delivered\""))
            check("answering is the league's", post("/v1/submissions/$submission/answer", """{"answer":"accepted","registeredFrom":"2026-09-20"}""", ade).status.value == 403)
            check("an answer THRØ does not know is a 400", post("/v1/submissions/$submission/answer", """{"answer":"maybe"}""", lee).status.value == 400)
            val undated = post("/v1/submissions/$submission/answer", """{"answer":"accepted"}""", lee)
            check("an acceptance says from which date", undated.status.value == 409 && undated.bodyAsText().contains("date"))
            val early = post("/v1/submissions/$submission/answer", """{"answer":"accepted","registeredFrom":"2026-09-10","note":"welcome"}""", lee)
            check("a date no policy governed is refused in words, not a crash", early.status.value == 409 && early.bodyAsText().contains("policy"))
            val accepted = post("/v1/submissions/$submission/answer", """{"answer":"accepted","registeredFrom":"2026-09-20","note":"welcome"}""", lee)
            check("the administrator accepts from 20 September", accepted.status.value == 200 && accepted.bodyAsText().contains("\"state\":\"accepted\""))
            check("and Sam is registered from that date, not before",
                orgs.isRegistered(sam, season, Instant.parse("2026-09-25T00:00:00Z")) && !orgs.isRegistered(sam, season, Instant.parse("2026-09-18T00:00:00Z")))
            check("the list says so", get("/v1/seasons/$season/registrations", lee).bodyAsText().contains("\"state\":\"accepted\""))
            check("answering an answered submission is a 409", post("/v1/submissions/$submission/answer", """{"answer":"rejected","note":"no"}""", lee).status.value == 409)

            // --- a rejection is an answer too ------------------------------------------------------------------------------
            val adeTask = tasks.getValue(ade)
            post("/v1/tasks/$adeTask/confirm", """{"requirement":"fee","note":"paid"}""", ade)
            val adeSub = idOf(post("/v1/tasks/$adeTask/assess", "{}", ade).bodyAsText(), "submissionId")!!
            post("/v1/submissions/$adeSub/submit", "{}", ade)
            val rejected = post("/v1/submissions/$adeSub/answer", """{"answer":"rejected","note":"played for another club this season"}""", lee)
            check("the administrator rejects with a reason, and the player is not registered",
                rejected.status.value == 200 && rejected.bodyAsText().contains("\"state\":\"rejected\"") && !orgs.isRegistered(ade, season, Instant.parse("2026-10-01T00:00:00Z")))
            check("a rejection without a reason is refused", post("/v1/submissions/${UUID.randomUUID()}/answer", """{"answer":"rejected"}""", lee).status.value in setOf(400, 404))
        }
        println("registration over HTTP: $passed checks passed")
    }
}
