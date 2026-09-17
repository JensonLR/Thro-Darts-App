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

/**
 * Walk-ups (PD-124). A pub knockout is entered by whoever is in the pub, and half of them will never have an account.
 * So the organiser adds them by name: a player with no account, in the draw like anybody else, decided by hand. THRØ
 * knows nothing about a walk-up — not their age, not what they agreed to — so their name is the organiser's to see
 * and nobody else's, unless the organiser says they are an adult who is happy to be on the draw; and thirty days after
 * the night, the name is forgotten, because nobody holds an account that could ask for it to be.
 */
class GuestsHttpTest {

    @Test
    fun `the organiser adds walk-ups by name, they are drawn and decided, named only where said, and forgotten`() {
        if (!TestDatabase.configured) {
            println("no database configured (set PGHOST) — guests HTTP tests skipped")
            return
        }
        val c = TestDatabase.migrated()
        val accounts = Accounts(c)
        var passed = 0
        fun check(name: String, cond: Boolean) {
            assertTrue(cond, "FAILED: $name")
            println("  PASS  $name")
            passed++
        }
        val device = UUID.randomUUID()
        fun person(sub: String, name: String): UUID {
            val s = accounts.signIn("apple", sub, device)
            accounts.setDisplayName(s.accountId, name)
            Friends(c).declareAge(s.accountId, "adult")
            Consent(c).say(s.accountId, Consent.Scope.LISTING, yes = true)
            return s.playerId!!
        }
        val lee = person("009.lee", "Lee Organiser"); val alice = person("009.alice", "Alice Aims"); val bob = person("009.bob", "Bob Board")
        // The night is in January, so by the real clock it ended long ago — which is what lets the forgetting be seen.
        val clock = Instant.parse("2026-01-02T12:00:00Z")

        testApplication {
            application { thro(Deps(connect = { TestDatabase.connect() }, authenticator = Authenticator.Dev(), now = { clock })) }
            suspend fun get(path: String, subject: UUID?): HttpResponse = client.get(path) { subject?.let { header(Authenticator.Dev.HEADER, it.toString()) } }
            suspend fun post(path: String, body: String, subject: UUID?): HttpResponse = client.post(path) {
                subject?.let { header(Authenticator.Dev.HEADER, it.toString()) }; header("X-Thro-Device", device.toString()); setBody(body)
            }
            fun idOf(text: String, key: String) = Regex("\"$key\":\"([0-9a-f-]{36})\"").find(text)?.groupValues?.get(1)

            val event = idOf(post("/v1/events", """{"name":"Friday Knockout","startsAt":"2026-01-09T19:00:00Z","sessionEndsAt":"2026-01-09T23:30:00Z","venueLabel":"the back room"}""", lee).bodyAsText(), "eventId")!!
            for (p in listOf(alice, bob)) post("/v1/events/$event/entries", "{}", p)

            check("adding a walk-up is the organiser's", post("/v1/events/$event/guests", """{"name":"Big Dave"}""", alice).status.value == 403)
            check("a walk-up has a name", post("/v1/events/$event/guests", """{"name":"  "}""", lee).status.value == 400)
            check("and not an essay", post("/v1/events/$event/guests", """{"name":"${"x".repeat(61)}"}""", lee).status.value == 400)
            val dave = post("/v1/events/$event/guests", """{"name":"Big Dave"}""", lee)
            check("the organiser adds Big Dave", dave.status.value == 200 && dave.bodyAsText().contains("\"name\":\"Big Dave\",\"checkedIn\":true") && dave.bodyAsText().contains("\"kind\":\"guest\""))
            val carol = post("/v1/events/$event/guests", """{"name":"Carol Smith","mayBeNamed":true}""", lee)
            check("and Carol, who is an adult and happy to be on the draw", carol.status.value == 200 && carol.bodyAsText().contains("Carol Smith"))
            val extra = post("/v1/events/$event/guests", """{"name":"Latecomer"}""", lee).bodyAsText()
            val latecomer = Regex("\"playerId\":\"([0-9a-f-]{36})\",\"name\":\"Latecomer\"").find(extra)!!.groupValues[1]
            check("the same name twice is refused: two Daves need telling apart", post("/v1/events/$event/guests", """{"name":"big dave"}""", lee).status.value == 409)
            check("the page counts them and names nobody", get("/v1/events/$event", null).bodyAsText().let { it.contains("\"entries\":5") && !it.contains("Big Dave") && !it.contains("Carol Smith") })
            check("a walk-up is removed like any entry, before the draw", post("/v1/events/$event/entries/$latecomer/remove", "{}", lee).status.value == 200)

            val drawn = post("/v1/events/$event/draw", "{}", lee).bodyAsText()
            check("the draw names them all for the organiser", drawn.contains("Big Dave") && drawn.contains("Carol Smith") && drawn.contains("Alice Aims"))
            val public = get("/v1/events/$event", null).bodyAsText()
            check("the public draw names Carol, and Big Dave is a guest", public.contains("Carol Smith") && !public.contains("Big Dave") && public.contains("A guest"))
            val tie = Regex("\"tieId\":\"([0-9a-f-]{36})\",\"round\":1,\"position\":\\d+,\"homeId\":\"([0-9a-f-]{36})\"").find(drawn)!!
            // Nobody scores for a walk-up on THRØ, so there is no match to cite: the result is the organiser's word, with a note.
            check("a tie with a walk-up in it is decided by hand, as the organiser's word",
                post("/v1/events/$event/ties/${tie.groupValues[1]}/result", """{"winnerId":"${tie.groupValues[2]}","outcome":"awarded","note":"Played on board 1: 2–0."}""", lee).status.value == 200)

            // A pairs night is not entered by one name.
            val doubles = idOf(post("/v1/events", """{"name":"Doubles","startsAt":"2026-01-16T19:00:00Z","sessionEndsAt":"2026-01-16T23:00:00Z","entrantKind":"pair"}""", lee).bodyAsText(), "eventId")!!
            check("a pairs or teams event takes no walk-up by one name", post("/v1/events/$doubles/guests", """{"name":"Big Dave"}""", lee).status.value == 400)

            // Thirty days after the night, the names go: nobody holds an account that could ask.
            TestDatabase.asServer().use { s -> s.createStatement().use { it.execute("SET ROLE app_competition"); it.execute("SELECT competition.forget_guests()") } }
            val after = get("/v1/events/$event", lee).bodyAsText()
            check("and thirty days on, the walk-ups' names are forgotten, the draw kept", !after.contains("Big Dave") && !after.contains("Carol Smith") && after.contains("A guest") && after.contains("Alice Aims"))
        }
        println("guests over HTTP: $passed checks passed")
    }
}
