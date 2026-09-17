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
import java.time.LocalDate
import java.time.temporal.ChronoUnit
import java.util.UUID
import thro.api.Accounts
import thro.api.CommandHandler
import thro.api.Consent
import thro.api.CommandResult
import thro.api.Discovery
import thro.api.Events
import thro.api.Fixtures
import thro.api.LiveBoard
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
import thro.api.LeagueTable
import thro.api.Reader
import thro.api.Reading
import thro.api.SeasonHistory
import thro.api.SystemOne
import thro.api.Understanding
import thro.api.Safety
import thro.api.Matches
import thro.api.Json
import thro.api.Migrations
import thro.api.OrganisationCommands
import thro.api.Organisations
import thro.api.SeasonPlanning
import thro.api.TeamFixtures
import thro.api.Ratings
import thro.api.Registrations
import thro.api.Rearrangements
import thro.api.Editions
import thro.api.Friendlies
import thro.api.LeagueActs
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
    /** The web's client ids at the same providers (PD-116): Apple's Services ID, Google's Web client. Optional. */
    public val webProviders: Map<Provider, String> = emptyMap(),
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
    /**
     * THRØ's reader of what people write (PD-118): a System One model asked narrow, typed questions about a report and
     * about a chosen name, whose answers sit beside the report for the person who answers it. Null — the default, and
     * the state until a key is configured — means no reading, and nothing else changes.
     */
    public val reader: Reader? = null,
    /** The same model, asked general questions (PD-119: Tell THRØ). Null means the desk cannot read a sentence. */
    public val systemOne: SystemOne? = null,
)

private class Http(val status: Int, val body: String)

/** One request: its call, the principal the authenticator found, its bounded body, and one lazily opened connection. */
/**
 * The database roles a request may run under (ADR-011: per-module roles). The connection is
 * opened as the deploy's one user, which holds all of them; every request narrows itself to the
 * module it is for before it touches a table, so a handler that reaches past its module fails on
 * a grant rather than succeeding by accident. The names are constants, never input.
 */
