package thro.api.http

import thro.api.Uploads

import thro.engine.PlayerId

import thro.engine.StructureMode

import thro.engine.Structure

import thro.engine.OutRule

import thro.engine.InRule

import thro.engine.MatchFormat

import io.ktor.http.ContentType
import io.ktor.http.HttpStatusCode
import io.ktor.server.application.Application
import io.ktor.server.application.ApplicationCall
import io.ktor.server.application.ApplicationStopped
import io.ktor.server.application.call
import io.ktor.server.application.install
import io.ktor.server.request.receiveText
import io.ktor.server.response.respondText
import io.ktor.server.routing.delete
import io.ktor.server.routing.get
import io.ktor.server.routing.post
import io.ktor.server.routing.put
import io.ktor.server.routing.routing
import java.sql.Connection
import java.time.Instant
import java.time.temporal.ChronoUnit
import java.util.UUID
import thro.api.Accounts
import thro.api.CommandHandler
import thro.api.CommandResult
import thro.api.Discovery
import thro.api.Events
import thro.api.Friends
import thro.api.Teams
import thro.api.Leagues
import thro.api.Grants
import thro.api.IdTokenVerifier
import thro.api.JwkSource
import thro.api.Provider
import thro.api.RelyingParty
import thro.api.WebAuthn
import java.util.Base64
import thro.api.MatchRecords
import thro.api.Safety
import thro.api.Matches
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
    /** Sign-in providers this server accepts, each with THRØ's client id at that provider. */
    public val providers: Map<Provider, String> = emptyMap(),
    /** Where the providers' keys come from; a test supplies its own. */
    public val keys: JwkSource = JwkSource { _, _ -> null },
    /** Passkeys: this server's relying party, or null when passkeys are not configured. */
    public val relyingParty: RelyingParty? = null,
    /** Apple app ids (TEAMID.bundleid) served in webcredentials, so iOS offers passkeys for this host. */
    public val appleAppIds: List<String> = emptyList(),
    /** The allowance for routes a stranger may call: thirty a minute per address and per device by default. */
    public val limiter: RateLimiter = RateLimiter(),
    /** How often a stream re-reads the log, and how often it pings a quiet client (ADR-007: fifteen seconds). */
    public val streamPoll: java.time.Duration = java.time.Duration.ofSeconds(1),
    public val streamHeartbeat: java.time.Duration = java.time.Duration.ofSeconds(15),
    /**
     * The accounts that may read the moderation queue and answer a report (PD-050).
     *
     * Named at boot rather than held in a table. THRØ has no staff and no admin role, and a list in the
     * database would be a list somebody holding a session could eventually add themselves to; inventing
     * either to make this route work would be inventing product behaviour. Empty by default, so a server
     * nobody has named a moderator for refuses everyone rather than admitting the first caller.
     */
    public val moderators: Set<UUID> = emptySet(),
)

private class Http(val status: Int, val body: String)

/** One request: its call, the principal the authenticator found, its bounded body, and one lazily opened connection. */
/**
 * The database roles a request may run under (ADR-011: per-module roles). The connection is
 * opened as the deploy's one user, which holds all of them; every request narrows itself to the
 * module it is for before it touches a table, so a handler that reaches past its module fails on
 * a grant rather than succeeding by accident. The names are constants, never input.
 */
internal enum class DbRole(val sql: String) { COMPETITION("app_competition"), MATCH("app_match"), READ("app_read"), TRUST("app_trust") }

private class Req(val call: ApplicationCall, val body: String, private val deps: Deps) {
    var principal: Principal? = null
    var role: DbRole = DbRole.COMPETITION
    private var conn: Connection? = null
    private var applied: DbRole? = null
    fun connection(): Connection {
        val c = conn ?: deps.connect().also { conn = it }
        if (applied != role) {
            c.createStatement().use { it.execute("SET ROLE " + role.sql) }
            applied = role
        }
        return c
    }
    fun close() { conn?.close() }
}

