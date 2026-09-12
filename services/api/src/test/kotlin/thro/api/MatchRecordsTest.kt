package thro.api

import java.sql.Connection
import java.sql.SQLException
import java.time.Duration
import java.time.Instant
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNotEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue
import thro.engine.InRule
import thro.engine.MatchFormat
import thro.engine.OutRule
import thro.engine.PlayerId
import thro.engine.Structure
import thro.engine.StructureMode

/**
 * A sent match, onward (PD-043): the sender's code for the other seat, the other player's claim with
 * it, their answer for the result, and what each of them reads back — derived from the log every time
 * and stored nowhere.
 *
 * Skipped cleanly when no database is configured, rather than passing silently.
 */
class MatchRecordsTest {
    private val configured = TestDatabase.configured
    private val at = Instant.parse("2026-09-11T19:30:00Z")

    /** One leg of 101, straight in, double out: three visits make a match. */
    private val format = MatchFormat(
        startingScore = 101, inRule = InRule.STRAIGHT, outRule = OutRule.DOUBLE,
        legs = Structure(StructureMode.FIRST_TO, 1), throwFirst = PlayerId("home"),
    )

    private fun player(c: Connection): UUID {
        val id = UUID.randomUUID()
        c.createStatement().use { it.execute("INSERT INTO competition.player (player_id, source) VALUES ('$id', 'self')") }
        return id
    }

    private fun visit(seq: Long, seat: String, total: Int) =
        Uploads.Row(seq, "visit", seat, total, null, at.plusSeconds(seq * 20), "Europe/London")

    private fun retraction(seq: Long, strikes: Long) =
        Uploads.Row(seq, "retraction", "home", null, strikes, at.plusSeconds(seq * 20), "Europe/London")

    private fun ending(seq: Long, kind: String, seat: String = "home") =
        Uploads.Row(seq, kind, seat, null, null, at.plusSeconds(seq * 20), "Europe/London")

    /** Home 60, away 45, home 41 on the double: home takes the only leg, and the match. */
    private val won = listOf(visit(1, "home", 60), visit(2, "away", 45), visit(3, "home", 41))

    /** [sender] sends a match from their phone, sitting at home; the away seat is minted. */
    private fun sent(c: Connection, sender: UUID, rows: List<Uploads.Row>, match: UUID = UUID.randomUUID(), device: UUID = UUID.randomUUID()): UUID {
        val out = Uploads(c) { at }.receive(sender, device, match, "home", format, rows)
        check(out is Uploads.Result.Stored) { "the upload was refused: $out" }
        return match
    }

    private fun refusal(block: () -> Unit): MatchRecords.Refused = assertFailsWith<MatchRecords.Refused> { block() }

    private fun count(c: Connection, sql: String): Int =
        c.createStatement().use { st -> st.executeQuery(sql).use { rs -> rs.next(); rs.getInt(1) } }

    private fun answersOn(c: Connection, match: UUID): List<String> =
        c.createStatement().use { st ->
            st.executeQuery("SELECT event_type FROM evidence.event WHERE match_id = '$match' AND event_type LIKE 'Result%' ORDER BY commit_xid, global_seq").use { rs ->
                generateSequence { if (rs.next()) rs.getString(1) else null }.toList()
            }
        }

