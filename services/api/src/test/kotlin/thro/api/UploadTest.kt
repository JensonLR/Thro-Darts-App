package thro.api

import java.sql.Connection
import java.time.Instant
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertEquals
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
 * Sending a match to THRØ (PD-040): the journal as the phone wrote it, idempotent by construction,
 * an opponent nobody has named, and one player's word until the other confirms it.
 */
class UploadTest {
    private val configured = TestDatabase.configured
    private fun migrated(): Connection = TestDatabase.migrated()

    private val at = Instant.parse("2026-09-11T19:30:00Z")
    private val format = MatchFormat(
        startingScore = 501, inRule = InRule.STRAIGHT, outRule = OutRule.DOUBLE,
        legs = Structure(StructureMode.FIRST_TO, 3), throwFirst = PlayerId("home"),
    )

    private fun player(c: Connection): UUID {
        val id = UUID.randomUUID()
        c.createStatement().use { it.execute("INSERT INTO competition.player (player_id, source) VALUES ('$id', 'self')") }
        return id
    }

    private fun visit(seq: Long, seat: String, total: Int) =
        Uploads.Row(seq, "visit", seat, total, null, at.plusSeconds(seq * 20), "Europe/London")

    private fun retraction(seq: Long, seat: String, strikes: Long) =
        Uploads.Row(seq, "retraction", seat, null, strikes, at.plusSeconds(seq * 20), "Europe/London")

    private fun count(c: Connection, sql: String): Int =
        c.createStatement().use { st -> st.executeQuery(sql).use { rs -> rs.next(); rs.getInt(1) } }

    private fun one(c: Connection, sql: String): String? =
        c.createStatement().use { st -> st.executeQuery(sql).use { rs -> if (rs.next()) rs.getString(1) else null } }

    @Test
    fun `a match arrives as the journal wrote it, retractions and all`() {
        if (!configured) return
        migrated().use { c ->
            val me = player(c); val device = UUID.randomUUID(); val match = UUID.randomUUID()
            // 60, then 100 that the scorer struck, then the 45 that replaced it.
            val rows = listOf(visit(1, "home", 60), visit(2, "away", 45), visit(3, "home", 100),
                              retraction(4, "home", 3), visit(5, "home", 45))
            val out = Uploads(c) { at }.receive(me, device, match, "home", format, rows)
            val stored = out as? Uploads.Result.Stored ?: error("refused: $out")
            assertTrue(stored.opened)
            assertEquals(4, stored.visits); assertEquals(1, stored.retractions); assertEquals(0, stored.alreadyHeld)

            // The struck visit is STILL THERE. That is the whole point: the board showed it, so the
            // record holds it, with the retraction pointing at it.
            assertEquals(4, count(c, "SELECT count(*) FROM evidence.event WHERE match_id = '$match' AND event_type = 'VisitRecorded'"))
            assertEquals(1, count(c, "SELECT count(*) FROM evidence.event WHERE match_id = '$match' AND event_type = 'VisitRetracted'"))
            val struck = one(c, """SELECT e2.device_seq::text FROM evidence.event e
                                     JOIN evidence.event e2 ON e2.event_id = e.corrects_event_id
                                    WHERE e.match_id = '$match' AND e.event_type = 'VisitRetracted'""")
            assertEquals("3", struck, "the retraction names the visit it struck")

            // One player's word until the other confirms (PD-011).
            assertEquals("true", one(c, "SELECT self_reported::text FROM evidence.match WHERE match_id = '$match'"))
        }
    }

    @Test
    fun `the other seat is a competitor THRO holds no name for`() {
        if (!configured) return
        migrated().use { c ->
            val me = player(c); val match = UUID.randomUUID()
            val out = Uploads(c) { at }.receive(me, UUID.randomUUID(), match, "home", format,
                                                listOf(visit(1, "home", 60))) as Uploads.Result.Stored
            assertNotEquals(me, out.opponentId)
            // The competitor row exists and carries nothing about a person — no name column to fill,
            // no account, no claim. Exactly what somebody THRØ has never met should look like.
            assertEquals(1, count(c, "SELECT count(*) FROM competition.player WHERE player_id = '${out.opponentId}'"))
            assertEquals(0, count(c, "SELECT count(*) FROM identity.player_claim WHERE player_id = '${out.opponentId}'"))
            assertEquals("false", one(c, "SELECT identity.player_may_be_disclosed('${out.opponentId}')::text"))
        }
    }