public fun Application.thro(deps: Deps) {
    val verifier = IdTokenVerifier(deps.keys, deps.now)
    // One LISTEN connection for every open stream (V036), held only while somebody is watching and
    // told to go when the server does.
    val notifier = MatchNotifier(deps.connect)
    monitor.subscribe(ApplicationStopped) { notifier.stop() }
    val handlers: Map<String, (Req) -> Http> = mapOf(
        "auth.apple" to { r -> signIn(r.connection(), deps, verifier, Provider.APPLE, r.body, r.principal) },
        "auth.google" to { r -> signIn(r.connection(), deps, verifier, Provider.GOOGLE, r.body, r.principal) },
        "auth.refresh" to { r -> refresh(r.connection(), deps, r.body) },
        "passkey.register.options" to { r -> passkeyRegisterOptions(r.connection(), deps, r.principal, r.body) },
        "passkey.register" to { r -> passkeyRegister(r.connection(), deps, r.principal, r.body) },
        "passkey.options" to { r -> passkeyOptions(r.connection(), deps, r.body) },
        "passkey.assert" to { r -> passkeyAssert(r.connection(), deps, r.body) },
        "aasa" to { _ -> if (deps.appleAppIds.isEmpty()) Http(404, """{"error":"no app ids configured"}""") else Http(200, """{"webcredentials":{"apps":[${deps.appleAppIds.joinToString(",") { Contract.q(it) }}]}}""") },
        "auth.logout" to { r -> Http(200, """{"revoked":${Accounts(r.connection(), deps.now).logout(bearer(r.call) ?: "")}}""") },
        "matches.upload" to { r -> r.role = DbRole.MATCH; upload(r.connection(), deps, r.principal!!, r.body) },
        // A sent match, onward (PD-043): the sender's code for the other seat, the other player's claim
        // with it and their answer for the result, and what either of them reads back. The answer is the
        // trust module's to write; everything handed back is read as the read role.
        "matches.code" to { r -> recordly { MatchRecords(r.connection(), deps.now).let { m -> Http(200, m.json(m.codeFor(r.principal!!.subject, UUID.fromString(r.call.parameters["matchId"])))) } } },
        "matches.claim" to { r ->
            recordly {
                val claimed = MatchRecords(r.connection(), deps.now).claim(r.principal!!.subject, str(Json.parseObject(r.body), "code"))
                r.role = DbRole.READ
                matchRead(r, deps, claimed)
            }
        },
        "matches.one" to { r -> r.role = DbRole.READ; matchRead(r, deps, UUID.fromString(r.call.parameters["matchId"])) },
        "matches.mine" to { r -> r.role = DbRole.READ; MatchRecords(r.connection(), deps.now).let { m -> Http(200, m.json(m.mine(r.principal!!.subject))) } },
        "matches.answer" to { r ->
            recordly {
                val id = UUID.fromString(r.call.parameters["matchId"])
                val agree = Json.parseObject(r.body)["agree"] as? Boolean ?: throw IllegalArgumentException("agree must be true or false")
                val phone = r.call.request.headers["X-Thro-Device"]?.let { runCatching { UUID.fromString(it) }.getOrNull() }
                    ?: throw IllegalArgumentException("X-Thro-Device must name the phone that is answering")
                r.role = DbRole.TRUST
                MatchRecords(r.connection(), deps.now).answer(r.principal!!.subject, id, phone, agree)
                r.role = DbRole.READ
                matchRead(r, deps, id)
            }
        },
        "me" to { r -> profile(r.connection(), deps, r.principal!!) },
        "me.erase" to { r -> erase(r.connection(), deps, r.principal!!) },
        "me.profile" to { r ->
            val account = r.principal!!.accountId
            if (account == null) Http(403, """{"error":"the development principal has no account"}""")
            else {
                val m = Json.parseObject(r.body)
                (m["displayName"] as? String)?.let { Accounts(r.connection(), deps.now).setDisplayName(account, it) }
                (m["ageBand"] as? String)?.let { Friends(r.connection(), deps.now).declareAge(account, it) }
                if (m["displayName"] == null && m["ageBand"] == null) Http(400, """{"error":"displayName or ageBand"}""") else profile(r.connection(), deps, r.principal!!)
            }
        },
        "teams.create" to { r -> teamly { val m = Json.parseObject(r.body); Teams(r.connection(), deps.now).let { Http(200, it.json(it.create(r.principal!!.subject, str(m, "name"), m["locality"] as? String))) } } },
        "teams.mine" to { r -> Teams(r.connection(), deps.now).let { Http(200, it.json(it.mine(r.principal!!.subject))) } },
        "teams.front" to { r -> r.role = DbRole.READ; val id = UUID.fromString(r.call.parameters["teamId"]); Teams(r.connection(), deps.now).let { t -> t.front(id, r.principal?.subject)?.let { Http(200, t.json(it)) } ?: Http(404, """{"error":"no such team"}""") } },
        "teams.invite" to { r -> teamly(403) { Teams(r.connection(), deps.now).let { Http(200, it.json(it.invite(r.principal!!.subject, UUID.fromString(r.call.parameters["teamId"])))) } } },
        "venues" to { r -> r.role = DbRole.READ; val q = r.call.request.queryParameters["q"]?.trim().orEmpty(); if (q.length < 2) Http(400, """{"error":"q: at least two characters"}""") else Teams(r.connection(), deps.now).let { Http(200, it.venuesJson(it.venues(q, r.call.request.queryParameters["locality"]))) } },
        "teams.home" to { r -> teamly(403) { val m = Json.parseObject(r.body); Teams(r.connection(), deps.now).let { Http(200, it.json(it.setHome(r.principal!!.subject, UUID.fromString(r.call.parameters["teamId"]), (m["venueId"] as? String)?.let(UUID::fromString), m["name"] as? String, m["locality"] as? String))) } } },
        "teams.join" to { r -> teamly(409) { Teams(r.connection(), deps.now).let { Http(200, it.json(it.join(r.principal!!.subject, str(Json.parseObject(r.body), "code")))) } } },
        // PD-045: the admin names the captain or vice-captain; a refusal says why, 403 when not the admin.
        "teams.role" to { r ->
            teamly(422) {
                val m = Json.parseObject(r.body)
                val member = try { UUID.fromString(str(m, "memberId")) } catch (e: IllegalArgumentException) { throw IllegalArgumentException("memberId must be a UUID") }
                Teams(r.connection(), deps.now).let { Http(200, it.json(it.assign(r.principal!!.subject, UUID.fromString(r.call.parameters["teamId"]), member, str(m, "role")))) }
            }
        },
        // PD-050: reporting, blocking and the terms. A refusal is the sentence the phone shows.
        "safety.report" to { r ->
            withAccount(r) { a ->
                safely {
                    val m = Json.parseObject(r.body)
                    val subject = try { UUID.fromString(str(m, "subjectId")) } catch (e: IllegalArgumentException) { throw IllegalArgumentException("subjectId must be a UUID") }
                    Safety(r.connection(), deps.now).let { s ->
                        Http(200, s.json(s.report(a, str(m, "subjectKind"), subject, str(m, "reason"))))
                    }
                }
            }
        },
        "safety.block" to { r ->
            withAccount(r) { a ->
                safely {
                    val other = try { UUID.fromString(str(Json.parseObject(r.body), "accountId")) } catch (e: IllegalArgumentException) { throw IllegalArgumentException("accountId must be a UUID") }
                    Safety(r.connection(), deps.now).let { s -> s.block(a, other); Http(200, blocksJson(s.blocking(a))) }
                }
            }
        },
        "safety.unblock" to { r ->
            withAccount(r) { a ->
                safely {
                    Safety(r.connection(), deps.now).let { s ->
                        s.lift(a, UUID.fromString(r.call.parameters["accountId"])); Http(200, blocksJson(s.blocking(a)))
                    }
                }
            }
        },
        "safety.blocks" to { r -> withAccount(r) { a -> Http(200, blocksJson(Safety(r.connection(), deps.now).blocking(a))) } },
        // The fourth thing the stores ask for is that somebody answers. Two routes, closed to everyone but
        // the people named to answer: the queue as it should be worked, and the answer itself.
        "safety.queue" to { r ->
            withModerator(r, deps.moderators) { _ -> Http(200, queueJson(Safety(r.connection(), deps.now).queue())) }
        },
        "safety.decide" to { r ->
            withModerator(r, deps.moderators) { a ->
                safely {
                    val m = Json.parseObject(r.body)
                    val report = UUID.fromString(r.call.parameters["reportId"])
                    val decision = Safety(r.connection(), deps.now).decide(report, str(m, "outcome"), str(m, "note"), a)
                    Http(200, """{"decisionId":"$decision","reportId":"$report"}""")
                }
            }
        },
        "me.terms" to { r ->
            withAccount(r) { a ->
                safely {
                    val asked = (Json.parseObject(r.body)["version"] as? String)?.takeIf { it.isNotBlank() } ?: Safety.TERMS_VERSION
                    Safety(r.connection(), deps.now).acceptTerms(a, asked)
                    Http(200, """{"version":${Contract.q(asked)},"accepted":true}""")
                }
            }
        },
        // PD-049: the team's own admin or captain says which league it plays in, and stops saying it.
        "teams.league.say" to { r ->
            teamly(403) {
                val m = Json.parseObject(r.body)
                val league = try { UUID.fromString(str(m, "leagueId")) } catch (e: IllegalArgumentException) { throw IllegalArgumentException("leagueId must be a UUID") }
                Teams(r.connection(), deps.now).let { Http(200, it.json(it.saysItPlaysIn(r.principal!!.subject, UUID.fromString(r.call.parameters["teamId"]), league))) }
            }
        },
        "teams.league.withdraw" to { r ->
            teamly(403) {
                Teams(r.connection(), deps.now).let {
                    Http(200, it.json(it.stopsSayingItPlaysIn(r.principal!!.subject, UUID.fromString(r.call.parameters["teamId"]),
                                                              UUID.fromString(r.call.parameters["leagueId"]))))
                }
            }
        },
        // PD-047: a player takes on a listed league team nobody runs. A refusal is the sentence to show.
        "teams.adopt" to { r -> teamly(409) { Teams(r.connection(), deps.now).let { Http(200, it.json(it.adopt(r.principal!!.subject, UUID.fromString(r.call.parameters["teamId"])))) } } },
        "friends" to { r -> withAccount(r) { a -> Friends(r.connection(), deps.now).let { Http(200, it.json(it.friends(a))) } } },
        "friends.invite" to { r -> withAccount(r) { a -> friendly { Friends(r.connection(), deps.now).invite(a).let { Http(200, """{"code":"${it.code}","expiresAt":"${it.expiresAt}"}""") } } } },
        "friends.accept" to { r -> withAccount(r) { a -> friendly(codeProblem = 409) { Friends(r.connection(), deps.now).accept(a, str(Json.parseObject(r.body), "code")).let { Http(200, """{"friend":{"accountId":"${it.accountId}","displayName":${Contract.q(it.displayName)},"since":"${it.since}"}}""") } } } },
        "friends.remove" to { r -> withAccount(r) { a -> Http(200, """{"removed":${Friends(r.connection(), deps.now).remove(a, UUID.fromString(r.call.parameters["accountId"]))}}""") } },
        "health" to { _ -> health(deps) },
        "openapi" to { _ -> Http(200, Contract.openApi()) },
        "commands" to { r ->
            // A visit is the match module's; everything else on this endpoint is organisational.
            if (r.body.contains("\"RecordVisit\"")) r.role = DbRole.MATCH
            command(r.connection(), r.principal!!, r.call.request.headers["X-Thro-Device"], r.body)
        },
        "me.inbox" to { r -> Http(200, inboxJson(Secretary(r.connection()).inboxForPlayer(r.principal!!.subject, deps.now()))) },
        "team.inbox" to { r -> teamInbox(r.connection(), r.principal!!, r.call.parameters["teamId"], deps.now()) },
        "leagues" to { r -> r.role = DbRole.READ; Http(200, Leagues(r.connection()).let { it.json(it.all(r.call.request.queryParameters["locality"]?.take(80), deps.now())) }) },
        "events" to { r -> r.role = DbRole.READ; Http(200, Events(r.connection()).let { it.json(it.upcoming(r.call.request.queryParameters["from"]?.let { f -> Instant.parse(f) } ?: deps.now())) }) },
        "me.discovery" to { r -> discovery(r.connection(), r.principal!!, r.call.request.queryParameters["from"], r.call.request.queryParameters["to"], r.call.request.queryParameters["locality"], deps.now()) },
    )
    // The registry and the handlers are held to each other at start, not discovered at first call.
    val missing = Contract.endpoints.filter { !it.stream }.map { it.id }.filter { it !in handlers }
    val orphaned = handlers.keys.filter { id -> Contract.endpoints.none { it.id == id } }
    check(missing.isEmpty() && orphaned.isEmpty()) { "contract and handlers disagree: missing $missing, orphaned $orphaned" }

    routing {
        for (e in Contract.endpoints) {
            if (e.stream) { matchStream(e.path, deps, notifier); continue }
            val handle: suspend (ApplicationCall) -> Unit = { call ->
                // The body is bounded before it is read, and read before any connection is held:
                // a declared length over the cap is 413, no declared length is 411, and what
                // arrives is measured again.
                val out: Http = run {
                    // GET and DELETE carry no body, so neither needs a length declared. Requiring
                    // one turned `DELETE /v1/me` into a 411 for every caller that sent no body —
                    // which is every correct caller — and made erasure look broken on the phone.
                    // A body that IS sent is still measured twice, which is what the rule is for.
                    val bodyless = e.method == "GET" || e.method == "DELETE"
                    val body = if (e.method == "GET") "" else {
                        val declared = call.request.headers["Content-Length"]?.toLongOrNull()
                        when {
                            declared == null && !bodyless -> return@run Http(411, """{"error":"Content-Length is required"}""")
                            (declared ?: 0) > MAX_BODY -> return@run Http(413, """{"error":"body over 64 KiB"}""")
                        }
                        val text = call.receiveText()
                        if (text.length > MAX_BODY) return@run Http(413, """{"error":"body over 64 KiB"}""")
                        text
                    }
                    // Routes a stranger may call are rationed per address and per device before any
                    // work is done for them; the answer says how long to wait. The routes that take a
                    // code are rationed the same way, from allowances of their own (CODE_ROUTES).
                    val codeRoute = e.id in CODE_ROUTES
                    if (codeRoute || e.id.startsWith("auth.") || e.id.startsWith("passkey.")) {
                        val address = call.request.headers["X-Forwarded-For"]?.substringBefore(",")?.trim()?.takeIf { it.isNotEmpty() }
                            ?: call.request.local.remoteHost
                        // Signing in names its device in the body. A code route's body is only the code;
                        // the phone names itself in the header every one of its requests carries.
                        val device = if (codeRoute) call.request.headers["X-Thro-Device"]?.takeIf { Regex("[0-9a-fA-F-]{36}").matches(it) }
                                     else Regex("\"deviceId\"\\s*:\\s*\"([0-9a-fA-F-]{36})\"").find(body)?.groupValues?.get(1)
                        val prefix = if (codeRoute) "code:" else ""
                        val wait = listOfNotNull(deps.limiter.take("${prefix}a:$address"), device?.let { deps.limiter.take("${prefix}d:$it") }).maxOrNull()
                        if (wait != null) {
                            call.response.headers.append("Retry-After", wait.toString())
                            val what = if (codeRoute) "too many codes tried" else "too many attempts"
                            return@run Http(429, """{"error":"$what; try again in $wait seconds"}""")
                        }
                    }
                    val req = Req(call, body, deps)
                    try {
                        req.principal = deps.authenticator.authenticate({ name -> call.request.headers[name] }, req::connection)
                        if (e.authenticated && req.principal == null) Http(401, """{"error":"no principal"}""")
                        else handlers.getValue(e.id)(req)
                    } catch (x: IllegalArgumentException) {
                        Http(400, """{"error":${Contract.q(x.message ?: "malformed")}}""")
                    } catch (x: ClassCastException) {
                        Http(400, """{"error":"a field has the wrong type"}""")
                    } catch (x: IndexOutOfBoundsException) {
                        Http(400, """{"error":"the body is not complete JSON"}""")
                    } catch (x: java.time.DateTimeException) {
                        // A date the caller could not write is the caller's error, not the server's.
                        Http(400, """{"error":${Contract.q("a date-time must be ISO-8601: " + (x.message ?: "unparseable"))}}""")
                    } catch (x: IdTokenVerifier.KeysUnavailable) {
                        System.err.println("sign-in: ${x.message}")
                        Http(503, """{"error":"the sign-in provider's keys are unavailable; try again shortly"}""")
                    } catch (x: Accounts.AccountDeleted) {
                        Http(403, """{"error":"this account was deleted"}""")
                    } catch (x: Accounts.SubjectHeldElsewhere) {
                        Http(409, """{"error":"that sign-in already belongs to another account; nobody was signed in"}""")
                    } finally {
                        req.close()
                    }
                }
                call.respondText(out.body, ContentType.Application.Json, HttpStatusCode.fromValue(out.status))
            }
            when (e.method) {
                "GET" -> get(e.path) { handle(call) }
                "POST" -> post(e.path) { handle(call) }
                "PUT" -> put(e.path) { handle(call) }
                // DELETE arrived with erasure (V031) and is the right verb for it: the caller is
                // asking for the thing to stop existing, not for a flag to be set on it.
                "DELETE" -> delete(e.path) { handle(call) }
                else -> error("unsupported method ${e.method}")
            }
        }
    }
}