    @Test
    fun `only the sender makes a code, for the other seat, and asking twice hands back the same one`() {
        if (!configured) return
        TestDatabase.migrated().use { c ->
            val me = player(c); val stranger = player(c)
            val match = sent(c, me, won)
            val records = MatchRecords(c) { at }
            val code = records.codeFor(me, match)
            assertEquals("away", code.seat, "the code is for the seat the sender did not sit in")
            assertTrue(Regex("^[A-HJ-NP-Z2-9]{8}$").matches(code.code), "eight characters, none of them 0, O, 1 or I: ${code.code}")
            assertEquals(at.plus(MatchRecords.CODE_TTL), code.expiresAt)
            assertEquals(code, records.codeFor(me, match), "a live code is handed back, not a second one made")
            assertEquals(1, count(c, "SELECT count(*) FROM competition.match_claim_code WHERE match_id = '$match'"))
            assertEquals(404, refusal { records.codeFor(stranger, match) }.status, "a stranger is told it is not their match")
            assertEquals(404, refusal { records.codeFor(me, UUID.randomUUID()) }.status)
            val later = MatchRecords(c) { at.plus(Duration.ofDays(8)) }.codeFor(me, match)
            assertNotEquals(code.code, later.code, "an expired code is not handed back; a new one is made")

            // A match scored on THRØ as it was played already knows who played it.
            val live = UUID.randomUUID()
            Matches(c).open(live, me, player(c), playtestFormat())
            val scored = CommandHandler(c).handle(VisitCommand(
                commandId = UUID.randomUUID(), matchId = live, deviceId = UUID.randomUUID(), deviceSeq = 1, actorId = me,
                actorRole = "participant", correlationId = UUID.randomUUID(), player = "home", visitTotal = 60, dartsUsed = 3,
                occurredAt = "2026-09-11T19:00:00Z", occurredTz = "Europe/London",
            ))
            assertTrue(scored is CommandResult.Applied, "the live visit is recorded: $scored")
            assertTrue(refusal { records.codeFor(me, live) }.why.contains("sent from a phone"))
        }
    }

    @Test
    fun `the player they played takes the seat with the code, once, and nothing under the match is rewritten`() {
        if (!configured) return
        TestDatabase.migrated().use { c ->
            val me = player(c); val them = player(c); val third = player(c)
            val match = sent(c, me, won)
            val records = MatchRecords(c) { at }
            val code = records.codeFor(me, match).code
            fun seats(): String = c.createStatement().use { st ->
                st.executeQuery("SELECT home_id::text || ' ' || away_id::text FROM evidence.match WHERE match_id = '$match'").use { it.next(); it.getString(1) }
            }
            val sentAs = seats()
            val evidence = count(c, "SELECT count(*) FROM evidence.event WHERE match_id = '$match'")

            assertTrue(refusal { records.claim(them, "NOPE") }.why.contains("not a THRØ match code"))
            assertTrue(refusal { records.claim(them, "ABCDEFGH") }.why.contains("No match code like that"))
            assertTrue(refusal { records.claim(me, code) }.why.contains("the code you made"))
            assertTrue(refusal { MatchRecords(c) { at.plus(Duration.ofDays(8)) }.claim(them, code) }.why.contains("expired"))

            // Case, spaces and dashes are how a code is said across a table, not part of it.
            assertEquals(match, records.claim(them, code.lowercase().chunked(4).joinToString(" - ")))
            assertEquals("away", records.seatOf(match, them))
            assertEquals("home", records.seatOf(match, me))
            assertNull(records.seatOf(match, third))
            assertTrue(refusal { records.claim(third, code) }.why.contains("used already"))
            assertTrue(refusal { records.codeFor(me, match) }.why.contains("already somebody's"), "the seat is taken, so there is no code to give")

            assertEquals(sentAs, seats(), "the match still names the competitor it was sent with")
            assertEquals(evidence, count(c, "SELECT count(*) FROM evidence.event WHERE match_id = '$match'"), "and no evidence was written or rewritten")
        }
    }

