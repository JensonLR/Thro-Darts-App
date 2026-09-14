package thro.client

import com.sun.net.httpserver.HttpServer
import java.io.File
import java.io.IOException
import java.net.InetSocketAddress
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * The notice about people's information, on Android (PD-094, PD-097): what counts as one, who it speaks to, and that
 * asking for it says nothing about the person asking. The cases are the iPhone's `NoticeTests`, one for one, so the two
 * readers of one file cannot quietly disagree — and one more, which the iPhone cannot run: the request as it actually
 * reaches a server.
 */
class NoticeTest {

    /** Answers in order and records what it was asked; with nothing left to say it behaves like no network. */
    class Script(vararg answers: Pair<Int, String>) : ThroNoticeTransport {
        private val left = answers.toMutableList()
        val seen = mutableListOf<ThroNoticeRequest>()
        override fun send(request: ThroNoticeRequest): Pair<Int, String> {
            seen += request
            if (left.isEmpty()) throw IOException("no network")
            return left.removeAt(0)
        }
    }

    private val web = "https://web.example"

    private fun file(fields: String) = "{$fields}"

    private val live = """
        "format": 1, "active": true, "id": "2026-10-01", "published": "2026-10-01T09:00:00Z",
        "title": "Somebody read THRØ's records", "summary": "What happened, in a sentence.", "body": ["More."],
        "under18": {"title": "Somebody saw some information", "summary": "What happened, shorter.", "body": ["More."]}
    """

    @Test
    fun `a live notice is read with words for both readers`() {
        val answer = ThroNotice.answer(file(live))
        assertIs<ThroNoticeAnswer.Live>(answer)
        assertEquals("2026-10-01", answer.notice.id)
        assertEquals("Somebody read THRØ's records", answer.notice.adult.title)
        assertEquals("What happened, shorter.", answer.notice.under18.summary)
    }

    @Test
    fun `an inactive file says there is nothing live`() {
        assertEquals(ThroNoticeAnswer.NothingLive, ThroNotice.answer(file("\"format\": 1, \"active\": false")))
    }

    @Test
    fun `the committed file reads as nothing live`() {
        // The iPhone, thro.js, check_notice.py and this read one file. This holds Android to the file actually published,
        // so a change to its shape cannot pass the web's checks and leave every Android phone reading it as unknown.
        var dir: File? = File(System.getProperty("user.dir") ?: ".").absoluteFile
        while (dir != null && !File(dir, "apps/web/notice.json").exists()) dir = dir.parentFile
        val committed = File(checkNotNull(dir) { "no apps/web/notice.json above ${System.getProperty("user.dir")}" },
                             "apps/web/notice.json")
        assertEquals(ThroNoticeAnswer.NothingLive, ThroNotice.answer(committed.readText()))
    }

    @Test
    fun `anything short of a readable live notice is not a notice`() {
        val published = "\"published\": \"2026-10-01T09:00:00Z\""
        val adult = "\"title\": \"t\", \"summary\": \"s\", \"body\": [\"b\"]"
        val young = "\"under18\": {\"title\": \"t\", \"summary\": \"s\", \"body\": [\"b\"]}"
        val broken = listOf(
            "no words for under-18s" to "\"format\": 1, \"active\": true, \"id\": \"a\", $published, $adult",
            "an empty paragraph" to "\"format\": 1, \"active\": true, \"id\": \"a\", $published, \"title\": \"t\", \"summary\": \"s\", \"body\": [\"  \"], $young",
            "no body at all" to "\"format\": 1, \"active\": true, \"id\": \"a\", $published, \"title\": \"t\", \"summary\": \"s\", \"body\": [], $young",
            "an empty title" to "\"format\": 1, \"active\": true, \"id\": \"a\", $published, \"title\": \"\", \"summary\": \"s\", \"body\": [\"b\"], $young",
            "no id" to "\"format\": 1, \"active\": true, $published, $adult, $young",
            "a date with no time" to "\"format\": 1, \"active\": true, \"id\": \"a\", \"published\": \"2026-10-01\", $adult, $young",
            "a date nobody can read" to "\"format\": 1, \"active\": true, \"id\": \"a\", \"published\": \"yesterday\", $adult, $young",
            "a format this build does not know" to "\"format\": 2, \"active\": true",
            "active written as a number" to "\"format\": 1, \"active\": 1",
            "no format" to "\"active\": true",
        )
        for ((why, fields) in broken) {
            assertEquals(ThroNoticeAnswer.Unknown, ThroNotice.answer(file(fields)), why)
        }
        assertEquals(ThroNoticeAnswer.Unknown, ThroNotice.answer("<html>not the file</html>"),
                     "a site that answers every path with a page must not be read as a notice")
    }