private const val MAX_BODY: Long = 64 * 1024
private const val MAX_LINEUP: Int = 32

/**
 * Routes that take a code somebody was handed: a friend's, a team's, a match's seat. A code opens
 * something, so guessing one is the attack, and these are rationed like signing in — in allowances of
 * their own, so a run of mistyped codes costs nobody their sign-in.
 */
private val CODE_ROUTES: Set<String> = setOf("friends.accept", "teams.join", "matches.claim")

/** A match-record refusal is an answer: the sentence the phone shows, with the status it carries. */
private fun recordly(block: () -> Http): Http = try { block() } catch (e: MatchRecords.Refused) { Http(e.status, """{"error":${Contract.q(e.why)}}""") }

/** A match as the caller reads it. Anyone not in it is answered as though it did not exist. */
private fun matchRead(r: Req, deps: Deps, matchId: UUID): Http = MatchRecords(r.connection(), deps.now).let { m ->
    m.summary(matchId, r.principal!!.subject)?.let { Http(200, m.json(it)) } ?: Http(404, """{"error":"That match is not one of yours."}""")
}

private fun health(deps: Deps): Http = try {
    deps.connect().use { c ->
        c.createStatement().use { it.execute("SET ROLE " + DbRole.READ.sql) }
        val v = Migrations.currentVersion(c)
        val latest = Migrations.files().maxOfOrNull { Migrations.versionOf(it) }
        if (v == null || (latest != null && v < latest)) Http(503, """{"database":"behind the code","schemaVersion":${v ?: "null"},"codeVersion":${latest ?: "null"}}""")
        else Http(200, """{"database":"ok","schemaVersion":"V${"%03d".format(v)}"}""")
    }
} catch (e: Exception) {
    // The detail — host, user, the driver's words — is for the log, not for an unauthenticated caller.
    System.err.println("healthz: database unreachable: ${e.message}")
    Http(503, """{"database":"unreachable"}""")
}

