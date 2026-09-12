package thro.api

import java.sql.Connection
import thro.competition.EventAccess
import java.time.Instant
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** The notice on the pub door: what a stranger may see of what is coming up, and what they may not. */
class EventsTest {
    private val configured = TestDatabase.configured
    private fun migrated(): Connection = TestDatabase.migrated()

    @Test
    fun `only open, unstarted events at public venues are advertised`() {
        if (!configured) return
        migrated().use { c ->
            val org = Organisations(c)
            val comp = Competitions(c)
            val now = Instant.parse("2026-09-10T12:00:00Z")
            val pub = org.createVenue("The Sun Inn", "Stockton-on-Tees")
            val secret = org.createVenue("Back room", "Stockton-on-Tees")
            c.createStatement().use { st ->
                st.execute("UPDATE competition.venue SET latitude = 54.5655947, longitude = -1.3118501, postcode = 'TS18 1SU', row_version = 2 WHERE venue_id = '$pub'")
                st.execute("UPDATE competition.venue SET visibility = 'private', row_version = 2 WHERE venue_id = '$secret'")
            }
            val open = UUID.randomUUID(); val members = UUID.randomUUID(); val past = UUID.randomUUID(); val hidden = UUID.randomUUID()
            comp.openEvent(open, "Sun Inn Open", now.plusSeconds(86_400), now.plusSeconds(90_000), venueId = pub, capacity = 32)
            comp.openEvent(members, "Members' Knockout", now.plusSeconds(86_400), now.plusSeconds(90_000), venueId = pub, access = EventAccess.MEMBER_ONLY)
            comp.openEvent(past, "Last week", now.minusSeconds(86_400), now.minusSeconds(80_000), venueId = pub)
            comp.openEvent(hidden, "Back room singles", now.plusSeconds(172_800), now.plusSeconds(180_000), venueId = secret, venueLabel = "ask at the bar")

            val listed = Events(c).upcoming(now)
            assertEquals(listOf("Sun Inn Open", "Back room singles"), listed.map { it.name }, "open and unstarted only, soonest first")
            val first = listed[0]
            assertEquals("TS18 1SU", first.venue?.postcode); assertEquals(32, first.capacity)
            assertNull(listed[1].venue, "a private venue is not disclosed"); assertEquals("ask at the bar", listed[1].venueLabel)

            val json = Events(c).json(listed)
            assertTrue(json.startsWith("""{"events":[{"eventId":"$open""""))
            assertTrue(json.contains(""""latitude":54.565595"""), "six decimal places, as the column stores them")
            // entrantKind says "player" as a KIND of entrant; no person is on the notice.
            assertTrue(!json.contains("playerId") && !json.contains("displayName") && !json.contains("\"entered\""), "no person on the notice, and not whether you are in")
        }
    }
}