    @Test
    fun `sending the same match twice changes nothing, and a half-sent one finishes`() {
        if (!configured) return
        migrated().use { c ->
            val me = player(c); val device = UUID.randomUUID(); val match = UUID.randomUUID()
            val all = listOf(visit(1, "home", 60), visit(2, "away", 45), visit(3, "home", 100))
            val uploads = Uploads(c) { at }

            // A phone that got half way before the signal went.
            val first = uploads.receive(me, device, match, "home", format, all.take(2)) as Uploads.Result.Stored
            assertEquals(2, first.visits)

            // It sends the lot again. The two it already sent are recognised; the third lands.
            val second = uploads.receive(me, device, match, "home", format, all) as Uploads.Result.Stored
            assertEquals(1, second.visits, "only the missing row was new")
            assertEquals(2, second.alreadyHeld)
            assertTrue(!second.opened, "and the match was not opened a second time")

            // And a third send changes nothing at all.
            val third = uploads.receive(me, device, match, "home", format, all) as Uploads.Result.Stored
            assertEquals(0, third.visits); assertEquals(3, third.alreadyHeld)
            assertEquals(3, count(c, "SELECT count(*) FROM evidence.event WHERE match_id = '$match'"))
            assertEquals(1, count(c, "SELECT count(*) FROM evidence.match WHERE match_id = '$match'"))
        }
    }

    @Test
    fun `a journal that is not a journal is refused, in words`() {
        if (!configured) return
        migrated().use { c ->
            val me = player(c); val uploads = Uploads(c) { at }
            fun send(rows: List<Uploads.Row>, seat: String = "home") =
                uploads.receive(me, UUID.randomUUID(), UUID.randomUUID(), seat, format, rows)
            fun why(rows: List<Uploads.Row>, seat: String = "home") = (send(rows, seat) as Uploads.Result.Refused).why

            assertTrue(why(emptyList()).contains("nothing in it"))
            assertTrue(why(listOf(visit(2, "home", 60), visit(1, "home", 60))).contains("order"))
            assertTrue(why(listOf(visit(1, "home", 60), visit(1, "away", 60))).contains("order"), "two rows cannot hold one place")
            assertTrue(why(listOf(visit(1, "home", 181))).contains("no three darts score 181"))
            // A retraction of something that has not happened yet is a claim about the future.
            assertTrue(why(listOf(visit(1, "home", 60), retraction(2, "home", 9))).contains("before it"))
            assertTrue(why(listOf(visit(1, "home", 60), retraction(2, "home", 3), visit(3, "home", 20))).contains("before it"))
            assertTrue(why(listOf(visit(1, "home", 60)), seat = "Jenson").contains("never a person"))
            assertTrue(why(listOf(Uploads.Row(1, "confession", "home", null, null, at, "Europe/London"))).contains("does not know how to store"))
            assertTrue(why(listOf(Uploads.Row(1, "visit", "home", null, null, at, "Europe/London"))).contains("no total"))
        }
    }

    @Test
    fun `somebody else's match is not yours to add to`() {
        if (!configured) return
        migrated().use { c ->
            val me = player(c); val stranger = player(c); val match = UUID.randomUUID()
            val uploads = Uploads(c) { at }
            uploads.receive(me, UUID.randomUUID(), match, "home", format, listOf(visit(1, "home", 60)))
            // Same match id, a different person claiming the same seat.
            val out = uploads.receive(stranger, UUID.randomUUID(), match, "home", format, listOf(visit(2, "home", 60)))
            assertTrue((out as Uploads.Result.Refused).why.contains("not in that seat"))
            assertEquals(1, count(c, "SELECT count(*) FROM evidence.event WHERE match_id = '$match'"), "and nothing of theirs landed")
        }
    }

    @Test
    fun `nothing lands at all when one row of the journal is impossible`() {
        if (!configured) return
        migrated().use { c ->
            val me = player(c); val match = UUID.randomUUID()
            // The last row strikes a visit that is not in the upload. The first two are fine, and
            // must not be stored: half a match is a record of something that did not happen.
            val out = Uploads(c) { at }.receive(me, UUID.randomUUID(), match, "home", format,
                                                listOf(visit(1, "home", 60), visit(2, "away", 45), retraction(3, "home", 9)))
            assertTrue(out is Uploads.Result.Refused)
            assertEquals(0, count(c, "SELECT count(*) FROM evidence.event WHERE match_id = '$match'"))
            assertNull(one(c, "SELECT match_id::text FROM evidence.match WHERE match_id = '$match'"))
        }
    }
}