    @Test
    fun `the other player answers for the result, the latest answer stands, and the sender cannot answer for themselves`() {
        if (!configured) return
        TestDatabase.migrated().use { c ->
            val me = player(c); val them = player(c); val stranger = player(c)
            val phone = UUID.randomUUID()
            val match = sent(c, me, won)
            val records = MatchRecords(c) { at }
            assertEquals(404, refusal { records.answer(them, match, phone, true) }.status, "nobody answers for a seat they have not taken")
            records.claim(them, records.codeFor(me, match).code)

            val first = records.summary(match, me)!!
            assertEquals("self-reported", first.standing, "one player's word until the other answers (PD-011)")
            assertEquals(mapOf("home" to 1, "away" to 0), first.legs)
            assertEquals("home", first.winner)
            assertEquals(3, first.visits)
            assertEquals("home", first.sentBy, "the sender's seat is named, so the other phone knows the answer is its to give")

            assertTrue(refusal { records.answer(me, match, phone, true) }.why.contains("your word already"))
            assertEquals(404, refusal { records.answer(stranger, match, phone, true) }.status)

            records.answer(them, match, phone, false)
            assertEquals("disputed", records.summary(match, me)!!.standing)
            assertEquals("contested", records.summary(match, them)!!.answers["away"])
            records.answer(them, match, phone, true)
            val settled = records.summary(match, them)!!
            assertEquals("confirmed", settled.standing, "the latest answer stands")
            assertEquals(mapOf("home" to null, "away" to "confirmed"), settled.answers)
            assertEquals(listOf("ResultContested", "ResultConfirmed"), answersOn(c, match), "every answer is kept, in order")
            assertEquals(0, count(c, "SELECT count(*) FROM evidence.event WHERE match_id = '$match' AND event_type LIKE 'Result%' AND device_id = '$phone'"),
                "an answer never takes a place in the phone's own journal sequence")
        }
    }

    @Test
    fun `an answer stands for the record it answered, and a match sent on afterwards is answered again`() {
        if (!configured) return
        TestDatabase.migrated().use { c ->
            val me = player(c); val them = player(c)
            val phone = UUID.randomUUID(); val device = UUID.randomUUID()
            val match = sent(c, me, won.take(2), device = device)
            val records = MatchRecords(c) { at }
            records.claim(them, records.codeFor(me, match).code)
            records.answer(them, match, phone, true)
            assertEquals("confirmed", records.summary(match, me)!!.standing)
            assertNull(records.summary(match, me)!!.winner, "two visits in, nobody has won")

            // The sender's phone sends the rest of the night: the whole journal again, one row longer.
            sent(c, me, won, match = match, device = device)
            val after = records.summary(match, me)!!
            assertEquals("self-reported", after.standing, "agreeing to two visits is not agreeing to three")
            assertNull(after.answers["away"])
            assertEquals("home", after.winner)
            records.answer(them, match, phone, true)
            assertEquals("confirmed", records.summary(match, me)!!.standing)
        }
    }

    @Test
    fun `a retirement is won by the seat that stayed and can be confirmed, and an abandonment has no result to confirm`() {
        if (!configured) return
        TestDatabase.migrated().use { c ->
            val me = player(c); val them = player(c); val phone = UUID.randomUUID()
            val records = MatchRecords(c) { at }

            val retired = sent(c, me, listOf(visit(1, "home", 60), visit(2, "away", 45), ending(3, "retirement", "away")))
            records.claim(them, records.codeFor(me, retired).code)
            val r = records.summary(retired, them)!!
            assertEquals("retired", r.ending); assertEquals("away", r.retired); assertEquals("home", r.winner)
            records.answer(them, retired, phone, true)
            assertEquals("confirmed", records.summary(retired, me)!!.standing, "an answer after the end is still an answer")

            val abandoned = sent(c, me, listOf(visit(1, "home", 60), ending(2, "abandonment")))
            records.claim(them, records.codeFor(me, abandoned).code)
            val a = records.summary(abandoned, them)!!
            assertEquals("abandoned", a.ending); assertNull(a.winner); assertNull(a.retired)
            assertTrue(refusal { records.answer(them, abandoned, phone, true) }.why.contains("no result to confirm"))
        }
    }

