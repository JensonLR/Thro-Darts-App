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
            summary = "Who am I",
            description = "The caller's account id, player id, display name (and whether they have set one), and age band. "
                + "Carries the terms in force and whether this account has accepted them (PD-050), so the phone can hold "
                + "somebody at the agreement before their first public word without a second request to find out.",
            responses = mapOf(200 to "profile", 401 to "no principal"),
        ),
        Endpoint(
            id = "me.profile", method = "PUT", path = "/v1/me/profile", authenticated = true,
            summary = "Set my display name",
            request = Schema("""{"type":"object","properties":{"displayName":{"type":"string","maxLength":60},"ageBand":{"type":"string","enum":["adult","minor"],"description":"Self-declared, once asked. Never back to unknown. What unlocks friends (V028) is adult."}}}"""),
            description = "A name is the person's to give; it is never taken from a provider's token on their behalf.",
            responses = mapOf(200 to "profile", 400 to "malformed", 401 to "no principal"),
        ),
        Endpoint(
            id = "me.erase", method = "DELETE", path = "/v1/me", authenticated = true,
            summary = "Erase my account and everything that identifies me",
            description = "Destroys the display name, every Apple, Google and passkey credential, every session on "
                + "every device, the device labels, live friendships, the claim on the competitor row and the consent "
                + "record. Keeps the matches played, because a match is the other player's record too and a league's "
                + "table stands on it — and after this those rows carry a competitor id that resolves to no person "
                + "(V031, the shape V018 set). Cannot be undone; signing in again makes a new account. The caller's "
                + "session is dead the moment this returns.",
            responses = mapOf(200 to "what was destroyed, as counts", 401 to "no principal", 409 to "already erased"),
        ),
        Endpoint(
            id = "teams.create", method = "POST", path = "/v1/teams", authenticated = true,
            summary = "Start a team",
            description = "The caller becomes its first member and admin (team#admin). Plan §6, row one.",
            request = Schema("""{"type":"object","required":["name"],"properties":{"name":{"type":"string","minLength":2,"maxLength":60},"locality":{"type":["string","null"]}}}"""),
            responses = mapOf(200 to "the team, with your role", 400 to "a bad name", 401 to "no principal"),
        ),
        Endpoint(
            id = "teams.mine", method = "GET", path = "/v1/me/teams", authenticated = true,
            summary = "The teams the caller is in",
            description = "Current memberships only, newest first, with the caller's role and the member count.",
            responses = mapOf(200 to "teams", 401 to "no principal"),
        ),
        Endpoint(
            id = "teams.front", method = "GET", path = "/v1/teams/{teamId}", authenticated = false,
            summary = "A team's front",
            description = "Name, locality, home venue, the seasons it is in, and its roster — names only where identity.player_may_be_disclosed allows, everyone else counted and not named. A private team answers 404 to anyone not in it. With a bearer, yourRole says what you are in it, and the team's admin also sees each roster entry's memberId, to name a captain with (PD-045).",
            responses = mapOf(200 to "the front", 400 to "not a UUID", 404 to "no such team, or not yours to see"),
        ),
        Endpoint(
            id = "teams.invite", method = "POST", path = "/v1/teams/{teamId}/invite", authenticated = true,
            summary = "A team code to give the side",
            description = "Eight characters, thirty days, up to twenty people. Admin or captain only (V029).",
            responses = mapOf(200 to "code, expiresAt, maxUses", 401 to "no principal", 403 to "not the admin or captain, with the sentence to show"),
        ),
        Endpoint(
            id = "venues", method = "GET", path = "/v1/venues", authenticated = false,
            summary = "Public venues by name",
            description = "For a captain choosing a home: name contains q, optionally in a locality; at most twenty.",
            query = listOf("q" to "part of the venue's name, required", "locality" to "part of the town, optional"),
            responses = mapOf(200 to "venues", 400 to "q missing"),
        ),
        Endpoint(
            id = "teams.home", method = "POST", path = "/v1/teams/{teamId}/home", authenticated = true,
            summary = "Set the team's home venue",
            description = "An existing public venue by venueId, or a new one by name and locality. Admin or captain only. A change closes the old tenure and opens the new; nothing is overwritten.",
            request = Schema("""{"type":"object","properties":{"venueId":{"type":["string","null"],"format":"uuid"},"name":{"type":["string","null"]},"locality":{"type":["string","null"]}}}"""),
            responses = mapOf(200 to "the team's front", 400 to "neither a venue nor a name", 401 to "no principal", 403 to "not the admin or captain"),
        ),
        Endpoint(
            id = "teams.join", method = "POST", path = "/v1/teams/join", authenticated = true,
            summary = "Enter a team code",
            description = "The caller becomes a member, as a player. Refusals say why: not a code, unknown, expired, full, already in.",
            request = Schema("""{"type":"object","required":["code"],"properties":{"code":{"type":"string"}}}"""),
            responses = mapOf(200 to "the team, with your role", 401 to "no principal", 409 to "the code cannot be used, with the sentence to show",
                              429 to "too many codes tried from this address or device; Retry-After says when"),
        ),
        Endpoint(
            id = "safety.report", method = "POST", path = "/v1/reports", authenticated = true,
            summary = "Report something somebody wrote (PD-050)",
            description = "A team, venue or league name, an account, or a match. Names the thing and a sentence of reason; "
                + "the answer is due within a day, and a report raised by or about a child goes to the front of the queue.",
            request = Schema("""{"type":"object","required":["subjectKind","subjectId","reason"],"properties":{"subjectKind":{"type":"string","enum":["account","team","venue","league","match"]},"subjectId":{"type":"string","format":"uuid"},"reason":{"type":"string"}}}"""),
            responses = mapOf(200 to "the report, with when it is answered by", 400 to "not something THRØ can report, or no reason given",
                              401 to "no principal"),
        ),
        Endpoint(
            id = "safety.block", method = "POST", path = "/v1/blocks", authenticated = true,
            summary = "Ask not to be reached by an account (PD-050)",
            description = "No reason is asked for and none is stored. Neither account can invite, befriend, claim a seat "
                + "against or watch the other while it stands. Blocking twice is blocking once.",
            request = Schema("""{"type":"object","required":["accountId"],"properties":{"accountId":{"type":"string","format":"uuid"}}}"""),
            responses = mapOf(200 to "the accounts you have blocked", 400 to "you cannot block yourself", 401 to "no principal"),
        ),
        Endpoint(
            id = "safety.unblock", method = "DELETE", path = "/v1/blocks/{accountId}", authenticated = true,
            summary = "Lift a block (PD-050)",
            description = "The row is kept and marked lifted; blocking again later is a new block.",
            responses = mapOf(200 to "the accounts you have blocked", 401 to "no principal"),
        ),
        Endpoint(
            id = "safety.blocks", method = "GET", path = "/v1/blocks", authenticated = true,
            summary = "The accounts you have blocked (PD-050)",
            description = "Ids only: a block list names nobody it does not have to, and the phone already knows who it asked "
                + "to block. Lifted blocks are not in it.",
            responses = mapOf(200 to "the list", 401 to "no principal"),
        ),
        Endpoint(
            id = "safety.queue", method = "GET", path = "/v1/reports", authenticated = true,
            summary = "What is waiting to be answered (PD-050)",
            description = "The moderation queue: unanswered first, then a report raised by or about a child, then by the "
                + "hour its answer is due. Open only to the accounts named at boot as answering reports — THRØ has no "
                + "staff table, and a queue anyone could read is a queue that tells people they were reported.",
            responses = mapOf(200 to "the queue, each report with its reason and when it is due", 401 to "no principal",
                              403 to "not one of the people who answer reports"),
        ),
        Endpoint(
            id = "safety.decide", method = "POST", path = "/v1/reports/{reportId}/decisions", authenticated = true,
            summary = "Answer a report (PD-050)",
            description = "A decision is a row of its own, so a second look is a second decision and never an edit of the "
                + "first. Nothing a player wrote is destroyed by one: it is left, hidden or corrected, or the account is "
                + "suspended, and the note says why.",
            request = Schema("""{"type":"object","required":["outcome","note"],"properties":{"outcome":{"type":"string","enum":["left","hidden","corrected","account_suspended","not_upheld"]},"note":{"type":"string"}}}"""),
            responses = mapOf(200 to "the decision", 400 to "not one of the answers a report can have, or no note given",
                              401 to "no principal", 403 to "not one of the people who answer reports",
                              404 to "no such report"),
        ),
        Endpoint(
            id = "me.terms", method = "POST", path = "/v1/me/terms", authenticated = true,
            summary = "Accept the terms (PD-050)",
            description = "Recorded once per version, with the version accepted, because that is the only honest answer to "
                + "what somebody agreed to. Accepting a version twice changes nothing.",
            request = Schema("""{"type":"object","properties":{"version":{"type":"string"}}}"""),
            responses = mapOf(200 to "the version now accepted", 401 to "no principal"),
        ),
        Endpoint(
            id = "teams.league.say", method = "POST", path = "/v1/teams/{teamId}/league", authenticated = true,
            summary = "Say which league the team plays in (PD-049)",
            description = "The team's admin or captain says the team plays in a league THRØ lists. It is carried as their "
                + "say and never as the league's listing: a league's divisions are filled from the league's own published "
                + "pages and from nothing else. Saying it twice is saying it once.",
            request = Schema("""{"type":"object","required":["leagueId"],"properties":{"leagueId":{"type":"string","format":"uuid"}}}"""),
            responses = mapOf(200 to "the team's front", 401 to "no principal", 403 to "not the team's admin or captain",
                              404 to "THRØ lists no league like that"),
        ),
        Endpoint(
            id = "teams.league.withdraw", method = "DELETE", path = "/v1/teams/{teamId}/league/{leagueId}", authenticated = true,
            summary = "Stop saying the team plays in that league (PD-049)",
            description = "Marked withdrawn and kept, never deleted: who said their team played there, and when, stays readable.",
            responses = mapOf(200 to "the team's front", 401 to "no principal", 403 to "not the team's admin or captain"),
        ),
        Endpoint(
            id = "teams.adopt", method = "POST", path = "/v1/teams/{teamId}/adopt", authenticated = true,
            summary = "Say a listed league team is yours, and run it on THRØ (PD-047)",
            description = "For a team read out of a league's pages that nobody on THRØ runs. The caller becomes its admin by their "
                + "own say, and the team's front says that is what happened. Adults only, and an age nobody has said is not adult. "
                + "A team somebody already runs is joined with their code instead.",
            responses = mapOf(200 to "the team, with your role", 401 to "no principal",
                              409 to "it cannot be taken on, with the sentence to show"),
        ),
        Endpoint(
            id = "teams.role", method = "POST", path = "/v1/teams/{teamId}/roles", authenticated = true,
            summary = "Name the captain or vice-captain, or make somebody a player again (PD-045)",
            description = "Admin only. One captain and one vice-captain at a time: naming one when there is one makes the old one "
                + "a player. A change ends the membership row and opens another — who captained the side is the team's "
                + "history (V014) — and the captain's team.manage relation is granted and revoked with it. memberId is the "
                + "roster entry's own handle, which the team's front shows to its admin alone.",
            request = Schema("""{"type":"object","required":["memberId","role"],"properties":{"memberId":{"type":"string","format":"uuid"},"role":{"type":"string","enum":["captain","vice_captain","player"]}}}"""),
            responses = mapOf(200 to "the team's front, as its admin reads it", 400 to "malformed", 401 to "no principal",
                              403 to "not the team's admin, with the sentence to show", 422 to "refused, in words"),
        ),
        Endpoint(
            id = "friends", method = "GET", path = "/v1/friends", authenticated = true,
            summary = "The caller's friends",
            description = "Display names only: a friend is somebody who told you their name across a table. Newest first.",
            responses = mapOf(200 to "friends", 401 to "no principal", 403 to "the development principal has no account"),
        ),
        Endpoint(
            id = "friends.invite", method = "POST", path = "/v1/friends/invite", authenticated = true,
            summary = "A friend code for the caller to give somebody in person",
            description = "Eight characters, seven days, one use. Only an account that has said it is an adult may make one; an unknown age is refused, not guessed (V028).",
            responses = mapOf(200 to "code and expiresAt", 401 to "no principal", 403 to "not an adult account, with the sentence to show"),
        ),
        Endpoint(
            id = "friends.accept", method = "POST", path = "/v1/friends/accept", authenticated = true,
            summary = "Enter a friend code",
            description = "Both become friends and the code is spent. Refusals say why: not a code, unknown, used, expired, your own, already friends.",
            request = Schema("""{"type":"object","required":["code"],"properties":{"code":{"type":"string","description":"eight letters and numbers, case and spaces ignored"}}}"""),
            responses = mapOf(200 to "the new friend", 401 to "no principal", 403 to "not an adult account", 409 to "the code cannot be used, with the sentence to show",
                              429 to "too many codes tried from this address or device; Retry-After says when"),
        ),
        Endpoint(
            id = "friends.remove", method = "POST", path = "/v1/friends/{accountId}/remove", authenticated = true,
            summary = "End a friendship from this side",
            description = "Recorded as ended, never deleted. Either side may.",
            responses = mapOf(200 to "removed: whether there was one to end", 400 to "not a UUID", 401 to "no principal"),
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
            id = "matches.upload", method = "POST", path = "/v1/matches", authenticated = true,
            summary = "Send a match this phone scored to THRØ (PD-040)",
            description = "The device's journal as it wrote it — every visit and every retraction, in deviceSeq order — "
                + "rather than a replayed total, because a screen that shows a struck row and a server that never heard "
                + "of it are two accounts of one night. Idempotent by (match, device, deviceSeq): the same upload twice "
                + "is the same rows, and a phone that lost signal half way sends the lot again. The other seat becomes a "
                + "competitor THRØ holds no name for, claimable later by a code. The match is recorded self-reported: "
                + "one player's word until the other confirms it (PD-011). A match that ended short (PD-016) is sent "
                + "as it ended: its retirement or abandonment is the last row, and nothing is added after it (V034).",
            request = Schema("""{"type":"object","required":["matchId","deviceId","seat","format","rows"],"properties":{"matchId":{"type":"string","format":"uuid"},"deviceId":{"type":"string","format":"uuid"},"seat":{"type":"string","enum":["home","away"],"description":"Which seat the caller sat in. The other is minted."},"format":{"type":"object","required":["startingScore","inRule","outRule","legsMode","legsTarget","throwFirst"],"properties":{"startingScore":{"type":"integer"},"inRule":{"type":"string"},"outRule":{"type":"string"},"legsMode":{"type":"string"},"legsTarget":{"type":"integer"},"throwFirst":{"type":"string","enum":["home","away"]}}},"rows":{"type":"array","items":{"type":"object","required":["deviceSeq","kind","occurredAt"],"properties":{"deviceSeq":{"type":"integer"},"kind":{"type":"string","enum":["visit","retraction","retirement","abandonment"],"description":"An ending — retirement or abandonment — is the last row when there is one."},"seat":{"type":"string","enum":["home","away"],"description":"The seat that threw; for a retirement, the seat that retired. An abandonment names nobody and may leave it out."},"visitTotal":{"type":["integer","null"]},"correctsSeq":{"type":["integer","null"]},"occurredAt":{"type":"string"},"occurredTz":{"type":"string"}}}}}}"""),
            responses = mapOf(200 to "what was stored, and what was already held", 400 to "malformed",
                              401 to "no principal", 413 to "body over 64 KiB", 422 to "refused, in words"),
        ),
        Endpoint(
            id = "matches.code", method = "POST", path = "/v1/matches/{matchId}/code", authenticated = true,
            summary = "A code for the other seat of a match the caller sent (PD-043)",
            description = "Eight characters, seven days, one use. The sender gives it to the player they played, who enters it "
                + "on their own phone to take the other seat. Only the player who sent the match may make one, only for a "
                + "match sent from a phone, and only while the other seat is nobody's; asking again while a code is live "
                + "hands back the same code rather than a second one.",
            responses = mapOf(200 to "code, seat and expiresAt", 400 to "not a UUID", 401 to "no principal",
                              404 to "not a match the caller sent", 422 to "no code can be made for it, in words"),
        ),
        Endpoint(
            id = "matches.claim", method = "POST", path = "/v1/matches/claim", authenticated = true,
            summary = "Enter a match code: the seat it was made for becomes the caller's",
            description = "Recorded as a seat claim (V037) and nothing else: the match, and the evidence under it, stay exactly "
                + "as they were written. Refusals say why — not a code, unknown, used, expired, your own, already in the "
                + "match, the seat already taken. Rationed per address and per device, like every route that takes a code.",
            request = Schema("""{"type":"object","required":["code"],"properties":{"code":{"type":"string","description":"eight letters and numbers; case, spaces and dashes ignored"}}}"""),
            responses = mapOf(200 to "the match, as the caller now reads it", 400 to "malformed", 401 to "no principal",
                              422 to "the code cannot be used, with the sentence to show",
                              429 to "too many codes tried from this address or device; Retry-After says when"),
        ),
        Endpoint(
            id = "matches.one", method = "GET", path = "/v1/matches/{matchId}", authenticated = true,
            summary = "A match the caller played in",
            description = "Both seats — a name only where identity.player_may_be_disclosed allows — the legs as the engine replays "
                + "the record with struck visits left out, how it ended, who won, which seat sent it, each seat's answer where it still stands, "
                + "and its standing: self-reported, confirmed, disputed, or recorded for a match scored on THRØ as it was "
                + "played. Derived from the log on every read and stored nowhere. Anyone not in the match is answered 404.",
            responses = mapOf(200 to "the match", 400 to "not a UUID", 401 to "no principal", 404 to "not a match the caller played in"),
        ),
        Endpoint(
            id = "matches.mine", method = "GET", path = "/v1/me/matches", authenticated = true,
            summary = "The matches the caller played in, newest first",
            description = "Sent by the caller, or taken with a code; at most thirty, each in the shape GET /v1/matches/{matchId} answers.",
            responses = mapOf(200 to "matches", 401 to "no principal"),
        ),
        Endpoint(
            id = "matches.answer", method = "POST", path = "/v1/matches/{matchId}/answer", authenticated = true,
            summary = "The other player's answer for a result they did not send",
            description = "agree true confirms the result and false contests it, appended to the trust stream as ResultConfirmed "
                + "or ResultContested naming the seat (V037). Every answer is kept and the latest stands — but only for the "
                + "record it answered: when the sender sends more of the match, the other player is asked again. The player "
                + "who sent a match cannot answer for it, because their word is the match, and an abandoned match has no "
                + "result to confirm. The phone names itself in X-Thro-Device.",
            request = Schema("""{"type":"object","required":["agree"],"properties":{"agree":{"type":"boolean","description":"true confirms the result, false contests it"}}}"""),
            responses = mapOf(200 to "the match, with the answer counted", 400 to "malformed, or no X-Thro-Device", 401 to "no principal",
                              404 to "not a match the caller played in", 409 to "the answer could not be recorded; try again",
                              422 to "refused, in words"),
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
            id = "leagues.affiliation.accept", method = "POST",
            path = "/v1/seasons/{leagueSeasonId}/affiliations/{affiliationId}", authenticated = true,
            summary = "Accept a team into a league season (PD-053)",
            description = "Applied becomes accepted, and never the other way back. Only an accepted team is a row in "
                + "the season's table, so this is the act that puts a side in the league. The caller must administer "
                + "the season: a league administrator is named, never self-appointed, so a server where nobody has "
                + "been named refuses everybody.",
            responses = mapOf(200 to "the affiliation, accepted", 400 to "not a UUID", 401 to "no principal",
                              403 to "you do not administer this league season", 404 to "no such affiliation",
                              409 to "that team is not waiting to be accepted"),
        ),
        Endpoint(
            id = "leagues.result", method = "POST", path = "/v1/fixtures/{fixtureId}/result", authenticated = true,
            summary = "Record what a fixture finished as (PD-055)",
            description = "The legs each side won. **The caller does not choose what kind of result this is — the "
                + "evidence does.** A fixture with a match scored on THRØ behind it records a played result; one "
                + "without records the official's declared word, which counts in the table exactly the same and is "
                + "never evidence for a rating. **Correcting a result is a second decision that supersedes the "
                + "first, never an edit**: send the standing result's `outcomeId` as `supersedes` and the earlier "
                + "decision stays on the record with its author. Omit it and a fixture that already has a result "
                + "answers 409; send one that has itself been superseded since you read it and it answers 409 too, "
                + "because that is a correction somebody else made and this would silently undo it (PD-059).",
            request = Schema("""{"type":"object","required":["legsHome","legsAway"],"properties":{"legsHome":{"type":"integer","minimum":0},"legsAway":{"type":"integer","minimum":0},"supersedes":{"type":"string","format":"uuid","description":"the outcomeId of the result being corrected"}}}"""),
            responses = mapOf(200 to "the outcome, saying whether it was played or declared", 400 to "not two numbers, or supersedes is not a UUID",
                              401 to "no principal", 403 to "you do not administer this league season",
                              404 to "no such fixture",
                              409 to "this fixture already has a result, or the one you named is no longer the standing one"),
        ),
        Endpoint(
            id = "leagues.award", method = "POST", path = "/v1/fixtures/{fixtureId}/award", authenticated = true,
            summary = "Award a fixture nobody played (PD-055)",
            description = "A decision with an actor and a reason, and never a scoreline: inventing one would reward "
                + "an unplayed match in every leg-difference tie-break beneath it (ADR-012). The award goes to one of "
                + "the fixture's two teams and says why. It corrects a standing result the same way a scoreline does, "
                + "by naming it as `supersedes`, because a fixture recorded as played and later awarded is a "
                + "correction and not a second result (PD-059).",
            request = Schema("""{"type":"object","required":["toTeamId","reason"],"properties":{"toTeamId":{"type":"string","format":"uuid"},"reason":{"type":"string"},"supersedes":{"type":"string","format":"uuid","description":"the outcomeId of the result being corrected"}}}"""),
            responses = mapOf(200 to "the outcome", 400 to "not a UUID, or no reason given", 401 to "no principal",
                              403 to "you do not administer this league season", 404 to "no such fixture",
                              409 to "this fixture already has a result, or the one you named is no longer the standing one"),
        ),
        Endpoint(
            id = "seasons.fixtures", method = "GET", path = "/v1/seasons/{leagueSeasonId}/fixtures",
            authenticated = false,
            summary = "A league season's fixtures, played and still to play (PD-056)",
            description = "The other half of a league's own data: the table says how the season stands, this says "
                + "what is left. Each fixture carries its date, its lifecycle — scheduled, rearranged, postponed — "
                + "the venue, and what it finished as where it has: played, declared by an official, awarded or "
                + "walked over. Read from the same rows the table is, so the two cannot disagree. Public means "
                + "public: a team or venue marked private is not named, though the fixture is still listed, because "
                + "hiding it would leave a hole in a league's own calendar.",
            responses = mapOf(200 to "the fixtures, soonest first", 400 to "not a UUID", 404 to "no such league season"),
        ),
        Endpoint(
            id = "seasons.standings", method = "GET", path = "/v1/seasons/{leagueSeasonId}/standings",
            authenticated = false,
            summary = "A league season's table, computed from the results under it (PD-054)",
            description = "Derived on every read from each fixture's live outcome and the league's own approved points "
                + "policy. Nothing is stored, so a table cannot drift from the results beneath it, be edited into "
                + "disagreeing with them, or be left behind by a correction. Only teams the league affiliated are rows: "
                + "a team that merely says it plays in the league (PD-049) never is. An awarded fixture or a walkover "
                + "moves the points and never the legs, so a match nobody played cannot pollute a leg-difference "
                + "tie-break. Every row says which step of the declared chain separated it from the one below, and every "
                + "table says whose rules ordered it — the league's own, or THRØ's standard of two a win and one a draw, "
                + "named as the standard so nobody mistakes it for their league's constitution.",
            query = listOf("division" to "a division of this season; omitted gives every division"),
            responses = mapOf(200 to "the table, by division, with the rules it was ordered under",
                              400 to "not a UUID", 404 to "no such league season",
                              409 to "this league's own points rules name something THRØ cannot apply, and say what"),
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