internal enum class DbRole(val sql: String) { COMPETITION("app_competition"), MATCH("app_match"), READ("app_read"), TRUST("app_trust"), RATING("app_rating") }

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
        // webcredentials: iOS offers this host's passkeys to the app. applinks (PD-117): a link to /link/<code> — a
        // screen's sign-in code — opens the app rather than Safari, so the phone that holds the account approves it.
        // PD-127: and a league, a tournament night and a team, whose pages at this host are the same address the app opens.
        "aasa" to { _ ->
            if (deps.appleAppIds.isEmpty()) Http(404, """{"error":"no app ids configured"}""")
            else {
                val apps = deps.appleAppIds.joinToString(",") { Contract.q(it) }
                Http(200, """{"webcredentials":{"apps":[$apps]},"applinks":{"details":[{"appIDs":[$apps],"components":[{"/":"/link/*","comment":"a screen's sign-in code, approved by the phone (PD-117)"},{"/":"/league/*","comment":"a league on THRØ (PD-127)"},{"/":"/event/*","comment":"a tournament night (PD-127)"},{"/":"/team/*","comment":"a team on THRØ (PD-127)"}]}]}}""")
            }
        },
        // PD-114: a screen signs in by the phone that holds the account.
        "auth.link.start" to { r ->
            val m = Json.parseObject(r.body)
            val device = (m["deviceId"] as? String)?.let { runCatching { UUID.fromString(it) }.getOrNull() } ?: throw IllegalArgumentException("deviceId is required")
            val link = Accounts(r.connection(), deps.now).startLink(device)
            Http(200, """{"linkId":"${link.linkId}","code":${Contract.q(link.code)},"expiresAt":"${link.expiresAt}"}""")
        },
        "auth.link.approve" to { r ->
            val accounts = Accounts(r.connection(), deps.now)
            val account = r.principal!!.accountId ?: return@to Http(401, """{"error":"approving a screen needs a signed-in account, not a development principal"}""")
            try { accounts.approveLink(r.call.parameters["code"] ?: "", account); Http(200, """{"approved":true}""") }
            catch (e: Accounts.LinkNotFound) { Http(404, """{"error":"THRØ has no such code, or it has expired. Ask the screen for a new one."}""") }
            catch (e: Accounts.LinkAlreadyApproved) { Http(409, """{"error":"That code was already approved."}""") }
            catch (e: Accounts.AccountSuspended) { Http(403, """{"error":"This account is suspended."}""") }
        },
        "auth.link.claim" to { r ->
            val device = r.call.request.queryParameters["deviceId"]?.let { runCatching { UUID.fromString(it) }.getOrNull() } ?: throw IllegalArgumentException("deviceId is required")
            val accounts = Accounts(r.connection(), deps.now)
            try { Http(200, sessionJson(accounts.claimLink(UUID.fromString(r.call.parameters["linkId"]), device))) }
            catch (e: Accounts.LinkWaiting) { Http(202, """{"state":"waiting"}""") }
            catch (e: Accounts.LinkNotFound) { Http(404, """{"error":"no such link for this device"}""") }
            catch (e: Accounts.LinkSpent) { Http(410, """{"error":"This link was used or has expired. Ask for a new code."}""") }
        },
        // PD-116: which providers the web may offer, by the client ids configured for it; nothing secret.
        "auth.providers" to { _ ->
            Http(200, """{"apple":${deps.webProviders[Provider.APPLE]?.let { Contract.q(it) } ?: "null"},"google":${deps.webProviders[Provider.GOOGLE]?.let { Contract.q(it) } ?: "null"},"reads":${deps.systemOne != null}}""")
        },
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
                (m["displayName"] as? String)?.let {
                    Accounts(r.connection(), deps.now).setDisplayName(account, it)
                    Safety(r.connection(), deps.reader, deps.now).noteName("account", account, it.trim())
                }
                (m["ageBand"] as? String)?.let { Friends(r.connection(), deps.now).declareAge(account, it) }
                // PD-104: an organiser's contact email. Present and empty takes it away; absent leaves it alone.
                val contact = m.containsKey("contactEmail")
                if (contact) {
                    try { Accounts(r.connection(), deps.now).setContactEmail(account, m["contactEmail"] as? String) }
                    catch (e: Accounts.ContactRefused) { return@to Http(e.status, """{"error":${Contract.q(e.why)}}""") }
                }
                if (m["displayName"] == null && m["ageBand"] == null && !contact) Http(400, """{"error":"displayName, ageBand or contactEmail"}""") else profile(r.connection(), deps, r.principal!!)
            }
        },
        "teams.create" to { r ->
            teamly {
                val m = Json.parseObject(r.body)
                Teams(r.connection(), deps.now).let { teams ->
                    val made = teams.create(r.principal!!.subject, str(m, "name"), m["locality"] as? String)
                    Safety(r.connection(), deps.reader, deps.now).noteName("team", made.teamId, made.name)
                    Http(200, teams.json(made))
                }
            }
        },
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
                    Safety(r.connection(), deps.reader, deps.now).let { s ->
                        Http(200, s.json(s.report(a, str(m, "subjectKind"), subject, str(m, "reason"))))
                    }
                }
            }
        },
        "safety.block" to { r ->
            withAccount(r) { a ->
                safely {
                    val other = try { UUID.fromString(str(Json.parseObject(r.body), "accountId")) } catch (e: IllegalArgumentException) { throw IllegalArgumentException("accountId must be a UUID") }
                    Safety(r.connection(), deps.reader, deps.now).let { s -> s.block(a, other); Http(200, blocksJson(s.blocking(a))) }
                }
            }
        },
        "safety.unblock" to { r ->
            withAccount(r) { a ->
                safely {
                    Safety(r.connection(), deps.reader, deps.now).let { s ->
                        s.lift(a, UUID.fromString(r.call.parameters["accountId"])); Http(200, blocksJson(s.blocking(a)))
                    }
                }
            }
        },
        "safety.blocks" to { r -> withAccount(r) { a -> Http(200, blocksJson(Safety(r.connection(), deps.reader, deps.now).blocking(a))) } },
        // The fourth thing the stores ask for is that somebody answers. Two routes, closed to everyone but
        // the people named to answer: the queue as it should be worked, and the answer itself.
        "safety.queue" to { r ->
            withModerator(r, deps.moderators) { _ -> Http(200, queueJson(Safety(r.connection(), deps.reader, deps.now).queue())) }
        },
        "safety.decide" to { r ->
            withModerator(r, deps.moderators) { a ->
                safely {
                    val m = Json.parseObject(r.body)
                    val report = UUID.fromString(r.call.parameters["reportId"])
                    val decision = Safety(r.connection(), deps.reader, deps.now).decide(report, str(m, "outcome"), str(m, "note"), a)
                    Http(200, """{"decisionId":"$decision","reportId":"$report"}""")
                }
            }
        },
        "me.consent" to { r ->
            withAccount(r) { a ->
                val body = Json.parseObject(r.body)
                val scope = Consent.Scope.of(body["scope"] as? String)
                if (scope == null) Http(400, """{"error":"scope must be listing or live"}""")
                else {
                    val answer = Consent(r.connection(), deps.now).say(a, scope, body["given"] as? Boolean ?: false)
                    val why = answer.refusedBecause?.let { ""","why":${'$'}{Contract.q(it)}""" } ?: ""
                    Http(200, """{"scope":${'$'}{Contract.q(scope.stored)},"given":${'$'}{answer.given}${'$'}why}""")
                }
            }
        },
        "seasons.live" to { r ->
            val season = UUID.fromString(r.call.parameters["leagueSeasonId"])
            val limit = (r.call.request.queryParameters["limit"]?.toIntOrNull() ?: 20).coerceIn(1, 20)
            shown(r, season) { Http(200, liveJson(LiveBoard(r.connection()).inPlay(season, limit))) }
        },
        "me.terms" to { r ->
            withAccount(r) { a ->
                safely {
                    val asked = (Json.parseObject(r.body)["version"] as? String)?.takeIf { it.isNotBlank() } ?: Safety.TERMS_VERSION
                    Safety(r.connection(), deps.reader, deps.now).acceptTerms(a, asked)
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
        // PD-053: running a league. Nothing here can grant the relation these check for — a league
        // administrator is named out of band and never self-appointed — so on a server where nobody has
        // been named, every one of these refuses.
        "leagues.affiliation.accept" to { r ->
            val affiliation = UUID.fromString(r.call.parameters["affiliationId"])
            val orgs = Organisations(r.connection())
            when (val season = orgs.seasonOfAffiliation(affiliation)) {
                null -> Http(404, """{"error":"THRØ has no such affiliation."}""")
                else -> leagueAdmin(r, season) {
                    try {
                        orgs.acceptAffiliation(affiliation, deps.now())
                        Http(200, """{"affiliationId":"$affiliation","status":"accepted"}""")
                    } catch (e: IllegalArgumentException) {
                        Http(409, """{"error":"That team is not waiting to be accepted."}""")
                    }
                }
            }
        },
        "leagues.result" to { r ->
            val fixtureId = UUID.fromString(r.call.parameters["fixtureId"])
            val orgs = Organisations(r.connection())
            when (val fixture = orgs.fixtureRef(fixtureId)) {
                null -> Http(404, """{"error":"THRØ has no such fixture."}""")
                else -> leagueAdmin(r, fixture.leagueSeasonId) {
                    val m = Json.parseObject(r.body)
                    val home = (m["legsHome"] as? Number)?.toInt()
                    val away = (m["legsAway"] as? Number)?.toInt()
                    val supersedes = supersededOutcome(m)
                    if (home == null || away == null) {
                        Http(400, """{"error":"A result is two numbers: legsHome and legsAway."}""")
                    } else if (supersedes is Named.NotAUuid) {
                        Http(400, """{"error":"supersedes must be the outcomeId of the result being corrected."}""")
                    } else {
                        // PD-055: the evidence decides the kind, not the caller. A match scored on THRØ makes
                        // this a played result; without one it is the official's declared word, which counts
                        // the same in the table and is never evidence.
                        val played = fixture.matchId != null
                        val old = (supersedes as Named.Ok).id
                        outcomely(superseding = old != null) {
                            val id = if (played) orgs.recordPlayedResult(fixtureId, home, away, by = r.principal!!.subject, supersedes = old)
                                     else orgs.declareResult(fixtureId, home, away, by = r.principal!!.subject, supersedes = old)
                            Http(200, """{"outcomeId":"$id","fixtureId":"$fixtureId","kind":${Contract.q(if (played) "played" else "declared")},"supersedes":${old?.let { Contract.q(it.toString()) } ?: "null"}}""")
                        }
                    }
                }
            }
        },
        "leagues.award" to { r ->
            val fixtureId = UUID.fromString(r.call.parameters["fixtureId"])
            val orgs = Organisations(r.connection())
            when (val fixture = orgs.fixtureRef(fixtureId)) {
                null -> Http(404, """{"error":"THRØ has no such fixture."}""")
                else -> leagueAdmin(r, fixture.leagueSeasonId) {
                    val m = Json.parseObject(r.body)
                    val to = try { UUID.fromString(str(m, "toTeamId")) } catch (e: IllegalArgumentException) { throw IllegalArgumentException("toTeamId must be a UUID") }
                    val reason = str(m, "reason")
                    when (val supersedes = supersededOutcome(m)) {
                        is Named.NotAUuid -> Http(400, """{"error":"supersedes must be the outcomeId of the result being corrected."}""")
                        is Named.Ok -> outcomely(superseding = supersedes.id != null) {
                            val id = orgs.awardFixture(fixtureId, to, reason, by = r.principal!!.subject, supersedes = supersedes.id)
                            Http(200, """{"outcomeId":"$id","fixtureId":"$fixtureId","kind":"awarded","supersedes":${supersedes.id?.let { Contract.q(it.toString()) } ?: "null"}}""")
                        }
                    }
                }
            }
        },
        "leagues.void" to { r ->
            val fixtureId = UUID.fromString(r.call.parameters["fixtureId"])
            val orgs = Organisations(r.connection())
            when (val fixture = orgs.fixtureRef(fixtureId)) {
                null -> Http(404, """{"error":"THRØ has no such fixture."}""")
                else -> leagueAdmin(r, fixture.leagueSeasonId) {
                    val m = Json.parseObject(r.body)
                    val reason = str(m, "reason").trim()
                    when (val supersedes = supersededOutcome(m)) {
                        is Named.NotAUuid -> Http(400, """{"error":"supersedes must be the outcomeId of the result being annulled."}""")
                        is Named.Ok -> when {
                            reason.isEmpty() ->
                                // The database insists too; refusing here says which field, and a void with no
                                // reason is the one shape of this that a league could not later account for.
                                Http(400, """{"error":"An annulment says why. A result withdrawn without a reason is one nobody can answer for."}""")
                            supersedes.id == null ->
                                Http(409, """{"error":"There is no result on this fixture to annul."}""")
                            else -> outcomely(superseding = true) {
                                val id = orgs.voidOutcome(fixtureId, supersedes.id!!, reason, by = r.principal!!.subject)
                                Http(200, """{"outcomeId":"$id","fixtureId":"$fixtureId","kind":"void","supersedes":${Contract.q(supersedes.id.toString())}}""")
                            }
                        }
                    }
                }
            }
        },
        // PD-056: a season's fixtures, publicly. Read as `app_read`, like the table it belongs beside.
        "seasons.fixtures" to { r ->
            val season = UUID.fromString(r.call.parameters["leagueSeasonId"])
            shown(r, season) { Fixtures(r.connection()).let { f -> Http(200, f.json(f.of(season))) } }
        },
        // PD-099: what running a season needs before any result — its teams, and its fixtures. The season is looked
        // for first, so a mistyped one is a 404 rather than a refusal that reads like a permission.
        "seasons.teams" to { r ->
            val season = UUID.fromString(r.call.parameters["leagueSeasonId"])
            val planning = SeasonPlanning(r.connection())
            when (val s = planning.season(season)) {
                null -> Http(404, """{"error":"THRØ has no such league season."}""")
                else -> leagueAdmin(r, season) { Http(200, planning.json(s)) }
            }
        },
        // PD-120: who changed what in a season, for the people who run it — read back from rows that already name them.
        "seasons.history" to { r ->
            val season = UUID.fromString(r.call.parameters["leagueSeasonId"])
            if (SeasonPlanning(r.connection()).season(season) == null) Http(404, """{"error":"THRØ has no such league season."}""")
            else leagueAdmin(r, season) { SeasonHistory(r.connection()).let { h -> Http(200, h.json(h.of(season))) } }
        },
        // PD-122: paste the fixture list. Each line read into a row to confirm; nothing is scheduled here.
        "seasons.fixtures.read" to { r ->
            val season = UUID.fromString(r.call.parameters["leagueSeasonId"])
            val model = deps.systemOne
            val desk = Understanding.desk(r.connection(), season)
            when {
                desk == null -> Http(404, """{"error":"THRØ has no such league season."}""")
                else -> leagueAdmin(r, season) {
                    val text = (Json.parseObject(r.body)["text"] as? String).orEmpty()
                    when {
                        model == null -> Http(503, """{"error":"THRØ cannot read a list on this server yet."}""")
                        text.isBlank() -> Http(400, """{"error":"Paste the fixture list: one fixture to a line."}""")
                        text.length > 20_000 -> Http(400, """{"error":"That is more than a season's list. Paste it in parts."}""")
                        else -> {
                            val u = Understanding(model) { deps.now().atZone(Understanding.ZONE).toLocalDate() }
                            try {
                                when (val read = u.readList(desk, text)) {
                                    null -> Http(503, """{"error":"THRØ could not read that just now. Try again, or add the fixtures below."}""")
                                    else -> Http(200, u.json(read))
                                }
                            } catch (e: IllegalArgumentException) { Http(400, """{"error":${Contract.q(e.message ?: "That list could not be read.")}}""") }
                        }
                    }
                }
            }
        },
        // PD-119: Tell THRØ. A sentence on the desk, read into an act to confirm; nothing is recorded here.
        "seasons.understand" to { r ->
            val season = UUID.fromString(r.call.parameters["leagueSeasonId"])
            val model = deps.systemOne
            val desk = Understanding.desk(r.connection(), season)
            when {
                desk == null -> Http(404, """{"error":"THRØ has no such league season."}""")
                else -> leagueAdmin(r, season) {
                    val text = (Json.parseObject(r.body)["text"] as? String)?.trim().orEmpty()
                    when {
                        model == null -> Http(503, """{"error":"THRØ cannot read sentences on this server yet."}""")
                        text.isEmpty() -> Http(400, """{"error":"Say what happened, in a sentence."}""")
                        text.length > 400 -> Http(400, """{"error":"One act at a time: a sentence, not a page."}""")
                        else -> {
                            val u = Understanding(model) { deps.now().atZone(Understanding.ZONE).toLocalDate() }
                            when (val read = u.understand(desk, text)) {
                                null -> Http(503, """{"error":"THRØ could not read that just now. Try again, or use the boxes below."}""")
                                else -> Http(200, u.json(read))
                            }
                        }
                    }
                }
            }
        },
        // PD-100: a league started on THRØ is run by whoever starts it. A listed league stays named-only (PD-053).
        "leagues.start" to { r ->
            planned {
                val m = Json.parseObject(r.body)
                val name = m["name"] as? String ?: throw IllegalArgumentException("A league has a name.")
                val opening = SeasonPlanning.parseOpening(m["season"])
                val visibility = m["visibility"] as? String ?: "public"
                SeasonPlanning(r.connection()).let { p -> Http(200, p.json(p.startLeague(r.principal!!.subject, name, m["locality"] as? String, opening, visibility))) }
            }
        },
        "leagues.update" to { r ->
            planned {
                val league = UUID.fromString(r.call.parameters["leagueId"])
                val m = Json.parseObject(r.body)
                val ended = when (val e = m["ended"]) { null -> false; is Boolean -> e; else -> throw IllegalArgumentException("ended is true or false.") }
                SeasonPlanning(r.connection()).let { p ->
                    Http(200, p.json(p.updateLeague(r.principal!!.subject, league, m["name"] as? String, m["visibility"] as? String, ended)))
                }
            }
        },
        "leagues.season.open" to { r ->
            planned {
                val league = UUID.fromString(r.call.parameters["leagueId"])
                val opening = SeasonPlanning.parseOpening(Json.parseObject(r.body))
                SeasonPlanning(r.connection()).let { p -> Http(200, p.json(p.openSeason(r.principal!!.subject, league, opening))) }
            }
        },
        "seasons.teams.add" to { r ->
            val season = UUID.fromString(r.call.parameters["leagueSeasonId"])
            val planning = SeasonPlanning(r.connection())
            when (planning.season(season)) {
                null -> Http(404, """{"error":"THRØ has no such league season."}""")
                else -> leagueAdmin(r, season) {
                    planned {
                        val m = Json.parseObject(r.body)
                        val division = (m["divisionId"] as? String)?.let {
                            try { UUID.fromString(it) } catch (e: IllegalArgumentException) { throw IllegalArgumentException("divisionId must be a UUID.") }
                        }
                        Http(200, planning.json(planning.addTeam(season, m["name"] as? String ?: "", division, r.principal!!.subject, deps.now())))
                    }
                }
            }
        },
        "me.seasons" to { r -> SeasonPlanning(r.connection()).let { Http(200, it.runsJson(it.seasonsRunBy(r.principal!!.subject))) } },
        // PD-105: the provisional rating. Read — and replayed when the evidence has moved — as `app_rating`, the one
        // role that may write the rating tables and may not write a match.
        // PD-112: the organiser's remaining acts — points rules, division moves, transfers.
        "seasons.points" to { r ->
            leagueActs {
                val m = Json.parseObject(r.body)
                fun n(key: String) = (m[key] as? Number)?.toInt()
                LeagueActs(r.connection(), deps.now).let {
                    Http(200, it.json(it.setPoints(UUID.fromString(r.call.parameters["leagueSeasonId"]), r.principal!!.subject, n("win"), n("draw"), n("loss"), n("awarded"), n("pointsPerLegWon"),
                                                   (m["tieBreak"] as? List<*>)?.map { x -> x.toString() }, m["awardsCountAsPlayed"] as? Boolean)))
                }
            }
        },
        "seasons.teams.division" to { r ->
            leagueActs {
                val m = Json.parseObject(r.body)
                LeagueActs(r.connection(), deps.now).let { Http(200, it.json(it.moveDivision(UUID.fromString(r.call.parameters["leagueSeasonId"]), UUID.fromString(r.call.parameters["teamId"]), (m["divisionId"] as? String)?.let(UUID::fromString), r.principal!!.subject))) }
            }
        },
        "seasons.registrations.transfer" to { r ->
            leagueActs {
                val m = Json.parseObject(r.body)
                val from = try { LocalDate.parse(m["from"] as? String ?: "") } catch (e: Exception) { throw IllegalArgumentException("from is a date") }
                val to = UUID.fromString(m["toTeamId"] as? String ?: throw IllegalArgumentException("toTeamId is required"))
                LeagueActs(r.connection(), deps.now).let { Http(200, it.json(it.transfer(UUID.fromString(r.call.parameters["leagueSeasonId"]), UUID.fromString(r.call.parameters["playerId"]), to, from, m["note"] as? String, r.principal!!.subject))) }
            }
        },
        // PD-110: a friendly between two teams — challenge, read, answer, withdraw, cite the match.
        "teams.friendlies" to { r -> friendlies { val team = UUID.fromString(r.call.parameters["teamId"]); Friendlies(r.connection(), deps.now).let { Http(200, it.json(it.ofTeam(team, r.principal!!.subject), team)) } } },
        "teams.challenge" to { r ->
            friendlies {
                val m = Json.parseObject(r.body)
                val team = UUID.fromString(r.call.parameters["teamId"])
                val to = UUID.fromString(m["toTeamId"] as? String ?: throw IllegalArgumentException("toTeamId is required"))
                val at = try { Instant.parse(m["playAt"] as? String ?: "") } catch (e: Exception) { throw IllegalArgumentException("playAt is not a date-time") }
                Friendlies(r.connection(), deps.now).let { Http(200, it.json(it.challenge(team, to, at, m["message"] as? String, r.principal!!.subject), team)) }
            }
        },
        "friendlies.answer" to { r ->
            friendlies {
                val m = Json.parseObject(r.body)
                Friendlies(r.connection(), deps.now).let { Http(200, it.json(it.answer(UUID.fromString(r.call.parameters["friendlyId"]), m["answer"] as? String ?: "", m["note"] as? String, r.principal!!.subject))) }
            }
        },
        "friendlies.withdraw" to { r -> friendlies { Friendlies(r.connection(), deps.now).let { Http(200, it.json(it.withdraw(UUID.fromString(r.call.parameters["friendlyId"]), r.principal!!.subject))) } } },
        "friendlies.cite" to { r ->
            friendlies {
                val m = Json.parseObject(r.body)
                val match = UUID.fromString(m["matchId"] as? String ?: throw IllegalArgumentException("matchId is required"))
                Friendlies(r.connection(), deps.now).let { Http(200, it.json(it.cite(UUID.fromString(r.call.parameters["friendlyId"]), match, r.principal!!.subject))) }
            }
        },
        // PD-109: a knockout run on THRØ — open, enter, withdraw, check in, close, draw.
        "events.open" to { r ->
            editions {
                val m = Json.parseObject(r.body)
                fun instant(key: String) = (m[key] as? String)?.let { try { Instant.parse(it) } catch (e: Exception) { throw IllegalArgumentException("$key is not a date-time") } }
                val ed = Editions(r.connection(), deps.now)
                Http(200, ed.json(ed.open(
                    r.principal!!.subject, m["name"] as? String ?: "", instant("startsAt") ?: throw IllegalArgumentException("startsAt is required"),
                    instant("sessionEndsAt") ?: throw IllegalArgumentException("sessionEndsAt is required"),
                    (m["venueId"] as? String)?.let(UUID::fromString), m["venueLabel"] as? String, instant("entriesCloseAt"), (m["capacity"] as? Number)?.toInt(),
                    access = m["access"] as? String ?: "open", entrantKind = m["entrantKind"] as? String ?: "player",
                )))
            }
        },
        "me.events" to { r -> Editions(r.connection(), deps.now).let { Http(200, it.json(it.mine(r.principal!!.subject))) } },
        "events.get" to { r -> editions { Editions(r.connection(), deps.now).let { Http(200, it.json(it.view(UUID.fromString(r.call.parameters["eventId"]), r.principal?.subject))) } } },
        "events.enter" to { r ->
            editions {
                val m = if (r.body.isBlank()) emptyMap() else Json.parseObject(r.body)
                val named = (m["playerId"] as? String)?.let(UUID::fromString)
                val me = r.principal!!.subject
                Editions(r.connection(), deps.now).let {
                    Http(200, it.json(it.enter(UUID.fromString(r.call.parameters["eventId"]), named ?: me, by = me,
                                               partner = (m["partnerId"] as? String)?.let(UUID::fromString),
                                               pairIds = (m["playerIds"] as? List<*>)?.map { x -> UUID.fromString(x.toString()) },
                                               teamId = (m["teamId"] as? String)?.let(UUID::fromString))))
                }
            }
        },
        // PD-124: a walk-up, by name, by the organiser.
        "events.guests" to { r ->
            editions {
                val m = Json.parseObject(r.body)
                Editions(r.connection(), deps.now).let {
                    Http(200, it.json(it.enterGuest(UUID.fromString(r.call.parameters["eventId"]), (m["name"] as? String).orEmpty(), m["mayBeNamed"] == true, r.principal!!.subject)))
                }
            }
        },
        "events.entries.seed" to { r ->
            editions {
                val m = Json.parseObject(r.body)
                Editions(r.connection(), deps.now).let { Http(200, it.json(it.seed(UUID.fromString(r.call.parameters["eventId"]), UUID.fromString(r.call.parameters["playerId"]), (m["seed"] as? Number)?.toInt(), r.principal!!.subject))) }
            }
        },
        "events.boards" to { r ->
            editions {
                val m = Json.parseObject(r.body)
                val labels = (m["labels"] as? List<*>)?.map { it.toString() } ?: emptyList()
                Http(200, """{"boards":[${Editions(r.connection(), deps.now).boards(UUID.fromString(r.call.parameters["eventId"]), labels, r.principal!!.subject).joinToString(",") { Contract.q(it) }}]}""")
            }
        },
        "events.tie.board" to { r ->
            editions {
                val m = Json.parseObject(r.body)
                Editions(r.connection(), deps.now).let { Http(200, it.json(it.sendToBoard(UUID.fromString(r.call.parameters["eventId"]), UUID.fromString(r.call.parameters["tieId"]), m["label"] as? String ?: "", r.principal!!.subject))) }
            }
        },
        "events.entries.remove" to { r -> editions { Editions(r.connection(), deps.now).let { Http(200, it.json(it.remove(UUID.fromString(r.call.parameters["eventId"]), UUID.fromString(r.call.parameters["playerId"]), r.principal!!.subject))) } } },
        "events.withdraw" to { r -> editions { Editions(r.connection(), deps.now).let { Http(200, it.json(it.withdraw(UUID.fromString(r.call.parameters["eventId"]), r.principal!!.subject))) } } },
        "events.checkin" to { r ->
            editions {
                val phone = r.call.request.headers["X-Thro-Device"]?.let { runCatching { UUID.fromString(it) }.getOrNull() }
                    ?: throw IllegalArgumentException("X-Thro-Device must name the phone that is checking in")
                Editions(r.connection(), deps.now, asRole = { role -> r.role = if (role == "trust") DbRole.TRUST else DbRole.COMPETITION; r.connection() }).let { Http(200, it.json(it.checkIn(UUID.fromString(r.call.parameters["eventId"]), r.principal!!.subject, phone))) }
            }
        },
        "events.close" to { r -> editions { Editions(r.connection(), deps.now).let { Http(200, it.json(it.close(UUID.fromString(r.call.parameters["eventId"]), r.principal!!.subject))) } } },
        "events.draw" to { r -> editions { Editions(r.connection(), deps.now).let { Http(200, it.json(it.draw(UUID.fromString(r.call.parameters["eventId"]), r.principal!!.subject))) } } },
        "events.tie.result" to { r ->
            editions {
                val m = Json.parseObject(r.body)
                val winner = UUID.fromString(m["winnerId"] as? String ?: throw IllegalArgumentException("winnerId is required"))
                Editions(r.connection(), deps.now).let { Http(200, it.json(it.declare(UUID.fromString(r.call.parameters["eventId"]), UUID.fromString(r.call.parameters["tieId"]), winner, m["outcome"] as? String ?: "", m["note"] as? String, r.principal!!.subject))) }
            }
        },
        "events.tie.match" to { r ->
            editions {
                val m = Json.parseObject(r.body)
                val match = UUID.fromString(m["matchId"] as? String ?: throw IllegalArgumentException("matchId is required"))
                Editions(r.connection(), deps.now).let { Http(200, it.json(it.citeTie(UUID.fromString(r.call.parameters["eventId"]), UUID.fromString(r.call.parameters["tieId"]), match, r.principal!!.subject))) }
            }
        },
        "events.advance" to { r -> editions { Editions(r.connection(), deps.now).let { Http(200, it.json(it.advance(UUID.fromString(r.call.parameters["eventId"]), r.principal!!.subject))) } } },
        // PD-108: moving a fixture by agreement — one team proposes, the other answers, the league applies.
        "fixtures.proposals" to { r ->
            rearrangements { Rearrangements(r.connection(), deps.now).let { Http(200, it.json(it.ofFixture(UUID.fromString(r.call.parameters["fixtureId"]), r.principal!!.subject))) } }
        },
        "fixtures.propose" to { r ->
            rearrangements {
                val m = Json.parseObject(r.body)
                val to = try { Instant.parse(m["to"] as? String ?: "") } catch (e: Exception) { throw IllegalArgumentException("to is not a date-time") }
                val team = UUID.fromString(m["teamId"] as? String ?: throw IllegalArgumentException("teamId is required"))
                Rearrangements(r.connection(), deps.now).let { Http(200, it.json(it.propose(UUID.fromString(r.call.parameters["fixtureId"]), team, to, m["reason"] as? String, r.principal!!.subject))) }
            }
        },
        "proposals.get" to { r ->
            rearrangements { Rearrangements(r.connection(), deps.now).let { Http(200, it.json(it.read(UUID.fromString(r.call.parameters["proposalId"]), r.principal!!.subject))) } }
        },
        "proposals.answer" to { r ->
            rearrangements {
                val m = Json.parseObject(r.body)
                Rearrangements(r.connection(), deps.now).let { Http(200, it.json(it.answer(UUID.fromString(r.call.parameters["proposalId"]), m["answer"] as? String ?: "", m["note"] as? String, r.principal!!.subject))) }
            }
        },
        "proposals.withdraw" to { r -> rearrangements { Rearrangements(r.connection(), deps.now).let { Http(200, it.json(it.withdraw(UUID.fromString(r.call.parameters["proposalId"]), r.principal!!.subject))) } } },
        "proposals.apply" to { r ->
            rearrangements {
                val m = Json.parseObject(r.body)
                val phone = r.call.request.headers["X-Thro-Device"]?.let { runCatching { UUID.fromString(it) }.getOrNull() }
                    ?: throw IllegalArgumentException("X-Thro-Device must name the device that is applying")
                val expected = (m["expectedVersion"] as? Number)?.toInt() ?: throw IllegalArgumentException("expectedVersion is required")
                val rr = Rearrangements(r.connection(), deps.now)
                when (val a = rr.apply(UUID.fromString(r.call.parameters["proposalId"]), expected, r.principal!!.subject, phone)) {
                    is Rearrangements.Applied.Moved -> Http(200, rr.json(a.proposal))
                    is Rearrangements.Applied.Stale -> Http(409, """{"outcome":"stale","currentVersion":${a.currentVersion},"current":${a.current}}""")
                }
            }
        },
        "seasons.proposals" to { r ->
            rearrangements { Rearrangements(r.connection(), deps.now).let { Http(200, it.json(it.openInSeason(UUID.fromString(r.call.parameters["leagueSeasonId"]), r.principal!!.subject))) } }
        },
        // PD-107: registering players with a league run on THRØ — what it needs, who owes one, sending, the answer.
        "seasons.policy" to { r ->
            registrations { Registrations(r.connection(), deps.now).let { Http(200, it.json(it.policy(UUID.fromString(r.call.parameters["leagueSeasonId"]), r.principal!!.subject))) } }
        },
        "seasons.policy.set" to { r ->
            registrations {
                val m = Json.parseObject(r.body)
                fun strings(key: String) = (m[key] as? List<*>)?.map { it.toString() } ?: emptyList()
                val closes = (m["registrationClosesOn"] as? String)?.let { try { LocalDate.parse(it) } catch (e: Exception) { throw IllegalArgumentException("registrationClosesOn is not a date") } }
                Registrations(r.connection(), deps.now).let {
                    Http(200, it.json(it.setPolicy(UUID.fromString(r.call.parameters["leagueSeasonId"]), r.principal!!.subject, strings("requires"), strings("manualRequirements"),
                                                   (m["deadlineDaysBeforeFirstFixture"] as? Number)?.toInt(), closes)))
                }
            }
        },
        "teams.reconcile" to { r ->
            registrations { Registrations(r.connection(), deps.now).let { Http(200, it.json(it.reconcile(UUID.fromString(r.call.parameters["teamId"]), r.principal!!.subject))) } }
        },
        "tasks.assess" to { r ->
            registrations { Registrations(r.connection(), deps.now).let { Http(200, it.json(it.assess(UUID.fromString(r.call.parameters["taskId"]), r.principal!!.subject))) } }
        },
        "tasks.confirm" to { r ->
            registrations {
                val m = Json.parseObject(r.body)
                Registrations(r.connection(), deps.now).confirm(UUID.fromString(r.call.parameters["taskId"]), m["requirement"] as? String ?: "", m["note"] as? String ?: "", r.principal!!.subject)
                Http(200, """{"taskId":"${r.call.parameters["taskId"]}","confirmed":${Contract.q(m["requirement"].toString())}}""")
            }
        },
        "submissions.submit" to { r ->
            registrations {
                val id = UUID.fromString(r.call.parameters["submissionId"])
                Http(200, """{"submissionId":"$id","state":${Contract.q(Registrations(r.connection(), deps.now).submit(id, r.principal!!.subject))}}""")
            }
        },
        "seasons.registrations" to { r ->
            registrations { val season = UUID.fromString(r.call.parameters["leagueSeasonId"]); Registrations(r.connection(), deps.now).let { Http(200, it.json(it.list(season, r.principal!!.subject), it.registered(season))) } }
        },
        "submissions.answer" to { r ->
            registrations {
                val id = UUID.fromString(r.call.parameters["submissionId"])
                val m = Json.parseObject(r.body)
                val from = (m["registeredFrom"] as? String)?.let { try { LocalDate.parse(it) } catch (e: Exception) { throw IllegalArgumentException("registeredFrom is not a date") } }
                val state = Registrations(r.connection(), deps.now).answer(id, r.principal!!.subject, m["answer"] as? String ?: "", m["note"] as? String, from)
                Http(200, """{"submissionId":"$id","state":${Contract.q(state)}}""")
            }
        },
        // PD-106: a fixture as one team lives it, and the match it was played in.
        "fixtures.team" to { r ->
            teamFixture {
                val t = TeamFixtures(r.connection())
                Http(200, t.json(t.view(UUID.fromString(r.call.parameters["fixtureId"]), UUID.fromString(r.call.parameters["teamId"]), r.principal!!.subject)))
            }
        },
        "fixtures.cite" to { r ->
            teamFixture {
                val fixture = UUID.fromString(r.call.parameters["fixtureId"])
                val match = try { UUID.fromString(str(Json.parseObject(r.body), "matchId")) } catch (e: IllegalArgumentException) { throw IllegalArgumentException("matchId must be a UUID") }
                TeamFixtures(r.connection()).cite(fixture, match, r.principal!!.subject)
                Http(200, """{"fixtureId":"$fixture","matchId":"$match"}""")
            }
        },
        "me.rating" to { r -> rated(r, deps, r.principal!!.subject) },
        "players.rating" to { r ->
            val player = UUID.fromString(r.call.parameters["playerId"])
            // A player THRØ may not name is not shown at all — 404, the same answer as a player who does not exist, so
            // the route cannot be used to tell the two apart. Asked as the read role, which holds the disclosure rule.
            r.role = DbRole.READ
            if (player != r.principal!!.subject && !Ratings(r.connection(), deps.now).mayBeShown(player)) Http(404, """{"error":"THRØ shows no rating for that player."}""")
            else rated(r, deps, player)
        },
        // PD-104: how the teams in a league reach the person running it. The season is looked for first (a mistyped
        // address is a 404, not a refusal); then the caller must administer the season, or a team accepted into it.
        "seasons.organiser" to { r ->
            val season = UUID.fromString(r.call.parameters["leagueSeasonId"])
            val accounts = Accounts(r.connection(), deps.now)
            if (!Fixtures(r.connection()).seasonExists(season)) Http(404, """{"error":"THRØ has no such league season."}""")
            else {
                val me = r.principal!!.subject
                val allowed = accounts.runsATeamIn(me, season)
                    || Relations(r.connection()).decide(me, "league_season.administer", ObjectRef(ObjectType.LEAGUE_SEASON, season.toString())).allowed
                if (!allowed) Http(403, """{"error":"The organiser's contact is for the teams in this season and the people who run it."}""")
                else Http(200, """{"contacts":[${accounts.organiserContacts(season).joinToString(",") { """{"email":${Contract.q(it)}}""" }}]}""")
            }
        },
        "seasons.fixtures.schedule" to { r ->
            val season = UUID.fromString(r.call.parameters["leagueSeasonId"])
            val planning = SeasonPlanning(r.connection())
            when (planning.season(season)) {
                null -> Http(404, """{"error":"THRØ has no such league season."}""")
                else -> leagueAdmin(r, season) {
                    planned {
                        val wanted = SeasonPlanning.parse(Json.parseObject(r.body))
                        Http(200, planning.json(planning.schedule(season, wanted, by = r.principal!!.subject)))
                    }
                }
            }
        },
        // PD-054: the table is arithmetic over the fixtures, so it is read as `app_read` and computed here
        // rather than kept anywhere. A season nobody has given rules to is ordered by THRØ's standard, and
        // the answer says so on its face.
        "seasons.standings" to { r ->
            val season = UUID.fromString(r.call.parameters["leagueSeasonId"])
            val division = r.call.request.queryParameters["division"]?.let { UUID.fromString(it) }
            shown(r, season) { tabled { LeagueTable(r.connection()).let { Http(200, it.json(it.of(season, division, deps.now()))) } } }
        },
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
                    } catch (x: Accounts.AccountSuspended) {
                        Http(403, """{"error":"this account is suspended"}""")
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

/** The commit this image was built from, where the host says so — Render sets `RENDER_GIT_COMMIT` (PD-095). */
private val builtFrom: String? = System.getenv("RENDER_GIT_COMMIT")?.trim()?.takeIf { Regex("[0-9a-f]{7,40}").matches(it) }

private fun health(deps: Deps): Http = try {
    deps.connect().use { c ->
        c.createStatement().use { it.execute("SET ROLE " + DbRole.READ.sql) }
        val v = Migrations.currentVersion(c)
        val latest = Migrations.files().maxOfOrNull { Migrations.versionOf(it) }
        if (v == null || (latest != null && v < latest)) Http(503, """{"database":"behind the code","schemaVersion":${v ?: "null"},"codeVersion":${latest ?: "null"}}""")
        // Which code is answering, as well as which schema (PD-095). Once a migration has run, the API being replaced
        // and the one replacing it answer at the same schema version, so a deploy waiting on the schema alone could not
        // tell whether the new code had come up. The commit is the host's word for it; the code's own version is the rest.
        else Http(200, """{"database":"ok","schemaVersion":"V${"%03d".format(v)}","codeVersion":${latest?.let { "\"V${"%03d".format(it)}\"" } ?: "null"},"commit":${builtFrom?.let { "\"$it\"" } ?: "null"}}""")
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
    return when (val v = verifier.verify(token, provider, setOfNotNull(clientId, deps.webProviders[provider]), nonce)) {
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
            """"subjectId":"${q.report.subjectId}","subject":${Contract.q(q.subject)},"reason":${Contract.q(q.report.reason)},""" +
            """"urgent":${q.report.urgent},"reportedAt":"${q.report.reportedAt}",""" +
            """"answerDueAt":"${q.report.answerDueAt}","decisions":${q.decisions},""" +
            """"raisedBy":${if (q.report.raisedByAPerson) "\"player\"" else "\"thro\""},"reading":${readingJson(q.reading)}}"""
    } + "]}"

/** THRØ's reading of a report (PD-118), or null: a hint beside it, in the words the queue shows. A NaN is a number the reading did not have. */
private fun readingJson(r: Reading?): String {
    if (r == null) return "null"
    fun n(d: Double) = if (d.isNaN()) "null" else "%.2f".format(java.util.Locale.ROOT, d)
    return """{"category":${Contract.q(r.category)},"confidence":${n(r.categoryConfidence)},"childSafety":${n(r.childSafety)},"severity":${n(r.severity)},"model":${Contract.q(r.model)}}"""
}

/** A safety refusal is an answer too: the sentence to show, with 400 unless the refusal names a status. */
private fun safely(status: Int = 400, block: () -> Http): Http = try { block() } catch (e: Safety.Refused) {
    Http(e.status ?: status, """{"error":${Contract.q(e.why)}}""")
}

/** The accounts somebody has blocked. Ids only: a block list names nobody it does not have to. */
private fun blocksJson(ids: List<java.util.UUID>): String =
    "{\"blocked\":[" + ids.joinToString(",") { "\"$it\"" } + "]}"

/** A team refusal is an answer too: the sentence, with the status the route names. */
private fun teamly(status: Int = 400, block: () -> Http): Http = try { block() } catch (e: Teams.Refused) { Http(e.status ?: status, """{"error":${Contract.q(e.why)}}""") }

/**
 * A route only a league season's administration may call (PD-053).
 *
 * The decision goes through the same Authorizer every other relation does and is audited by it, so a refusal
 * is on the record beside the ones that were allowed. **Nothing in THRØ grants this relation**: a league
 * administrator is named out of band, because an administrator publishes a table a whole town reads as
 * official and the founder does not want that handed to whoever asks first.
 */
/** Absent is not the same as malformed: one means a first result, the other is a caller to correct. */
private sealed interface Named {
    @JvmInline value class Ok(val id: UUID?) : Named
    object NotAUuid : Named
}

/**
 * The outcome a decision replaces, where it replaces one (PD-059). Absent means this is the fixture's first
 * result and the database will say so if it is not; present means a correction, and naming it is what stops
 * two organisers from silently overwriting one another.
 */
private fun supersededOutcome(m: Map<String, Any?>): Named {
    val raw = m["supersedes"] ?: return Named.Ok(null)
    if (raw !is String) return Named.NotAUuid
    return try { Named.Ok(UUID.fromString(raw)) } catch (e: IllegalArgumentException) { Named.NotAUuid }
}

private fun leagueAdmin(r: Req, season: UUID, block: () -> Http): Http {
    val decision = Relations(r.connection())
        .decide(r.principal!!.subject, "league_season.administer", ObjectRef(ObjectType.LEAGUE_SEASON, season.toString()))
    return if (decision.allowed) block() else Http(403, """{"error":"You do not administer this league season."}""")
}

/**
 * A fixture already holding a result is a 409, not a 500. The database refuses a second live outcome — a new
 * decision must supersede the one standing — and that is a thing the caller can act on rather than a fault.
 *
 * **The same refusal means two different things, and the caller is owed the difference** (PD-059). It fires
 * when nothing was superseded and a result already stands, which is "you meant to correct this"; and it
 * fires when the outcome you named has itself been superseded since you read it, which is "somebody
 * corrected it while you were typing". The second is a lost update the database refused on our behalf, and
 * telling an organiser to reload is the only honest answer to it. [superseding] is what separates them,
 * because the trigger cannot say which case it is and the handler knows.
 */
private fun outcomely(superseding: Boolean = false, block: () -> Http): Http = try {
    block()
} catch (e: java.sql.SQLException) {
    val why = e.message.orEmpty()
    if (why.contains("already has an outcome")) {
        if (superseding) Http(409, """{"error":"This fixture's result changed while you were entering one. Reload, and correct the result that is standing now."}""")
        else Http(409, """{"error":"This fixture already has a result. Correcting one is a new decision that supersedes it: send its outcomeId as `supersedes`."}""")
    } else if (why.contains("supersede one of its own fixture")) {
        Http(409, """{"error":"That result belongs to a different fixture."}""")
    } else if (why.contains("outcome_supersedes_once")) {
        // **A 500 was reaching the caller here** (PD-067). `outcome_supersedes_once` is a unique index that
        // stops two decisions both claiming to replace the same one, which would fork the chain — right,
        // and it is the *database* noticing a stale write rather than the trigger. For a correction the
        // trigger gets there first, because the newer result is live and unaccounted for; for an annulment
        // it does not, because V043 excludes voids from that count and the annulled result is superseded
        // already. So the index threw raw, and two officials annulling the same result — or one person
        // pressing the button twice — got a server fault instead of an answer.
        Http(409, """{"error":"That result has already been dealt with. Reload, and act on the one that is standing now."}""")
    } else if (why.contains("read from the match")) Http(409, """{"error":"This fixture was scored on THRØ, so its result is read from the match."}""")
    else throw e
}

/** A table's refusal is an answer: there is no such season, or the league's own rules name something THRØ
 * cannot apply. The second is a 409 carrying the league's problem rather than a table quietly ordered by
 * somebody else's rules, which would be worse than no table at all.
 */
private fun tabled(block: () -> Http): Http = try { block() } catch (e: LeagueTable.Refused) {
    Http(e.status, """{"error":${Contract.q(e.why)}}""")
}

/**
 * A rating, in two roles (PD-105): replayed and read as `app_rating`, which may write the rating tables and read no
 * person; then named as `app_read`, which holds the disclosure rule and writes nothing. The connection is narrowed
 * twice, and each narrowing is on the audit of roles the HTTP tests keep.
 */
private fun rated(r: Req, deps: Deps, player: UUID): Http {
    r.role = DbRole.RATING
    val ratings = Ratings(r.connection(), deps.now)
    val answer = ratings.of(player)
    r.role = DbRole.READ
    val names = answer.lines.map { it.opponent }.distinct().associateWith { Ratings(r.connection(), deps.now).nameOf(it) }
    return Http(200, ratings.json(answer, names))
}

/**
 * A season's public pages answer for a public, unended league — or for the people who run the season, whatever the
 * league's standing (PD-103). A stranger holding a private season's id is told there is no such season, which is the
 * same answer as a season that does not exist, so the id tells nobody which. The check reads as the competition role
 * (the relation lives in `authz`), then the page is read as `app_read` like every public read.
 */
private fun shown(r: Req, season: UUID, block: () -> Http): Http {
    r.role = DbRole.COMPETITION
    val standing = r.connection().prepareStatement(
        "SELECT l.visibility = 'public' AND l.dissolved_at IS NULL FROM competition.league_season ls JOIN competition.league l ON l.league_id = ls.league_id WHERE ls.league_season_id = ?",
    ).use { ps -> ps.setObject(1, season); ps.executeQuery().use { rs -> if (rs.next()) rs.getBoolean(1) else null } }
    val allowed = when (standing) {
        null -> false
        true -> true
        false -> r.principal?.let { p ->
            Relations(r.connection()).decide(p.subject, "league_season.administer", ObjectRef(ObjectType.LEAGUE_SEASON, season.toString())).allowed
        } ?: false
    }
    if (!allowed) return Http(404, """{"error":"THRØ has no such league season."}""")
    r.role = DbRole.READ
    return block()
}

/** An organiser's act refused is an answer, with the status that says which kind (PD-112). */
private fun leagueActs(block: () -> Http): Http = try { block() } catch (e: LeagueActs.Refused) {
    Http(e.status, """{"error":${Contract.q(e.why)}}""")
}

/** A friendly step refused is an answer, with the status that says which kind (PD-110). */
private fun friendlies(block: () -> Http): Http = try { block() } catch (e: Friendlies.Refused) {
    Http(e.status, """{"error":${Contract.q(e.why)}}""")
}

/** An event step refused is an answer, with the status that says which kind (PD-109). */
private fun editions(block: () -> Http): Http = try { block() } catch (e: Editions.Refused) {
    Http(e.status, """{"error":${Contract.q(e.why)}}""")
}

/** A rearrangement step refused is an answer, with the status that says which kind (PD-108). */
private fun rearrangements(block: () -> Http): Http = try { block() } catch (e: Rearrangements.Refused) {
    Http(e.status, """{"error":${Contract.q(e.why)}}""")
}

/** A registration step refused is an answer, with the status that says which kind (PD-107). */
private fun registrations(block: () -> Http): Http = try { block() } catch (e: Registrations.Refused) {
    Http(e.status, """{"error":${Contract.q(e.why)}}""")
}

/** A team's fixture refused is an answer, with the status that says which kind (PD-106). */
private fun teamFixture(block: () -> Http): Http = try { block() } catch (e: TeamFixtures.Refused) {
    Http(e.status, """{"error":${Contract.q(e.why)}}""")
}

/** A season's plan refused is an answer: which fixture, and why it cannot be played (PD-099). */
private fun planned(block: () -> Http): Http = try { block() } catch (e: SeasonPlanning.Refused) {
    Http(e.status, """{"error":${Contract.q(e.why)}}""")
}

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
        ?: return Http(200, """{"accountId":null,"playerId":"${p.subject}","displayName":null,"named":false,"ageBand":"unknown",$terms,"acceptedTerms":false,"consents":[],"note":"development principal: no account"}""")
    val pr = Accounts(c, deps.now).profile(account) ?: return Http(404, """{"error":"no such account"}""")
    val accepted = Safety(c, deps.reader, deps.now).hasAcceptedTerms(account)
    // What they have agreed to, for the same reason the terms travel here (PD-050, PD-088): a screen
    // with a switch on it has to know which way the switch is set, and a fact the client must remember
    // to go and ask for separately is a fact some build ships without.
    val given = Consent(c, deps.now).given(account)
    val consents = given.joinToString(",") { Contract.q(it.stored) }
    return Http(200, """{"accountId":"${pr.accountId}","playerId":${pr.playerId?.let { "\"$it\"" } ?: "null"},"displayName":${Contract.q(pr.displayName)},"named":${pr.named},"ageBand":${Contract.q(pr.ageBand)},"credentials":${pr.credentials},"ways":[${pr.ways.joinToString(",") { Contract.q(it) }}],"organiser":${pr.organiser},"contactEmail":${pr.contactEmail?.let { Contract.q(it) } ?: "null"},$terms,"acceptedTerms":$accepted,"consents":[$consents]}""")
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

/**
 * A game in play, as a public screen gets it.
 *
 * A player THRØ may not name is **absent from the JSON**, not present as an empty string or a
 * placeholder. A client that forgets to handle the missing key draws nothing, which is the safe
 * failure; one that received `""` would have to know to treat it specially, and would eventually not.
 */
private fun liveJson(panels: List<LiveBoard.Panel>): String =
    """{"games":[""" + panels.joinToString(",") { p ->
        buildString {
            append("""{"matchId":${'$'}{Contract.q(p.matchId.toString())}""")
            p.homeTeam?.let { append(""","homeTeam":${'$'}{Contract.q(it)}""") }
            p.awayTeam?.let { append(""","awayTeam":${'$'}{Contract.q(it)}""") }
            p.venue?.let { append(""","venue":${'$'}{Contract.q(it)}""") }
            p.homeName?.let { append(""","homeName":${'$'}{Contract.q(it)}""") }
            p.awayName?.let { append(""","awayName":${'$'}{Contract.q(it)}""") }
            append(""","homeRemaining":${'$'}{p.homeRemaining},"awayRemaining":${'$'}{p.awayRemaining}""")
            append(""","homeLegs":${'$'}{p.homeLegs},"awayLegs":${'$'}{p.awayLegs}""")
            p.thrower?.let { append(""","thrower":${'$'}{Contract.q(it)}""") }
            append("}")
        }
    } + "]}"

private fun inboxJson(sections: Map<thro.competition.InboxSection, List<Secretary.InboxItem>>): String =
    "{\"sections\":{" + sections.entries.joinToString(",") { (s, items) ->
        Contract.q(s.name) + ":[" + items.joinToString(",") { i ->
            """{"taskId":"${i.taskId}","kind":${Contract.q(i.kind)},"reason":${Contract.q(i.reason)},"dueAt":${i.dueAt?.let { Contract.q(it.toString()) } ?: "null"},"state":${Contract.q(i.state)},"player":${i.player?.let { "\"$it\"" } ?: "null"},"proposal":${i.proposal?.let { "\"$it\"" } ?: "null"}}"""
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
