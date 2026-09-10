package thro.api

import io.ktor.client.request.get
import io.ktor.client.request.header
import io.ktor.client.request.post
import io.ktor.client.request.setBody
import io.ktor.client.statement.HttpResponse
import io.ktor.client.statement.bodyAsText
import io.ktor.server.testing.testApplication
import java.io.File
import java.time.Instant
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import thro.api.http.Authenticator
import thro.api.http.Contract
import thro.api.http.Deps
import thro.api.http.thro
import thro.authz.ObjectRef
import thro.authz.ObjectType

/**
 * The HTTP layer, held to the three rules it keeps: identity is the principal and never the body;
 * a replay returns what it returned, status included; and the served contract is the committed one.
 *
 * Skipped cleanly when no database is configured, rather than passing silently.
 */
class HttpTest {

    @Test
    fun `routes over the handlers - identity from the principal, replays verbatim, the contract as committed`() {
        if (!TestDatabase.configured) {
            println("no database configured (set PGHOST) — HTTP tests skipped")
            return
        }
        val c = TestDatabase.migrated()
        val orgs = Organisations(c)
        var passed = 0
        fun check(name: String, cond: Boolean) {
            assertTrue(cond, "FAILED: $name")
            println("  PASS  $name")
            passed++
        }
        val ade = UUID.randomUUID(); val zed = UUID.randomUUID()
        val phone = UUID.randomUUID()
        val team = orgs.createTeam("Riverside A", by = ade)
        Relations(c).grant(ade, "admin", ObjectRef(ObjectType.TEAM, team.toString()))
        val home = orgs.createPlayer(); val away = orgs.createPlayer()
        val match = UUID.randomUUID()
        Matches(c).open(match, home, away, playtestFormat())

        // Every connection a request opens is watched: the first statement on it must be SET ROLE,
        // and the role must be a module's. ADR-011's per-module roles, held at the wire.
        val roles = java.util.Collections.synchronizedList(mutableListOf<String>())
        val bareUse = java.util.concurrent.atomic.AtomicInteger()
        fun watched(): java.sql.Connection {
            val real = TestDatabase.connect()
            var narrowed = false
            fun watchStatement(st: Any): Any = java.lang.reflect.Proxy.newProxyInstance(st.javaClass.classLoader, st.javaClass.interfaces) { _, m, args ->
                val sql = args?.firstOrNull() as? String
                if (sql != null && m.name in setOf("execute", "executeQuery", "executeUpdate")) {
                    if (sql.startsWith("SET ROLE ")) { roles += sql.removePrefix("SET ROLE "); narrowed = true }
                    else if (!narrowed) bareUse.incrementAndGet()
                }
                try { if (args == null) m.invoke(st) else m.invoke(st, *args) } catch (e: java.lang.reflect.InvocationTargetException) { throw e.targetException }
            }
            return java.lang.reflect.Proxy.newProxyInstance(real.javaClass.classLoader, arrayOf(java.sql.Connection::class.java)) { _, m, args ->
                val out = try { if (args == null) m.invoke(real) else m.invoke(real, *args) } catch (e: java.lang.reflect.InvocationTargetException) { throw e.targetException }
                if (m.name == "prepareStatement" && !narrowed) bareUse.incrementAndGet()
                if (m.name == "createStatement") watchStatement(out!!) else out
            } as java.sql.Connection
        }
        testApplication {
            application { thro(Deps(connect = { watched() }, authenticator = Authenticator.Dev(), now = { Instant.parse("2026-09-11T18:00:00Z") })) }

            suspend fun post(path: String, body: String, subject: UUID? = ade, device: UUID? = phone): HttpResponse = client.post(path) {
                subject?.let { header(Authenticator.Dev.HEADER, it.toString()) }
                device?.let { header("X-Thro-Device", it.toString()) }
                setBody(body)
            }
            suspend fun get(path: String, subject: UUID? = ade): HttpResponse = client.get(path) { subject?.let { header(Authenticator.Dev.HEADER, it.toString()) } }

            // --- who is calling -------------------------------------------------------------------
            check("no principal is 401 on a command", post("/v1/commands", "{}", subject = null).status.value == 401)
            check("no principal is 401 on a read", get("/v1/me/inbox", subject = null).status.value == 401)
            check("no device is 400", post("/v1/commands", """{"type":"RenameTeam","commandId":"${UUID.randomUUID()}"}""", device = null).status.value == 400)
            check("an unknown command type is 400", post("/v1/commands", """{"type":"Explode","commandId":"${UUID.randomUUID()}"}""").status.value == 400)
            check("a body that is not JSON is 400", post("/v1/commands", "not json").status.value == 400)
            check("a body over 64 KiB is 413 before anything is read into a handler", post("/v1/commands", "{\"pad\":\"" + "x".repeat(70_000) + "\"}").status.value == 413)
            check("a body nested a thousand deep is 400, not a stack overflow", post("/v1/commands", "[".repeat(1000) + "]".repeat(1000)).status.value == 400)
            check("a lineup whose players are not UUID strings is 400", post("/v1/commands", """{"type":"NameLineup","commandId":"${UUID.randomUUID()}","fixtureId":"${UUID.randomUUID()}","teamId":"$team","players":[1],"expectedVersion":0}""").status.value == 400)
            check("an integer out of range is 400, not silently truncated", post("/v1/commands", """{"type":"RenameTeam","commandId":"${UUID.randomUUID()}","teamId":"$team","to":"X","expectedVersion":4294967297}""").status.value == 400)

            // --- the one command endpoint ---------------------------------------------------------
            val rename = post("/v1/commands", """{"type":"RenameTeam","commandId":"${UUID.randomUUID()}","teamId":"$team","to":"Riverside Reds","expectedVersion":1}""")
            check("an admin renames the team through the endpoint", rename.status.value == 200 && rename.bodyAsText() == """{"outcome":"applied","version":2}""")
            val smuggled = post("/v1/commands", """{"type":"RenameTeam","commandId":"${UUID.randomUUID()}","actorId":"$ade","teamId":"$team","to":"Zed's","expectedVersion":2}""", subject = zed)
            check("an actor named in the body is ignored: the stranger is refused as the stranger", smuggled.status.value == 422 && smuggled.bodyAsText().contains("you do not run this team"))
            val staleId = UUID.randomUUID()
            val stale = post("/v1/commands", """{"type":"RenameTeam","commandId":"$staleId","teamId":"$team","to":"Riverside Blues","expectedVersion":1}""")
            check("a stale version is 409 with the current row", stale.status.value == 409 && stale.bodyAsText().contains("\"currentVersion\":2") && stale.bodyAsText().contains("Riverside Reds"))
            val replay = post("/v1/commands", """{"type":"RenameTeam","commandId":"$staleId","teamId":"$team","to":"Riverside Blues","expectedVersion":1}""")
            // The stored answer comes back through jsonb, which normalises whitespace and key order,
            // so "the same answer" is the parsed document, not the bytes.
            check("a replay returns what it returned — the same 409 and the same answer", replay.status.value == 409 && Json.parseObject(replay.bodyAsText()) == Json.parseObject(stale.bodyAsText()))
            val appliedId = UUID.randomUUID()
            val applied = post("/v1/commands", """{"type":"RenameTeam","commandId":"$appliedId","teamId":"$team","to":"Riverside Blues","expectedVersion":2}""")
            val appliedAgain = post("/v1/commands", """{"type":"RenameTeam","commandId":"$appliedId","teamId":"$team","to":"Riverside Blues","expectedVersion":2}""")
            check("a replayed applied command is 200 with the same answer, and applies nothing twice",
                applied.status.value == 200 && appliedAgain.status.value == 200 && Json.parseObject(appliedAgain.bodyAsText()) == Json.parseObject(applied.bodyAsText()) && c.prepareStatement("SELECT name FROM competition.team WHERE team_id = ?").use { ps -> ps.setObject(1, team); ps.executeQuery().use { rs -> rs.next(); rs.getString(1) } } == "Riverside Blues")

            val v1 = post("/v1/commands", """{"type":"RecordVisit","commandId":"${UUID.randomUUID()}","matchId":"$match","deviceSeq":1,"player":"home","visitTotal":60,"occurredAt":"2026-09-11T19:00:00Z"}""", subject = home)
            check("a visit travels the same endpoint and is applied", v1.status.value == 200 && v1.bodyAsText().contains("\"outcome\":\"applied\""))
            val gap = post("/v1/commands", """{"type":"RecordVisit","commandId":"${UUID.randomUUID()}","matchId":"$match","deviceSeq":3,"player":"away","visitTotal":60,"occurredAt":"2026-09-11T19:00:10Z"}""", subject = home)
            check("a sequence gap is 409 naming the expected sequence", gap.status.value == 409 && gap.bodyAsText() == """{"outcome":"gap","expectedSeq":2}""")
            val stranger = post("/v1/commands", """{"type":"RecordVisit","commandId":"${UUID.randomUUID()}","matchId":"$match","deviceSeq":2,"player":"Sam","visitTotal":60,"occurredAt":"2026-09-11T19:00:10Z"}""", subject = home)
            check("a visit naming something that is not a seat is 404: not this match", stranger.status.value == 404 && stranger.bodyAsText().contains("not a seat"))
            val injectId = UUID.randomUUID()
            val inject = post("/v1/commands", """{"type":"RecordVisit","commandId":"$injectId","matchId":"$match","deviceSeq":1,"player":"home","visitTotal":180,"occurredAt":"2026-09-11T19:00:20Z"}""", subject = zed, device = UUID.randomUUID())
            check("a stranger with a good seat is still a stranger: 404, and no evidence exists from them",
                inject.status.value == 404 && inject.bodyAsText().contains("hold no grant") &&
                    c.prepareStatement("SELECT count(*) FROM evidence.event WHERE match_id = ? AND actor_id = ?").use { ps -> ps.setObject(1, match); ps.setObject(2, zed); ps.executeQuery().use { rs -> rs.next(); rs.getInt(1) == 0 } })
            val injectAgain = post("/v1/commands", """{"type":"RecordVisit","commandId":"$injectId","matchId":"$match","deviceSeq":1,"player":"home","visitTotal":180,"occurredAt":"2026-09-11T19:00:20Z"}""", subject = zed, device = UUID.randomUUID())
            check("and a replayed visit refusal is a refusal the second time, status included", injectAgain.status.value == 404 && injectAgain.bodyAsText().contains("hold no grant"))

            // --- reads, filtered on the caller's relation ----------------------------------------
            val mine = get("/v1/me/inbox", subject = home)
            check("a player reads their own inbox", mine.status.value == 200 && mine.bodyAsText().startsWith("""{"sections":{"""))
            check("a stranger cannot read a team's inbox", get("/v1/teams/$team/inbox", subject = zed).status.value == 403)
            check("its admin can", get("/v1/teams/$team/inbox").status.value == 200)
            val disc = get("/v1/me/discovery?locality=Stockton", subject = home)
            check("discovery answers for the caller", disc.status.value == 200 && disc.bodyAsText().startsWith("""{"sections":{"""))
            check("a malformed date is 400, not a 500", get("/v1/me/discovery?from=yesterday", subject = home).status.value == 400)
            // The leagues' public front needs no principal and answers the same shape empty or full.
            val leagues = get("/v1/leagues?locality=Stockton", subject = null)
            check("the leagues are public and answer without a principal", leagues.status.value == 200 && leagues.bodyAsText().startsWith("""{"leagues":["""))
            check("friends need a principal, and the development principal has no account to be friends from",
                get("/v1/friends", subject = null).status.value == 401 && get("/v1/friends", subject = home).status.value == 403
                    && post("/v1/friends/invite", "{}", subject = home).status.value == 403)
            val events = get("/v1/events", subject = null)
            check("upcoming open events are public too, and a bad date is a 400", events.status.value == 200 && events.bodyAsText().startsWith("""{"events":[""") && get("/v1/events?from=soon", subject = null).status.value == 400)

            // --- health and the contract ------------------------------------------------------------
            val health = get("/healthz", subject = null)
            check("health reports the ledger's version without a principal", health.status.value == 200 && health.bodyAsText().contains("\"schemaVersion\":\"V%03d\"".format(Migrations.currentVersion(c))))
            val served = get("/openapi.json", subject = null).bodyAsText()
            check("the served contract lists every endpoint the server mounts, and no other",
                Contract.endpoints.all { served.contains("\"operationId\":\"${it.id}\"") } && Regex("\"operationId\"").findAll(served).count() == Contract.endpoints.size)
            val committed = File(generateSequence(File(".").absoluteFile) { it.parentFile }.map { File(it, "services/api/openapi.json") }.first { it.parentFile.isDirectory }.path)
            if (System.getenv("THRO_WRITE_OPENAPI") == "1") committed.writeText(served)
            check("the committed contract is the served one (regenerate with THRO_WRITE_OPENAPI=1 and review the diff)",
                committed.exists() && committed.readText() == served)
            check("every request narrowed its connection to a module role before touching a table: visits as app_match, organisational commands and reads as app_competition, health as app_read",
                bareUse.get() == 0 && roles.contains("app_match") && roles.contains("app_competition") && roles.contains("app_read") && roles.all { it in setOf("app_match", "app_competition", "app_read") })
        }
        println("  $passed HTTP properties held")
        assertEquals(31, passed)
    }
}
