package thro.api

import com.sun.net.httpserver.HttpServer
import java.net.InetSocketAddress
import java.net.URI
import java.time.Duration
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * The wire between THRØ and TypeSafe's System One endpoint (PD-118), held against a local stand-in for it: what
 * THRØ sends, how it reads what comes back, and that nothing TypeSafe does — a refusal, nonsense, silence — can
 * reach a report. A reading is a hint for the person who answers; when there is none, there is none.
 */
class TypeSafeReaderTest {

    private class Stub(val status: Int, val body: String, val delay: Duration = Duration.ZERO) {
        var lastBody: String? = null
        var lastAuth: String? = null
        var lastContentType: String? = null
        val server: HttpServer = HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0).apply {
            createContext("/v1/systemone") { ex ->
                lastBody = ex.requestBody.readBytes().decodeToString()
                lastAuth = ex.requestHeaders.getFirst("Authorization")
                lastContentType = ex.requestHeaders.getFirst("Content-Type")
                if (!delay.isZero) Thread.sleep(delay.toMillis())
                val bytes = body.toByteArray()
                ex.sendResponseHeaders(status, bytes.size.toLong())
                ex.responseBody.use { it.write(bytes) }
            }
            start()
        }
        val uri: URI get() = URI("http://127.0.0.1:${server.address.port}/v1/systemone")
        fun stop() = server.stop(0)
    }

    private val reportAnswer = """{"model":"jev-latest","answers":{
        "category":{"type":"choice","choice":"harassment","probabilities":{"harassment":0.82,"hate_or_slur":0.1,"other":0.08},"confidence":0.8},
        "child_safety":{"type":"noul","noul":0.03},
        "severity":{"type":"score","score":1.7,"legend":{"0":"a","1":"b","2":"c","3":"d"},"probabilities":{"0":0.05,"1":0.3,"2":0.55,"3":0.1},"confidence":0.6}
      },"usage":{"input_tokens":200,"output_tokens":30}}"""

    @Test
    fun `a report is read as a category, a child-safety probability and a severity`() {
        val stub = Stub(200, reportAnswer)
        try {
            val reader = TypeSafeReader("key-123", endpoint = stub.uri, timeout = Duration.ofSeconds(2))
            val reading = reader.readReport("account", "Dave D.", "He keeps messaging my daughter's team about meeting up")
            assertNotNull(reading)
            assertEquals("harassment", reading.category)
            assertEquals(0.8, reading.categoryConfidence, 1e-9)
            assertEquals(0.03, reading.childSafety, 1e-9)
            assertEquals(1.7, reading.severity, 1e-9)
            assertEquals("jev-latest", reading.model)

            assertEquals("Bearer key-123", stub.lastAuth, "the key is sent as a bearer token, never in the body or the address")
            assertTrue(stub.lastContentType!!.startsWith("application/json"))
            val sent = Json.parseObject(stub.lastBody!!)
            assertEquals("jev-latest", sent["model"])
            @Suppress("UNCHECKED_CAST")
            val questions = sent["questions"] as Map<String, Any?>
            assertEquals(setOf("category", "child_safety", "severity"), questions.keys)
            @Suppress("UNCHECKED_CAST")
            assertEquals("choice", (questions["category"] as Map<String, Any?>)["type"])
            @Suppress("UNCHECKED_CAST")
            assertEquals("noul", (questions["child_safety"] as Map<String, Any?>)["type"])
            @Suppress("UNCHECKED_CAST")
            assertEquals("score", (questions["severity"] as Map<String, Any?>)["type"])
            @Suppress("UNCHECKED_CAST")
            val state = sent["state"] as Map<String, Any?>
            @Suppress("UNCHECKED_CAST")
            val report = state["report"] as Map<String, Any?>
            assertEquals("He keeps messaging my daughter's team about meeting up", report["reason"])
            assertEquals("Dave D.", report["name_reported"])
            assertEquals("account", report["about"])
            assertTrue((state["context"] as String).contains("under 18"), "the model is told that children may be among the players")
        } finally { stub.stop() }
    }

    @Test
    fun `a name is read for abuse and for impersonation`() {
        val stub = Stub(200, """{"model":"jev-latest","answers":{"abusive":{"type":"noul","noul":0.94},"impersonates":{"type":"noul","noul":0.02}},"usage":{"input_tokens":50,"output_tokens":8}}""")
        try {
            val reading = TypeSafeReader("k", endpoint = stub.uri, timeout = Duration.ofSeconds(2)).readName("team", "Kill All Referees")
            assertNotNull(reading)
            assertEquals(0.94, reading.abusive, 1e-9)
            assertEquals(0.02, reading.impersonates, 1e-9)
            val sent = Json.parseObject(stub.lastBody!!)
            @Suppress("UNCHECKED_CAST")
            assertEquals(setOf("abusive", "impersonates"), (sent["questions"] as Map<String, Any?>).keys)
            @Suppress("UNCHECKED_CAST")
            assertEquals("Kill All Referees", (sent["state"] as Map<String, Any?>)["name"])
        } finally { stub.stop() }
    }

    @Test
    fun `a refusal, nonsense or silence from TypeSafe is no reading, never an error`() {
        val refused = Stub(429, """{"error":"rate limited"}""")
        try { assertNull(TypeSafeReader("k", endpoint = refused.uri, timeout = Duration.ofSeconds(2)).readReport("team", "X", "why")) } finally { refused.stop() }

        val nonsense = Stub(200, "<html>not json</html>")
        try { assertNull(TypeSafeReader("k", endpoint = nonsense.uri, timeout = Duration.ofSeconds(2)).readReport("team", "X", "why")) } finally { nonsense.stop() }

        val incomplete = Stub(200, """{"model":"jev-latest","answers":{"category":{"type":"choice","choice":"other","probabilities":{"other":1},"confidence":1}},"usage":{}}""")
        try { assertNull(TypeSafeReader("k", endpoint = incomplete.uri, timeout = Duration.ofSeconds(2)).readReport("team", "X", "why"), "three answers or none") } finally { incomplete.stop() }

        val slow = Stub(200, reportAnswer, delay = Duration.ofMillis(1500))
        try { assertNull(TypeSafeReader("k", endpoint = slow.uri, timeout = Duration.ofMillis(300)).readReport("team", "X", "why"), "a reading that does not come in time does not come") } finally { slow.stop() }

        val unreachable = TypeSafeReader("k", endpoint = URI("http://127.0.0.1:9/v1/systemone"), timeout = Duration.ofMillis(300))
        assertNull(unreachable.readName("account", "Anybody"))
    }
}
