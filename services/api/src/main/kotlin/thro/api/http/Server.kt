package thro.api.http

import io.ktor.http.ContentType
import io.ktor.http.HttpStatusCode
import io.ktor.server.application.Application
import io.ktor.server.application.ApplicationCall
import io.ktor.server.application.call
import io.ktor.server.request.receiveText
import io.ktor.server.response.respondText
import io.ktor.server.routing.get
import io.ktor.server.routing.post
import io.ktor.server.routing.routing
import java.sql.Connection
import java.time.Instant
import java.time.temporal.ChronoUnit
import java.util.UUID
import thro.api.CommandHandler
import thro.api.CommandResult
import thro.api.Discovery
import thro.api.Json
import thro.api.Migrations
import thro.api.OrganisationCommands
import thro.api.Organisations
import thro.api.Relations
import thro.api.Secretary
import thro.api.VisitCommand
import thro.authz.ObjectRef
import thro.authz.ObjectType

/**
 * The HTTP layer: routes over the handlers that already exist, and nothing decided here that the
 * handlers do not decide. Plan §5, step 1.
 *
 * Three rules the routes keep:
 *  - **Identity is the principal.** No route reads an actor from a body or a query string; the
 *    authenticator says who is calling and the handlers are given that and only that (ADR-008).
 *  - **One connection per request**, opened from [Deps.connect] and closed whatever happens; the
 *    handlers own their transactions.
 *  - **A replay returns what it returned.** The stored response carries its outcome, and the HTTP
 *    status is derived from it, so a replayed refusal is a refusal the second time too.
 */
public class Deps(
    public val connect: () -> Connection,
    public val authenticator: Authenticator,
    public val now: () -> Instant = { Instant.now() },
)

private class Http(val status: Int, val body: String)

public fun Application.thro(deps: Deps) {
    val handlers: Map<String, suspend (ApplicationCall, Principal?) -> Http> = mapOf(
        "health" to { _, _ -> health(deps) },
        "openapi" to { _, _ -> Http(200, Contract.openApi()) },
        "commands" to { call, p -> withConnection(deps) { c -> command(c, p!!, call.request.headers["X-Thro-Device"], call.receiveText()) } },
        "me.inbox" to { _, p -> withConnection(deps) { c -> Http(200, inboxJson(Secretary(c).inboxForPlayer(p!!.subject, deps.now()))) } },
        "team.inbox" to { call, p -> withConnection(deps) { c -> teamInbox(c, p!!, call.parameters["teamId"], deps.now()) } },
        "me.discovery" to { call, p -> withConnection(deps) { c -> discovery(c, p!!, call.request.queryParameters["from"], call.request.queryParameters["to"], call.request.queryParameters["locality"], deps.now()) } },
    )
    // The registry and the handlers are held to each other at start, not discovered at first call.
    val missing = Contract.endpoints.map { it.id }.filter { it !in handlers }
    val orphaned = handlers.keys.filter { id -> Contract.endpoints.none { it.id == id } }
    check(missing.isEmpty() && orphaned.isEmpty()) { "contract and handlers disagree: missing $missing, orphaned $orphaned" }

    routing {
        for (e in Contract.endpoints) {
            val handle: suspend (ApplicationCall) -> Unit = { call ->
                val principal = deps.authenticator.authenticate { name -> call.request.headers[name] }
                val out = if (e.authenticated && principal == null) {
                    Http(401, """{"error":"no principal"}""")
                } else {
                    try {
                        handlers.getValue(e.id)(call, principal)
                    } catch (x: IllegalArgumentException) {
                        Http(400, """{"error":${Contract.q(x.message ?: "malformed")}}""")
                    } catch (x: java.time.DateTimeException) {
                        // A date the caller could not write is the caller's error, not the server's.
                        Http(400, """{"error":${Contract.q("a date-time must be ISO-8601: " + (x.message ?: "unparseable"))}}""")
                    }
                }
                call.respondText(out.body, ContentType.Application.Json, HttpStatusCode.fromValue(out.status))
            }
            when (e.method) {
                "GET" -> get(e.path) { handle(call) }
                "POST" -> post(e.path) { handle(call) }
                else -> error("unsupported method ${e.method}")
            }
        }
    }
}

