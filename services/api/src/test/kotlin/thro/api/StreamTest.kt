package thro.api

import io.ktor.server.cio.CIO
import io.ktor.server.engine.embeddedServer
import java.io.BufferedReader
import java.net.URI
import java.net.http.HttpClient
import java.net.http.HttpRequest
import java.net.http.HttpResponse
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.runBlocking
import java.time.Duration
import java.time.Instant
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import thro.api.http.Authenticator
import thro.api.http.Deps
import thro.api.http.thro

/**
 * `match:{id}` over server-sent events (ADR-007): every event in commit order, ids that resume,
 * a heartbeat, and a door that opens only to the match's own people.
 *
 * Skipped cleanly when no database is configured, rather than passing silently.
 */
class StreamTest {

    @Test
    fun `a match stream replays in commit order, resumes from Last-Event-ID, pings, and refuses a stranger`() {
        if (!TestDatabase.configured) {
            println("no database configured (set PGHOST) — stream tests skipped")
            return
        }
        val c = TestDatabase.migrated()
        var passed = 0
        fun check(name: String, cond: Boolean) {
            assertTrue(cond, "FAILED: $name")
            println("  PASS  $name")
            passed++
        }
        val home = UUID.randomUUID(); val away = UUID.randomUUID(); val stranger = UUID.randomUUID()
        val match = UUID.randomUUID(); val device = UUID.randomUUID()
        Matches(c).open(match, home, away, playtestFormat())
        val handler = CommandHandler(c)
        fun visit(seq: Long, seat: String, total: Int) = handler.handle(VisitCommand(
            commandId = UUID.randomUUID(), matchId = match, deviceId = device, deviceSeq = seq, actorId = home, actorRole = "participant",
            correlationId = UUID.randomUUID(), player = seat, visitTotal = total, dartsUsed = 3, occurredAt = "2026-09-12T19:0$seq:00Z", occurredTz = "Europe/London",
        ))
        check("three visits are recorded before anyone is watching", listOf(visit(1, "home", 60), visit(2, "away", 100), visit(3, "home", 45)).all { it is CommandResult.Applied })

        // A real engine on an ephemeral port: the test engine buffers a streaming response until
        // the handler ends, and a stream's handler does not end. The client is the JDK's, reading
        // the body line by line as it arrives.
        val server = embeddedServer(CIO, port = 0) {
            thro(Deps(connect = { TestDatabase.connect() }, authenticator = Authenticator.Dev(), now = { Instant.parse("2026-09-12T19:00:00Z") },
                streamPoll = Duration.ofMillis(50), streamHeartbeat = Duration.ofMillis(200)))
        }.start(wait = false)
        try {
            val port = runBlocking { server.engine.resolvedConnectors().first().port }
            val http = HttpClient.newHttpClient()
            val pool = Executors.newCachedThreadPool()
            // Reads frames until [count] events (and a ping when [wantPing]) have arrived, or ten seconds pass.
            fun frames(subject: UUID?, matchId: UUID = match, lastId: String? = null, count: Int, wantPing: Boolean = false, dev: UUID? = device): Pair<Int, List<Triple<String, String, String>>> {
                val b = HttpRequest.newBuilder(URI("http://127.0.0.1:$port/v1/streams/match/$matchId")).header("Accept", "text/event-stream")
                subject?.let { b.header(Authenticator.Dev.HEADER, it.toString()) }
                dev?.let { b.header("X-Thro-Device", it.toString()) }
                lastId?.let { b.header("Last-Event-ID", it) }
                val response = http.send(b.build(), HttpResponse.BodyHandlers.ofInputStream())
                if (response.statusCode() != 200) { response.body().close(); return response.statusCode() to emptyList() }
                val events = mutableListOf<Triple<String, String, String>>()
                var sawPing = false
                val reader = BufferedReader(response.body().reader())
                val job = pool.submit {
                    var id = ""; var event = ""; var data = ""
                    while (true) {
                        val line = reader.readLine() ?: break
                        when {
                            line.startsWith(":") -> if (line.contains("ping")) sawPing = true
                            line.startsWith("id:") -> id = line.removePrefix("id:").trim()
                            line.startsWith("event:") -> event = line.removePrefix("event:").trim()
                            line.startsWith("data:") -> data = line.removePrefix("data:").trim()
                            line.isEmpty() -> { if (data.isNotEmpty()) events += Triple(id, event, data); id = ""; event = ""; data = "" }
                        }
                        if (events.size >= count && (!wantPing || sawPing)) break
                    }
                }
                try { job.get(10, TimeUnit.SECONDS) } catch (_: java.util.concurrent.TimeoutException) { job.cancel(true) }
                response.body().close()
                return 200 to (if (wantPing && !sawPing) emptyList() else events.toList())
            }

            val (status, all) = frames(home, count = 3)
            check("a participant receives the three visits in commit order, each with its type and id",
                status == 200 && all.map { it.second } == listOf("VisitRecorded", "VisitRecorded", "VisitRecorded") &&
                    all.first().third.replace(" ", "").contains("\"visitTotal\":60") && all.all { it.first.startsWith("match:$match:") })
            val ids = all.map { it.first.removePrefix("match:$match:") }
            check("ids are the (commit, sequence) pair and strictly increase", ids == ids.sortedWith(compareBy({ it.substringBefore("-").toLong() }, { it.substringAfter("-").toLong() })) && ids.toSet().size == 3)
            check("a payload names a seat and no person", all.all { val d = it.third.replace(" ", ""); d.contains("\"player\":\"home\"") || d.contains("\"player\":\"away\"") })

            visit(4, "away", 85)
            val (_, resumed) = frames(home, lastId = all[1].first, count = 2)
            check("a reconnect with Last-Event-ID replays only what came after it — the third visit and the fourth", resumed.size == 2 && resumed[0].first == all[2].first && resumed[1].third.contains("85"))

            val (_, withPing) = frames(away, count = 4, wantPing = true)
            check("a quiet stream pings", withPing.size == 4)

            check("a stranger is refused", frames(stranger, count = 1, dev = UUID.randomUUID()).first == 403)
            check("no principal is refused", frames(null, count = 1).first == 401)
            check("a match that does not exist is 404", frames(home, matchId = UUID.randomUUID(), count = 1).first == 404)
            pool.shutdownNow()
        } finally {
            server.stop(100, 500)
        }
        println("  $passed stream properties held")
        assertEquals(9, passed)
    }

