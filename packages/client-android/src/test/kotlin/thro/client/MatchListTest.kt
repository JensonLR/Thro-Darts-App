package thro.client

import java.nio.file.Files
import java.sql.DriverManager
import java.time.Instant
import java.time.ZoneId
import java.util.Locale
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue
import thro.journal.DeviceId
import thro.journal.Ending
import thro.journal.Journal
import thro.journal.Seat

/**
 * The list of matches this phone has kept.
 *
 * Written against a real journal on a real temporary file rather than a fake, for the reason ADR-006
 * gives: the append-only guarantee is a database trigger, and a fake would let this file pass while the
 * app it describes could not write a row.
 */
class MatchListTest {

    private val path = mutableListOf<String>()

    private fun journal(): Journal {
        val file = Files.createTempFile("thro-matches", ".sqlite")
        Files.deleteIfExists(file)
        path += file.toString()
        return Journal.open(file.toString(), DeviceId("00000000-0000-4000-8000-00000000000a"))
    }

    /**
     * Plays home to a win of the whole match, through the app's own path.
     *
     * **Driven by whose throw it is, not by a fixed sequence.** The first version alternated
     * HOME/AWAY/HOME/AWAY and silently stopped finishing after leg one, because the leg starter
     * alternates and `enter` gives the visit to whoever is actually at the oche. A fixture that
     * assumes the order is a fixture that tests a different match from the one being played.
     */
    private fun homeTakesTheMatch(session: ThroSession) {
        var guard = 0
        while (!session.state.isComplete && guard++ < 100) {
            val throwing = session.state.thrower ?: break
            if (throwing != session.state.home) { session.enter(0); continue }
            // 501 − 180 − 180 = 141, which is a legal double-out finish (T20 T19 D12).
            session.enter(if ((session.state.remaining[throwing] ?: 0) == 141) 141 else 180)
        }
    }

    @Test
    fun `a match scored on this phone is on the list, newest first`() {
        journal().use { j ->
            val first = ThroSession.start(j, "Ann", "Bob")
            Thread.sleep(5)
            val second = ThroSession.start(j, "Cal", "Dee")

            val rows = ThroMatchList.rows(j)
            assertEquals(2, rows.size)
            // The one somebody is looking for is the one they just played.
            assertEquals(second.matchId, rows[0].id)
            assertEquals(first.matchId, rows[1].id)
            assertEquals("Cal v Dee", rows[0].title)
        }
    }

    @Test
    fun `a match nobody has thrown in is in progress, at nil-nil`() {
        journal().use { j ->
            ThroSession.start(j, "Ann", "Bob")
            val row = ThroMatchList.rows(j).single()
            assertEquals("In progress", row.status)
            assertEquals("0–0", row.score)
            assertNull(row.wonBy, "nobody has won a match nobody has thrown in")
        }
    }

    @Test
    fun `a finished match says who won, in the name on the row`() {
        journal().use { j ->
            val session = ThroSession.start(j, "Ann", "Bob")
            homeTakesTheMatch(session)   // best of five: three legs takes it
            assertTrue(session.state.isComplete, "the fixture must actually finish the match")

            val row = ThroMatchList.rows(j).single()
            assertEquals("Finished", row.status)
            assertEquals("3–0", row.score)
            assertEquals("Ann", row.wonBy)
        }
    }

    @Test
    fun `an abandoned match is finished and is not a result`() {
        journal().use { j ->
            val session = ThroSession.start(j, "Ann", "Bob")
            session.enter(60)
            j.end(session.matchId, Ending.Abandoned)

            val row = ThroMatchList.rows(j).single()
            // Three states, not two. "In progress" would be wrong because the keypad is shut; "Finished"
            // would imply a result, and PD-016 is explicit that an abandoned match has none.
            assertEquals("No result", row.status)
            assertTrue(row.complete)
            assertNull(row.wonBy, "nobody won an abandoned match, and the row must not imply one did")
        }
    }

    @Test
    fun `retiring is losing, so the row names the other player`() {
        journal().use { j ->
            val session = ThroSession.start(j, "Ann", "Bob")
            session.enter(60)
            j.end(session.matchId, Ending.Retired(by = Seat.HOME))

            val row = ThroMatchList.rows(j).single()
            assertEquals("Retired", row.status)
            // Ann stopped, so Bob won. The wrong way round would print the loser as the winner on a
            // permanent record, which is the worst single thing a list like this can do.
            assertEquals("Bob", row.wonBy)
        }
    }

    @Test
    fun `a match written by a newer version of the app stays on the list and says so`() {
        val j = journal()
        val session = ThroSession.start(j, "Ann", "Bob")
        session.enter(60)
        val id = session.matchId
        j.close()

        // A row this build cannot interpret — the real forward-compatibility case the journal's own
        // `UNKNOWN_ROW_KIND` exists for. Written with plain SQL because there is deliberately no API for
        // it: the journal will not help you write a row it cannot read. INSERT is permitted; the
        // append-only triggers only forbid UPDATE and DELETE.
        DriverManager.getConnection("jdbc:sqlite:${path.last()}").use { c ->
            c.createStatement().use { st ->
                st.executeUpdate(
                    "INSERT INTO journal (match_id, device_id, device_seq, command_id, kind, seat, " +
                        "visit_total, occurred_at) VALUES ('${id.value}', " +
                        "'00000000-0000-4000-8000-00000000000a', 99, 'from-the-future', " +
                        "'handicap_adjustment', 'home', 0, '2027-01-01T00:00:00Z')",
                )
            }
        }

        Journal.open(path.last(), DeviceId("00000000-0000-4000-8000-00000000000a")).use { reopened ->
            val row = ThroMatchList.rows(reopened).single()
            // It happened. Dropping it would be this build deciding that something the player did did not,
            // on the grounds that a later build understood it better.
            assertEquals("Unreadable", row.status)
            assertTrue(row.unreadable!!.contains("UNKNOWN_ROW_KIND"), "it must say why: ${row.unreadable}")
            assertNull(row.score, "a score read off a journal that will not replay has nothing behind it")
        }
    }

    @Test
    fun `a match put away is off the list until it is asked for`() {
        journal().use { j ->
            val session = ThroSession.start(j, "Ann", "Bob")
            j.setArchived(session.matchId, archived = true)

            assertEquals(0, ThroMatchList.rows(j).size)
            assertEquals(1, ThroMatchList.rows(j, archived = true).size)
            assertEquals(1, ThroMatchList.rows(j, archived = null).size, "and null is everything")
        }
    }

    @Test
    fun `the year appears only once it is another year`() {
        val zone = ZoneId.of("Europe/London")
        val uk = Locale.UK
        val now = Instant.parse("2026-09-12T20:00:00Z")
        val thisYear = ThroMatchList.day(Instant.parse("2026-09-03T20:00:00Z"), now, zone, uk)
        val lastYear = ThroMatchList.day(Instant.parse("2025-09-03T20:00:00Z"), now, zone, uk)

        // The property, not the spelling. An earlier version of this test asserted "3 Sep" and failed
        // with "3 Sept", because CLDR changed September's abbreviation in en-GB — which is the platform
        // being right, and not something this app should be holding an opinion about.
        assertTrue(thisYear.startsWith("3 Sep"), "the day and month are there: $thisYear")
        assertFalse("2026" in thisYear, "this year is noise on a list of last month's darts: $thisYear")
        assertEquals("$thisYear 2025", lastYear, "another year is the same line with the year on it")
    }
}