private inline fun withConnection(deps: Deps, block: (Connection) -> Http): Http = deps.connect().use(block)

private fun health(deps: Deps): Http = try {
    deps.connect().use { c ->
        val v = Migrations.currentVersion(c)
        val latest = Migrations.files().maxOfOrNull { Migrations.versionOf(it) }
        if (v == null || (latest != null && v < latest)) Http(503, """{"database":"behind the code","schemaVersion":${v ?: "null"},"codeVersion":${latest ?: "null"}}""")
        else Http(200, """{"database":"ok","schemaVersion":"V${"%03d".format(v)}"}""")
    }
} catch (e: Exception) {
    Http(503, """{"database":"unreachable","error":${Contract.q(e.message ?: e::class.simpleName ?: "error")}}""")
}

// --- the one command endpoint -------------------------------------------------------------------

private fun command(c: Connection, principal: Principal, deviceHeader: String?, body: String): Http {
    val device = deviceHeader?.let { runCatching { UUID.fromString(it.trim()) }.getOrNull() }
        ?: return Http(400, """{"error":"X-Thro-Device header must be a UUID"}""")
    val m = try { Json.parseObject(body) } catch (e: Exception) { return Http(400, """{"error":"body is not a JSON object"}""") }
    fun uuid(k: String): UUID = UUID.fromString(str(m, k))
    fun int(k: String): Int = (m[k] as? Number)?.toInt() ?: throw IllegalArgumentException("$k must be an integer")
    val commandId = uuid("commandId")
    return when (val type = m["type"]) {
        "RecordVisit" -> visit(
            CommandHandler(c).handle(
                VisitCommand(
                    commandId = commandId, matchId = uuid("matchId"), deviceId = device,
                    deviceSeq = (m["deviceSeq"] as? Number)?.toLong() ?: throw IllegalArgumentException("deviceSeq must be an integer"),
                    actorId = principal.subject, actorRole = "participant", correlationId = UUID.randomUUID(),
                    player = str(m, "player"), visitTotal = int("visitTotal"),
                    dartsUsed = (m["dartsUsed"] as? Number)?.toInt(), dartsAtDouble = (m["dartsAtDouble"] as? Number)?.toInt(),
                    occurredAt = str(m, "occurredAt"), occurredTz = (m["occurredTz"] as? String) ?: "Europe/London",
                    clientEffect = m["clientEffect"] as? String, engineVersion = (m["engineVersion"] as? String) ?: "unknown",
                ),
            ),
        )
        "RenameTeam" -> organisational(OrganisationCommands(c).handle(
            OrganisationCommands.Command.RenameTeam(commandId, device, principal.subject, uuid("teamId"), str(m, "to"), int("expectedVersion")),
        ))
        "RearrangeFixture" -> organisational(OrganisationCommands(c).handle(
            OrganisationCommands.Command.RearrangeFixture(
                commandId, device, principal.subject, uuid("fixtureId"), Instant.parse(str(m, "to")), int("expectedVersion"),
                venueId = (m["venueId"] as? String)?.let(UUID::fromString),
            ),
        ))
        "SetAvailability" -> organisational(OrganisationCommands(c).handle(
            OrganisationCommands.Command.SetAvailability(
                commandId, device, principal.subject, uuid("fixtureId"), uuid("playerId"), uuid("teamId"),
                Organisations.Availability.valueOf(str(m, "status").uppercase()), int("expectedVersion"),
            ),
        ))
        "NameLineup" -> organisational(OrganisationCommands(c).handle(
            OrganisationCommands.Command.NameLineup(
                commandId, device, principal.subject, uuid("fixtureId"), uuid("teamId"),
                ((m["players"] as? List<*>) ?: throw IllegalArgumentException("players must be a list")).map { UUID.fromString(it as String) },
                int("expectedVersion"),
            ),
        ))
        null -> Http(400, """{"error":"type is required"}""")
        else -> Http(400, """{"error":${Contract.q("unknown command type $type")}}""")
    }
}

private fun str(m: Map<String, Any?>, k: String): String = (m[k] as? String) ?: throw IllegalArgumentException("$k is required")

