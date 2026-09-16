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

/**
 * The knockout's other shapes (PD-115): pairs and teams as entrants, seeds the draw honours, and boards a tie is
 * sent to. A pair is two players who both stand entered; a team is entered by whoever runs it and checked in by any
 * member present; a seed is the organiser's and unique; a board is a label on a tie, nothing more.
 */
class EntrantsHttpTest {

    @Test
    fun `pairs and teams enter, seeds order the draw, and ties are sent to boards`() {
        if (!TestDatabase.configured) {
            println("no database configured (set PGHOST) — entrants HTTP tests skipped")
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
        val lee = person("007.lee", "Lee Organiser")
        val alice = person("007.alice", "Alice Aims"); val bob = person("007.bob", "Bob Board")
        val cara = person("007.cara", "Cara Checkout"); val dave = person("007.dave", "Dave Drifter")
        val ade = person("007.ade", "Ade Captain"); val sam = person("007.sam", "Sam Wilson"); val gil = person("007.gil", "Gil Captain")
        val riverside = orgs.createTeam("Riverside A", by = ade); val grange = orgs.createTeam("Grange A", by = gil)
        orgs.addMember(riverside, ade, MembershipRole.ADMIN, from = t0); orgs.addMember(riverside, sam, MembershipRole.PLAYER, from = t0)
        orgs.addMember(grange, gil, MembershipRole.ADMIN, from = t0)
        rel.grant(ade, "admin", ObjectRef(ObjectType.TEAM, riverside.toString())); rel.grant(gil, "admin", ObjectRef(ObjectType.TEAM, grange.toString()))
        var clock = Instant.parse("2026-09-16T12:00:00Z")

        testApplication {
            application { thro(Deps(connect = { TestDatabase.connect() }, authenticator = Authenticator.Dev(), now = { clock })) }
            suspend fun get(path: String, subject: UUID?): HttpResponse = client.get(path) { subject?.let { header(Authenticator.Dev.HEADER, it.toString()) } }
            suspend fun post(path: String, body: String, subject: UUID?): HttpResponse = client.post(path) {
                subject?.let { header(Authenticator.Dev.HEADER, it.toString()) }; header("X-Thro-Device", device.toString()); setBody(body)
            }
            fun idOf(text: String, key: String) = Regex("\"$key\":\"([0-9a-f-]{36})\"").find(text)?.groupValues?.get(1)

            // --- seeds (a singles event) -----------------------------------------------------------------------------
            val singles = idOf(post("/v1/events", """{"name":"Seeded Singles","startsAt":"2026-10-10T11:00:00Z","sessionEndsAt":"2026-10-10T22:00:00Z","venueLabel":"upstairs"}""", lee).bodyAsText(), "eventId")!!
            for (p in listOf(alice, bob, cara, dave)) post("/v1/events/$singles/entries", "{}", p)
            check("seeding is the organiser's", post("/v1/events/$singles/entries/$dave/seed", """{"seed":1}""", alice).status.value == 403)
            check("a seed is a positive number", post("/v1/events/$singles/entries/$dave/seed", """{"seed":0}""", lee).status.value == 400)
            check("the organiser seeds Dave first and Alice second", post("/v1/events/$singles/entries/$dave/seed", """{"seed":1}""", lee).status.value == 200 && post("/v1/events/$singles/entries/$alice/seed", """{"seed":2}""", lee).status.value == 200)
            check("two entrants cannot share a seed", post("/v1/events/$singles/entries/$bob/seed", """{"seed":1}""", lee).status.value == 409)
            check("the organiser reads the seeds on the entrants", get("/v1/events/$singles", lee).bodyAsText().contains("\"playerId\":\"$dave\",\"name\":\"Dave Drifter\",\"checkedIn\":false,\"seed\":1"))
            val drawn = post("/v1/events/$singles/draw", "{}", lee).bodyAsText()
            check("the draw honours the seeds: seed 1 in the first tie, seed 2 in the second, apart",
                Regex("\"position\":1,\"homeId\":\"$dave\"").containsMatchIn(drawn) && Regex("\"position\":2,\"homeId\":\"$alice\"").containsMatchIn(drawn))
            check("a seed is not changed after the draw", post("/v1/events/$singles/entries/$bob/seed", """{"seed":3}""", lee).status.value == 409)

            // --- boards --------------------------------------------------------------------------------------------
            check("boards are the organiser's", post("/v1/events/$singles/boards", """{"labels":["Board 1","Board 2"]}""", alice).status.value == 403)
            val boards = post("/v1/events/$singles/boards", """{"labels":["Board 1","Board 2"]}""", lee)
            check("the organiser names the boards", boards.status.value == 200 && boards.bodyAsText().contains("\"boards\":[\"Board 1\",\"Board 2\"]"))
            val tie = Regex("\"tieId\":\"([0-9a-f-]{36})\"").find(drawn)!!.groupValues[1]
            check("a board THRØ does not have is a 404", post("/v1/events/$singles/ties/$tie/board", """{"label":"Board 9"}""", lee).status.value == 404)
            check("the organiser sends the tie to Board 1, and the page says so", post("/v1/events/$singles/ties/$tie/board", """{"label":"Board 1"}""", lee).status.value == 200 && get("/v1/events/$singles", null).bodyAsText().contains("\"tieId\":\"$tie\"[^}]*\"board\":\"Board 1\"".toRegex()))

            // --- pairs ---------------------------------------------------------------------------------------------
            val doubles = idOf(post("/v1/events", """{"name":"Friday Doubles","startsAt":"2026-10-16T19:00:00Z","sessionEndsAt":"2026-10-16T23:00:00Z","venueLabel":"upstairs","entrantKind":"pair"}""", lee).bodyAsText(), "eventId")!!
            check("a kind THRØ does not run is refused", post("/v1/events", """{"name":"Odd","startsAt":"2026-10-16T19:00:00Z","sessionEndsAt":"2026-10-16T23:00:00Z","entrantKind":"trio"}""", lee).status.value == 400)
            check("a pair event is not entered alone", post("/v1/events/$doubles/entries", "{}", alice).status.value == 400)
            check("a partner who is yourself is refused", post("/v1/events/$doubles/entries", """{"partnerId":"$alice"}""", alice).status.value == 400)
            check("Alice enters with Bob", post("/v1/events/$doubles/entries", """{"partnerId":"$bob"}""", alice).status.value == 200)
            check("both stand entered", get("/v1/events/$doubles", bob).bodyAsText().contains("\"you\":{\"entered\":true,\"checkedIn\":false}"))
            check("Bob cannot enter again with Cara", post("/v1/events/$doubles/entries", """{"partnerId":"$cara"}""", bob).status.value == 409)
            check("the organiser enters a pair by two ids", post("/v1/events/$doubles/entries", """{"playerIds":["$cara","$dave"]}""", lee).status.value == 200)
            val pairsDrawn = post("/v1/events/$doubles/draw", "{}", lee).bodyAsText()
            // A pair's two names come in the pair's own fixed order (V014: player_a < player_b by id), so either way round.
            fun named(a: String, b: String) = pairsDrawn.contains("$a & $b") || pairsDrawn.contains("$b & $a")
            check("the draw names the pairs", named("Alice Aims", "Bob Board") && named("Cara Checkout", "Dave Drifter"))
            clock = Instant.parse("2026-10-16T18:30:00Z")
            check("either of a pair checks the pair in", post("/v1/events/$doubles/check-in", "{}", bob).status.value == 200 && get("/v1/events/$doubles", alice).bodyAsText().contains("\"checkedIn\":true"))
            clock = Instant.parse("2026-09-16T12:00:00Z")

            // --- teams ---------------------------------------------------------------------------------------------
            val teams = idOf(post("/v1/events", """{"name":"Teams Cup","startsAt":"2026-10-23T19:00:00Z","sessionEndsAt":"2026-10-23T23:00:00Z","venueLabel":"upstairs","entrantKind":"team"}""", lee).bodyAsText(), "eventId")!!
            check("a team event is not entered as a person", post("/v1/events/$teams/entries", "{}", ade).status.value == 400)
            check("entering a team is for whoever runs it", post("/v1/events/$teams/entries", """{"teamId":"$riverside"}""", sam).status.value == 403)
            check("Ade enters Riverside", post("/v1/events/$teams/entries", """{"teamId":"$riverside"}""", ade).status.value == 200)
            check("Sam, a member, stands entered", get("/v1/events/$teams", sam).bodyAsText().contains("\"you\":{\"entered\":true,\"checkedIn\":false}"))
            check("Gil enters Grange", post("/v1/events/$teams/entries", """{"teamId":"$grange"}""", gil).status.value == 200)
            check("the organiser's entrants are the teams by name", get("/v1/events/$teams", lee).bodyAsText().contains("\"name\":\"Riverside A\""))
            check("withdrawing a team is for whoever runs it", post("/v1/events/$teams/withdraw", "{}", sam).status.value == 403)
            val teamsDrawn = post("/v1/events/$teams/draw", "{}", lee).bodyAsText()
            check("the draw names the teams", teamsDrawn.contains("Riverside A") && teamsDrawn.contains("Grange A"))
            clock = Instant.parse("2026-10-23T18:30:00Z")
            check("a member checks the team in", post("/v1/events/$teams/check-in", "{}", sam).status.value == 200)
            check("somebody in no entered team cannot", post("/v1/events/$teams/check-in", "{}", alice).status.value == 409)
        }
        println("entrants over HTTP: $passed checks passed")
    }
}