    @Test
    fun `an adult reads the full notice and everybody else the under-18 one`() {
        val notice = assertIs<ThroNoticeAnswer.Live>(ThroNotice.answer(file(live))).notice
        assertEquals(notice.adult, notice.forReader("adult").words)
        assertFalse(notice.forReader("adult").underEighteen)
        assertTrue(notice.forReader("minor").underEighteen)
        assertTrue(notice.forReader("unknown").underEighteen, "an age nobody has said is not adult")
        assertTrue(notice.forReader(null).underEighteen, "nobody signed in is an age nobody has said")
        assertEquals("https://web.example/notice-under-18.html", ThroNotice.page(web, underEighteen = true))
        assertEquals("https://web.example/notice.html", ThroNotice.page(web, underEighteen = false))
    }

    @Test
    fun `asking says nothing about who is asking`() {
        val script = Script(200 to file(live))
        assertIs<ThroNoticeAnswer.Live>(ThroNotice.ask(web, script))
        val request = script.seen.single()
        assertEquals("https://web.example/notice.json", request.url)
        assertEquals("GET", request.method)
        assertNull(request.headers["X-Thro-Device"], "no device id")
        assertNull(request.headers["Authorization"], "no account")
        assertNull(request.headers["Cookie"], "no cookie")
        assertFalse(request.sendsCookies)
        assertFalse(request.useCaches)
    }

    @Test
    fun `the request that reaches the site carries the question and nothing else`() {
        // What the phone actually sends, to a real server: no cookie, no account, no identifier in the address, and a
        // user agent that does not name the phone's model and build the way Android's default one does.
        val server = HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0)
        val heard = mutableMapOf<String, String?>()
        server.createContext("/notice.json") { exchange ->
            heard["method"] = exchange.requestMethod
            heard["query"] = exchange.requestURI.rawQuery
            for (name in listOf("Cookie", "Authorization", "User-Agent", "Accept")) {
                heard[name] = exchange.requestHeaders.getFirst(name)
            }
            val body = file(live).toByteArray()
            exchange.sendResponseHeaders(200, body.size.toLong())
            exchange.responseBody.use { it.write(body) }
        }
        server.start()
        try {
            val answer = ThroNotice.ask("http://127.0.0.1:${server.address.port}", ThroNoticeTransport.Anonymous)
            assertIs<ThroNoticeAnswer.Live>(answer)
        } finally {
            server.stop(0)
        }
        assertEquals("GET", heard["method"])
        assertNull(heard["query"], "nothing about the phone in the address")
        assertNull(heard["Cookie"], "no cookie")
        assertNull(heard["Authorization"], "no account")
        assertEquals("THRO", heard["User-Agent"], "not the phone's model and build")
        assertEquals("application/json", heard["Accept"])
    }

    @Test
    fun `a taken down file is nothing live and an unreachable site is unknown`() {
        assertEquals(ThroNoticeAnswer.NothingLive, ThroNotice.ask(web, Script(404 to "Not Found")))
        assertEquals(ThroNoticeAnswer.Unknown, ThroNotice.ask(web, Script(503 to "")))
        assertEquals(ThroNoticeAnswer.Unknown, ThroNotice.ask(web, Script()))
    }
}
