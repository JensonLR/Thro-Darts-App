package thro.api.http

/**
 * The contract, once. Every route the server mounts is an [Endpoint] here, and `/openapi.json` is
 * rendered from this list — so the document cannot describe a route that is not served, and the
 * server cannot serve a route the document does not describe (the server refuses to start if a
 * handler is missing for an endpoint, or present for none). ADR-001's mitigation — a machine-checked
 * contract rather than a hand-maintained one — without a schema plugin: the registry is the schema.
 *
 * The committed copy at `services/api/openapi.json` is held equal to the served document by test,
 * so a change to the contract is a change to a reviewed file.
 */
public data class Endpoint(
    val id: String,
    val method: String,
    val path: String,
    val summary: String,
    val description: String,
    val authenticated: Boolean,
    val request: Schema? = null,
    val responses: Map<Int, String>,
    val query: List<Pair<String, String>> = emptyList(),
    /** A server-sent event stream rather than one answer: mounted with SSE, described as text/event-stream. */
    val stream: Boolean = false,
)

/** A JSON schema fragment, written by hand and rendered verbatim. */
public data class Schema(val json: String)

public object Contract {

    public const val VERSION: String = "0.1.0"

    private val commandEnvelope = Schema(
        """
        {"type":"object","required":["type","commandId"],
         "description":"One command. `type` selects the shape; the caller's identity is the authenticated principal and is never read from the body; the device is the X-Thro-Device header.",
         "properties":{
           "type":{"type":"string","enum":["RecordVisit","RenameTeam","RearrangeFixture","SetAvailability","NameLineup"]},
           "commandId":{"type":"string","format":"uuid","description":"Idempotency key per device: a replay returns the stored response verbatim."},
           "matchId":{"type":"string","format":"uuid"},
           "deviceSeq":{"type":"integer","description":"RecordVisit: the device's gapless sequence for this match."},
           "player":{"type":"string","enum":["home","away"],"description":"RecordVisit: the seat that threw."},
           "visitTotal":{"type":"integer"},"dartsUsed":{"type":["integer","null"]},"dartsAtDouble":{"type":["integer","null"]},
           "occurredAt":{"type":"string","format":"date-time"},"occurredTz":{"type":"string"},
           "clientEffect":{"type":["string","null"]},"engineVersion":{"type":"string"},
           "teamId":{"type":"string","format":"uuid"},"to":{"type":"string","description":"RenameTeam: the new name. RearrangeFixture: the new date-time."},
           "fixtureId":{"type":"string","format":"uuid"},"venueId":{"type":["string","null"],"format":"uuid"},
           "playerId":{"type":"string","format":"uuid"},"status":{"type":"string","enum":["available","unavailable","maybe"]},
           "players":{"type":"array","items":{"type":"string","format":"uuid"},"description":"NameLineup: the side in slot order."},
           "expectedVersion":{"type":"integer","description":"The row version the author last saw; 0 when the row does not exist yet. A different current version is a 409 with the current row."}
         }}
        """.trimIndent(),
    )

    private val signIn = Schema(
        """{"type":"object","required":["idToken","deviceId"],"properties":{"idToken":{"type":"string","description":"The provider's ID token (JWT) as the platform SDK returned it."},"deviceId":{"type":"string","format":"uuid","description":"This device's stable id; the session family is bound to it."},"nonce":{"type":"string","description":"The nonce the client generated for this sign-in and gave the provider SDK. Required when the token carries one; Apple's token carries its SHA-256, Google's the value."}}}""",
    )
    private val sessionResponse = "a session: accountId, playerId, accessToken (opaque, 15 minutes), refreshToken (single-use, 30 days), accessExpiresAt, created"

