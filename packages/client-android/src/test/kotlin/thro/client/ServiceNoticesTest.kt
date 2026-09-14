package thro.client

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * How the first screen holds the notice (PD-094, PD-097): when it asks, what keeps a notice up, and what takes it down.
 * The iPhone's `ServiceNoticesTests`, one for one.
 */
class ServiceNoticesTest {

    private val web = "https://web.example"
    private var clock = 1_800_000_000_000L

    /** Where "put away" is remembered; SharedPreferences on a phone. */
    class Memory : ThroNoticeMemory {
        var id: String? = null
        override fun putAway(): String? = id
        override fun remember(id: String) {
            this.id = id
        }
    }

    private fun live(id: String): Pair<Int, String> = 200 to """
        {"format": 1, "active": true, "id": "$id", "published": "2026-10-01T09:00:00Z",
         "title": "A notice", "summary": "What happened.", "body": ["More."],
         "under18": {"title": "A notice", "summary": "What happened, shorter.", "body": ["More."]}}
    """

    private fun notices(script: NoticeTest.Script, memory: Memory = Memory()) =
        ThroServiceNotices(web, script, memory) { clock }

    private fun later() {
        clock += ThroServiceNotices.INTERVAL_MILLIS
    }

    @Test
    fun `a live notice shows and stays away once it is put away`() {
        val memory = Memory()
        val first = notices(NoticeTest.Script(live("a")), memory)
        first.refresh()
        assertEquals("a", first.showing?.id)
        first.putAway()
        assertNull(first.showing)
        // The next launch reads the same notice and keeps it put away.
        val next = notices(NoticeTest.Script(live("a")), memory)
        next.refresh()
        assertNotNull(next.current)
        assertNull(next.showing)
    }

    @Test
    fun `an updated notice comes back after the old one was put away`() {
        val held = notices(NoticeTest.Script(live("a"), live("a-updated")))
        held.refresh()
        held.putAway()
        later()
        held.refresh()
        assertEquals("a-updated", held.showing?.id, "an update must not stay hidden behind the notice it replaced")
    }

    @Test
    fun `an inactive file or a taken down one takes the notice down`() {
        for (ending in listOf(200 to """{"format": 1, "active": false}""", 404 to "Not Found")) {
            val held = notices(NoticeTest.Script(live("a"), ending))
            held.refresh()
            later()
            held.refresh()
            assertNull(held.current, "the site answered ${ending.first}")
        }
    }

    @Test
    fun `a notice already read stays up when the site cannot be reached`() {
        val held = notices(NoticeTest.Script(live("a"), 503 to ""))
        held.refresh()
        later()
        held.refresh() // the site is failing
        later()
        held.refresh() // and then there is no network at all
        assertEquals("a", held.showing?.id, "losing signal in a pub is not the notice being withdrawn")
    }

    @Test
    fun `the site is asked at most once a minute`() {
        val script = NoticeTest.Script(live("a"), live("b"))
        val held = notices(script)
        held.refresh()
        clock += ThroServiceNotices.INTERVAL_MILLIS / 2
        held.refresh()
        assertEquals(1, script.seen.size, "a return to the front inside a minute does not ask again")
        clock += ThroServiceNotices.INTERVAL_MILLIS
        held.refresh()
        assertEquals(2, script.seen.size)
        assertEquals("b", held.showing?.id)
    }

    @Test
    fun `a build that names no web site asks nothing`() {
        val script = NoticeTest.Script(live("a"))
        val held = ThroServiceNotices(null, script, Memory()) { clock }
        held.refresh()
        assertTrue(script.seen.isEmpty())
        assertNull(held.showing)
        assertNull(held.page(underEighteen = true))
    }

    @Test
    fun `the page follows the reader`() {
        val held = ThroServiceNotices(web, NoticeTest.Script(), Memory()) { clock }
        assertEquals("https://web.example/notice-under-18.html", held.page(underEighteen = true))
        assertEquals("https://web.example/notice.html", held.page(underEighteen = false))
    }
}