// --- sign-in and sessions (PD-030) ---------------------------------------------------------------

private fun bearer(call: ApplicationCall): String? =
    call.request.headers["Authorization"]?.trim()?.takeIf { it.startsWith("Bearer ", ignoreCase = true) }?.substring(7)?.trim()

private fun signIn(c: Connection, deps: Deps, verifier: IdTokenVerifier, provider: Provider, body: String, principal: Principal?): Http {
    val clientId = deps.providers[provider] ?: return Http(503, """{"error":${Contract.q("Sign in with ${provider.name.lowercase().replaceFirstChar { it.uppercase() }} is not configured on this server")}}""")
    val m = try { Json.parseObject(body) } catch (e: Exception) { return Http(400, """{"error":"body is not a JSON object"}""") }
    val token = str(m, "idToken")
    val device = try { UUID.fromString(str(m, "deviceId")) } catch (e: IllegalArgumentException) { throw IllegalArgumentException("deviceId must be a UUID") }
    val nonce = m["nonce"] as? String
    return when (val v = verifier.verify(token, provider, clientId, nonce)) {
        is IdTokenVerifier.Result.Rejected -> Http(401, """{"error":${Contract.q("the ID token was not accepted: " + v.why)}}""")
        // With a bearer token, a subject nobody holds is added to the caller's account (PD-032:
        // recovery is a second way in); a subject somebody else holds signs that person in as before.
        is IdTokenVerifier.Result.Verified -> Http(200, sessionJson(Accounts(c, deps.now).signIn(provider.name.lowercase(), v.claims.subject, device, linkTo = principal?.accountId)))
    }
}

