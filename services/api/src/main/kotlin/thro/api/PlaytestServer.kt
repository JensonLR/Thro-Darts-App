package thro.api

import com.sun.net.httpserver.HttpExchange
import com.sun.net.httpserver.HttpServer
import java.io.FileDescriptor
import java.io.FileOutputStream
import java.io.PrintStream
import java.net.InetSocketAddress
import java.sql.Connection
import java.sql.DriverManager
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

/**
 * THRØ playtest harness.
 *
 * This is **not** the product. The shipped participant app is native iOS and Android, and it scores
 * offline on a local journal. This is a deliberately thin, online-only server that puts the real
 * scoring engine and the real command path behind a browser, so the competitive core can be played
 * against by real people at a real board before either client exists.
 *
 * What is real here: the engine, the command path, idempotency, per-device sequences, server-side
 * revalidation, and the Postgres event log. What is not: offline scoring, authentication, sync, and
 * anything to do with rating.
 *
 * Built on the JDK's own HTTP server so the harness adds no dependency to the project.
 */
public object PlaytestServer {

    private data class Registered(val home: String, val away: String, val device: UUID)

    private val matches = ConcurrentHashMap<UUID, Registered>()

    @JvmStatic
    public fun main(args: Array<String>) {
        // The JVM picks stdout's charset from the launching console, which mangles the Ø in the
        // product name to a question mark on a non-UTF-8 terminal. The name does not change to
        // suit a terminal.
        System.setOut(PrintStream(FileOutputStream(FileDescriptor.out), true, "UTF-8"))

        val port = (System.getenv("PORT") ?: "8080").toInt()
        val conn = connect()
        migrate(conn)

        val server = HttpServer.create(InetSocketAddress("0.0.0.0", port), 0)
        server.createContext("/") { ex -> serveIndex(ex) }
        server.createContext("/api/match") { ex -> handleMatch(ex, conn) }
        server.executor = null
        server.start()
        println("THRØ playtest harness on http://0.0.0.0:$port")
        println("This is a playtest harness, not the product. Online only, no auth, no rating.")
    }

    private fun connect(): Connection {
        val host = System.getenv("PGHOST") ?: "localhost"
        val port = System.getenv("PGPORT") ?: "5432"
        val db = System.getenv("PGDATABASE") ?: "postgres"
        val user = System.getenv("PGUSER") ?: "postgres"
        return DriverManager.getConnection("jdbc:postgresql://$host:$port/$db", user, "")
    }

    private fun migrate(c: Connection) {
        val dir = generateSequence(java.io.File(".").absoluteFile) { it.parentFile }
            .map { java.io.File(it, "services/api/migrations") }
            .firstOrNull { it.isDirectory } ?: java.io.File("migrations")
        c.createStatement().use { st ->
            val exists = st.executeQuery(
                "SELECT count(*) FROM information_schema.schemata WHERE schema_name='evidence'",
            ).use { rs -> rs.next(); rs.getInt(1) > 0 }
            if (!exists) {
                dir.listFiles { f -> f.extension == "sql" }?.sortedBy { it.name }?.forEach { f ->
                    st.execute(f.readText())
                }
                println("migrations applied")
            }
        }
    }

    private fun serveIndex(ex: HttpExchange) {
        val html = PlaytestServer::class.java.getResourceAsStream("/scorer.html")
            ?.readBytes() ?: "scorer.html not found".toByteArray()
        ex.responseHeaders.add("Content-Type", "text/html; charset=utf-8")
        ex.sendResponseHeaders(200, html.size.toLong())
        ex.responseBody.use { it.write(html) }
    }

    private fun handleMatch(ex: HttpExchange, conn: Connection) {
        try {
            val path = ex.requestURI.path.removePrefix("/api/match").trim('/')
            val body = ex.requestBody.readBytes().decodeToString()
            val response = when {
                ex.requestMethod == "POST" && path.isEmpty() -> createMatch(body)
                ex.requestMethod == "POST" && path.endsWith("/visit") ->
                    recordVisit(conn, UUID.fromString(path.removeSuffix("/visit")), body)
                ex.requestMethod == "GET" && path.endsWith("/stats") ->
                    matchStats(conn, UUID.fromString(path.removeSuffix("/stats")))
                ex.requestMethod == "GET" && path.isNotEmpty() ->
                    matchState(conn, UUID.fromString(path))
                else -> """{"error":"not found"}"""
            }
            send(ex, 200, response)
        } catch (e: Exception) {
            send(ex, 400, """{"error":${quote(e.message ?: "bad request")}}""")
        }
    }

    private fun createMatch(body: String): String {
        val home = field(body, "home") ?: "Home"
        val away = field(body, "away") ?: "Away"
        val id = UUID.randomUUID()
        matches[id] = Registered(home, away, UUID.randomUUID())
        return """{"matchId":"$id","home":${quote(home)},"away":${quote(away)}}"""
    }