    public val endpoints: List<Endpoint> = listOf(
        Endpoint(
            id = "auth.apple", method = "POST", path = "/v1/auth/apple", authenticated = false,
            summary = "Sign in with Apple", request = signIn,
            description = "Verifies Apple's ID token against Apple's published keys, issuer, this app's client id and expiry; creates the account, its player and its claim on first sight (PD-030). The session is THRØ's own.",
            responses = mapOf(200 to sessionResponse, 400 to "malformed", 401 to "the token does not verify, and why", 503 to "Sign in with Apple is not configured on this server", 429 to "too many attempts from this address or device; Retry-After says when"),
        ),
        Endpoint(
            id = "auth.google", method = "POST", path = "/v1/auth/google", authenticated = false,
            summary = "Sign in with Google", request = signIn,
            description = "As for Apple, against Google's published keys and issuers.",
            responses = mapOf(200 to sessionResponse, 400 to "malformed", 401 to "the token does not verify, and why", 503 to "Sign in with Google is not configured on this server", 429 to "too many attempts from this address or device; Retry-After says when"),
        ),
        Endpoint(
            id = "passkey.register.options", method = "POST", path = "/v1/auth/passkey/register/options", authenticated = false,
            summary = "Begin creating a passkey",
            request = Schema("""{"type":"object","required":["deviceId"],"properties":{"deviceId":{"type":"string","format":"uuid"}}}"""),
            description = "Returns the WebAuthn creation options (challenge, relying party, user handle, ES256/RS256, resident key and user verification required, attestation none). With a bearer token the passkey is added to that account; without one the registration creates an account. The challenge lives five minutes and is spent once.",
            responses = mapOf(200 to "challengeId and publicKey creation options", 400 to "malformed", 503 to "passkeys are not configured on this server", 429 to "too many attempts from this address or device; Retry-After says when"),
        ),
        Endpoint(
            id = "passkey.register", method = "POST", path = "/v1/auth/passkey/register", authenticated = false,
            summary = "Finish creating a passkey",
            request = Schema("""{"type":"object","required":["challengeId","deviceId","credentialId","clientDataJSON","attestationObject"],"properties":{"challengeId":{"type":"string","format":"uuid"},"deviceId":{"type":"string","format":"uuid"},"credentialId":{"type":"string","description":"base64url"},"clientDataJSON":{"type":"string","description":"base64url"},"attestationObject":{"type":"string","description":"base64url"}}}"""),
            description = "Verifies the client data (type, challenge, origin) and the authenticator data (relying party, user presence and verification, credential and COSE key); stores the public key; opens a session. The attestation statement is not verified: THRØ asks for none.",
            responses = mapOf(200 to sessionResponse, 400 to "malformed", 401 to "the registration does not verify, and why", 503 to "passkeys are not configured on this server", 429 to "too many attempts from this address or device; Retry-After says when"),
        ),
        Endpoint(
            id = "passkey.options", method = "POST", path = "/v1/auth/passkey/options", authenticated = false,
            summary = "Begin signing in with a passkey",
            request = Schema("""{"type":"object","required":["deviceId"],"properties":{"deviceId":{"type":"string","format":"uuid"}}}"""),
            description = "Returns the WebAuthn request options (challenge, relying party id, user verification required). Discoverable credentials: no username is asked for.",
            responses = mapOf(200 to "challengeId and publicKey request options", 400 to "malformed", 503 to "passkeys are not configured on this server", 429 to "too many attempts from this address or device; Retry-After says when"),
        ),
        Endpoint(
            id = "passkey.assert", method = "POST", path = "/v1/auth/passkey", authenticated = false,
            summary = "Sign in with a passkey",
            request = Schema("""{"type":"object","required":["challengeId","deviceId","credentialId","clientDataJSON","authenticatorData","signature"],"properties":{"challengeId":{"type":"string","format":"uuid"},"deviceId":{"type":"string","format":"uuid"},"credentialId":{"type":"string","description":"base64url"},"clientDataJSON":{"type":"string","description":"base64url"},"authenticatorData":{"type":"string","description":"base64url"},"signature":{"type":"string","description":"base64url"}}}"""),
            description = "Verifies the assertion — challenge, origin, relying party, user verification, sign count, signature over authenticator data and client data hash — and opens a session for the credential's account.",
            responses = mapOf(200 to sessionResponse, 400 to "malformed", 401 to "the assertion does not verify, and why", 503 to "passkeys are not configured on this server", 429 to "too many attempts from this address or device; Retry-After says when"),
        ),
        Endpoint(
            id = "stream.match", method = "GET", path = "/v1/streams/match/{matchId}", authenticated = true, stream = true,
            summary = "A match's evidence, live (ADR-007)",
            description = "text/event-stream. Every event of the match in commit order, then each new one as it commits; the event id is `match:{matchId}:{commitXid}-{seq}` and a reconnect with Last-Event-ID replays from there. A comment ping every 15 seconds; a client that has seen nothing for 45 seconds treats the stream as stale. Open to the match's participants, holders of a scoring grant for it, and officials of its event — there is no spectator stream yet.",
            responses = mapOf(200 to "text/event-stream", 401 to "no principal", 403 to "not in this match", 404 to "no such match"),
        ),
        Endpoint(
            id = "aasa", method = "GET", path = "/.well-known/apple-app-site-association", authenticated = false,
            summary = "Apple's association file for this host",
            description = "webcredentials for the configured app ids, so iOS offers passkeys for this relying party. 404 when no app id is configured.",
            responses = mapOf(200 to "the association file", 404 to "no app ids configured"),
        ),
        Endpoint(
            id = "auth.refresh", method = "POST", path = "/v1/auth/refresh", authenticated = false,
            summary = "Rotate a refresh token",
            request = Schema("""{"type":"object","required":["refreshToken"],"properties":{"refreshToken":{"type":"string"}}}"""),
            description = "A refresh token is single-use: this marks it used and issues a new pair. Presenting a used token is reuse — a copy exists — and revokes the whole session family (ADR-008).",
            responses = mapOf(200 to sessionResponse, 400 to "malformed", 401 to "unknown, expired, or reused (the family is now revoked)", 429 to "too many attempts from this address or device; Retry-After says when"),
        ),
        Endpoint(
            id = "auth.logout", method = "POST", path = "/v1/auth/logout", authenticated = true,
            summary = "End this session family", description = "Revokes the family the presented access token belongs to; its access and refresh tokens stop working.",
            responses = mapOf(200 to "revoked", 401 to "no principal"),
        ),
        Endpoint(
            id = "me", method = "GET", path = "/v1/me", authenticated = true,
            summary = "Who am I", description = "The caller's account id, player id, display name (and whether they have set one), and age band.",
            responses = mapOf(200 to "profile", 401 to "no principal"),
        ),
        Endpoint(
            id = "me.profile", method = "PUT", path = "/v1/me/profile", authenticated = true,
            summary = "Set my display name",
            request = Schema("""{"type":"object","required":["displayName"],"properties":{"displayName":{"type":"string","maxLength":60}}}"""),
            description = "A name is the person's to give; it is never taken from a provider's token on their behalf.",
            responses = mapOf(200 to "profile", 400 to "malformed", 401 to "no principal"),
        ),
        Endpoint(
            id = "health", method = "GET", path = "/healthz", authenticated = false,
            summary = "Liveness, and the schema version the database stands at",
            description = "Unauthenticated. Reports the migration ledger's current version; a database the code cannot serve is a 503.",
            responses = mapOf(200 to "ok, with schemaVersion", 503 to "database unreachable or behind the code"),
        ),
        Endpoint(
            id = "openapi", method = "GET", path = "/openapi.json", authenticated = false,
            summary = "This document", description = "Rendered from the same registry the routes are mounted from.",
            responses = mapOf(200 to "OpenAPI 3.1 document"),
        ),
        Endpoint(
            id = "commands", method = "POST", path = "/v1/commands", authenticated = true,
            summary = "The one command endpoint (ADR-007)",
            description = "Every client-to-server state change, online or from a queue. Identity comes from the principal, the device from X-Thro-Device. Applied is 200; a replay returns what it returned; stale is 409 with the current row; a refusal is 422 in the store's words; a sequence gap is 409; a match the caller is not in is 404.",
            request = commandEnvelope,
            responses = mapOf(200 to "applied, or a replay of an earlier answer", 400 to "malformed", 401 to "no principal", 404 to "not this match, or not in it", 409 to "stale version, or sequence gap", 413 to "body over 64 KiB", 422 to "refused"),
        ),
        Endpoint(
            id = "me.inbox", method = "GET", path = "/v1/me/inbox", authenticated = true,
            summary = "The caller's own Secretary tasks, by section",
            description = "Tasks whose subject is the caller: consent, claims, anything the Secretary needs from them.",
            responses = mapOf(200 to "sections of tasks", 401 to "no principal"),
        ),
        Endpoint(
            id = "team.inbox", method = "GET", path = "/v1/teams/{teamId}/inbox", authenticated = true,
            summary = "A team's Secretary inbox, for those who run it",
            description = "Requires team.manage on the team (admin or captain). Anyone else is 403, and the refusal is on the audit record.",
            responses = mapOf(200 to "sections of tasks", 401 to "no principal", 403 to "you do not run this team"),
        ),
        Endpoint(
            id = "leagues", method = "GET", path = "/v1/leagues", authenticated = false,
            summary = "The public front of the leagues: seasons, divisions, teams and their home venues",
            description = "Public rows only — no person is on any of them. Each league lists its sources and each venue the basis it was connected to its team on (a secretary's word, or an inference from the team's name), because imported data says where it came from (PD-033).",
            query = listOf("locality" to "a town or district; case-insensitive substring of the league's locality, optional"),
            responses = mapOf(200 to "leagues, newest season first"),
        ),
        Endpoint(
            id = "events", method = "GET", path = "/v1/events", authenticated = false,
            summary = "Open-entry events that have not started yet, with their venues",
            description = "The notice on the pub door: open access only, public venues only, no person on any row. Eligibility, entry counts and whether the caller is in are on /v1/me/discovery.",
            query = listOf("from" to "date-time, default now"),
            responses = mapOf(200 to "events, soonest first, at most 100", 400 to "malformed date"),
        ),
        Endpoint(
            id = "me.discovery", method = "GET", path = "/v1/me/discovery", authenticated = true,
            summary = "Darts the caller can play, and why each card is there",
            description = "The discovery read model for the caller between from and to. Every card carries its reasons; nothing is called eligible that THRØ cannot check.",
            query = listOf("from" to "date-time, default now", "to" to "date-time, default from + 60 days", "locality" to "the caller's team's locality, optional"),
            responses = mapOf(200 to "sections of cards", 400 to "malformed dates", 401 to "no principal"),
        ),
    )