// --- passkeys (PD-030's fallback, V025) ------------------------------------------------------------

private fun b64u(s: String): ByteArray = try { Base64.getUrlDecoder().decode(s) } catch (e: IllegalArgumentException) { throw IllegalArgumentException("a WebAuthn field is not base64url") }
private fun b64u(b: ByteArray): String = Base64.getUrlEncoder().withoutPadding().encodeToString(b)
private fun noPasskeys(): Http = Http(503, """{"error":"passkeys are not configured on this server (no relying party)"}""")

private fun passkeyRegisterOptions(c: Connection, deps: Deps, principal: Principal?, body: String): Http {
    val rp = deps.relyingParty ?: return noPasskeys()
    val m = Json.parseObject(body)
    val device = UUID.fromString(str(m, "deviceId"))
    val accounts = Accounts(c, deps.now)
    val ch = accounts.newChallenge("register", device, principal?.accountId)
    // The user id is the account's for life (V026), so a second passkey does not replace the first
    // in the platform's keychain; the live ones are excluded so the platform offers nothing twice.
    val identity = ch.accountId?.let { accounts.passkeyIdentity(it) }
    val userId = identity?.userHandle ?: ch.userHandle!!
    val exclude = identity?.credentialIds.orEmpty().joinToString(",") { """{"type":"public-key","id":${Contract.q(b64u(it))}}""" }
    val name = principal?.accountId?.let { accounts.profile(it)?.displayName } ?: Accounts.PLACEHOLDER_NAME
    return Http(200, """{"challengeId":"${ch.id}","publicKey":{"rp":{"id":${Contract.q(rp.id)},"name":${Contract.q(rp.name)}},"user":{"id":${Contract.q(b64u(userId))},"name":${Contract.q(name)},"displayName":${Contract.q(name)}},"challenge":${Contract.q(b64u(ch.bytes))},"pubKeyCredParams":[{"type":"public-key","alg":-7},{"type":"public-key","alg":-257}],"excludeCredentials":[$exclude],"authenticatorSelection":{"residentKey":"required","userVerification":"required"},"attestation":"none","timeout":300000}}""")
}

