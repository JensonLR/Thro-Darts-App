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
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import thro.api.http.Authenticator
import thro.api.http.Deps
import thro.api.http.thro
import thro.engine.BustRule
import thro.engine.InRule
import thro.engine.MatchFormat
import thro.engine.OutRule
import thro.engine.Structure
import thro.engine.StructureMode

/**
 * The wire for darts (OD-023), exactly as the iOS client will send it: `RecordDarts` on the command endpoint, a
 * `darts` list on an upload row, and `bustRule` on a match format both ways. What the engine does with darts is
 * DartsTest's; this holds the names on the wire and which mistakes are a 400 and which are the engine's 422.
 */
class DartsHttpTest {

    @Test
    fun `darts on the wire - a command, an upload, and the rule a match is played under`() {
        if (!TestDatabase.configured) {
            println("no database configured (set PGHOST) — darts HTTP tests skipped")
            return
        }
        val c = TestDatabase.migrated()
        var passed = 0
        fun check(name: String, cond: Boolean) {
            assertTrue(cond, "FAILED: $name")
            println("  PASS  $name")
            passed++
        }
        val home = Organisations(c).createPlayer(); val away = Organisations(c).createPlayer()
        val phone = UUID.randomUUID()
        val match = UUID.randomUUID()
        Matches(c).open(match, home, away, MatchFormat(
            startingScore = 40, inRule = InRule.STRAIGHT, outRule = OutRule.DOUBLE,
            legs = Structure(StructureMode.FIRST_TO, 3), throwFirst = Seat.home, bustRule = BustRule.KEEP_SCORED_DARTS,
        ))

        testApplication {
            application { thro(Deps(connect = { TestDatabase.connect() }, authenticator = Authenticator.Dev(), now = { Instant.parse("2026-09-24T18:00:00Z") })) }
            suspend fun post(path: String, body: String, subject: UUID = home): HttpResponse = client.post(path) {
                header(Authenticator.Dev.HEADER, subject.toString())
                header("X-Thro-Device", phone.toString())
                setBody(body)
            }
            suspend fun get(path: String, subject: UUID = home): HttpResponse = client.get(path) { header(Authenticator.Dev.HEADER, subject.toString()) }
            fun visit(seq: Int, rest: String) =
                """{"type":"RecordDarts","commandId":"${UUID.randomUUID()}","matchId":"$match","deviceSeq":$seq,"player":"home","occurredAt":"2026-09-24T19:00:00Z","occurredTz":"Europe/London","clientEffect":"bust","engineVersion":"1.4.0",$rest}"""

            // --- the command endpoint -------------------------------------------------------------------
            val badName = post("/v1/commands", visit(1, """"darts":["T2O"]"""))
            check("a name that is not a dart is a 400 in a sentence", badName.status.value == 400 && badName.bodyAsText().contains("is not the name of a dart"))
            val four = post("/v1/commands", visit(1, """"darts":["1","1","1","1"]"""))
            check("and so is a hand of four", four.status.value == 400 && four.bodyAsText().contains("one to three darts"))
            val both = post("/v1/commands", visit(1, """"darts":["20"],"visitTotal":20"""))
            check("a visit sent as darts does not also carry a total", both.status.value == 400 && both.bodyAsText().contains("visitTotal"))
            val offBoard = post("/v1/commands", visit(1, """"darts":["T25"]"""))
            check("a dart that reads but is not on the board is the engine's refusal, 422",
                offBoard.status.value == 422 && offBoard.bodyAsText() == """{"outcome":"refused","why":"DART_INVALID"}""")
            val kept = post("/v1/commands", visit(1, """"darts":["20","D15"]"""))
            check("RecordDarts is applied, and a keep-rule bust is a bust", kept.status.value == 200 &&
                Json.parseObject(kept.bodyAsText()) == Json.parseObject("""{"outcome":"applied","effect":"bust","reason":"BELOW_ZERO","deviceSeq":1}"""))
            val total = post("/v1/commands", """{"type":"RecordVisit","commandId":"${UUID.randomUUID()}","matchId":"$match","deviceSeq":2,"player":"away","visitTotal":50,"occurredAt":"2026-09-24T19:00:10Z"}""")
            check("a busting total under the keep rule is refused DARTS_REQUIRED", total.status.value == 422 && total.bodyAsText().contains("DARTS_REQUIRED"))

            // --- an upload ----------------------------------------------------------------------------------
            val format = """{"startingScore":40,"inRule":"straight","outRule":"double","legsMode":"first_to","legsTarget":1,"throwFirst":"home","bustRule":"keepScoredDarts"}"""
            val sent = UUID.randomUUID()
            val rows = """[{"deviceSeq":1,"kind":"visit","seat":"home","darts":["20","D15"],"occurredAt":"2026-09-24T19:30:00Z","occurredTz":"Europe/London"},""" +
                """{"deviceSeq":2,"kind":"visit","seat":"away","visitTotal":30,"occurredAt":"2026-09-24T19:30:20Z","occurredTz":"Europe/London"},""" +
                """{"deviceSeq":3,"kind":"visit","seat":"home","visitTotal":20,"darts":["D10"],"occurredAt":"2026-09-24T19:30:40Z","occurredTz":"Europe/London"}]"""
            val up = post("/v1/matches", """{"matchId":"$sent","deviceId":"$phone","seat":"home","format":$format,"rows":$rows}""")
            check("an upload with darts rows and a keep-rule format is stored", up.status.value == 200 && up.bodyAsText().contains("\"visits\":3"))
            val read = get("/v1/matches/$sent")
            check("and the match reads back with its bust rule and the winner the darts made",
                read.status.value == 200 && read.bodyAsText().contains("\"bustRule\":\"keepScoredDarts\"") && read.bodyAsText().contains("\"winner\":\"home\""))
            val badRule = post("/v1/matches", """{"matchId":"${UUID.randomUUID()}","deviceId":"$phone","seat":"home","format":${format.replace("keepScoredDarts", "keepEverything")},"rows":$rows}""")
            check("a bust rule THRØ does not play is a 400", badRule.status.value == 400 && badRule.bodyAsText().contains("bustRule"))
            val badDart = post("/v1/matches", """{"matchId":"${UUID.randomUUID()}","deviceId":"$phone","seat":"home","format":$format,"rows":${rows.replace("\"D10\"", "\"Double ten\"")}}""")
            check("a row whose dart is not a dart is a 400", badDart.status.value == 400 && badDart.bodyAsText().contains("Double ten"))
            val impossible = post("/v1/matches", """{"matchId":"${UUID.randomUUID()}","deviceId":"$phone","seat":"home","format":$format,"rows":[{"deviceSeq":1,"kind":"visit","seat":"home","visitTotal":50,"occurredAt":"2026-09-24T19:30:00Z"}]}""")
            check("a visit the engine refuses is a 422 naming its row", impossible.status.value == 422 && impossible.bodyAsText().contains("row 1"))
            val plain = post("/v1/matches", """{"matchId":"${UUID.randomUUID()}","deviceId":"$phone","seat":"home","format":${format.replace(",\"bustRule\":\"keepScoredDarts\"", "")},"rows":[{"deviceSeq":1,"kind":"visit","seat":"home","visitTotal":50,"occurredAt":"2026-09-24T19:30:00Z"}]}""")
            check("and a format without a bust rule is the standard one, where the same total is a plain bust", plain.status.value == 200)
        }
        println("  $passed darts wire properties held")
        assertEquals(12, passed)
    }
}
