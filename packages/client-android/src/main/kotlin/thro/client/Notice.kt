package thro.client

import android.content.Context
import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URI
import java.time.Instant
import java.time.OffsetDateTime
import java.time.format.DateTimeParseException

// A notice about people's information, read from THRØ's public web site (PD-094), on Android (PD-097).
//
// **Why the web site and not the API.** UK GDPR Art 34 asks THRØ to tell people without undue delay when a breach is
// likely to put them at high risk, and THRØ holds no email address, no phone number and no push token — so the app is
// the only way to reach anybody. The day that is needed may be the day the API is switched off to contain the breach,
// so the notice lives on the static site as one file, `notice.json`, and publishing it is an edit and a push.
//
// **The rules are the iPhone's** (`packages/client-ios/Sources/ThroNet/Notice.swift`), which are the ones
// `apps/web/thro.js` and `tools/check_notice.py` apply to the same file. `NoticeTest` holds this reader to the iPhone's
// cases, one for one, and to the file actually committed.
//
// **This is the only network code in the Android client.** Scoring still needs no network and no account (PD-012), and
// `tools/check_android_network.py` fails the build if anything else here starts speaking to one.

/** A readable, active notice: who wrote it when, and the words for each reader. */
public data class ThroNotice(
    val id: String,
    val published: Instant,
    val adult: Words,
    val under18: Words,
) {
    /** What one reader is shown: a title and a summary. The full account is on the web page. */
    public data class Words(val title: String, val summary: String)

    /** The words for one reader, and whether they belong on the under-18 page. */
    public data class Reading(val words: Words, val underEighteen: Boolean)

    /**
     * The words for somebody of this age band. Under 18, an age nobody has said and nobody signed in all get the under-18
     * words, because unknown is not adult. Android has no accounts yet, so today everybody on it reads those.
     */
    public fun forReader(ageBand: String?): Reading =
        if (ageBand == "adult") Reading(adult, underEighteen = false) else Reading(under18, underEighteen = true)

    public companion object {
        private val FILE_TEXT = listOf("id", "published", "title", "summary")
        private val PART_TEXT = listOf("title", "summary")

        /** A date and a time with its zone, as `check_notice.py` insists and the iPhone reads: seconds, and a zone. */
        private val MOMENT = Regex("""\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})""")

        /** Reads `notice.json`. Anything short of a readable, active notice is not a notice: half a breach notice is worse
         *  than none. */
        public fun answer(json: String): ThroNoticeAnswer {
            val file = try {
                JSONObject(json)
            } catch (_: JSONException) {
                return ThroNoticeAnswer.Unknown
            }
            // Typed, as the iPhone's decoder is: a field that is there must be the right kind, live or not, and one that
            // is not makes the whole file unreadable. So `"active": 1` is not true and `"format": true` is not 1.
            val young = present(file, "under18")
            val shapeHolds = textsHold(file, FILE_TEXT) && bodyHolds(file) &&
                (young == null || (young is JSONObject && textsHold(young, PART_TEXT) && bodyHolds(young)))
            val format = present(file, "format")
            val active = present(file, "active")
            if (!shapeHolds || format !is Number || format.toDouble() != 1.0 || active !is Boolean) {
                return ThroNoticeAnswer.Unknown
            }
            if (!active) return ThroNoticeAnswer.NothingLive
            val id = filled(present(file, "id"))
            val published = moment(present(file, "published"))
            val adult = words(file)
            val under18 = (young as? JSONObject)?.let(::words)
            if (id == null || published == null || adult == null || under18 == null) return ThroNoticeAnswer.Unknown
            return ThroNoticeAnswer.Live(ThroNotice(id, published, adult, under18))
        }

        /** The full notice on the web site. */
        public fun page(web: String, underEighteen: Boolean): String =
            web.trimEnd('/') + "/" + (if (underEighteen) "notice-under-18.html" else "notice.html")

        /**
         * The request for `notice.json`. **It says nothing about who is asking**: no device id, no account, no token, no
         * cookie, no copy kept from an earlier answer — and a user agent of its own, because Android's default one names
         * the phone's model and build.
         */
        public fun request(web: String): ThroNoticeRequest = ThroNoticeRequest(
            url = web.trimEnd('/') + "/notice.json",
            method = "GET",
            headers = mapOf("Accept" to "application/json", "User-Agent" to "THRO"),
            useCaches = false,
            sendsCookies = false,
            timeoutMillis = 15_000,
        )

        /** Asks the web site. A file that has been taken down is nothing live; every other failure is unknown. */
        public fun ask(web: String, transport: ThroNoticeTransport): ThroNoticeAnswer = try {
            val (status, body) = transport.send(request(web))
            when (status) {
                200 -> answer(body)
                404, 410 -> ThroNoticeAnswer.NothingLive
                else -> ThroNoticeAnswer.Unknown
            }
        } catch (_: Exception) {
            ThroNoticeAnswer.Unknown
        }

        private fun present(o: JSONObject, key: String): Any? = o.opt(key)?.takeUnless { it == JSONObject.NULL }

        private fun textsHold(o: JSONObject, keys: List<String>): Boolean =
            keys.all { key -> present(o, key).let { it == null || it is String } }

        private fun bodyHolds(o: JSONObject): Boolean = present(o, "body").let { body ->
            body == null || (body is JSONArray && (0 until body.length()).all { body.opt(it) is String })
        }

        private fun filled(text: Any?): String? = (text as? String)?.trim()?.takeIf { it.isNotEmpty() }

        /** One reader's words, when all of them are there — the body too, though the card does not show it, because a
         *  card that sends somebody to an empty page has told them less than nothing. */
        private fun words(o: JSONObject): Words? {
            val title = filled(present(o, "title")) ?: return null
            val summary = filled(present(o, "summary")) ?: return null
            val body = present(o, "body") as? JSONArray ?: return null
            if (body.length() == 0 || (0 until body.length()).any { filled(body.opt(it)) == null }) return null
            return Words(title, summary)
        }

        private fun moment(text: Any?): Instant? {
            val raw = filled(text)?.takeIf { MOMENT.matches(it) } ?: return null
            return try {
                OffsetDateTime.parse(raw).toInstant()
            } catch (_: DateTimeParseException) {
                null
            }
        }
    }
}