private fun organisational(r: OrganisationCommands.Result): Http = when (r) {
    is OrganisationCommands.Result.Applied -> Http(200, """{"outcome":"applied","version":${r.version}}""")
    is OrganisationCommands.Result.Refused -> Http(422, """{"outcome":"refused","why":${Contract.q(r.why)}}""")
    is OrganisationCommands.Result.Stale -> Http(409, """{"outcome":"stale","currentVersion":${r.currentVersion},"current":${r.current}}""")
    is OrganisationCommands.Result.Replayed -> replayed(r.stored)
}

private fun visit(r: CommandResult): Http = when (r) {
    is CommandResult.Applied -> Http(200, """{"outcome":"applied","effect":${Contract.q(r.effect)},"reason":${r.reason?.let(Contract::q) ?: "null"},"deviceSeq":${r.deviceSeq}}""")
    is CommandResult.Refused -> Http(422, """{"outcome":"refused","why":${Contract.q(r.reason)}}""")
    is CommandResult.Gap -> Http(409, """{"outcome":"gap","expectedSeq":${r.expectedSeq}}""")
    is CommandResult.NotThisMatch -> Http(404, """{"outcome":"not_this_match","why":${Contract.q(r.reason)}}""")
    is CommandResult.Replayed -> replayed(r.stored)
}

/** The stored answer, with the status it had: a replayed stale is still a 409. */
private fun replayed(stored: String): Http {
    val outcome = runCatching { Json.parseObject(stored)["outcome"] as? String }.getOrNull()
    val status = when (outcome) {
        "applied" -> 200
        "stale", "gap" -> 409
        "not_this_match" -> 404
        "refused" -> 422
        else -> 200
    }
    return Http(status, stored)
}

// --- reads ------------------------------------------------------------------------------------------

private fun teamInbox(c: Connection, p: Principal, teamId: String?, now: Instant): Http {
    val team = teamId?.let { runCatching { UUID.fromString(it) }.getOrNull() } ?: return Http(400, """{"error":"teamId must be a UUID"}""")
    val decision = Relations(c).decide(p.subject, "team.manage", ObjectRef(ObjectType.TEAM, team.toString()))
    if (!decision.allowed) return Http(403, """{"error":"you do not run this team"}""")
    return Http(200, inboxJson(Secretary(c).inbox(team, now)))
}

private fun inboxJson(sections: Map<thro.competition.InboxSection, List<Secretary.InboxItem>>): String =
    "{\"sections\":{" + sections.entries.joinToString(",") { (s, items) ->
        Contract.q(s.name) + ":[" + items.joinToString(",") { i ->
            """{"taskId":"${i.taskId}","kind":${Contract.q(i.kind)},"reason":${Contract.q(i.reason)},"dueAt":${i.dueAt?.let { Contract.q(it.toString()) } ?: "null"},"state":${Contract.q(i.state)}}"""
        } + "]"
    } + "}}"

private fun discovery(c: Connection, p: Principal, from: String?, to: String?, locality: String?, now: Instant): Http {
    val start = from?.let { Instant.parse(it) } ?: now
    val end = to?.let { Instant.parse(it) } ?: start.plus(60, ChronoUnit.DAYS)
    val sections = Discovery(c).forPlayer(p.subject, start, end, locality)
    val body = "{\"sections\":{" + sections.entries.joinToString(",") { (s, cards) ->
        Contract.q(s.name) + ":[" + cards.joinToString(",") { card ->
            """{"eventId":"${card.eventId}","name":${Contract.q(card.name)},"tournament":${card.tournamentName?.let(Contract::q) ?: "null"},"venue":${card.venueName?.let(Contract::q) ?: "null"},"locality":${card.locality?.let(Contract::q) ?: "null"},"startsAt":${Contract.q(card.startsAt.toString())},"entriesCloseAt":${card.entriesCloseAt?.let { Contract.q(it.toString()) } ?: "null"},"entrantKind":${Contract.q(card.entrantKind)},"access":${Contract.q(card.access)},"capacity":${card.capacity ?: "null"},"spotsRemaining":${card.spotsRemaining ?: "null"},"entered":${card.entered},"qualifies":${card.qualifies},"series":[${card.seriesLabels.joinToString(",") { Contract.q(it) }}],"reasons":[${card.reasons.joinToString(",") { Contract.q(it) }}]}"""
        } + "]"
    } + "}}"
    return Http(200, body)
}