    /** OpenAPI 3.1, rendered by hand from [endpoints]. Deterministic: the same registry, the same bytes. */
    public fun openApi(): String {
        val paths = endpoints.groupBy { it.path }.entries.sortedBy { it.key }.joinToString(",\n") { (path, eps) ->
            val ops = eps.sortedBy { it.method }.joinToString(",\n") { e ->
                val params = (Regex("\\{(\\w+)}").findAll(path).map { it.groupValues[1] }.map { name ->
                    """{"name":${q(name)},"in":"path","required":true,"schema":{"type":"string","format":"uuid"}}"""
                } + e.query.map { (name, desc) -> """{"name":${q(name)},"in":"query","required":false,"description":${q(desc)},"schema":{"type":"string"}}""" }).toList()
                val security = if (e.authenticated) ""","security":[{"principal":[]}]""" else ""
                val body = e.request?.let { ""","requestBody":{"required":true,"content":{"application/json":{"schema":${it.json}}}}""" } ?: ""
                val responses = e.responses.entries.sortedBy { it.key }.joinToString(",") { (code, desc) ->
                    if (e.stream && code == 200) """"$code":{"description":${q(desc)},"content":{"text/event-stream":{}}}""" else """"$code":{"description":${q(desc)}}"""
                }
                """    "${e.method.lowercase()}":{"operationId":${q(e.id)},"summary":${q(e.summary)},"description":${q(e.description)},"parameters":[${params.joinToString(",")}]$security$body,"responses":{$responses}}"""
            }
            """  ${q(path)}:{
$ops
  }"""
        }
        return """{
"openapi":"3.1.0",
"info":{"title":"THRØ API","version":"$VERSION","description":"Routes over the command handlers. One command endpoint (ADR-007); identity from the principal, never the body (ADR-008); every relationship decision recorded."},
"components":{"securitySchemes":{"principal":{"type":"http","scheme":"bearer","description":"An access token from /v1/auth/apple, /v1/auth/google or /v1/auth/refresh (PD-030). Opaque; looked up per request; names an account, never a permission. A development server started with THRO_DEV_AUTH=1 accepts ${Authenticator.Dev.HEADER} instead."}}},
"paths":{
$paths
}
}
"""
    }

    internal fun q(s: String): String {
        val b = StringBuilder(s.length + 2).append('"')
        for (ch in s) when {
            ch == '\\' -> b.append("\\\\")
            ch == '"' -> b.append("\\\"")
            ch == '\n' -> b.append("\\n")
            ch == '\r' -> b.append("\\r")
            ch == '\t' -> b.append("\\t")
            ch < ' ' -> b.append("\\u%04x".format(ch.code))
            else -> b.append(ch)
        }
        return b.append('"').toString()
    }
}