/** What asking the web site found. */
public sealed interface ThroNoticeAnswer {
    /** A readable, active notice. */
    public data class Live(val notice: ThroNotice) : ThroNoticeAnswer

    /** The site says there is nothing: the file is inactive, or it has been taken down. */
    public data object NothingLive : ThroNoticeAnswer

    /** The site could not be asked, or answered with something this build cannot read. That says nothing either way, so
     *  a notice already on screen stays on it. */
    public data object Unknown : ThroNoticeAnswer
}

/** One request, as data, so a test can read exactly what would be sent. */
public data class ThroNoticeRequest(
    val url: String,
    val method: String,
    val headers: Map<String, String>,
    val useCaches: Boolean,
    val sendsCookies: Boolean,
    val timeoutMillis: Int,
)

/** Sends a request and returns its status and body; throws when the site cannot be reached at all. */
public fun interface ThroNoticeTransport {
    public fun send(request: ThroNoticeRequest): Pair<Int, String>

    public companion object {
        /**
         * Keeps nothing between requests. No cache; and no cookies, because an `HttpURLConnection` sends one only through
         * a cookie handler, which nothing in this app installs (`tools/check_android_network.py` holds that too).
         */
        public val Anonymous: ThroNoticeTransport = ThroNoticeTransport { request ->
            val connection = URI(request.url).toURL().openConnection() as HttpURLConnection
            try {
                connection.requestMethod = request.method
                connection.useCaches = request.useCaches
                connection.connectTimeout = request.timeoutMillis
                connection.readTimeout = request.timeoutMillis
                request.headers.forEach { (name, value) -> connection.setRequestProperty(name, value) }
                val status = connection.responseCode
                val stream = if (status in 200..299) connection.inputStream else connection.errorStream
                status to (stream?.bufferedReader(Charsets.UTF_8)?.use { it.readText() } ?: "")
            } finally {
                connection.disconnect()
            }
        }
    }
}

/** Where "put away" is remembered. One id rather than a list: only the current notice can be on screen, and a new id is
 *  exactly what brings a notice back. */
public interface ThroNoticeMemory {
    public fun putAway(): String?
    public fun remember(id: String)
}

/** "Put away", kept in the same preferences file as the journal's device id. */
public class ThroNoticePreferences(context: Context) : ThroNoticeMemory {
    private val prefs = context.getSharedPreferences("thro", Context.MODE_PRIVATE)
    override fun putAway(): String? = prefs.getString(ThroServiceNotices.PUT_AWAY_KEY, null)
    override fun remember(id: String) {
        prefs.edit().putString(ThroServiceNotices.PUT_AWAY_KEY, id).apply()
    }
}

/**
 * The notice as the first screen holds it.
 *
 * **Asked at launch and on every return to the front, and at most once a minute.** A phone flicked between apps should
 * not ask a web site the same question twenty times over, and a notice published this morning should be on the first
 * screen the next time anybody opens THRØ, not the next time they relaunch it.
 *
 * **A notice already read stays up when the site cannot be reached**, and comes down only when the site says there is
 * nothing — an inactive file, or no file. Losing signal in a pub is not the notice being withdrawn.
 */
public class ThroServiceNotices(
    private val web: String?,
    private val transport: ThroNoticeTransport,
    private val memory: ThroNoticeMemory,
    private val now: () -> Long = System::currentTimeMillis,
) {
    public companion object {
        /** The iPhone's key, so both platforms name the same preference the same way. */
        public const val PUT_AWAY_KEY: String = "app.thro.notice.putAway"

        /** The shortest gap between two looks. */
        public const val INTERVAL_MILLIS: Long = 60_000
    }

    @Volatile
    public var current: ThroNotice? = null
        private set

    private var lastAsked: Long? = null

    /** The notice to show: the current one, unless it is the one somebody put away. */
    public val showing: ThroNotice?
        get() = current?.takeIf { it.id != memory.putAway() }

    /** The full notice on the web site, for an adult or for under-18s. */
    public fun page(underEighteen: Boolean): String? = web?.let { ThroNotice.page(it, underEighteen) }

    /** Asks the web site, unless it was asked less than a minute ago. It blocks, so call it off the main thread. A build
     *  that names no web site asks nothing. */
    @Synchronized
    public fun refresh() {
        val site = web ?: return
        val moment = now()
        lastAsked?.let { if (moment - it < INTERVAL_MILLIS) return }
        lastAsked = moment
        when (val answer = ThroNotice.ask(site, transport)) {
            is ThroNoticeAnswer.Live -> current = answer.notice
            ThroNoticeAnswer.NothingLive -> current = null
            ThroNoticeAnswer.Unknown -> Unit
        }
    }

    /** Takes this notice off the first screen. An updated notice carries a new id and shows again. */
    public fun putAway() {
        current?.let { memory.remember(it.id) }
    }
}