private fun passkeyRegister(c: Connection, deps: Deps, principal: Principal?, body: String): Http {
    val rp = deps.relyingParty ?: return noPasskeys()
    val m = Json.parseObject(body)
    val device = UUID.fromString(str(m, "deviceId"))
    val accounts = Accounts(c, deps.now)
    val ch = accounts.takeChallenge(UUID.fromString(str(m, "challengeId")), "register", device)
        ?: return Http(401, """{"error":"the registration was not accepted: unknown, expired or already used challenge"}""")
    // The challenge decided whose passkey this is when it was issued; a bearer presented now does not
    // change that — and a signed-in caller finishing an anonymous challenge would land in a new account
    // while believing they had added a passkey to theirs, so that is refused too.
    if (ch.accountId != null && ch.accountId != principal?.accountId) return Http(401, """{"error":"the registration was not accepted: this challenge belongs to another account"}""")
    if (ch.accountId == null && principal?.accountId != null) return Http(409, """{"error":"this challenge was issued to nobody; to add a passkey to your account, ask for options while signed in"}""")
    val credentialId = b64u(str(m, "credentialId"))
    return when (val r = WebAuthn.register(b64u(str(m, "clientDataJSON")), b64u(str(m, "attestationObject")), ch.bytes, rp)) {
        is WebAuthn.Outcome.Bad -> Http(401, """{"error":${Contract.q("the registration was not accepted: " + r.why)}}""")
        is WebAuthn.Outcome.Ok -> {
            if (!r.value.credentialId.contentEquals(credentialId)) return Http(401, """{"error":"the registration was not accepted: credential id does not match the authenticator data"}""")
            if (accounts.passkey(credentialId) != null) return Http(401, """{"error":"the registration was not accepted: this passkey is already registered"}""")
            try {
                Http(200, sessionJson(accounts.registerPasskey(ch.accountId, ch.userHandle, r.value.credentialId, r.value.publicKeyCose, r.value.signCount, device)))
            } catch (e: org.postgresql.util.PSQLException) {
                if (e.sqlState == "23505") Http(401, """{"error":"the registration was not accepted: this passkey is already registered"}""") else throw e
            }
        }
    }
}

private fun passkeyOptions(c: Connection, deps: Deps, body: String): Http {
    val rp = deps.relyingParty ?: return noPasskeys()
    val device = UUID.fromString(str(Json.parseObject(body), "deviceId"))
    val ch = Accounts(c, deps.now).newChallenge("assert", device)
    return Http(200, """{"challengeId":"${ch.id}","publicKey":{"challenge":${Contract.q(b64u(ch.bytes))},"rpId":${Contract.q(rp.id)},"userVerification":"required","timeout":300000}}""")
}

private fun passkeyAssert(c: Connection, deps: Deps, body: String): Http {
    val rp = deps.relyingParty ?: return noPasskeys()
    val m = Json.parseObject(body)
    val device = UUID.fromString(str(m, "deviceId"))
    val accounts = Accounts(c, deps.now)
    val ch = accounts.takeChallenge(UUID.fromString(str(m, "challengeId")), "assert", device)
        ?: return Http(401, """{"error":"the sign-in was not accepted: unknown, expired or already used challenge"}""")
    val passkey = accounts.passkey(b64u(str(m, "credentialId")))
        ?: return Http(401, """{"error":"the sign-in was not accepted: unknown passkey"}""")
    return when (val r = WebAuthn.assert(b64u(str(m, "clientDataJSON")), b64u(str(m, "authenticatorData")), b64u(str(m, "signature")), ch.bytes, rp, passkey.publicKeyCose, passkey.signCount)) {
        is WebAuthn.Outcome.Bad -> Http(401, """{"error":${Contract.q("the sign-in was not accepted: " + r.why)}}""")
        is WebAuthn.Outcome.Ok -> Http(200, sessionJson(accounts.signInWithPasskey(passkey, r.value, device)))
    }
}

private fun refresh(c: Connection, deps: Deps, body: String): Http {
    val m = try { Json.parseObject(body) } catch (e: Exception) { return Http(400, """{"error":"body is not a JSON object"}""") }
    val token = str(m, "refreshToken")
    return when (val r = Accounts(c, deps.now).refresh(token)) {
        is Accounts.Refreshed.Rotated -> Http(200, sessionJson(r.session))
        Accounts.Refreshed.Reused -> Http(401, """{"error":"that refresh token had already been used; the session family is revoked — sign in again"}""")
        Accounts.Refreshed.Expired -> Http(401, """{"error":"the session has expired; sign in again"}""")
        Accounts.Refreshed.Unknown -> Http(401, """{"error":"unknown refresh token"}""")
    }
}

private fun sessionJson(s: Accounts.Session): String =
    """{"accountId":"${s.accountId}","playerId":${s.playerId?.let { "\"$it\"" } ?: "null"},"accessToken":${Contract.q(s.accessToken)},"refreshToken":${Contract.q(s.refreshToken)},"accessExpiresAt":${Contract.q(s.accessExpiresAt.toString())},"created":${s.created}}"""

