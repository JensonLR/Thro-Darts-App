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
import thro.engine.InRule
import thro.engine.MatchFormat
import thro.engine.OutRule
import thro.engine.Structure
import thro.engine.StructureMode

/**
 * The provisional rating over the wire (PD-105): computed from matches scored on THRØ and nothing else, shown as a
 * range until it has earned a number, explained line by line from facts frozen at rating time, and shown of another
 * player only where THRØ may name them.
 */
class RatingHttpTest {

    @Test
    fun `a rating is replayed from recorded matches, shown as a range, explained, and shown of others only where allowed`() {
        if (!TestDatabase.configured) {
            println("no database configured (set PGHOST) — rating HTTP tests skipped")
            return
        }
        val c = TestDatabase.migrated()
        val orgs = Organisations(c)
        var passed = 0
        fun check(name: String, cond: Boolean) {
            assertTrue(cond, "FAILED: $name")
            println("  PASS  $name")
            passed++
        }
        val home = orgs.createPlayer(); val away = orgs.createPlayer(); val third = orgs.createPlayer()
        val phone = UUID.randomUUID()
        // One leg decides a match here, so a match is five visits: 180, 60, 180, 60 and a 141 finish.
        val oneLeg = MatchFormat(startingScore = 501, inRule = InRule.STRAIGHT, outRule = OutRule.DOUBLE,
                                 legs = Structure(StructureMode.FIRST_TO, 1), throwFirst = Seat.home)

        testApplication {
            application { thro(Deps(connect = { TestDatabase.connect() }, authenticator = Authenticator.Dev(), now = { Instant.parse("2026-09-16T19:00:00Z") })) }
            suspend fun post(path: String, body: String, subject: UUID): HttpResponse = client.post(path) {
                header(Authenticator.Dev.HEADER, subject.toString()); header("X-Thro-Device", phone.toString()); setBody(body)
            }
            suspend fun get(path: String, subject: UUID?): HttpResponse = client.get(path) { subject?.let { header(Authenticator.Dev.HEADER, it.toString()) } }
            // A device's sequence is per match, and a gap is a 409 — so each match counts from one.
            val seqs = HashMap<UUID, Long>()
            suspend fun visit(match: UUID, seat: String, total: Int, by: UUID) {
                val seq = (seqs[match] ?: 0L) + 1; seqs[match] = seq
                val r = post("/v1/commands", """{"type":"RecordVisit","commandId":"${UUID.randomUUID()}","matchId":"$match","deviceSeq":$seq,"player":"$seat","visitTotal":$total,"occurredAt":"2026-09-16T19:00:${"%02d".format(seq % 60)}Z"}""", by)
                check("visit $seq of ${match.toString().take(8)} is applied", r.status.value == 200 && r.bodyAsText().contains("\"outcome\":\"applied\""))
            }
            /** A whole match on THRØ, scored live from the home player's phone: [winner] takes the one leg. */
            suspend fun play(h: UUID, a: UUID, winner: String): UUID {
                val match = UUID.randomUUID()
                Matches(c).open(match, h, a, oneLeg)
                val loser = if (winner == "home") "away" else "home"
                // Home throws first in the leg; the winner's three visits are 180, 180, 141 and the loser scores 60 between.
                val order = if (winner == "home") listOf("home" to 180, "away" to 60, "home" to 180, "away" to 60, "home" to 141)
                            else listOf("home" to 60, "away" to 180, "home" to 60, "away" to 180, "home" to 60, "away" to 141)
                for ((seat, total) in order) visit(match, seat, total, h)
                check("the match ended with a winner", MatchRecords(c).summary(match, h)?.winner == winner && loser != winner)
                return match
            }

            // --- nothing until something is played --------------------------------------------------------------
            check("a rating needs a principal", get("/v1/me/rating", null).status.value == 401)
            val nothing = get("/v1/me/rating", home)
            check("a player who has played nothing on THRØ is unrated, and told so rather than guessed",
                nothing.status.value == 200 && nothing.bodyAsText().contains("\"kind\":\"unrated\"") && nothing.bodyAsText().contains("\"matches\":0"))

            // --- one match: a range, marked provisional, explained ---------------------------------------------------
            val m1 = play(home, away, "home")
            val one = get("/v1/me/rating", home).bodyAsText()
            check("after one match the winner has a provisional range, never a number",
                one.contains("\"kind\":\"provisional\"") && one.contains("\"low\":") && !one.contains("\"value\":") && one.contains("\"matches\":1"))
            check("and says how many players it is compared across", one.contains("\"comparedAcross\":2"))
            check("and names the model and its stage plainly", one.contains("\"model\":\"glicko2\"") && one.contains("\"stage\":\"provisional\""))
            check("the change is explained from facts frozen at the time: the match, the outcome, what was expected",
                one.contains("\"matchId\":\"$m1\"") && one.contains("\"outcome\":\"won\"") && one.contains("\"expected\":") && one.contains("\"delta\":"))
            check("an opponent THRØ may not name is not named", one.contains("\"opponent\":null"))
            val lost = get("/v1/me/rating", away).bodyAsText()
            check("the loser's range sits below the winner's", low(lost) < low(one) && lost.contains("\"outcome\":\"lost\""))

            // --- what does not count ----------------------------------------------------------------------------------
            val unfinished = UUID.randomUUID()
            Matches(c).open(unfinished, home, third, oneLeg)
            visit(unfinished, "home", 180, home)
            check("a match still being played counts for nobody", get("/v1/me/rating", third).bodyAsText().contains("\"kind\":\"unrated\"")
                && get("/v1/me/rating", home).bodyAsText().contains("\"matches\":1"))

            // --- the same evidence, the same answer -------------------------------------------------------------------
            check("reading twice is the same answer to the byte", get("/v1/me/rating", home).bodyAsText() == get("/v1/me/rating", home).bodyAsText())

            // --- somebody else's ------------------------------------------------------------------------------------
            check("another player's rating needs a principal", get("/v1/players/$home/rating", null).status.value == 401)
            val hidden = get("/v1/players/$home/rating", away)
            check("and is shown only of a player THRØ may name — an unclaimed one is not", hidden.status.value == 404)
            check("a player nobody has is a 404 too", get("/v1/players/${UUID.randomUUID()}/rating", away).status.value == 404)
            check("a malformed id is a 400", get("/v1/players/not-a-uuid/rating", away).status.value == 400)

            // --- more matches narrow the range ---------------------------------------------------------------------------
            repeat(3) { play(home, away, "home") }
            val four = get("/v1/me/rating", home).bodyAsText()
            check("four matches narrow the range and it is still provisional", four.contains("\"matches\":4") && width(four) < width(one) && four.contains("\"kind\":\"provisional\""))
            check("the ledger has one line per match, newest first", Regex("\"matchId\"").findAll(four).count() == 4)
        }
        println("rating over HTTP: $passed checks passed")
    }

    private fun low(json: String) = Regex("\"low\":(-?\\d+)").find(json)!!.groupValues[1].toInt()
    private fun width(json: String) = Regex("\"high\":(-?\\d+)").find(json)!!.groupValues[1].toInt() - low(json)
}