    @Test
    fun `a signed-in watcher is let in, and a new visit reaches them long before the poll would`() {
        if (!TestDatabase.configured) return
        val c = TestDatabase.migrated()
        val session = Accounts(c, { Instant.now() }).signIn("apple", "apple-subject-watcher-${UUID.randomUUID()}", UUID.randomUUID())
        val me = session.playerId ?: error("signing in made no competitor")
        val match = UUID.randomUUID(); val device = UUID.randomUUID()
        Matches(c).open(match, me, UUID.randomUUID(), playtestFormat())
        val handler = CommandHandler(c)
        // The scorer enters both seats' visits, in turn: the engine refuses a seat throwing twice.
        fun visit(seq: Long, seat: String, total: Int) = handler.handle(VisitCommand(
            commandId = UUID.randomUUID(), matchId = match, deviceId = device, deviceSeq = seq, actorId = me, actorRole = "participant",
            correlationId = UUID.randomUUID(), player = seat, visitTotal = total, dartsUsed = 3,
            occurredAt = "2026-09-12T19:0$seq:00Z", occurredTz = "Europe/London",
        ))
        assertTrue(visit(1, "home", 60) is CommandResult.Applied, "home's first visit is recorded")

        // A thirty-second poll: anything that arrives much sooner was woken by the database (V036).
        val server = embeddedServer(CIO, port = 0) {
            thro(Deps(connect = { TestDatabase.connect() }, authenticator = Authenticator.Bearer(), now = { Instant.now() },
                      streamPoll = Duration.ofSeconds(30), streamHeartbeat = Duration.ofSeconds(60)))
        }.start(wait = false)
        val pool = Executors.newSingleThreadExecutor()
        try {
            val port = runBlocking { server.engine.resolvedConnectors().first().port }
            val request = HttpRequest.newBuilder(URI("http://127.0.0.1:$port/v1/streams/match/$match"))
                .header("Accept", "text/event-stream").header("Authorization", "Bearer ${session.accessToken}").build()
            val response = HttpClient.newHttpClient().send(request, HttpResponse.BodyHandlers.ofInputStream())
            // The defect: the stream stood as the match role, which cannot read the token table, so a
            // signed-in watcher never got past the door. The development principal always did.
            assertEquals(200, response.statusCode(), "a signed-in participant is let in")

            val arrivals = java.util.concurrent.LinkedBlockingQueue<Pair<String, Long>>()
            val reader = BufferedReader(response.body().reader())
            pool.submit {
                while (true) {
                    val line = reader.readLine() ?: break
                    if (line.startsWith("data:")) arrivals.put(line to System.nanoTime())
                }
            }
            val replayed = arrivals.poll(10, TimeUnit.SECONDS) ?: error("the replay never came")
            assertTrue(replayed.first.replace(" ", "").contains("\"visitTotal\":60"), "the visit already there is replayed")

            val sent = System.nanoTime()
            assertTrue(visit(2, "away", 100) is CommandResult.Applied, "away's reply is recorded")
            val (data, at) = arrivals.poll(10, TimeUnit.SECONDS) ?: error("the new visit never arrived")
            assertTrue(data.replace(" ", "").contains("\"visitTotal\":100"))
            val ms = (at - sent) / 1_000_000
            println("  a new visit reached the watcher in $ms ms; the poll was set to 30 s")
            assertTrue(ms < 5_000, "it arrived in $ms ms: the database woke the stream, where the poll would have taken up to 30 s")
            response.body().close()
        } finally {
            pool.shutdownNow()
            server.stop(100, 500)
        }
    }
}
