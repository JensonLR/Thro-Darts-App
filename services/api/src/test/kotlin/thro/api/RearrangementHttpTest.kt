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
 * Moving a fixture by agreement (PD-108), over the wire: one team proposes a new date, the other answers from its
 * inbox, and the league applies what was agreed through the same command every rearrangement goes through — so the
 * fixture's history says which proposal moved it. A proposal is not a move: until the league applies it, the fixture
 * stands where it was.
 */
class RearrangementHttpTest {

    @Test
    fun `a team proposes, the opponent answers, and only the league's application moves the fixture`() {
        if (!TestDatabase.configured) {
            println("no database configured (set PGHOST) — rearrangement HTTP tests skipped")
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
        val lee = person("002.lee", "Lee Organiser")
        val ade = person("002.ade", "Ade Captain")
        val gil = person("002.gil", "Gil Captain")
        val sam = person("002.sam", "Sam Player")
        val zed = person("002.zed", "Zed Nobody")
        val league = orgs.createLeague("Teesside Thursday League")
        val season = orgs.openSeason(league, "2026/27", LocalDate.of(2026, 9, 1), LocalDate.of(2027, 5, 31))
        rel.grant(lee, "admin", ObjectRef(ObjectType.LEAGUE_SEASON, season.toString()))
        val riverside = orgs.createTeam("Riverside A", by = ade); val grange = orgs.createTeam("Grange A", by = gil)
        orgs.addMember(riverside, ade, MembershipRole.ADMIN, from = t0); orgs.addMember(riverside, sam, MembershipRole.PLAYER, from = t0)
        orgs.addMember(grange, gil, MembershipRole.ADMIN, from = t0)
        rel.grant(ade, "admin", ObjectRef(ObjectType.TEAM, riverside.toString())); rel.grant(gil, "admin", ObjectRef(ObjectType.TEAM, grange.toString()))
        for (t in listOf(riverside, grange)) orgs.acceptAffiliation(orgs.affiliate(t, season, from = t0), t0)
        val fixture = orgs.scheduleFixture(season, null, riverside, grange, Instant.parse("2026-10-08T19:30:00Z"))
        // PD-128: a second fixture, for a proposal that names somewhere else to play it.
        val away = orgs.scheduleFixture(season, null, grange, riverside, Instant.parse("2026-11-12T19:30:00Z"))
        val club = orgs.createVenue("Grange Social Club", "Stockton-on-Tees")
        val hidden = orgs.createVenue("A Private Room", "Stockton-on-Tees")
        c.prepareStatement("UPDATE competition.venue SET visibility = 'private' WHERE venue_id = ?").use { ps -> ps.setObject(1, hidden); ps.executeUpdate() }
        // PD-128: a venue nobody has said where it is, a venue whose name carries the punctuation JSON cares about,
        // and two fixtures already at a place of their own — so what a proposal does to a fixture's venue can be seen.
        val nowhere = orgs.createVenue("The Back Room", null)
        val awkward = orgs.createVenue("The \"Vic\" \\ Snug", "Middlesbrough")
        val homely = orgs.scheduleFixture(season, null, riverside, grange, Instant.parse("2026-12-03T19:30:00Z"), venueId = club)
        val kept = orgs.scheduleFixture(season, null, grange, riverside, Instant.parse("2027-01-14T19:30:00Z"), venueId = club)

        testApplication {
            application { thro(Deps(connect = { TestDatabase.connect() }, authenticator = Authenticator.Dev(), now = { Instant.parse("2026-09-16T12:00:00Z") })) }
            suspend fun get(path: String, subject: UUID?): HttpResponse = client.get(path) { subject?.let { header(Authenticator.Dev.HEADER, it.toString()) } }
            suspend fun post(path: String, body: String, subject: UUID?): HttpResponse = client.post(path) {
                subject?.let { header(Authenticator.Dev.HEADER, it.toString()) }; header("X-Thro-Device", device.toString()); setBody(body)
            }
            fun idOf(text: String, key: String) = Regex("\"$key\":\"([0-9a-f-]{36})\"").find(text)?.groupValues?.get(1)
            // One fixture out of the league's list, as the league's list gives it: the night and the place.
            suspend fun fixtureCard(id: java.util.UUID): String = get("/v1/seasons/$season/fixtures", null).bodyAsText()
                .substringAfter("\"fixtureId\":\"$id\"").substringBefore("\"fixtureId\"")

            // --- proposing is a team's act, by whoever runs it ------------------------------------------------------
            val proposal = """{"teamId":"$riverside","to":"2026-10-15T19:30:00Z","reason":"venue double-booked"}"""
            check("a proposal needs a principal", post("/v1/fixtures/$fixture/proposals", proposal, null).status.value == 401)
            check("and is for whoever runs the proposing team", post("/v1/fixtures/$fixture/proposals", proposal, sam).status.value == 403 && post("/v1/fixtures/$fixture/proposals", proposal, zed).status.value == 403)
            check("a team not in the fixture cannot propose for it", post("/v1/fixtures/$fixture/proposals", """{"teamId":"${UUID.randomUUID()}","to":"2026-10-15T19:30:00Z"}""", ade).status.value in setOf(403, 409))
            check("a date outside the season is refused", post("/v1/fixtures/$fixture/proposals", """{"teamId":"$riverside","to":"2027-08-01T19:30:00Z"}""", ade).status.value == 400)
            val gone = post("/v1/fixtures/$fixture/proposals", """{"teamId":"$riverside","to":"2026-09-10T19:30:00Z"}""", ade)
            check("a date already gone is refused in words, not by a number alone", gone.status.value == 400 && gone.bodyAsText().contains("The new date is in the past."))
            val nameless = post("/v1/fixtures/$fixture/proposals", """{"to":"2026-10-15T19:30:00Z"}""", ade)
            check("a proposal that names no team says which field it wants", nameless.status.value == 400 && nameless.bodyAsText().contains("teamId is required"))
            // The words as well as the number: a refusal that names what it could not read is the difference
            // between a caller fixing their request and a caller guessing (PD-139).
            val notATeam = post("/v1/fixtures/$fixture/proposals", """{"teamId":"the reds","to":"2026-10-15T19:30:00Z"}""", ade)
            check("a team that is not an id is the caller's mistake, not the server's, and it says which one",
                notATeam.status.value == 400 && notATeam.bodyAsText().contains("the reds"))
            val notAFixture = get("/v1/fixtures/not-a-fixture/proposals", ade)
            check("a fixture that is not an id is the caller's mistake too, and it says which one",
                notAFixture.status.value == 400 && notAFixture.bodyAsText().contains("not-a-fixture"))
            val noFixture = post("/v1/fixtures/${UUID.randomUUID()}/proposals", proposal, ade)
            check("a fixture THRØ does not hold says so", noFixture.status.value == 404 && noFixture.bodyAsText().contains("THRØ has no such fixture."))
            val made = post("/v1/fixtures/$fixture/proposals", proposal, ade)
            val proposalId = idOf(made.bodyAsText(), "proposalId")
            check("the captain proposes, and the proposal is delivered to the opponent", made.status.value == 200 && proposalId != null && made.bodyAsText().contains("\"state\":\"proposed\""))
            check("a second open proposal from the same team is refused", post("/v1/fixtures/$fixture/proposals", proposal, ade).status.value == 409)

            // --- both teams and the league read it; nobody else --------------------------------------------------
            check("a stranger cannot read a fixture's proposals", get("/v1/fixtures/$fixture/proposals", zed).status.value == 403)
            val seen = get("/v1/fixtures/$fixture/proposals", gil).bodyAsText()
            check("the opponent reads what was proposed, from whom, and why",
                seen.contains("\"proposalId\":\"$proposalId\"") && seen.contains("2026-10-15T19:30:00Z") && seen.contains("Riverside A") && seen.contains("venue double-booked") && seen.contains("\"state\":\"proposed\""))
            check("a member of the proposing team reads it too", get("/v1/fixtures/$fixture/proposals", sam).status.value == 200)
            val inbox = get("/v1/teams/$grange/inbox", gil).bodyAsText()
            check("the opponent's inbox carries the proposal it must answer", inbox.contains("\"proposal\":\"$proposalId\""))
            check("a proposal that is not an id is a 400, not a 500", get("/v1/proposals/not-a-proposal", gil).status.value == 400)
            check("and the proposal is read on its own by the same readers, and by nobody else",
                get("/v1/proposals/$proposalId", gil).bodyAsText().contains("\"scheduledAt\":\"2026-10-08T19:30:00Z\"") && get("/v1/proposals/$proposalId", zed).status.value == 403 && get("/v1/proposals/${UUID.randomUUID()}", gil).status.value == 404)

            // --- the answer is the opponent's ------------------------------------------------------------------------
            check("the proposing team cannot answer its own proposal", post("/v1/proposals/$proposalId/answer", """{"answer":"accepted"}""", ade).status.value == 403)
            check("an answer THRØ does not know is a 400", post("/v1/proposals/$proposalId/answer", """{"answer":"maybe"}""", gil).status.value == 400)
            check("nothing has moved", get("/v1/seasons/$season/fixtures", null).bodyAsText().contains("2026-10-08T19:30:00Z"))
            val answered = post("/v1/proposals/$proposalId/answer", """{"answer":"accepted","note":"fine by us"}""", gil)
            check("the opponent accepts", answered.status.value == 200 && answered.bodyAsText().contains("\"state\":\"accepted\""))
            check("answering again is a 409", post("/v1/proposals/$proposalId/answer", """{"answer":"rejected","note":"changed our minds"}""", gil).status.value == 409)
            check("accepted is not moved", get("/v1/seasons/$season/fixtures", null).bodyAsText().contains("2026-10-08T19:30:00Z"))

            // --- the league applies it, and the fixture moves through the command every rearrangement goes through -----
            check("applying is the league's", post("/v1/proposals/$proposalId/apply", """{"expectedVersion":1}""", gil).status.value == 403)
            val stale = post("/v1/proposals/$proposalId/apply", """{"expectedVersion":7}""", lee)
            check("a stale version is said, not applied", stale.status.value == 409 && get("/v1/seasons/$season/fixtures", null).bodyAsText().contains("2026-10-08T19:30:00Z"))
            val applied = post("/v1/proposals/$proposalId/apply", """{"expectedVersion":1}""", lee)
            check("the league applies it", applied.status.value == 200 && applied.bodyAsText().contains("\"state\":\"applied\""))
            val fixtures = get("/v1/seasons/$season/fixtures", null).bodyAsText()
            check("and the fixture is on the new date", fixtures.contains("2026-10-15T19:30:00Z") && !fixtures.contains("2026-10-08T19:30:00Z"))
            check("applying it twice is a 409", post("/v1/proposals/$proposalId/apply", """{"expectedVersion":2}""", lee).status.value == 409)
            check("the season's open requests are listed for the league, and this one is no longer open",
                get("/v1/seasons/$season/proposals", lee).bodyAsText().let { it.contains("\"proposals\":[") && !it.contains("\"state\":\"accepted\"") })

            // --- a rejection is an answer too ------------------------------------------------------------------------
            val second = idOf(post("/v1/fixtures/$fixture/proposals", """{"teamId":"$grange","to":"2026-10-22T19:30:00Z","reason":"cup night"}""", gil).bodyAsText(), "proposalId")!!
            check("a rejection needs a reason", post("/v1/proposals/$second/answer", """{"answer":"rejected"}""", ade).status.value == 400)
            val declined = post("/v1/proposals/$second/answer", """{"answer":"rejected","note":"we cannot raise a side that night"}""", ade)
            check("the opponent declines, with the reason kept", declined.status.value == 200 && declined.bodyAsText().contains("\"state\":\"declined\""))
            check("a declined proposal cannot be applied", post("/v1/proposals/$second/apply", """{"expectedVersion":2}""", lee).status.value == 409)

            // --- withdrawing is the proposer's, while unanswered -------------------------------------------------------
            val third = idOf(post("/v1/fixtures/$fixture/proposals", """{"teamId":"$riverside","to":"2026-10-29T19:30:00Z"}""", ade).bodyAsText(), "proposalId")!!
            check("withdrawing is for whoever runs the proposing team", post("/v1/proposals/$third/withdraw", "{}", gil).status.value == 403)
            val withdrawn = post("/v1/proposals/$third/withdraw", "{}", ade)
            check("the proposer withdraws (${withdrawn.status.value} ${withdrawn.bodyAsText().take(200)})", withdrawn.bodyAsText().contains("\"state\":\"withdrawn\""))
            check("a withdrawn proposal cannot be answered", post("/v1/proposals/$third/answer", """{"answer":"accepted"}""", gil).status.value == 409)
            check("and its task is no longer open in the opponent's inbox", !get("/v1/teams/$grange/inbox", gil).bodyAsText().contains("\"proposal\":\"$third\",\"state\":\"open\"") )
            check("a withdrawn proposal frees the fixture for a new one", post("/v1/fixtures/$fixture/proposals", """{"teamId":"$grange","to":"2026-11-05T19:30:00Z"}""", gil).status.value == 200)

            // --- a proposal may name somewhere else to play it (PD-128) -----------------------------------------------
            val notAnId = post("/v1/fixtures/$away/proposals", """{"teamId":"$grange","to":"2026-11-19T19:30:00Z","venueId":"the club"}""", gil)
            check("a venue that is not an id is a 400, and says which field it means", notAnId.status.value == 400 && notAnId.bodyAsText().contains("venueId must be a UUID"))
            val unheld = post("/v1/fixtures/$away/proposals", """{"teamId":"$grange","to":"2026-11-19T19:30:00Z","venueId":"${UUID.randomUUID()}"}""", gil)
            check("a venue THRØ does not hold is refused in words", unheld.status.value == 400 && unheld.bodyAsText().contains("That venue is not one THRØ can show the other team."))
            val secret = post("/v1/fixtures/$away/proposals", """{"teamId":"$grange","to":"2026-11-19T19:30:00Z","venueId":"$hidden"}""", gil)
            check("a private venue cannot be proposed: the other side could not be told where", secret.status.value == 400)
            check("and it is refused in the very same words, so the proposer cannot tell a room THRØ hides from one it does not hold",
                secret.bodyAsText() == unheld.bodyAsText())
            val elsewhere = post("/v1/fixtures/$away/proposals", """{"teamId":"$grange","to":"2026-11-19T19:30:00Z","reason":"the pub is shut for a refit","venueId":"$club"}""", gil)
            check("a proposal names a new date and somewhere else to play it", elsewhere.status.value == 200
                && elsewhere.bodyAsText().contains("\"venue\":{\"venueId\":\"$club\",\"name\":\"Grange Social Club\",\"locality\":\"Stockton-on-Tees\"}"))
            val elsewhereId = idOf(elsewhere.bodyAsText(), "proposalId")!!
            check("the opponent reads where as well as when", get("/v1/proposals/$elsewhereId", ade).bodyAsText().contains("Grange Social Club"))
            val desk = get("/v1/seasons/$season/proposals", lee).bodyAsText()
            check("the league's list of open requests carries the place, not only the date",
                desk.contains("\"proposalId\":\"$elsewhereId\"")
                    && desk.contains("\"venue\":{\"venueId\":\"$club\",\"name\":\"Grange Social Club\",\"locality\":\"Stockton-on-Tees\"}"))
            val answering = get("/v1/teams/$riverside/inbox", ade).bodyAsText()
            check("the card in the answering captain's inbox reaches the place: the proposal it points at reads back with its venue",
                answering.contains("\"proposal\":\"$elsewhereId\"") && get("/v1/proposals/$elsewhereId", ade).bodyAsText().contains("\"name\":\"Grange Social Club\""))
            check("a proposal with no venue says none", get("/v1/fixtures/$fixture/proposals", ade).bodyAsText().contains("\"venue\":null"))
            post("/v1/proposals/$elsewhereId/answer", """{"answer":"accepted"}""", ade)
            check("applied, the fixture is on the new date at the new place",
                post("/v1/proposals/$elsewhereId/apply", """{"expectedVersion":1}""", lee).status.value == 200
                && get("/v1/seasons/$season/fixtures", null).bodyAsText().let { it.contains("2026-11-19T19:30:00Z") && it.contains("Grange Social Club") })

            // --- the picker offers only what THRØ may show the other team (PD-128) -----------------------------------
            val offered = get("/v1/venues?q=Grange", null).bodyAsText()
            check("the picker offers the club by name", offered.contains("\"venueId\":\"$club\"") && offered.contains("Grange Social Club"))
            val searched = get("/v1/venues?q=Private", null).bodyAsText()
            check("and never offers a private room, however plainly it is asked for",
                searched.contains("\"venues\":[") && !searched.contains("\"venueId\":\"$hidden\"") && !searched.contains("A Private Room"))

            // --- a proposal says where, whatever becomes of the proposal (PD-128) ------------------------------------
            val unsaid = post("/v1/fixtures/$homely/proposals", """{"teamId":"$riverside","to":"2026-12-10T19:30:00Z","venueId":"$nowhere"}""", ade)
            val unsaidId = idOf(unsaid.bodyAsText(), "proposalId")!!
            check("a venue nobody has said the town of reads back as nothing, not as the word null",
                unsaid.status.value == 200 && unsaid.bodyAsText().contains("\"name\":\"The Back Room\",\"locality\":null") && !unsaid.bodyAsText().contains("\"locality\":\"null\""))
            check("the proposer takes it back", post("/v1/proposals/$unsaidId/withdraw", "{}", ade).bodyAsText().contains("\"state\":\"withdrawn\""))
            val takenBack = get("/v1/proposals/$unsaidId", ade).bodyAsText()
            check("a withdrawn proposal still says where it would have been played",
                takenBack.contains("\"state\":\"withdrawn\"") && takenBack.contains("\"name\":\"The Back Room\""))
            check("and the fixture never moved: the same night, at the same place",
                fixtureCard(homely).let { it.contains("\"scheduledAt\":\"2026-12-03T19:30:00Z\"") && it.contains("\"venue\":\"Grange Social Club\"") })

            val punctuated = post("/v1/fixtures/$homely/proposals", """{"teamId":"$riverside","to":"2026-12-17T19:30:00Z","reason":"the snug is free","venueId":"$awkward"}""", ade)
            val punctuatedId = idOf(punctuated.bodyAsText(), "proposalId")!!
            check("a venue whose name carries a quote and a backslash comes back whole, and the reading still parses",
                punctuated.status.value == 200 && (Json.parseObject(punctuated.bodyAsText())["venue"] as Map<*, *>)["name"] == "The \"Vic\" \\ Snug")
            check("the opponent declines it, saying why", post("/v1/proposals/$punctuatedId/answer", """{"answer":"rejected","note":"the snug will not hold two sides"}""", gil).bodyAsText().contains("\"state\":\"declined\""))
            val notApplied = post("/v1/proposals/$punctuatedId/apply", """{"expectedVersion":1}""", lee)
            check("a declined proposal is not applied, and the refusal says which state it is in",
                notApplied.status.value == 409 && notApplied.bodyAsText().contains("Only an accepted proposal is applied; this one is declined."))
            check("and the fixture keeps the night and the place it already had",
                fixtureCard(homely).let { it.contains("\"scheduledAt\":\"2026-12-03T19:30:00Z\"") && it.contains("\"venue\":\"Grange Social Club\"") })

            // --- a proposal that names no place leaves the fixture's own where it is (PD-128) ------------------------
            val samePlace = post("/v1/fixtures/$kept/proposals", """{"teamId":"$grange","to":"2027-01-21T19:30:00Z"}""", gil)
            val samePlaceId = idOf(samePlace.bodyAsText(), "proposalId")!!
            check("a proposal about the night alone names no place", samePlace.status.value == 200 && samePlace.bodyAsText().contains("\"venue\":null"))
            post("/v1/proposals/$samePlaceId/answer", """{"answer":"accepted"}""", ade)
            check("applied, the fixture moves to the new night and is still at the place it always was",
                post("/v1/proposals/$samePlaceId/apply", """{"expectedVersion":1}""", lee).status.value == 200
                && fixtureCard(kept).let { it.contains("\"scheduledAt\":\"2027-01-21T19:30:00Z\"") && it.contains("\"venue\":\"Grange Social Club\"") })
        }
        println("rearrangement over HTTP: $passed checks passed")
    }
}
