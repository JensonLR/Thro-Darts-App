package thro.api

import io.ktor.client.request.delete
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
            suspend fun del(path: String, subject: UUID? = ade): HttpResponse = client.delete(path) { subject?.let { header(Authenticator.Dev.HEADER, it.toString()) } }

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

            // --- erasure (V031) -------------------------------------------------------------------
            // The route exists, is authenticated, and answers a principal with no account to erase
            // with a sentence rather than a 500 from a null. What erasure DOES is ErasureTest's; this
            // holds that DELETE is routed at all, which no other endpoint in the contract exercises.
            // Sending a match (PD-040). What an upload DOES is UploadTest's; this holds that the
            // route is reachable, authenticated, and answers a bad journal in words rather than 500.
            check("sending a match needs a principal", post("/v1/matches", "{}", subject = null).status.value == 401)
            val emptyMatch = post("/v1/matches", """{"matchId":"${UUID.randomUUID()}","deviceId":"$phone","seat":"home","format":{"startingScore":501,"inRule":"straight","outRule":"double","legsMode":"first_to","legsTarget":3,"throwFirst":"home"},"rows":[]}""", subject = home)
            check("a match with nothing in it is refused in words", emptyMatch.status.value == 422 && emptyMatch.bodyAsText().contains("nothing in it"))
            val sentMatch = UUID.randomUUID()
            val oneVisit = post("/v1/matches", """{"matchId":"$sentMatch","deviceId":"$phone","seat":"home","format":{"startingScore":501,"inRule":"straight","outRule":"double","legsMode":"first_to","legsTarget":3,"throwFirst":"home"},"rows":[{"deviceSeq":1,"kind":"visit","seat":"home","visitTotal":60,"occurredAt":"2026-09-11T19:30:00Z","occurredTz":"Europe/London"}]}""", subject = home)
            check("a match this phone scored is stored, self-reported", oneVisit.status.value == 200 && oneVisit.bodyAsText().contains("\"selfReported\":true"))

            // The other seat, taken by a code and answered for (PD-043). What the records DO is
            // MatchRecordsTest's; this holds the routes, the roles they run under, and refusals in words.
            val made = post("/v1/matches/$sentMatch/code", "{}", subject = home)
            val matchCode = Regex(""""code":"([A-Z2-9]{8})"""").find(made.bodyAsText())?.groupValues?.get(1)
            check("only the player who sent a match makes a code for its other seat",
                made.status.value == 200 && matchCode != null && post("/v1/matches/$sentMatch/code", "{}", subject = zed).status.value == 404)
            val taken = post("/v1/matches/claim", """{"code":"${matchCode?.lowercase()}"}""", subject = away)
            check("the player they played takes the seat with it, case ignored, and the code is refused in words after that",
                taken.status.value == 200 && taken.bodyAsText().contains(""""seat":"away","you":true""")
                    && post("/v1/matches/claim", """{"code":"$matchCode"}""", subject = zed).let { it.status.value == 422 && it.bodyAsText().contains("used already") })
            check("the sender cannot answer for their own match; the other player confirms it, and it reads confirmed to both",
                post("/v1/matches/$sentMatch/answer", """{"agree":true}""", subject = home).status.value == 422
                    && post("/v1/matches/$sentMatch/answer", """{"agree":true}""", subject = away).bodyAsText().contains(""""standing":"confirmed"""")
                    && get("/v1/matches/$sentMatch", subject = home).bodyAsText().contains(""""standing":"confirmed""""))
            check("a match is read only by the people in it, and each finds it among their own",
                get("/v1/matches/$sentMatch", subject = zed).status.value == 404
                    && get("/v1/me/matches", subject = away).bodyAsText().contains(""""matchId":"$sentMatch"""")
                    && !get("/v1/me/matches", subject = zed).bodyAsText().contains("$sentMatch"))

            check("erasing an account needs a principal", del("/v1/me", subject = null).status.value == 401)
            // A DELETE carries no body, so it declares no length. Demanding one answered every
            // correct caller with 411 and made erasure look broken on the phone.
            check("a bodyless DELETE is not refused for having no Content-Length", del("/v1/me").status.value != 411)
            val noAccount = del("/v1/me")
            check("a development principal has no account to erase, and is told so",
                  noAccount.status.value == 400 && noAccount.bodyAsText().contains("no account to erase"))
            val started = post("/v1/teams", """{"name":"The Sun Inn","locality":"Stockton-on-Tees"}""", subject = home)
            check("a team is started over the wire and its starter is its admin",
                started.status.value == 200 && started.bodyAsText().contains(""""role":"admin"""")
                    && get("/v1/me/teams", subject = home).bodyAsText().contains(""""name":"The Sun Inn""""))
            val teamId = Regex(""""teamId":"([0-9a-f-]+)"""").find(started.bodyAsText())!!.groupValues[1]
            val front = get("/v1/teams/$teamId", subject = null)
            check("its front is public without a principal, and names nobody whose disclosure is not settled",
                front.status.value == 200 && front.bodyAsText().contains(""""roster":[{"name":null,"role":"admin"}]"""))
            val code = Regex(""""code":"([A-Z2-9]{8})"""").find(post("/v1/teams/$teamId/invite", "{}", subject = home).bodyAsText())!!.groupValues[1]
            check("a stranger cannot make the team's code, a member joins on it once, and a bad code says why",
                post("/v1/teams/$teamId/invite", "{}", subject = away).status.value == 403
                    && post("/v1/teams/join", """{"code":"$code"}""", subject = away).status.value == 200
                    && post("/v1/teams/join", """{"code":"$code"}""", subject = away).status.value == 409
                    && post("/v1/teams/join", """{"code":"nope"}""", subject = away).status.value == 409)
            check("a home venue is chosen by name from the public venues and set by whoever runs the team",
                get("/v1/venues?q=xy", subject = null).status.value == 200
                    && get("/v1/venues?q=", subject = null).status.value == 400
                    && post("/v1/teams/$teamId/home", """{"name":"The Sun Inn","locality":"Stockton-on-Tees"}""", subject = away).status.value == 403
                    && post("/v1/teams/$teamId/home", """{"name":"The Sun Inn","locality":"Stockton-on-Tees"}""", subject = home).bodyAsText().contains(""""venue":{"""))
            // Roles (PD-045): the admin's front carries each entry's handle, and names a captain with it.
            // After the home check, not before it: a captain may set the home, and that check holds that
            // a player may not.
            val adminFront = get("/v1/teams/$teamId", subject = home).bodyAsText()
            val playerHandle = Regex(""""role":"player","memberId":"([0-9a-f-]+)"""").find(adminFront)?.groupValues?.get(1)
            check("the admin names a captain from the roster, nobody else may, and a public front carries no handles",
                playerHandle != null && !get("/v1/teams/$teamId", subject = null).bodyAsText().contains("memberId")
                    && post("/v1/teams/$teamId/roles", """{"memberId":"$playerHandle","role":"captain"}""", subject = away).status.value == 403
                    && post("/v1/teams/$teamId/roles", """{"memberId":"$playerHandle","role":"captain"}""", subject = home).bodyAsText().contains(""""role":"captain""""))
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
            check("every request narrowed its connection to a module role before touching a table: visits as app_match, organisational commands and reads as app_competition, health as app_read, an answer for a result as app_trust",
                bareUse.get() == 0 && roles.contains("app_match") && roles.contains("app_competition") && roles.contains("app_read") && roles.contains("app_trust")
                    && roles.all { it in setOf("app_match", "app_competition", "app_read", "app_trust") })
        }
        println("  $passed HTTP properties held")
        assertEquals(46, passed)
    }
}