/** A route that needs an account behind the principal: the development principal has none, and says so. */
private fun withAccount(r: Req, block: (UUID) -> Http): Http {
    val account = r.principal!!.accountId ?: return Http(403, """{"error":"the development principal has no account"}""")
    return block(account)
}

/**
 * A route only somebody who answers reports may call (PD-050).
 *
 * Two refusals rather than one, because they are two different truths: a principal with no account behind it
 * cannot be a moderator, and an account that is not on the list is not one either. Neither answer says who is.
 */
private fun withModerator(r: Req, moderators: Set<UUID>, block: (UUID) -> Http): Http {
    val account = r.principal!!.accountId ?: return Http(403, """{"error":"the development principal has no account"}""")
    if (account !in moderators) return Http(403, """{"error":"reports are answered by the people named to answer them"}""")
    return block(account)
}

/** The queue for whoever works it: what was reported, why, when the answer is due, and how often it has been answered. */
private fun queueJson(queued: List<Safety.Queued>): String =
    "{\"reports\":[" + queued.joinToString(",") { q ->
        """{"reportId":"${q.report.reportId}","subjectKind":${Contract.q(q.report.subjectKind)},""" +
            """"subjectId":"${q.report.subjectId}","reason":${Contract.q(q.report.reason)},""" +
            """"urgent":${q.report.urgent},"reportedAt":"${q.report.reportedAt}",""" +
            """"answerDueAt":"${q.report.answerDueAt}","decisions":${q.decisions}}"""
    } + "]}"

/** A safety refusal is an answer too: the sentence to show, with 400 unless the refusal names a status. */
private fun safely(status: Int = 400, block: () -> Http): Http = try { block() } catch (e: Safety.Refused) {
    Http(e.status ?: status, """{"error":${Contract.q(e.why)}}""")
}

/** The accounts somebody has blocked. Ids only: a block list names nobody it does not have to. */
private fun blocksJson(ids: List<java.util.UUID>): String =
    "{\"blocked\":[" + ids.joinToString(",") { "\"$it\"" } + "]}"

/** A team refusal is an answer too: the sentence, with the status the route names. */
private fun teamly(status: Int = 400, block: () -> Http): Http = try { block() } catch (e: Teams.Refused) { Http(e.status ?: status, """{"error":${Contract.q(e.why)}}""") }

/** A friends refusal is an answer: the sentence the phone shows, with the status that says which kind. */
private fun friendly(codeProblem: Int = 403, block: () -> Http): Http = try { block() } catch (e: Friends.Refused) {
    val status = if (e.why.startsWith("Friends on THRØ are for adults") || e.why.startsWith("Say you are 18")) 403 else codeProblem
    Http(status, """{"error":${Contract.q(e.why)}}""")
}

private fun profile(c: Connection, deps: Deps, p: Principal): Http {
    // PD-050: the terms in force travel with the profile the phone already reads, rather than behind a route
    // of their own. A fact the client has to remember to go and ask for is a fact some build ships without.
    val terms = """"termsVersion":${Contract.q(Safety.TERMS_VERSION)}"""
    val account = p.accountId
        ?: return Http(200, """{"accountId":null,"playerId":"${p.subject}","displayName":null,"named":false,"ageBand":"unknown",$terms,"acceptedTerms":false,"note":"development principal: no account"}""")
    val pr = Accounts(c, deps.now).profile(account) ?: return Http(404, """{"error":"no such account"}""")
    val accepted = Safety(c, deps.now).hasAcceptedTerms(account)
    return Http(200, """{"accountId":"${pr.accountId}","playerId":${pr.playerId?.let { "\"$it\"" } ?: "null"},"displayName":${Contract.q(pr.displayName)},"named":${pr.named},"ageBand":${Contract.q(pr.ageBand)},"credentials":${pr.credentials},$terms,"acceptedTerms":$accepted}""")
}

/**
 * Erasure (V031). A development principal has no account and so has nothing to erase; saying so is
 * better than a 500 from a null.
 */
private fun erase(c: Connection, deps: Deps, p: Principal): Http {
    val account = p.accountId ?: return Http(400, """{"error":"this principal has no account to erase"}""")
    return try {
        val e = Accounts(c, deps.now).erase(account)
        Http(200, """{"erased":true,"credentials":${e.credentials},"sessions":${e.sessions},"devices":${e.devices},""" +
            """"friendships":${e.friendships},"claims":${e.claims},"consents":${e.consents}}""")
    } catch (ex: Exception) {
        // The function raises for an account that is already gone or was never there. Neither is a
        // fault in the caller's request beyond its timing, and neither should read as a crash.
        val why = ex.message ?: "the account could not be erased"
        if (why.contains("already erased")) Http(409, """{"error":"this account was already erased"}""")
        else if (why.contains("no such account")) Http(404, """{"error":"no such account"}""")
        else throw ex
    }
}

/**
 * Sending a match (PD-040). The caller is one seat; the other is minted. Every refusal is a sentence,
 * because a phone holding a match it cannot send needs to know whether to try again or to stop.
 */
