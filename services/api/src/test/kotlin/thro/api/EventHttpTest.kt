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
 * A knockout run on THRØ (PD-109), over the wire: an organiser opens an edition, players enter and withdraw, the
 * organiser closes entries and makes the draw, and a player present on the day checks in from their own phone and
 * holds the grant that lets them score with no signal. The domain (`Competitions`) was held by `CompetitionTest`;
 * this holds that each step is reachable by the right person and nobody else, and that the notice on the door
 * (`/v1/events`) and the event's own page say what is true.
 */
class EventHttpTest {

    @Test
    fun `an organiser opens an event, players enter, the draw is made, and a player checks in on the day`() {
        if (!TestDatabase.configured) {
            println("no database configured (set PGHOST) — event HTTP tests skipped")
            return
        }
        val c = TestDatabase.migrated()
        val orgs = Organisations(c)
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
        val lee = person("003.lee", "Lee Organiser")
        val alice = person("003.alice", "Alice Aims")
        val bob = person("003.bob", "Bob Board")
        val cara = person("003.cara", "Cara Checkout")
        val dave = person("003.dave", "Dave Drifter")
        val zed = person("003.zed", "Zed Nobody")
        val pub = orgs.createVenue("The Sun Inn", "Stockton-on-Tees")
        var clock = Instant.parse("2026-09-16T12:00:00Z")

        testApplication {
            application { thro(Deps(connect = { TestDatabase.connect() }, authenticator = Authenticator.Dev(), now = { clock })) }
            suspend fun get(path: String, subject: UUID?): HttpResponse = client.get(path) { subject?.let { header(Authenticator.Dev.HEADER, it.toString()) } }
            suspend fun post(path: String, body: String, subject: UUID?): HttpResponse = client.post(path) {
                subject?.let { header(Authenticator.Dev.HEADER, it.toString()) }; header("X-Thro-Device", device.toString()); setBody(body)
            }
            fun idOf(text: String, key: String) = Regex("\"$key\":\"([0-9a-f-]{36})\"").find(text)?.groupValues?.get(1)

            // --- opening an edition is an organiser's act, and the one that makes them its organiser ------------------
            val open = """{"name":"Sun Inn Open","startsAt":"2026-10-03T11:00:00Z","sessionEndsAt":"2026-10-03T22:00:00Z","venueId":"$pub","capacity":2,"entriesCloseAt":"2026-10-02T20:00:00Z"}"""
            check("opening an event needs a principal", post("/v1/events", open, null).status.value == 401)
            check("a session that ends before it starts is refused", post("/v1/events", """{"name":"Backwards","startsAt":"2026-10-03T11:00:00Z","sessionEndsAt":"2026-10-03T10:00:00Z"}""", lee).status.value == 400)
            check("a nameless event is refused", post("/v1/events", """{"name":" ","startsAt":"2026-10-03T11:00:00Z","sessionEndsAt":"2026-10-03T22:00:00Z"}""", lee).status.value == 400)
            val made = post("/v1/events", open, lee)
            val event = idOf(made.bodyAsText(), "eventId")
            check("the organiser opens it, open for entries", made.status.value == 200 && event != null && made.bodyAsText().contains("\"state\":\"open\""))
            check("it is on the notice on the door, with its venue", get("/v1/events", null).bodyAsText().let { it.contains("\"eventId\":\"$event\"") && it.contains("The Sun Inn") })
            check("and among the organiser's own events, and nobody else's",
                get("/v1/me/events", lee).bodyAsText().contains("\"eventId\":\"$event\"") && !get("/v1/me/events", alice).bodyAsText().contains("\"eventId\":\"$event\""))
            val page = get("/v1/events/$event", null).bodyAsText()
            check("its page reads without a session: capacity, no entries yet, nobody named",
                page.contains("\"capacity\":2") && page.contains("\"entries\":0") && page.contains("\"you\":null") && !page.contains("Lee Organiser"))

            // --- entering is a player's own act ------------------------------------------------------------------------
            check("entering needs a principal", post("/v1/events/$event/entries", "{}", null).status.value == 401)
            check("Alice enters", post("/v1/events/$event/entries", "{}", alice).status.value == 200 && get("/v1/events/$event", alice).bodyAsText().contains("\"you\":{\"entered\":true,\"checkedIn\":false}"))
            check("entering twice is a 409", post("/v1/events/$event/entries", "{}", alice).status.value == 409)
            check("Bob enters and the event is full", post("/v1/events/$event/entries", "{}", bob).status.value == 200 && get("/v1/events/$event", null).bodyAsText().contains("\"spotsRemaining\":0"))
            val full = post("/v1/events/$event/entries", "{}", cara)
            check("Cara cannot: full, said in words", full.status.value == 409 && full.bodyAsText().contains("full"))
            check("Bob withdraws, and a place opens", post("/v1/events/$event/withdraw", "{}", bob).status.value == 200 && get("/v1/events/$event", null).bodyAsText().contains("\"spotsRemaining\":1"))
            check("withdrawing when not entered is a 409", post("/v1/events/$event/withdraw", "{}", bob).status.value == 409)
            check("Cara enters the place", post("/v1/events/$event/entries", "{}", cara).status.value == 200)
            check("Bob may enter again if a place opens, but there is none", post("/v1/events/$event/entries", "{}", bob).status.value == 409)

            // --- the day: check-in is the entrant's, from their own phone, when the event is near ------------------------
            check("checking in weeks early is refused in words", post("/v1/events/$event/check-in", "{}", alice).status.value == 409)
            clock = Instant.parse("2026-10-02T21:00:00Z")
            check("after entries close nobody enters", post("/v1/events/$event/entries", "{}", dave).status.value == 409)
            clock = Instant.parse("2026-10-03T10:30:00Z")
            check("somebody not entered cannot check in", post("/v1/events/$event/check-in", "{}", dave).status.value == 409)
            val checked = post("/v1/events/$event/check-in", "{}", alice)
            check("Alice checks in and holds a grant that outlives the session", checked.status.value == 200 && idOf(checked.bodyAsText(), "grantId") != null && checked.bodyAsText().contains("\"expiresAt\":\"2026-10-04T22:00:00Z\""))
            check("her page says so", get("/v1/events/$event", alice).bodyAsText().contains("\"you\":{\"entered\":true,\"checkedIn\":true}"))
            check("checking in again from the same phone is the same answer, not a second entry", post("/v1/events/$event/check-in", "{}", alice).status.value == 200 && get("/v1/events/$event", null).bodyAsText().contains("\"entries\":2"))

            // --- the draw is the organiser's ---------------------------------------------------------------------------
            check("a player cannot draw", post("/v1/events/$event/draw", "{}", alice).status.value == 403)
            val drawn = post("/v1/events/$event/draw", "{}", lee)
            check("the organiser draws: two entrants, one tie, no bye", drawn.status.value == 200 && drawn.bodyAsText().contains("\"state\":\"drawn\"") && drawn.bodyAsText().contains("\"isBye\":false"))
            val after = get("/v1/events/$event", null).bodyAsText()
            check("the page shows the draw with the players named, where THRØ may name them", after.contains("Alice Aims") && after.contains("Cara Checkout") && after.contains("\"round\":1"))
            check("drawing again is a 409", post("/v1/events/$event/draw", "{}", lee).status.value == 409)
            check("withdrawing after the draw is a 409", post("/v1/events/$event/withdraw", "{}", cara).status.value == 409)
            check("a drawn event is off the notice on the door", !get("/v1/events", null).bodyAsText().contains("\"eventId\":\"$event\""))

            // --- an event with one entrant cannot be drawn; closing entries is a state of its own ----------------------
            clock = Instant.parse("2026-09-16T12:00:00Z")
            val second = idOf(post("/v1/events", """{"name":"Tuesday Singles","startsAt":"2026-10-06T19:00:00Z","sessionEndsAt":"2026-10-06T23:00:00Z","venueLabel":"ask at the bar"}""", lee).bodyAsText(), "eventId")!!
            post("/v1/events/$second/entries", "{}", alice)
            check("closing entries is the organiser's", post("/v1/events/$second/close", "{}", alice).status.value == 403)
            check("the organiser closes entries", post("/v1/events/$second/close", "{}", lee).bodyAsText().contains("\"state\":\"entries_closed\""))
            check("and nobody enters after", post("/v1/events/$second/entries", "{}", bob).status.value == 409)
            check("one entrant is no draw", post("/v1/events/$second/draw", "{}", lee).status.value == 409)

            // --- rounds (PD-111): four entrants, two rounds, one decided by a match and one by the organiser's word ------
            val third = idOf(post("/v1/events", """{"name":"Friday Fours","startsAt":"2026-10-09T19:00:00Z","sessionEndsAt":"2026-10-09T23:00:00Z","venueLabel":"the back room"}""", lee).bodyAsText(), "eventId")!!
            for (p in listOf(alice, bob, cara, dave)) post("/v1/events/$third/entries", "{}", p)
            check("advancing before the draw is a 409", post("/v1/events/$third/advance", "{}", lee).status.value == 409)
            val drawnFours = post("/v1/events/$third/draw", "{}", lee).bodyAsText()
            val ties = Regex("\"tieId\":\"([0-9a-f-]{36})\"[^}]*\"homeId\":\"([0-9a-f-]{36})\"[^}]*\"awayId\":\"([0-9a-f-]{36})\"").findAll(drawnFours)
                .map { Triple(it.groupValues[1], UUID.fromString(it.groupValues[2]), UUID.fromString(it.groupValues[3])) }.toList()
            check("four entrants draw into two ties with no bye", ties.size == 2 && !drawnFours.contains("\"isBye\":true"))
            check("advancing with nothing decided is a 409 that says so", post("/v1/events/$third/advance", "{}", lee).bodyAsText().contains("undecided"))
            val (tieA, homeA, awayA) = ties[0]; val (tieB, homeB, awayB) = ties[1]
            // Tie A: the organiser's word — a walkover to the home side because the away side did not turn up.
            check("declaring a winner is the organiser's", post("/v1/events/$third/ties/$tieA/result", """{"winnerId":"$homeA","outcome":"walkover","note":"did not arrive"}""", alice).status.value == 403)
            check("a winner who is not in the tie is refused", post("/v1/events/$third/ties/$tieA/result", """{"winnerId":"$lee","outcome":"walkover","note":"x"}""", lee).status.value == 400)
            val walk = post("/v1/events/$third/ties/$tieA/result", """{"winnerId":"$homeA","outcome":"walkover","note":"did not arrive"}""", lee)
            check("the organiser records a walkover, and the tie says who and why", walk.status.value == 200 && walk.bodyAsText().contains("\"outcome\":\"walkover\"") && walk.bodyAsText().contains("\"winnerId\":\"$homeA\""))
            check("a decided tie is not decided again", post("/v1/events/$third/ties/$tieA/result", """{"winnerId":"$awayA","outcome":"awarded","note":"changed my mind"}""", lee).status.value == 409)
            // Tie B: played on THRØ; the winner is read from the match's own record, not typed.
            val played = UUID.randomUUID()
            Matches(c).open(played, homeB, awayB, thro.engine.MatchFormat(startingScore = 501, inRule = thro.engine.InRule.STRAIGHT, outRule = thro.engine.OutRule.DOUBLE, legs = thro.engine.Structure(thro.engine.StructureMode.FIRST_TO, 1), throwFirst = Seat.home))
            var seq = 0L
            for ((seat, total) in listOf("home" to 180, "away" to 60, "home" to 180, "away" to 60, "home" to 141)) {
                post("/v1/commands", """{"type":"RecordVisit","commandId":"${UUID.randomUUID()}","matchId":"$played","deviceSeq":${++seq},"player":"$seat","visitTotal":$total,"occurredAt":"2026-10-09T19:${30 + seq}:00Z"}""", homeB)
            }
            check("a stranger cannot cite a match to a tie", post("/v1/events/$third/ties/$tieB/match", """{"matchId":"$played"}""", zed).status.value == 403)
            val wrong = UUID.randomUUID()
            Matches(c).open(wrong, homeB, lee, thro.engine.MatchFormat(startingScore = 501, inRule = thro.engine.InRule.STRAIGHT, outRule = thro.engine.OutRule.DOUBLE, legs = thro.engine.Structure(thro.engine.StructureMode.FIRST_TO, 1), throwFirst = Seat.home))
            check("a match between other players is not this tie's", post("/v1/events/$third/ties/$tieB/match", """{"matchId":"$wrong"}""", homeB).status.value == 409)
            val cited = post("/v1/events/$third/ties/$tieB/match", """{"matchId":"$played"}""", homeB)
            check("a player in the tie cites the match, and the winner is the record's", cited.status.value == 200 && cited.bodyAsText().contains("\"outcome\":\"played\"") && cited.bodyAsText().contains("\"winnerId\":\"$homeB\""))
            check("the event is in progress", get("/v1/events/$third", null).bodyAsText().contains("\"state\":\"in_progress\""))
            check("advancing is the organiser's", post("/v1/events/$third/advance", "{}", alice).status.value == 403)
            val next = post("/v1/events/$third/advance", "{}", lee).bodyAsText()
            check("the organiser advances: one tie in round two between the two winners", next.contains("\"round\":2") && next.contains("\"homeId\":\"$homeA\"") && next.contains("\"awayId\":\"$homeB\""))
            val finalTie = Regex("\"tieId\":\"([0-9a-f-]{36})\",\"round\":2").find(next)!!.groupValues[1]
            post("/v1/events/$third/ties/$finalTie/result", """{"winnerId":"$homeB","outcome":"awarded","note":"won 3-1 on the board"}""", lee)
            val done = post("/v1/events/$third/advance", "{}", lee).bodyAsText()
            check("after the final the event is complete, and names its winner", done.contains("\"state\":\"complete\"") && done.contains("\"winnerId\":\"$homeB\""))
            check("a complete event does not advance", post("/v1/events/$third/advance", "{}", lee).status.value == 409)

            // --- an invitational (PD-113): the organiser names who plays; nobody enters themselves ------------------------
            val invite = idOf(post("/v1/events", """{"name":"Champions' Night","startsAt":"2026-10-16T19:00:00Z","sessionEndsAt":"2026-10-16T23:00:00Z","venueLabel":"upstairs","access":"invitational"}""", lee).bodyAsText(), "eventId")!!
            check("an access THRØ does not run is refused", post("/v1/events", """{"name":"Odd","startsAt":"2026-10-16T19:00:00Z","sessionEndsAt":"2026-10-16T23:00:00Z","access":"members_and_guests"}""", lee).status.value == 400)
            check("an invitational is not on the notice on the door", !get("/v1/events", null).bodyAsText().contains("\"eventId\":\"$invite\""))
            check("nobody enters themselves", post("/v1/events/$invite/entries", "{}", alice).status.value == 403)
            check("the organiser invites a player by id", post("/v1/events/$invite/entries", """{"playerId":"$alice"}""", lee).status.value == 200 && get("/v1/events/$invite", alice).bodyAsText().contains("\"you\":{\"entered\":true,\"checkedIn\":false}"))
            check("only the organiser invites", post("/v1/events/$invite/entries", """{"playerId":"$bob"}""", alice).status.value == 403)
            check("inviting somebody THRØ does not have is a 404", post("/v1/events/$invite/entries", """{"playerId":"${UUID.randomUUID()}"}""", lee).status.value == 404)
            check("inviting twice is a 409", post("/v1/events/$invite/entries", """{"playerId":"$alice"}""", lee).status.value == 409)
            post("/v1/events/$invite/entries", """{"playerId":"$bob"}""", lee)
            check("the page counts the invited", get("/v1/events/$invite", null).bodyAsText().contains("\"entries\":2"))
            check("the organiser reads who is entered, by name; the public page names nobody before the draw",
                get("/v1/events/$invite", lee).bodyAsText().contains("\"entrants\":[{\"playerId\":\"$alice\",\"name\":\"Alice Aims\"") && get("/v1/events/$invite", null).bodyAsText().contains("\"entrants\":null") && !get("/v1/events/$invite", alice).bodyAsText().contains("Bob Board"))
            check("removing an entry is the organiser's", post("/v1/events/$invite/entries/$bob/remove", "{}", alice).status.value == 403)
            check("the organiser removes one", post("/v1/events/$invite/entries/$bob/remove", "{}", lee).status.value == 200 && get("/v1/events/$invite", null).bodyAsText().contains("\"entries\":1"))
            check("removing somebody not entered is a 409", post("/v1/events/$invite/entries/$bob/remove", "{}", lee).status.value == 409)
            check("an invited player may still withdraw themselves", post("/v1/events/$invite/withdraw", "{}", alice).status.value == 200)
            check("and on an open event the organiser may also enter a player by id", post("/v1/events/$second/entries", """{"playerId":"$cara"}""", lee).status.value == 409 && post("/v1/events/$second/entries", """{"playerId":"$cara"}""", lee).bodyAsText().contains("closed"))
        }
        println("events over HTTP: $passed checks passed")
    }
}
