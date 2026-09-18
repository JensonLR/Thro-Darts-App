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
            description = "webcredentials for the configured app ids, so iOS offers passkeys for this relying party, and applinks for /link/* so a screen's sign-in code opens the app (PD-117), and for /league/*, /event/* and /team/* so a shared page opens the same thing in the app (PD-127). 404 when no app id is configured.",
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
            id = "auth.link.start", method = "POST", path = "/v1/auth/link", authenticated = false,
            summary = "A screen asks to be signed in by the phone that holds the account (PD-114)",
            request = Schema("""{"type":"object","required":["deviceId"],"properties":{"deviceId":{"type":"string","format":"uuid","description":"This screen's device id; the session that results is bound to it."}}}"""),
            description = "Returns a six-character code (no look-alikes) to show, a link to poll, and when the code expires (five minutes). "
                + "The person types the code into the app they are signed in on; nothing here is a password.",
            responses = mapOf(200 to "linkId, code, expiresAt", 400 to "no device id", 429 to "too many attempts from this address or device; Retry-After says when"),
        ),
        Endpoint(
            id = "auth.link.approve", method = "POST", path = "/v1/auth/link/{code}/approve", authenticated = true,
            summary = "The signed-in phone approves a screen's code (PD-114)",
            description = "Binds the code to this account and the credential it last signed in with; the screen then collects a session of its own. "
                + "Read however it is typed. A code THRØ does not have, or that expired, is a 404; one already approved a 409.",
            responses = mapOf(200 to "approved", 401 to "no principal", 403 to "this account is suspended", 404 to "no such code, or expired", 409 to "already approved"),
        ),
        Endpoint(
            id = "auth.link.claim", method = "GET", path = "/v1/auth/link/{linkId}", authenticated = false,
            summary = "The screen collects its session, once (PD-114)",
            query = listOf("deviceId" to "the device id the screen asked with; another device's ask is a 404"),
            description = "202 while the phone has not spoken; 200 with the session once it has, once only; 410 after that, or once the code has expired.",
            responses = mapOf(200 to sessionResponse, 202 to "waiting for the phone", 400 to "no device id", 404 to "no such link for this device", 410 to "used or expired; ask for a new code"),
        ),
        Endpoint(
            id = "auth.providers", method = "GET", path = "/v1/auth/providers", authenticated = false,
            summary = "Which providers the web may offer (PD-116)",
            description = "Apple's Services ID and Google's Web client id, when the server is configured with them; null otherwise. Public: a client id is not a secret.",
            responses = mapOf(200 to "apple and google, each a client id or null"),
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
            request = Schema("""{"type":"object","properties":{"displayName":{"type":"string","maxLength":60},"ageBand":{"type":"string","enum":["adult","minor"],"description":"Self-declared, once asked. Never back to unknown. What unlocks friends (V028) is adult."},"contactEmail":{"type":"string","maxLength":254,"description":"PD-104: an organiser's contact email — an adult who runs a league or a team. Empty takes it away. 403 for anybody else, with why."}}}"""),
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
                + "against or watch the other while it stands. Blocking twice is blocking once. Name the person by "
                + "`playerId` — the id a roster, a seat or a fixture shows — and THRØ joins it to the account behind "
                + "them; `accountId` is accepted too, for a caller that already holds one. A player nobody has "
                + "claimed, such as a walk-up, has no account and cannot be blocked.",
            request = Schema("""{"type":"object","properties":{"accountId":{"type":"string","format":"uuid"},"playerId":{"type":"string","format":"uuid"}},"oneOf":[{"required":["accountId"]},{"required":["playerId"]}]}"""),
            responses = mapOf(200 to "the accounts you have blocked", 400 to "you cannot block yourself", 401 to "no principal",
                              404 to "no account behind that player"),
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
            id = "me.consent", method = "POST", path = "/v1/me/consent", authenticated = true,
            summary = "Say whether you may be named",
            description = "Two separate answers (PD-088). `listing` is being named on your team's public page; " +
                "`live` is being named on a screen while you are playing, which says where you are at the time and " +
                "is therefore asked for on its own. Only for yourself: a guardian's consent is recorded by a named " +
                "person through the secretary, never by a caller asserting it here. Saying no revokes and keeps the " +
                "record, so what somebody agreed to and when is answerable. `live` is refused for anyone not " +
                "recorded as an adult, with the sentence to show them.",
            request = Schema("""{"type":"object","required":["scope","given"],"properties":{"scope":{"enum":["listing","live"]},"given":{"type":"boolean"}}}"""),
            responses = mapOf(200 to "scope, given, and why not when it was refused", 400 to "no such scope",
                              401 to "no principal", 403 to "the development principal has no account"),
        ),
        Endpoint(
            id = "seasons.live", method = "GET", path = "/v1/seasons/{leagueSeasonId}/live", authenticated = false,
            summary = "The games in play in this season, for a screen in the room (PD-088)",
            description = "Every match with a visit in it and no outcome yet: the two teams, the venue, the legs, " +
                "the remainders and whose throw it is. A player is **named only** where " +
                "`identity.player_may_be_shown_live` allows — an adult who has said yes, and nobody else; a minor " +
                "and an unknown age are both null, never a placeholder. A private team is unnamed and its game is " +
                "still listed. Needs no account, because the screen it is for has nobody signed in to it.",
            query = listOf("limit" to "at most this many, default 20, capped at 20"),
            responses = mapOf(200 to "games", 400 to "not a UUID"),
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
            summary = "Liveness, the schema version the database stands at, and which code is answering",
            description = "Unauthenticated. Reports the migration ledger's current version; a database the code cannot serve is a 503. " +
                "Also the newest migration this code carries (codeVersion) and the commit it was built from where the host names one " +
                "(commit), so a deploy can tell the new API from the one it replaced: after a migration both answer at the same " +
                "schemaVersion (PD-095).",
            responses = mapOf(200 to "ok, with schemaVersion, codeVersion and commit", 503 to "database unreachable or behind the code"),
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
            id = "leagues.get", method = "GET", path = "/v1/leagues/{leagueId}", authenticated = false,
            summary = "One public league, as the list words it (PD-127)",
            description = "What the league's page at thro.uk/league/{leagueId} reads: its standing (run here, or listed from elsewhere), its seasons with their fixture and result counts, its divisions and teams, and the teams that say they play in it. No person is on it.",
            responses = mapOf(200 to "the league", 400 to "an id that is not a UUID", 404 to "no public league has that id"),
        ),
        Endpoint(
            id = "leagues.start", method = "POST", path = "/v1/leagues", authenticated = true,
            summary = "Start a league on THRØ, with its first season, and run it (PD-100)",
            description = "The league, its first season and that season's divisions, together or not at all, and whoever "
                + "starts it becomes the season's administrator. A league THRØ lists from elsewhere is not this: it already "
                + "has somebody who runs it, and is run only by the person named for it (PD-053).",
            request = Schema("""{"type":"object","required":["name","season"],"properties":{"name":{"type":"string","minLength":2,"maxLength":80},"locality":{"type":"string"},"visibility":{"type":"string","enum":["public","private"],"description":"private keeps it off the public list: a rehearsal, or not yet public"},"season":{"type":"object","required":["label","startsOn","endsOn"],"properties":{"label":{"type":"string","minLength":1,"maxLength":40},"startsOn":{"type":"string","format":"date"},"endsOn":{"type":"string","format":"date"},"divisions":{"type":"array","maxItems":12,"items":{"type":"string"}}}}}}"""),
            responses = mapOf(200 to "the league and its first season", 400 to "a name, label, date, division or visibility of the wrong shape", 401 to "no principal"),
        ),
        Endpoint(
            id = "leagues.update", method = "POST", path = "/v1/leagues/{leagueId}", authenticated = true,
            summary = "Rename a league started on THRØ, take it private or public, or end it (PD-103)",
            description = "Only the person who started the league. A private league is off the public list and its name is "
                + "shown nowhere public; its seasons still run for its organiser. Ending is recorded once and never undone: "
                + "an ended league keeps and answers for every season it had and takes no more. A league THRØ lists from "
                + "elsewhere refuses everybody here.",
            request = Schema("""{"type":"object","properties":{"name":{"type":"string","minLength":2,"maxLength":80},"visibility":{"type":"string","enum":["public","private"]},"ended":{"type":"boolean"}}}"""),
            responses = mapOf(200 to "the league as it now stands", 400 to "a name or visibility of the wrong shape", 401 to "no principal",
                              403 to "you did not start this league, or THRØ lists it from elsewhere", 404 to "no such league",
                              409 to "the league has already ended"),
        ),
        Endpoint(
            id = "leagues.season.open", method = "POST", path = "/v1/leagues/{leagueId}/seasons", authenticated = true,
            summary = "Open the next season of a league started on THRØ (PD-100)",
            description = "Only the person who started the league opens its seasons, and becomes each one's administrator. "
                + "A league THRØ lists from elsewhere refuses everybody here, and says why.",
            request = Schema("""{"type":"object","required":["label","startsOn","endsOn"],"properties":{"label":{"type":"string","minLength":1,"maxLength":40},"startsOn":{"type":"string","format":"date"},"endsOn":{"type":"string","format":"date"},"divisions":{"type":"array","maxItems":12,"items":{"type":"string"}}}}"""),
            responses = mapOf(200 to "the league and the season opened", 400 to "a label, date or division of the wrong shape", 401 to "no principal",
                              403 to "you did not start this league, or THRØ lists it from elsewhere", 404 to "no such league",
                              409 to "this league already has a season with that label"),
        ),
        Endpoint(
            id = "seasons.teams.add", method = "POST", path = "/v1/seasons/{leagueSeasonId}/teams", authenticated = true,
            summary = "Add a team to a league season, in it at once (PD-100)",
            description = "The league letting a team in itself, so there is no application to accept. The team is a listed "
                + "one that nobody runs yet. In a season with divisions it names one of them.",
            request = Schema("""{"type":"object","required":["name"],"properties":{"name":{"type":"string","minLength":2,"maxLength":60},"divisionId":{"type":"string","format":"uuid"}}}"""),
            responses = mapOf(200 to "the team, accepted into the season", 400 to "no name, or divisionId is not a UUID", 401 to "no principal",
                              403 to "you do not administer this league season", 404 to "no such league season",
                              409 to "the season already has a team with that name", 422 to "the division is not this season's, or none was named"),
        ),
        Endpoint(
            id = "seasons.organiser", method = "GET", path = "/v1/seasons/{leagueSeasonId}/organiser", authenticated = true,
            summary = "How to reach the people running a league season (PD-104)",
            description = "The contact emails the season's administrators chose to give, for the admins of teams accepted into "
                + "the season and for the administrators themselves. Nobody else, and never public. An organiser who gave "
                + "none is not on the list, and a season whose organisers gave none answers an empty list rather than an "
                + "invented one.",
            responses = mapOf(200 to "the contacts, possibly none", 400 to "not a UUID", 401 to "no principal",
                              403 to "you neither run this season nor a team in it", 404 to "no such league season"),
        ),
        Endpoint(
            id = "seasons.history", method = "GET", path = "/v1/seasons/{leagueSeasonId}/history", authenticated = true,
            summary = "Who changed what in a season, newest first (PD-120)",
            description = "By the season's administrators. Results, corrections, awards, annulments, moved fixtures, rules and "
                + "registrations, each read back from the row that already records its actor and its time, as a sentence. An "
                + "official is named only where THRØ may name them; otherwise `who` is null and the sentence stands.",
            responses = mapOf(200 to "entries: at, who, kind (result, correction, award, void, move, rules, registration), what",
                              401 to "no principal", 403 to "you do not administer this season", 404 to "no such season"),
        ),
        Endpoint(
            id = "seasons.fixtures.read", method = "POST", path = "/v1/seasons/{leagueSeasonId}/fixtures/read", authenticated = true,
            summary = "Paste the fixture list: read each line into a fixture to confirm (PD-122)",
            description = "By the season's administrator. The league's list as it is written — a date heading, 'Riverside A v Grange A "
                + "7.30pm', '15 Oct - Grange v Dolphin' — is read a line at a time by a System One model against the season's own "
                + "teams. A heading's date carries down; the year is the one that puts the date inside the season; a fixture "
                + "with no time takes the list's usual one. Each row names its doubt (teams, date, time). **Nothing is "
                + "scheduled here**: the rows go, confirmed, to `POST /v1/seasons/{id}/fixtures`. At most 200 lines.",
            request = Schema("""{"type":"object","required":["text"],"properties":{"text":{"type":"string","maxLength":20000}}}"""),
            responses = mapOf(200 to "rows (line, text, homeTeamId, home, awayTeamId, away, on, time, scheduledAt, confidence, doubt) and skipped (line, text, why)",
                              400 to "nothing pasted, or too much", 401 to "no principal", 403 to "you do not administer this season", 404 to "no such season",
                              503 to "no model on this server, or the model did not answer"),
        ),
        Endpoint(
            id = "seasons.results.read", method = "POST", path = "/v1/seasons/{leagueSeasonId}/results/read", authenticated = true,
            summary = "Paste the results sheet: read each line into a result to confirm (PD-159)",
            description = "By the season's administrator. A week's sheet as it is published — a heading carrying the date, "
                + "'Grange A 5 Dolphin 3', 'Crown w/o Grange B', 'Riverside B v Crown — postponed' — is read a line at a time "
                + "against the season's own teams and fixtures. **No model is used**: the pair is matched by name, the "
                + "scoreline by the same expression the desk uses, and which of a pair's two meetings is meant comes from the "
                + "date the sheet's own heading carries down. A row that cannot be settled says which part is in doubt and is "
                + "not offered for a tick. **Nothing is recorded here**: the rows go, confirmed, to the ordinary result and "
                + "award routes. At most 200 lines and 20,000 characters.",
            request = Schema("""{"type":"object","required":["text"],"properties":{"text":{"type":"string","maxLength":20000}}}"""),
            responses = mapOf(200 to "rows (line, text, kind, fixtureId, home, away, at, legsHome, legsAway, awardToTeamId, awardTo, doubt, ready) and skipped (line, text, why)",
                              400 to "nothing pasted, or too much", 401 to "no principal", 403 to "you do not administer this season", 404 to "no such season"),
        ),
        Endpoint(
            id = "seasons.understand", method = "POST", path = "/v1/seasons/{leagueSeasonId}/understand", authenticated = true,
            summary = "Tell THRØ: read a sentence on the desk into an act to confirm (PD-119)",
            description = "By the season's administrator. One sentence — 'Grange A beat Dolphin 5-3 last night', 'walkover to Riverside', "
                + "'add Riverside A v Dolphin next Thursday at 8' — is read by a System One model against the season's own fixtures "
                + "and teams into one of six acts (result, award, void, move, schedule, points) with its arguments filled, a confidence, and the "
                + "part in doubt named. **Nothing is recorded here**: the answer is a card for the person to confirm through the "
                + "act's own route. 503 when this server has no model to read with.",
            request = Schema("""{"type":"object","required":["text"],"properties":{"text":{"type":"string","maxLength":400}}}"""),
            responses = mapOf(200 to "what the sentence was read as: act, confidence, ready, say, doubt, fixture (with alternatives), result, award, schedule, move, points, reason",
                              400 to "no sentence, or more than one", 401 to "no principal", 403 to "you do not administer this season", 404 to "no such season",
                              503 to "no model on this server, or the model did not answer"),
        ),
        Endpoint(
            id = "seasons.points", method = "POST", path = "/v1/seasons/{leagueSeasonId}/points", authenticated = true,
            summary = "Set the points rules a season's table is ordered by (PD-112)",
            description = "By the season's administrator: points for a win, a draw, a loss and an award, points per leg won, and the order "
                + "of tie-breaks (points, leg_difference, legs_for, head_to_head, played). Read by the same parser the table uses, so a "
                + "rule THRØ cannot order by is refused here. In force from today; the rules before are kept, superseded. A season whose "
                + "table is pinned is not changed after the fact.",
            request = Schema("""{"type":"object","properties":{"win":{"type":"integer","minimum":0},"draw":{"type":"integer","minimum":0},"loss":{"type":"integer","minimum":0},"awarded":{"type":"integer","minimum":0},"pointsPerLegWon":{"type":"integer","minimum":0},"tieBreak":{"type":"array","items":{"type":"string","enum":["points","leg_difference","legs_for","head_to_head","played"]}},"awardsCountAsPlayed":{"type":"boolean"}}}"""),
            responses = mapOf(200 to "the rules, approved, and the sentence the table will show", 400 to "a rule THRØ cannot execute, said in words", 401 to "no principal", 403 to "you do not administer this season", 404 to "no such season", 409 to "the table is pinned"),
        ),
        Endpoint(
            id = "seasons.teams.division", method = "POST", path = "/v1/seasons/{leagueSeasonId}/teams/{teamId}/division", authenticated = true,
            summary = "Move a team to another division, or out of any (PD-112)",
            description = "By the season's administrator. Refused while the team has an undecided fixture in its current division — rearrange or void "
                + "it first; decided fixtures stay where they were played.",
            request = Schema("""{"type":"object","properties":{"divisionId":{"type":["string","null"],"format":"uuid"}}}"""),
            responses = mapOf(200 to "the team and its division", 400 to "not this season's division", 401 to "no principal", 403 to "you do not administer this season", 404 to "no such season or team", 409 to "already there, or undecided fixtures"),
        ),
        Endpoint(
            id = "seasons.registrations.transfer", method = "POST", path = "/v1/seasons/{leagueSeasonId}/registrations/{playerId}/transfer", authenticated = true,
            summary = "Transfer a registered player to another team (PD-112)",
            description = "By the season's administrator, from a date, with a reason: the current registration ends on that date and a new one "
                + "with the other team begins, naming the one it supersedes, under the same policy. Registered throughout.",
            request = Schema("""{"type":"object","required":["toTeamId","from","note"],"properties":{"toTeamId":{"type":"string","format":"uuid"},"from":{"type":"string","format":"date"},"note":{"type":"string","maxLength":200}}}"""),
            responses = mapOf(200 to "the new registration", 400 to "no reason, or malformed", 401 to "no principal", 403 to "you do not administer this season", 404 to "no such season or team", 409 to "not registered on that date, or already with that team"),
        ),
        Endpoint(
            id = "teams.friendlies", method = "GET", path = "/v1/teams/{teamId}/friendlies", authenticated = true,
            summary = "A team's friendlies, sent and received (PD-110)",
            description = "For the team's own members: every challenge to or from this team, newest game first, with its state, the other "
                + "team, the message, the answer, and the match it was played in once cited. `direction` says sent or received.",
            responses = mapOf(200 to "the friendlies", 400 to "not a UUID", 401 to "no principal", 403 to "not a member", 404 to "no such team"),
        ),
        Endpoint(
            id = "teams.challenge", method = "POST", path = "/v1/teams/{teamId}/friendlies", authenticated = true,
            summary = "Challenge another team to a friendly (PD-110)",
            description = "By whoever runs this team: the other team, when, and a message. One open challenge between a pair of teams "
                + "at a time, in either direction. A friendly reaches no league table and touches no rating.",
            request = Schema("""{"type":"object","required":["toTeamId","playAt"],"properties":{"toTeamId":{"type":"string","format":"uuid"},"playAt":{"type":"string","format":"date-time"},"message":{"type":"string","maxLength":280}}}"""),
            responses = mapOf(200 to "the challenge, proposed", 400 to "itself, or a date in the past", 401 to "no principal", 403 to "you do not run this team", 404 to "no such team", 409 to "a challenge between these teams is already waiting"),
        ),
        Endpoint(
            id = "friendlies.answer", method = "POST", path = "/v1/friendlies/{friendlyId}/answer", authenticated = true,
            summary = "Accept or decline a challenge (PD-110)",
            description = "By whoever runs the challenged team. A refusal says why.",
            request = Schema("""{"type":"object","required":["answer"],"properties":{"answer":{"type":"string","enum":["accepted","declined"]},"note":{"type":"string","maxLength":280}}}"""),
            responses = mapOf(200 to "the friendly as it now stands", 400 to "not an answer, or a refusal with no reason", 401 to "no principal", 403 to "not yours to answer", 404 to "no such friendly", 409 to "already answered or withdrawn"),
        ),
        Endpoint(
            id = "friendlies.withdraw", method = "POST", path = "/v1/friendlies/{friendlyId}/withdraw", authenticated = true,
            summary = "Withdraw an unanswered challenge (PD-110)",
            description = "By whoever runs the challenging team, before it is answered.",
            responses = mapOf(200 to "withdrawn", 400 to "not a UUID", 401 to "no principal", 403 to "not yours to withdraw", 404 to "no such friendly", 409 to "already answered"),
        ),
        Endpoint(
            id = "friendlies.cite", method = "POST", path = "/v1/friendlies/{friendlyId}/match", authenticated = true,
            summary = "Name the match a friendly was played in (PD-110)",
            description = "Once, on an accepted friendly, by somebody who played the match and runs one of the two teams — the rule a league fixture keeps.",
            request = Schema("""{"type":"object","required":["matchId"],"properties":{"matchId":{"type":"string","format":"uuid"}}}"""),
            responses = mapOf(200 to "the friendly, naming its match", 400 to "malformed", 401 to "no principal", 403 to "you did not play it, or do not run a team in it", 404 to "no such friendly or match", 409 to "not accepted, or already named"),
        ),
        Endpoint(
            id = "events.open", method = "POST", path = "/v1/events", authenticated = true,
            summary = "Open an edition of a knockout (PD-109)",
            description = "Whoever opens it is its organiser. A name, when it starts and when the session ends (the scoring grants issued at "
                + "check-in outlive that by a day), a venue on THRØ or a label, optionally when entries close and how many places. Single "
                + "players. `access` is open (anybody enters; on the notice on the door) or invitational (PD-113: the organiser names who plays; "
                + "not on the notice).",
            request = Schema("""{"type":"object","required":["name","startsAt","sessionEndsAt"],"properties":{"name":{"type":"string"},"startsAt":{"type":"string","format":"date-time"},"sessionEndsAt":{"type":"string","format":"date-time"},"venueId":{"type":"string","format":"uuid"},"venueLabel":{"type":"string"},"entriesCloseAt":{"type":"string","format":"date-time"},"capacity":{"type":"integer","minimum":2},"access":{"type":"string","enum":["open","invitational"]},"entrantKind":{"type":"string","enum":["player","pair","team"],"description":"PD-115: who enters — single players, pairs, or teams."}}}"""),
            responses = mapOf(200 to "the event's page, as its organiser reads it", 400 to "a name, dates or capacity THRØ cannot accept", 401 to "no principal"),
        ),
        Endpoint(
            id = "me.events", method = "GET", path = "/v1/me/events", authenticated = true,
            summary = "The events you organise (PD-109)",
            description = "Every edition the caller opened or was made organiser of, newest first, with its state and entry count.",
            responses = mapOf(200 to "the events", 401 to "no principal"),
        ),
        Endpoint(
            id = "events.get", method = "GET", path = "/v1/events/{eventId}", authenticated = false,
            summary = "An event's page (PD-109)",
            description = "For anybody: what, when, where (a public venue, or the organiser's label), how many places and entries, and once "
                + "drawn, the first round with players named where THRØ may name them. With a session, `you` says whether you are "
                + "entered and checked in; without one it is null. No organiser is named.",
            responses = mapOf(200 to "the event", 400 to "not a UUID", 404 to "no such event"),
        ),
        Endpoint(
            id = "events.enter", method = "POST", path = "/v1/events/{eventId}/entries", authenticated = true,
            summary = "Enter yourself, or — as the organiser — enter a player by id (PD-109, PD-113)",
            description = "With an empty body: yourself, on an open event, while entries are open and a place remains. With `playerId`: the organiser "
                + "enters that player, on any event they run, including an invitational; the entries-close time does not bind the organiser. "
                + "A withdrawn entry comes back rather than doubling.",
            request = Schema("""{"type":"object","properties":{"playerId":{"type":"string","format":"uuid","description":"the organiser entering a player"},"partnerId":{"type":"string","format":"uuid","description":"a pair event: you and this partner (PD-115)"},"playerIds":{"type":"array","items":{"type":"string","format":"uuid"},"description":"a pair event: the organiser entering two players"},"teamId":{"type":"string","format":"uuid","description":"a team event: the team, by whoever runs it or the organiser"}}}"""),
            responses = mapOf(200 to "the event, with the entrant entered", 400 to "not a UUID, or the wrong shape for this event's kind", 401 to "no principal", 403 to "entry is by the organiser, or you do not run the team", 404 to "no such event, player or team", 409 to "closed, full, or already entered — said in words"),
        ),
        Endpoint(
            id = "events.entries.seed", method = "POST", path = "/v1/events/{eventId}/entries/{playerId}/seed", authenticated = true,
            summary = "Seed an entrant (PD-115)",
            description = "By the organiser, before the draw: a positive number, unique in the event, or null to unseed. The draw honours seeds — byes to the highest, "
                + "then pairing in seed order. The path's id is the competitor's, whatever its kind.",
            request = Schema("""{"type":"object","properties":{"seed":{"type":["integer","null"],"minimum":1}}}"""),
            responses = mapOf(200 to "the event", 400 to "not a positive number", 401 to "no principal", 403 to "not the organiser", 404 to "not entered", 409 to "seed taken, or the draw is made"),
        ),
        Endpoint(
            id = "events.boards", method = "POST", path = "/v1/events/{eventId}/boards", authenticated = true,
            summary = "Name the boards (PD-115)",
            description = "By the organiser: labels, each once. A tie is sent to one by label.",
            request = Schema("""{"type":"object","required":["labels"],"properties":{"labels":{"type":"array","items":{"type":"string","maxLength":40}}}}"""),
            responses = mapOf(200 to "the event's boards", 400 to "no labels", 401 to "no principal", 403 to "not the organiser", 404 to "no such event"),
        ),
        Endpoint(
            id = "events.tie.board", method = "POST", path = "/v1/events/{eventId}/ties/{tieId}/board", authenticated = true,
            summary = "Send a tie to a board (PD-115)",
            description = "By the organiser. The tie then says its board; nothing else changes.",
            request = Schema("""{"type":"object","required":["label"],"properties":{"label":{"type":"string"}}}"""),
            responses = mapOf(200 to "the event, the tie on its board", 401 to "no principal", 403 to "not the organiser", 404 to "no such event, tie or board"),
        ),
        Endpoint(
            id = "events.guests", method = "POST", path = "/v1/events/{eventId}/guests", authenticated = true,
            summary = "Add a walk-up to a singles event by name (PD-124), or a pair with a walk-up in it to a pairs event (PD-130)",
            description = "By the event's organiser. Somebody in the pub with no account: a player in the draw like any other, present "
                + "by being added, decided by hand. The name is shown to the organiser; to anybody else only with `mayBeNamed` — the "
                + "organiser's word that this is an adult happy to be on the draw — and otherwise as *A guest*. It is forgotten thirty "
                + "days after the event ends. Two walk-ups on one night cannot share a name. On a pairs event: `names` of two, or `name` with "
                + "`partnerId` for a partner who is on THRØ; each walk-up half is named exactly as a walk-up alone is.",
            request = Schema("""{"type":"object","properties":{"name":{"type":"string","minLength":1,"maxLength":60},"names":{"type":"array","minItems":2,"maxItems":2,"items":{"type":"string","minLength":1,"maxLength":60}},"partnerId":{"type":"string","format":"uuid"},"mayBeNamed":{"type":"boolean"}}}"""),
            responses = mapOf(200 to "the event, as its organiser sees it", 400 to "no name, too long a one, the wrong number of names for the event's kind, or a teams event",
                              401 to "no principal", 403 to "you do not run this event", 404 to "no such event, or no such partner", 409 to "entries closed, full, the name is taken, or the partner is already in a pair here"),
        ),
        Endpoint(
            id = "events.entries.remove", method = "POST", path = "/v1/events/{eventId}/entries/{playerId}/remove", authenticated = true,
            summary = "The organiser removes an entry (PD-113)",
            description = "Before the draw. The row is kept with the time, as a withdrawal is; a place opens.",
            responses = mapOf(200 to "the event, with the entry removed", 400 to "not a UUID", 401 to "no principal", 403 to "not the organiser", 404 to "no such event", 409 to "not entered, or the draw is made"),
        ),
        Endpoint(
            id = "events.withdraw", method = "POST", path = "/v1/events/{eventId}/withdraw", authenticated = true,
            summary = "Withdraw your entry (PD-109)",
            description = "Before the draw. The row is kept with the time; a place opens.",
            responses = mapOf(200 to "the event, with you withdrawn", 400 to "not a UUID", 401 to "no principal", 404 to "no such event", 409 to "not entered, or the draw is made"),
        ),
        Endpoint(
            id = "events.checkin", method = "POST", path = "/v1/events/{eventId}/check-in", authenticated = true,
            summary = "Check in on the day, from your own phone (PD-109)",
            description = "For an entrant, from twelve hours before the start until the session ends. Issues the scoring grant (ADR-006) that "
                + "lets this phone score the event with no signal; it expires a day after the session ends. Again from the same phone is the same answer.",
            responses = mapOf(200 to "grantId and when it expires", 400 to "not a UUID, or no X-Thro-Device", 401 to "no principal", 404 to "no such event", 409 to "not an entrant, too early, or the session has ended"),
        ),
        Endpoint(
            id = "events.close", method = "POST", path = "/v1/events/{eventId}/close", authenticated = true,
            summary = "Close entries (PD-109)",
            description = "By the organiser. Nobody enters after; the draw can still be made.",
            responses = mapOf(200 to "the event, entries closed", 400 to "not a UUID", 401 to "no principal", 403 to "not the organiser", 404 to "no such event", 409 to "entries were not open"),
        ),
        Endpoint(
            id = "events.draw", method = "POST", path = "/v1/events/{eventId}/draw", authenticated = true,
            summary = "Make the first-round draw (PD-109)",
            description = "By the organiser, once, from at least two entrants: byes to the highest seeds, the rest paired in seed then entry order. "
                + "A bye is not a win and creates no match. Later rounds are the organiser's to run by hand: THRØ does not yet advance winners.",
            responses = mapOf(200 to "the event, drawn, with its first round", 400 to "not a UUID", 401 to "no principal", 403 to "not the organiser", 404 to "no such event", 409 to "already drawn, or fewer than two entrants"),
        ),
        Endpoint(
            id = "events.tie.result", method = "POST", path = "/v1/events/{eventId}/ties/{tieId}/result", authenticated = true,
            summary = "The organiser declares a tie: a walkover or an award (PD-111)",
            description = "With a note that says why. A played tie is never declared — it cites its match and the winner is read from the record. "
                + "A decided tie is not decided again; a bye is not decided at all.",
            request = Schema("""{"type":"object","required":["winnerId","outcome","note"],"properties":{"winnerId":{"type":"string","format":"uuid"},"outcome":{"type":"string","enum":["walkover","awarded"]},"note":{"type":"string","maxLength":280}}}"""),
            responses = mapOf(200 to "the event, with the tie decided", 400 to "not a side of the tie, no note, or a played outcome", 401 to "no principal", 403 to "not the organiser", 404 to "no such event or tie", 409 to "already decided, a bye, or the event is not in play"),
        ),
        Endpoint(
            id = "events.tie.match", method = "POST", path = "/v1/events/{eventId}/ties/{tieId}/match", authenticated = true,
            summary = "Name the match a tie was played in; the winner is the record's (PD-111)",
            description = "By somebody who played the match, or the organiser. The match must be between the tie's two players and finished; "
                + "the winner is derived from its record by the one derivation a rating reads, never typed.",
            request = Schema("""{"type":"object","required":["matchId"],"properties":{"matchId":{"type":"string","format":"uuid"}}}"""),
            responses = mapOf(200 to "the event, with the tie decided as played", 400 to "malformed", 401 to "no principal", 403 to "you did not play it", 404 to "no such event, tie or match", 409 to "not this tie's match, no winner yet, or already decided"),
        ),
        Endpoint(
            id = "events.advance", method = "POST", path = "/v1/events/{eventId}/advance", authenticated = true,
            summary = "Draw the next round from the winners (PD-111)",
            description = "By the organiser, once every tie in the current round is decided: winners paired in position order; byes go through. "
                + "A round of one decided tie completes the event, which then names its winner.",
            responses = mapOf(200 to "the event, with the next round or complete", 400 to "not a UUID", 401 to "no principal", 403 to "not the organiser", 404 to "no such event", 409 to "undecided ties, no draw yet, or already complete"),
        ),
        Endpoint(
            id = "fixtures.proposals", method = "GET", path = "/v1/fixtures/{fixtureId}/proposals", authenticated = true,
            summary = "The dates proposed for a fixture (PD-108)",
            description = "Every proposal to move this fixture, newest first: the date, from which team, why, and where it stands. For "
                + "the two teams' members and the season's administrator. A proposal is not a move: the fixture's date is the league's.",
            responses = mapOf(200 to "the proposals", 400 to "not a UUID", 401 to "no principal", 403 to "not your fixture", 404 to "no such fixture"),
        ),
        Endpoint(
            id = "fixtures.propose", method = "POST", path = "/v1/fixtures/{fixtureId}/proposals", authenticated = true,
            summary = "Propose a new date for a fixture to the other team (PD-108)",
            description = "By whoever runs one of the fixture's teams. The proposal reaches the other team's inbox as a task due within "
                + "seven days or by the fixture, whichever is first. One open proposal per fixture; the date must fall inside the season.",
            request = Schema("""{"type":"object","required":["teamId","to"],"properties":{"teamId":{"type":"string","format":"uuid"},"to":{"type":"string","format":"date-time"},"reason":{"type":"string"},"venueId":{"type":"string","format":"uuid","description":"somewhere else to play it (PD-128): a public venue THRØ holds; omitted, the fixture stays where it was going to be"}}}"""),
            responses = mapOf(200 to "the proposal, delivered", 400 to "a date outside the season or in the past, or a venue THRØ cannot show the other team", 401 to "no principal", 403 to "you do not run a team in this fixture", 404 to "no such fixture", 409 to "a proposal is already waiting"),
        ),
        Endpoint(
            id = "fixtures.propose.read", method = "POST", path = "/v1/fixtures/{fixtureId}/proposals/read", authenticated = true,
            summary = "Read a captain's sentence as a new day and time for this fixture (PD-129)",
            description = "For whoever may propose for the team. A System One model reads the parts of the date; code does the calendar; the time stays "
                + "where it was unless the sentence says one. Nothing is proposed by reading: the answer fills the form, and the captain sends it. "
                + "The sentence goes to TypeSafe with the two teams' names and the fixture's date, and nothing about a person.",
            request = Schema("""{"type":"object","required":["teamId","text"],"properties":{"teamId":{"type":"string","format":"uuid"},"text":{"type":"string","maxLength":300}}}"""),
            responses = mapOf(200 to "what was read: ready, say, doubt, and to/on/time where a day was read", 400 to "nothing to read, or a page", 401 to "no principal",
                              403 to "you do not run a team in this fixture", 404 to "no such fixture", 503 to "no model on this server, or no answer from it"),
        ),
        Endpoint(
            id = "proposals.get", method = "GET", path = "/v1/proposals/{proposalId}", authenticated = true,
            summary = "One proposed date, as its fixture's teams and league read it (PD-108)",
            description = "What the inbox's task points at: the fixture, the date proposed and the one it stands on, from which team, why, and where it stands.",
            responses = mapOf(200 to "the proposal", 400 to "not a UUID", 401 to "no principal", 403 to "not your fixture", 404 to "no such proposal"),
        ),
        Endpoint(
            id = "proposals.answer", method = "POST", path = "/v1/proposals/{proposalId}/answer", authenticated = true,
            summary = "The other team's answer to a proposed date (PD-108)",
            description = "Accepted or rejected, by whoever runs the team the date was proposed to; a rejection says why. Accepting does not "
                + "move the fixture — the league applies what was agreed.",
            request = Schema("""{"type":"object","required":["answer"],"properties":{"answer":{"type":"string","enum":["accepted","rejected"]},"note":{"type":"string"}}}"""),
            responses = mapOf(200 to "the proposal as it now stands", 400 to "not an answer, or a rejection with no reason", 401 to "no principal", 403 to "not your proposal to answer", 404 to "no such proposal", 409 to "already answered"),
        ),
        Endpoint(
            id = "proposals.withdraw", method = "POST", path = "/v1/proposals/{proposalId}/withdraw", authenticated = true,
            summary = "Take back an unanswered proposal (PD-108)",
            description = "By whoever runs the proposing team, before the other team answers. The opponent's task is cancelled and the fixture is free for a new proposal.",
            responses = mapOf(200 to "withdrawn", 400 to "not a UUID", 401 to "no principal", 403 to "not yours to withdraw", 404 to "no such proposal", 409 to "already answered"),
        ),
        Endpoint(
            id = "proposals.apply", method = "POST", path = "/v1/proposals/{proposalId}/apply", authenticated = true,
            summary = "The league applies an agreed date (PD-108)",
            description = "Moves the fixture through the same command every rearrangement goes through, so its history names the proposal. "
                + "Names the fixture version the administrator last saw; a stale version is a 409 with the current row. X-Thro-Device names the device.",
            request = Schema("""{"type":"object","required":["expectedVersion"],"properties":{"expectedVersion":{"type":"integer"}}}"""),
            responses = mapOf(200 to "applied: the proposal, now applied", 400 to "malformed", 401 to "no principal", 403 to "you do not administer the season", 404 to "no such proposal", 409 to "not accepted, or a stale fixture version", 422 to "refused by the store"),
        ),
        Endpoint(
            id = "seasons.proposals", method = "GET", path = "/v1/seasons/{leagueSeasonId}/proposals", authenticated = true,
            summary = "A season's open requests to move fixtures (PD-108)",
            description = "Proposed and waiting for the other team, or agreed and waiting for the league to apply. For the season's administrator.",
            responses = mapOf(200 to "the open proposals", 400 to "not a UUID", 401 to "no principal", 403 to "you do not administer this season", 404 to "no such season"),
        ),
        Endpoint(
            id = "seasons.policy", method = "GET", path = "/v1/seasons/{leagueSeasonId}/policy", authenticated = true,
            summary = "What a registration with this league season needs (PD-107)",
            description = "The registration policy in force today, for the season's administrator: which facts THRØ checks (name, "
                + "age band, account, consent), which requirements a person confirms by hand, and when registration closes.",
            responses = mapOf(200 to "the policy, or null when none is set", 400 to "not a UUID", 401 to "no principal", 403 to "you do not administer this season", 404 to "no such season"),
        ),
        Endpoint(
            id = "seasons.policy.set", method = "POST", path = "/v1/seasons/{leagueSeasonId}/policy", authenticated = true,
            summary = "Set what a registration with this league season needs (PD-107)",
            description = "Drafted and approved in one act by the season's administrator, in force from today, superseding the one before. "
                + "Read by the same strict parser the Secretary executes: a requirement THRØ cannot check goes under manualRequirements, "
                + "where a named person confirms it; one THRØ does not know at all is refused.",
            request = Schema("""{"type":"object","required":["requires"],"properties":{"requires":{"type":"array","items":{"type":"string","enum":["name","age_band","account_claimed","consent"]}},"manualRequirements":{"type":"array","items":{"type":"string"}},"deadlineDaysBeforeFirstFixture":{"type":"integer","minimum":0},"registrationClosesOn":{"type":"string","format":"date"}}}"""),
            responses = mapOf(200 to "the policy, approved", 400 to "a rule THRØ cannot execute", 401 to "no principal", 403 to "you do not administer this season", 404 to "no such season"),
        ),
        Endpoint(
            id = "teams.reconcile", method = "POST", path = "/v1/teams/{teamId}/reconcile", authenticated = true,
            summary = "Find out what the team owes its leagues (PD-107)",
            description = "Derives a registration task for every active member of the team in every season it is accepted into that "
                + "has an approved registration policy, due by the policy's deadline. Doing it again derives nothing new. The tasks are "
                + "read from the team's inbox. For whoever runs the team.",
            responses = mapOf(200 to "how many tasks were derived, and when they are due", 400 to "not a UUID", 401 to "no principal", 403 to "you do not run this team"),
        ),
        Endpoint(
            id = "tasks.assess", method = "POST", path = "/v1/tasks/{taskId}/assess", authenticated = true,
            summary = "What a registration task is still missing, or the submission it prepares (PD-107)",
            description = "Checks the player against the policy: the facts THRØ can check are named where missing, the requirements a "
                + "person must confirm are listed while unconfirmed, and when nothing is missing a submission is prepared, ready to send.",
            responses = mapOf(200 to "what is missing, or the submission", 400 to "not a UUID", 401 to "no principal", 403 to "you do not run the team", 404 to "no such task", 409 to "not a registration task"),
        ),
        Endpoint(
            id = "tasks.confirm", method = "POST", path = "/v1/tasks/{taskId}/confirm", authenticated = true,
            summary = "Confirm, by name, a requirement THRØ cannot check (PD-107)",
            description = "A fee paid, a form signed: a named person says it was met, with a note that is kept. Shown as a manual step, never a tick THRØ gave.",
            request = Schema("""{"type":"object","required":["requirement","note"],"properties":{"requirement":{"type":"string"},"note":{"type":"string","minLength":3}}}"""),
            responses = mapOf(200 to "confirmed", 400 to "no requirement or no note", 401 to "no principal", 403 to "you do not run the team", 404 to "no such task"),
        ),
        Endpoint(
            id = "submissions.submit", method = "POST", path = "/v1/submissions/{submissionId}/submit", authenticated = true,
            summary = "Send a prepared registration to the league (PD-107)",
            description = "For whoever runs the sending team. On THRØ the league's page is the delivery, so a sent submission is delivered "
                + "at once — and delivered is not accepted: the player is registered only when the season's administrator answers.",
            responses = mapOf(200 to "sent and delivered", 400 to "not a UUID", 401 to "no principal", 403 to "you do not run the team", 404 to "no such submission", 409 to "it cannot be sent from where it is"),
        ),
        Endpoint(
            id = "seasons.registrations", method = "GET", path = "/v1/seasons/{leagueSeasonId}/registrations", authenticated = true,
            summary = "The registrations sent to a league season (PD-107)",
            description = "For the season's administrator: every registration sent, newest first, with its state, the team, and the player by name where THRØ may name them.",
            responses = mapOf(200 to "the registrations", 400 to "not a UUID", 401 to "no principal", 403 to "you do not administer this season", 404 to "no such season"),
        ),
        Endpoint(
            id = "submissions.answer", method = "POST", path = "/v1/submissions/{submissionId}/answer", authenticated = true,
            summary = "The league's answer to a registration (PD-107)",
            description = "Accepted from a date, which registers the player from that date under the policy in force; or rejected with a reason. "
                + "The one act that registers anybody. Acknowledged on the way if it had not been.",
            request = Schema("""{"type":"object","required":["answer"],"properties":{"answer":{"type":"string","enum":["accepted","rejected"]},"registeredFrom":{"type":"string","format":"date"},"note":{"type":"string"}}}"""),
            responses = mapOf(200 to "the submission's state", 400 to "not an answer, or a rejection with no reason", 401 to "no principal", 403 to "you do not administer the season", 404 to "no such submission", 409 to "an acceptance needs a date, or the submission cannot be answered from where it is"),
        ),
        Endpoint(
            id = "fixtures.team", method = "GET", path = "/v1/fixtures/{fixtureId}/team/{teamId}", authenticated = true,
            summary = "A fixture as one team lives it (PD-106)",
            description = "For the team's own members only: the opponent and the hour, every member with what they have said "
                + "about playing (and the version the next change must name), who has been picked and in what order, whether "
                + "the caller may pick the side, and the match on THRØ the fixture was played in, if it has been cited. A "
                + "member's name is shown only where THRØ may name them; their player id is theirs to be picked by. Changes "
                + "go through POST /v1/commands as SetAvailability and NameLineup.",
            responses = mapOf(200 to "the fixture, the side and the lineup", 400 to "not a UUID", 401 to "no principal",
                              403 to "you are not a member of this team", 404 to "no such fixture, or the team is not in it"),
        ),
        Endpoint(
            id = "fixtures.cite", method = "POST", path = "/v1/fixtures/{fixtureId}/match", authenticated = true,
            summary = "Name the match on THRØ a fixture was played in (PD-106)",
            description = "Once, and only by somebody who was in the match and runs one of the fixture's teams. This is what "
                + "makes the league's result for the fixture a played one — read against a match scored visit by visit — "
                + "rather than the organiser's declared word (PD-055). A fixture that already names its match answers 409.",
            request = Schema("""{"type":"object","required":["matchId"],"properties":{"matchId":{"type":"string","format":"uuid"}}}"""),
            responses = mapOf(200 to "the fixture and its match", 400 to "matchId is not a UUID", 401 to "no principal",
                              403 to "you were not in the match, or run neither team", 404 to "no such fixture or match",
                              409 to "the fixture already names its match"),
        ),
        Endpoint(
            id = "me.rating", method = "GET", path = "/v1/me/rating", authenticated = true,
            summary = "Your THRØ rating, provisional (PD-105)",
            description = "Replayed from matches scored on THRØ that finished with a winner and stand as recorded or confirmed "
                + "— never from a league's declared result, a match nobody confirmed, or a disputed one. Shown as one of three "
                + "shapes: unrated, a range marked provisional, or a number with its margin once enough has been played "
                + "and the uncertainty has narrowed. Each match line carries the facts frozen at rating time and a sentence "
                + "from a bounded vocabulary; the opponent is named only where THRØ may name them. Says how many players the "
                + "rating is comparable with, because two pools that never meet are two pools.",
            responses = mapOf(200 to "the rating, its display shape, and its lines", 401 to "no principal"),
        ),
        Endpoint(
            id = "players.rating", method = "GET", path = "/v1/players/{playerId}/rating", authenticated = true,
            summary = "Another player's THRØ rating, where THRØ may show them (PD-105)",
            description = "The same answer as /v1/me/rating, for a player an adult has agreed to be shown as. A player THRØ may "
                + "not name is a 404, the same as a player who does not exist, so the route tells nobody which.",
            responses = mapOf(200 to "the rating", 400 to "not a UUID", 401 to "no principal", 404 to "no such player, or one THRØ does not show"),
        ),
        Endpoint(
            id = "me.seasons", method = "GET", path = "/v1/me/seasons", authenticated = true,
            summary = "The league seasons you administer (PD-100)",
            description = "Newest first, with the league's name, so an organiser can find their way back to the season they run.",
            responses = mapOf(200 to "the seasons", 401 to "no principal"),
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
            id = "leagues.void", method = "POST", path = "/v1/fixtures/{fixtureId}/void", authenticated = true,
            summary = "Annul a result, leaving the fixture to be replayed (PD-065)",
            description = "**Different from correcting one.** A correction says the scoreline was wrong; this says "
                + "the fixture should not have had a result at all — played under protest, abandoned, ordered "
                + "again by the league. The annulled decision stays on the record, superseded, and the fixture is "
                + "open: the table counts it as unplayed and the fixture list shows it as annulled with the reason "
                + "rather than quietly returning it to the ones still to play, because a result that vanishes "
                + "without trace is how a league stops trusting its own table. A reason is required and the "
                + "database has always insisted on one. Send the standing result's `outcomeId` as `supersedes`; a "
                + "fixture with nothing standing has nothing to annul and answers 409.",
            request = Schema("""{"type":"object","required":["supersedes","reason"],"properties":{"supersedes":{"type":"string","format":"uuid","description":"the outcomeId being annulled"},"reason":{"type":"string","minLength":1}}}"""),
            responses = mapOf(200 to "the void", 400 to "no reason, or supersedes is not a UUID",
                              401 to "no principal", 403 to "you do not administer this league season",
                              404 to "no such fixture",
                              409 to "this fixture has no standing result, or the one you named is no longer it"),
        ),
        Endpoint(
            id = "seasons.teams", method = "GET", path = "/v1/seasons/{leagueSeasonId}/teams", authenticated = true,
            summary = "A league season as its administrator runs it: its dates, divisions and every team that asked in (PD-099)",
            description = "Waiting and accepted alike, each with the division it asked for and the affiliationId that "
                + "accepting it needs. The public fixture list and table show only what the league has decided; this is "
                + "the season before that, so it is for the season's administrator alone. A season nobody has is a 404 "
                + "whoever asks, so a mistyped address does not read as a refusal.",
            responses = mapOf(200 to "the season, its divisions and its teams", 400 to "not a UUID", 401 to "no principal",
                              403 to "you do not administer this league season", 404 to "no such league season"),
        ),
        Endpoint(
            id = "seasons.fixtures.schedule", method = "POST", path = "/v1/seasons/{leagueSeasonId}/fixtures", authenticated = true,
            summary = "Give a league season its fixtures (PD-099)",
            description = "A list of fixtures, written together or not at all: one that cannot be played refuses the "
                + "list and says which. Each is between two teams the league has **accepted** into this season — a "
                + "team still waiting is not in the league, and a fixture it played would count in nobody's table — "
                + "in the same division, on a day inside the season's dates as they fall in the UK. The division may be "
                + "omitted, and is then the teams' own. The venue is the home team's at the time of the fixture, and "
                + "is frozen on it. A fixture already scheduled between the same teams at the same moment is a 409, so "
                + "sending a list twice does not play every match twice.",
            request = Schema("""{"type":"object","required":["fixtures"],"properties":{"fixtures":{"type":"array","minItems":1,"maxItems":400,"items":{"type":"object","required":["homeTeamId","awayTeamId","scheduledAt"],"properties":{"homeTeamId":{"type":"string","format":"uuid"},"awayTeamId":{"type":"string","format":"uuid"},"scheduledAt":{"type":"string","format":"date-time"},"divisionId":{"type":"string","format":"uuid"}}}}}}"""),
            responses = mapOf(200 to "the fixtures created", 400 to "not a list of fixtures, or a field of the wrong shape",
                              401 to "no principal", 403 to "you do not administer this league season",
                              404 to "no such league season", 409 to "a fixture in the list is already scheduled",
                              422 to "a fixture in the list cannot be played, and which"),
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