    private fun recordVisit(conn: Connection, matchId: UUID, body: String): String {
        val reg = matches[matchId] ?: return """{"error":"unknown match"}"""
        val player = field(body, "player") ?: return """{"error":"player required"}"""
        val total = field(body, "visitTotal")?.toIntOrNull()
            ?: return """{"error":"visitTotal required"}"""
        val darts = field(body, "dartsUsed")?.toIntOrNull()
        val atDouble = field(body, "dartsAtDouble")?.toIntOrNull()

        val handler = CommandHandler(conn)
        // The next sequence is derived server-side here because the browser holds no journal. A
        // real client owns its own sequence, which is what makes offline scoring possible.
        val seq = nextSeq(conn, matchId, reg.device)
        val result = handler.handle(
            VisitCommand(
                commandId = UUID.randomUUID(), matchId = matchId, deviceId = reg.device,
                deviceSeq = seq, actorId = UUID.randomUUID(), actorRole = "participant",
                correlationId = UUID.randomUUID(), player = player, visitTotal = total,
                dartsUsed = darts, dartsAtDouble = atDouble,
                occurredAt = java.time.OffsetDateTime.now().toString(),
                occurredTz = java.time.ZoneId.systemDefault().id,
            ),
            reg.home, reg.away,
        )
        val outcome = when (result) {
            is CommandResult.Applied ->
                """{"result":"applied","effect":${quote(result.effect)},"reason":${
                    result.reason?.let { quote(it) } ?: "null"}}"""
            is CommandResult.Refused -> """{"result":"refused","reason":${quote(result.reason)}}"""
            is CommandResult.Gap -> """{"result":"gap","expected":${result.expectedSeq}}"""
            is CommandResult.Replayed -> """{"result":"replayed"}"""
        }
        return """{"outcome":$outcome,"state":${stateJson(conn, matchId, reg)}}"""
    }

    /**
     * Both competitors' figures, each carrying its own basis. Derived by replaying the log through
     * the engine — nothing is stored, so this cannot drift from the evidence it is computed from.
     */
    private fun matchStats(conn: Connection, matchId: UUID): String {
        val reg = matches[matchId] ?: throw IllegalArgumentException("unknown match")
        val proj = StatsProjection(conn)
        return """{"home":${proj.summaryFor(matchId, reg.device, reg.home, reg.away, reg.home)},""" +
            """"away":${proj.summaryFor(matchId, reg.device, reg.home, reg.away, reg.away)}}"""
    }

    private fun matchState(conn: Connection, matchId: UUID): String {
        val reg = matches[matchId] ?: return """{"error":"unknown match"}"""
        return """{"state":${stateJson(conn, matchId, reg)}}"""
    }

    /** Rebuilt by folding the event log, so the browser holds no authoritative state. */
    private fun stateJson(conn: Connection, matchId: UUID, reg: Registered): String {
        val state = CommandHandler(conn).replayFor(matchId, reg.device, reg.home, reg.away)
        val h = thro.engine.PlayerId(reg.home)
        val a = thro.engine.PlayerId(reg.away)
        return """{"home":${quote(reg.home)},"away":${quote(reg.away)},""" +
            """"remainingHome":${state.remaining.getValue(h)},""" +
            """"remainingAway":${state.remaining.getValue(a)},""" +
            """"legsHome":${state.legsWonTotal.getValue(h)},""" +
            """"legsAway":${state.legsWonTotal.getValue(a)},""" +
            """"currentLeg":${state.currentLeg},""" +
            """"thrower":${state.thrower?.let { quote(it.value) } ?: "null"},""" +
            """"winner":${state.winner?.let { quote(it.value) } ?: "null"}}"""
    }

    private fun nextSeq(conn: Connection, matchId: UUID, device: UUID): Long {
        conn.prepareStatement(
            "SELECT coalesce(max(device_seq),0)+1 FROM evidence.event WHERE match_id=? AND device_id=?",
        ).use { ps ->
            ps.setObject(1, matchId); ps.setObject(2, device)
            ps.executeQuery().use { rs -> rs.next(); return rs.getLong(1) }
        }
    }

    private fun field(body: String, name: String): String? =
        Regex(""""$name"\s*:\s*(?:"([^"]*)"|([0-9]+)|null)""").find(body)
            ?.let { it.groupValues[1].ifEmpty { it.groupValues[2] } }?.ifEmpty { null }

    private fun quote(s: String) = "\"" + s.replace("\\", "\\\\").replace("\"", "\\\"") + "\""

    private fun send(ex: HttpExchange, code: Int, body: String) {
        val bytes = body.toByteArray()
        ex.responseHeaders.add("Content-Type", "application/json; charset=utf-8")
        ex.sendResponseHeaders(code, bytes.size.toLong())
        ex.responseBody.use { it.write(bytes) }
    }
}