    @Test
    fun `a match is read by the people in it and nobody else, and a struck visit counts for nothing`() {
        if (!configured) return
        TestDatabase.migrated().use { c ->
            val me = player(c); val them = player(c); val stranger = player(c)
            // Home's 100 from 41 was a bust the scorer struck anyway; the 41 thrown instead takes the leg.
            val match = sent(c, me, listOf(visit(1, "home", 60), visit(2, "away", 45), visit(3, "home", 100), retraction(4, 3), visit(5, "home", 41)))
            val records = MatchRecords(c) { at }
            val mine = records.summary(match, me)!!
            assertEquals(3, mine.visits, "the struck visit is evidence, and counts for nothing")
            assertEquals("home", mine.winner)
            assertEquals(listOf(true, false), mine.seats.map { it.you })
            assertEquals(listOf(false, true), mine.seats.map { it.claimable }, "the minted seat is nobody's yet")
            assertNull(records.summary(match, stranger))
            assertEquals(listOf(match), records.mine(me).map { it.matchId })
            assertTrue(records.mine(them).isEmpty())

            records.claim(them, records.codeFor(me, match).code)
            assertEquals(listOf(match), records.mine(them).map { it.matchId }, "a match taken with a code is among the taker's own")
            assertEquals(listOf(false, true), records.summary(match, them)!!.seats.map { it.you })
            assertEquals(listOf(false, false), records.summary(match, me)!!.seats.map { it.claimable })
            assertTrue(records.mine(stranger).isEmpty())
            assertTrue(records.json(mine).contains(""""standing":"self-reported""""))
            assertTrue(records.json(mine).contains(""""throwFirst":"home""""), "a phone replaying the match needs to know who threw first")
        }
    }

    @Test
    fun `a seat shows a name only where THRO may show it, and never for an age it does not know`() {
        if (!configured) return
        TestDatabase.migrated().use { c ->
            // Parenthesised: a trailing lambda would bind to Accounts' last parameter, its SecureRandom.
            val accounts = Accounts(c, { at })
            fun signedIn(name: String, adult: Boolean): UUID {
                val session = accounts.signIn("apple", "apple-subject-seat-${UUID.randomUUID()}", UUID.randomUUID())
                accounts.setDisplayName(session.accountId, name)
                if (adult) Friends(c, { at }).declareAge(session.accountId, "adult")
                return session.playerId ?: error("signing in made no competitor")
            }
            val sam = signedIn("Sam Cross", adult = true)
            val unknown = signedIn("Never Shown", adult = false)
            val records = MatchRecords(c) { at }

            val match = sent(c, unknown, won)
            records.claim(sam, records.codeFor(unknown, match).code)
            val read = records.summary(match, sam)!!
            assertEquals(listOf(null, "Sam Cross"), read.seats.map { it.name }, "an adult who has said so is named; an age THRØ does not know is not")
            assertTrue("Never Shown" !in records.json(read))
        }
    }

    @Test
    fun `each step runs under the role its route uses, and the match role cannot answer`() {
        if (!configured) return
        TestDatabase.migrated().use { c ->
            val me = player(c); val them = player(c); val phone = UUID.randomUUID()
            val match = sent(c, me, won)
            val records = MatchRecords(c) { at }
            fun <T> asRole(role: String, block: () -> T): T {
                c.createStatement().use { it.execute("SET ROLE $role") }
                try { return block() } finally { c.createStatement().use { it.execute("RESET ROLE") } }
            }
            val code = asRole("app_competition") { records.codeFor(me, match) }
            asRole("app_competition") { records.claim(them, code.code) }
            asRole("app_trust") { records.answer(them, match, phone, true) }
            assertEquals("confirmed", asRole("app_read") { records.summary(match, me)?.standing })
            assertEquals(listOf(match), asRole("app_read") { records.mine(them).map { it.matchId } })
            val refused = assertFailsWith<SQLException> { asRole("app_match") { records.answer(them, match, phone, false) } }
            assertTrue(refused.message.orEmpty().contains("belongs to app_trust"), "the match role writes visits, not opinions: ${refused.message}")
        }
    }
}