private fun upload(c: Connection, deps: Deps, p: Principal, body: String): Http {
    val m = try { Json.parseObject(body) } catch (e: Exception) { return Http(400, """{"error":"body is not a JSON object"}""") }
    fun uuid(k: String): UUID = try { UUID.fromString(str(m, k)) } catch (e: IllegalArgumentException) { throw IllegalArgumentException("$k must be a UUID") }
    val f = m["format"] as? Map<*, *> ?: return Http(400, """{"error":"format is required"}""")
    fun fstr(k: String) = f[k] as? String ?: throw IllegalArgumentException("format.$k is required")
    fun fint(k: String) = (f[k] as? Number)?.toInt() ?: throw IllegalArgumentException("format.$k is required")

    val format = try {
        MatchFormat(
            startingScore = fint("startingScore"),
            inRule = InRule.valueOf(fstr("inRule").uppercase()),
            outRule = OutRule.valueOf(fstr("outRule").uppercase()),
            legs = Structure(StructureMode.valueOf(fstr("legsMode").uppercase()), fint("legsTarget")),
            throwFirst = PlayerId(fstr("throwFirst")),
        )
    } catch (e: Exception) {
        return Http(400, """{"error":${Contract.q("that match format is not one THRØ can read: " + (e.message ?: "unreadable"))}}""")
    }

    val rows: List<Uploads.Row> = (m["rows"] as? List<*>)?.map { raw ->
        val r = raw as? Map<*, *> ?: throw IllegalArgumentException("every row is an object")
        Uploads.Row(
            deviceSeq = (r["deviceSeq"] as? Number)?.toLong() ?: throw IllegalArgumentException("deviceSeq must be an integer"),
            kind = r["kind"] as? String ?: throw IllegalArgumentException("kind must be visit, retraction, retirement or abandonment"),
            // An abandonment names nobody, so it may come without a seat; every other row says one.
            seat = r["seat"] as? String ?: if (r["kind"] == "abandonment") "home" else throw IllegalArgumentException("seat must be home or away"),
            visitTotal = (r["visitTotal"] as? Number)?.toInt(),
            correctsSeq = (r["correctsSeq"] as? Number)?.toLong(),
            occurredAt = try { Instant.parse(r["occurredAt"] as? String ?: "") } catch (e: Exception) { throw IllegalArgumentException("occurredAt must be an instant") },
            occurredTz = r["occurredTz"] as? String ?: "Europe/London",
        )
    } ?: return Http(400, """{"error":"rows is required"}""")

    return when (val out = Uploads(c, deps.now).receive(p.subject, uuid("deviceId"), uuid("matchId"), str(m, "seat"), format, rows)) {
        is Uploads.Result.Refused -> Http(422, """{"error":${Contract.q(out.why)}}""")
        is Uploads.Result.Stored -> Http(200, """{"matchId":"${out.matchId}","opponentId":"${out.opponentId}","visits":${out.visits},""" +
            """"retractions":${out.retractions},"alreadyHeld":${out.alreadyHeld},"opened":${out.opened},""" +
            """"ending":${out.ending?.let { "\"$it\"" } ?: "null"},"selfReported":true}""")
    }
}

// --- the one command endpoint -------------------------------------------------------------------

private fun command(c: Connection, principal: Principal, deviceHeader: String?, body: String): Http {
    val device = deviceHeader?.let { runCatching { UUID.fromString(it.trim()) }.getOrNull() }
        ?: return Http(400, """{"error":"X-Thro-Device header must be a UUID"}""")
    val m = try { Json.parseObject(body) } catch (e: Exception) { return Http(400, """{"error":"body is not a JSON object"}""") }
    fun uuid(k: String): UUID = try { UUID.fromString(str(m, k)) } catch (e: IllegalArgumentException) { throw IllegalArgumentException("$k must be a UUID") }
    fun long(k: String): Long = (m[k] as? Long) ?: throw IllegalArgumentException("$k must be an integer")
    fun int(k: String): Int {
        val v = long(k)
        require(v in Int.MIN_VALUE..Int.MAX_VALUE) { "$k is out of range" }
        return v.toInt()
    }
    fun intOrNull(k: String): Int? = m[k]?.let { int(k) }
    val commandId = uuid("commandId")
    return when (val type = m["type"]) {
        "RecordVisit" -> {
            val matchId = uuid("matchId")
            // The role the evidence is annotated with is what the store knows about the caller:
            // a participant of the match, else the role their grant names, else a stranger's
            // "participant" that the handler will refuse before it is written.
            val role = if (Matches(c).load(matchId)?.participants?.contains(principal.subject) == true) "participant"
            else Grants(c).roleFor(principal.subject, device, matchId) ?: "participant"
            visit(
            CommandHandler(c).handle(
                VisitCommand(
                    commandId = commandId, matchId = matchId, deviceId = device,
                    deviceSeq = long("deviceSeq"),
                    actorId = principal.subject, actorRole = role, correlationId = UUID.randomUUID(),
                    player = str(m, "player"), visitTotal = int("visitTotal"),
                    dartsUsed = intOrNull("dartsUsed"), dartsAtDouble = intOrNull("dartsAtDouble"),
                    occurredAt = str(m, "occurredAt"), occurredTz = (m["occurredTz"] as? String) ?: "Europe/London",
                    clientEffect = m["clientEffect"] as? String, engineVersion = (m["engineVersion"] as? String) ?: "unknown",
                ),
            ),
            )
        }
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
                ((m["players"] as? List<*>) ?: throw IllegalArgumentException("players must be a list"))
                    .also { require(it.size <= MAX_LINEUP) { "a lineup names at most $MAX_LINEUP players" } }
                    .map { UUID.fromString((it as? String) ?: throw IllegalArgumentException("players must be UUID strings")) },
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
