# Runbook — the HTTP API

The API is Ktor routes over the command handlers in `services/api`. It decides nothing the handlers
do not decide; its three rules are that identity is the authenticated principal and never the body,
that one connection is opened per request and closed whatever happens, and that a replay returns
the stored answer with the status it had.

## Running it

```bash
export PGHOST=localhost            # and PGPORT/PGUSER/PGDATABASE if not the defaults
THRO_DEV_AUTH=1 gradle -p services/api serve
```

It refuses to start without an authenticator. In a deployment that is the **bearer** authenticator,
enabled by configuring at least one sign-in provider:

```bash
THRO_APPLE_CLIENT_ID=<your Apple Services ID or bundle id> \
THRO_GOOGLE_CLIENT_ID=<your Google OAuth client id> \
PGHOST=... PGPASSWORD=... gradle -p services/api serve
```

A client posts the provider's ID token to `POST /v1/auth/apple` or `/v1/auth/google` with its
device id and receives THRØ's own session: an opaque access token (15 minutes, sent as
`Authorization: Bearer …`) and a single-use refresh token (30 days) for `POST /v1/auth/refresh`.
Presenting a used refresh token revokes the whole family — that is how a stolen copy gives itself
away — and `POST /v1/auth/logout` revokes it on purpose. A family lives ninety days at most, however
often it rotates; then the person signs in again. Only the SHA-256 of any token is stored, and no
row is ever deleted: `identity.access_token` grows by one row per quarter-hour of use per person,
which is an audit trail today and a partitioning-and-retention decision before real load. Clients
generate a nonce per sign-in, hand it to the provider SDK, and send it with the token; a token that
carries a nonce is refused without it.

**Passkeys** (the fallback, PD-030) need a relying party: the public host the app talks to.
On Fly it is `<app>.fly.dev` by default (from `FLY_APP_NAME`); `THRO_RP_ID` overrides it and
`THRO_RP_ORIGINS` lists the origins allowed to sign (default `https://<rp id>`). iOS offers a
passkey for a host only when that host serves `/.well-known/apple-app-site-association` naming
the app: set `THRO_APPLE_APP_IDS=<TEAMID>.<bundle id>` and the server serves it, and the app's
Associated Domains entitlement carries `webcredentials:<rp id>`. The four routes are
`/v1/auth/passkey/register/options` and `/register` (create; with a bearer token, add to that
account), `/v1/auth/passkey/options` and `/v1/auth/passkey` (sign in). A challenge is spent once
within five minutes by the device that asked. Recovery is a second way in (PD-032): the profile's
`credentials` count tells the client whether to offer one.

For local work there is also the **development**
authenticator, which trusts an `X-Thro-Dev-Subject: <uuid>` header — that is, it trusts anyone who
can reach the port — and cannot be constructed unless `THRO_DEV_AUTH=1` is set **and** `PGHOST` is
this machine (`localhost`, `127.0.0.1`, `::1`): a development door on a remote database is a
deployment with the door open, whatever the variable says. It says so on every start. `PGPASSWORD`
is honoured. The production scheme (passkeys, short-lived access tokens, rotating refresh tokens, ADR-008)
is founder decision FB-1 and replaces it; nothing in a deployment manifest may set that variable.

Migrations are a deploy step (ADR-013), not a boot step. `GET /healthz` reports the migration
ledger's version and answers 503 when the database is behind the code.

## Routes

The contract is `services/api/openapi.json`, served at `GET /openapi.json` from the registry the
routes are mounted from. In brief:

| Route | Who | What |
|---|---|---|
| `POST /v1/auth/apple`, `/v1/auth/google` | anyone, with the provider's ID token | Sign in; creates the account, player and claim on first sight (PD-030) |
| `POST /v1/auth/passkey/register/options`, `/register` | anyone; with a bearer, the caller's account | Create a passkey (WebAuthn registration) |
| `POST /v1/auth/passkey/options`, `/v1/auth/passkey` | anyone, with the passkey | Sign in with a passkey (WebAuthn assertion) |
| `GET /.well-known/apple-app-site-association` | anyone | webcredentials for the configured app ids |
| `POST /v1/auth/refresh` | anyone, with a refresh token | Rotates it; reuse revokes the family |
| `POST /v1/auth/logout` | principal | Revokes the session family |
| `GET /v1/me`, `PUT /v1/me/profile` | principal | Who am I; set my display name |
| `POST /v1/commands` | principal + `X-Thro-Device` | The one command endpoint (ADR-007): `RecordVisit`, `RenameTeam`, `RearrangeFixture`, `SetAvailability`, `NameLineup`. Applied 200; replay returns what it returned; stale 409 with the current row; refused 422 in the store's words; sequence gap 409; not this match — or not in it — 404; body over 64 KiB 413 |
| `GET /v1/me/inbox` | principal | The caller's own Secretary tasks by section |
| `GET /v1/teams/{teamId}/inbox` | principal with `team.manage` | The team's Secretary inbox; anyone else is 403 and the refusal is on the audit record |
| `GET /v1/me/discovery?from&to&locality` | principal | Discovery cards with their reasons |
| `GET /v1/leagues?locality` | anyone | The leagues' public front (PD-033): seasons, divisions, teams, home venues with coordinates, and the source and basis of each; every league carries its own point and website (PD-037), and one the directory placed is listed with no season |
| `POST /v1/teams` | principal | Start a team; the caller is its first member and admin (plan §6) |
| `GET /v1/me/teams` | principal | The caller's current teams with their role and the member count |
| `GET /v1/teams/{teamId}` | anyone | A team's front: name, town, home venue, seasons, roster — names only where `identity.player_may_be_disclosed` allows; private teams 404 to non-members; `yourRole` with a bearer |
| `POST /v1/teams/{teamId}/invite` | principal | A team code: eight characters, thirty days, twenty people; admin or captain only (V029) |
| `GET /v1/venues?q&locality` | anyone | Public venues whose name contains q, at most twenty: for a captain choosing a home |
| `POST /v1/teams/{teamId}/home` | principal | Set the home venue by id, or add one by name and town; a change closes the old tenure and opens the new (admin or captain) |
| `POST /v1/teams/join` | principal | Enter a team code and join as a player; 409 with the sentence when the code is unknown, expired, full or you are in already |
| `GET /v1/friends` | principal | The caller's friends: display names and since when (PD-035) |
| `POST /v1/friends/invite` | principal | A friend code to give in person: eight characters, seven days, one use; 403 with the sentence to show unless the account has said it is an adult |
| `POST /v1/friends/accept` | principal | Enter a code; both become friends; 409 with the sentence to show when the code is unknown, used, expired, your own, or you are friends already |
| `POST /v1/friends/{accountId}/remove` | principal | End a friendship from this side; recorded, never deleted |
| `PUT /v1/me/profile` | principal | `displayName` and/or `ageBand` (adult or minor, self-declared, never back to unknown) |
| `GET /v1/events?from` | anyone | Open-entry events that have not started, with their public venues: the notice on the pub door. Entry counts and eligibility stay on `/v1/me/discovery` |
| `POST /v1/matches` | principal | Send a match this phone scored (PD-040): the journal as it was written — visits, retractions, and an ending (PD-042) last — idempotent by (match, device, sequence); the other seat becomes a competitor THRØ holds no name for; recorded self-reported |
| `POST /v1/matches/{matchId}/code` | the principal who sent the match | A code for the other seat (PD-043): eight characters, seven days, one use; only for a match sent from a phone, and only while the seat is nobody's; asking twice hands back the same live code |
| `POST /v1/matches/claim` | principal | Enter a match code: the seat becomes the caller's (`competition.seat_claim`) and nothing under the match is rewritten; 422 with the sentence when the code is unknown, used, expired, your own, or the seat is taken; rationed |
| `GET /v1/matches/{matchId}`, `GET /v1/me/matches` | a player in the match | The match as its log reads now: both seats (names only where `identity.player_may_be_disclosed` allows), legs replayed by the engine with struck visits left out, the ending, the winner, which seat sent it, each seat's answer where it still stands, and its standing — self-reported, confirmed, disputed, or recorded; anyone else 404 |
| `POST /v1/matches/{matchId}/answer` | the other player, with `X-Thro-Device` | `{"agree": true}` confirms and `false` contests: `ResultConfirmed` or `ResultContested` on the trust stream, written as `app_trust`; the latest answer stands, and only for the record it answered; the sender cannot answer, and nobody answers for an abandoned match |
| `GET /v1/streams/match/{matchId}` | a participant, the holder of a grant in force, or an official of the event | `text/event-stream`: every event of the match in commit order, then each new one — woken by the database the moment one commits (V036), and still polling once a second beneath that; `Last-Event-ID` resumes; a comment ping every 15 s; the client treats 45 quiet seconds as stale; who may watch is asked again every minute, so a revoked grant or an ended session closes the stream (ADR-007) |
| `GET /healthz` | anyone | Liveness and the schema version |
| `GET /openapi.json` | anyone | This contract |

## Changing the contract

Add or change an `Endpoint` in `Api.kt` and its handler in `Server.kt`; the server refuses to start
if the two disagree. Regenerate the committed file and review the diff:

```bash
THRO_WRITE_OPENAPI=1 gradle -p services/api test --tests 'thro.api.HttpTest'
```

## Not built

The other ADR-007 streams (`event:{id}:public`, `event:{id}:queue`, `event:{id}:organiser`,
`player:{id}:inbox`) — the match stream is the only one, woken by LISTEN/NOTIFY since V036; email
recovery (PD-032 says why not yet); a client generated from the schema (ADR-001's acceptance
condition, waiting on the organiser console). The match stream's door reads a match's two
competitors and its grants, so a player who took their seat with a code (PD-043) is not yet let in;
watching is the next piece, and that door changes with it.

## Rationing the routes a stranger may call

`/v1/auth/*` and `/v1/auth/passkey/*` are rationed before any work is done for the caller:
thirty attempts a minute per client address (the first hop of `X-Forwarded-For`, else the socket)
and thirty per device id named in the body, refilled continuously. The thirty-first is a 429 with
`Retry-After` in seconds. It is one instance's memory — the difference between a thousand token
guesses a second and thirty a minute, not a flood defence; a flood is the host's business
(Render and Fly both sit behind one).

The routes that take a code somebody was handed — `POST /v1/friends/accept`, `/v1/teams/join` and
`/v1/matches/claim` (PD-043) — are rationed the same way, from allowances of their own, keyed on the
client address and the `X-Thro-Device` header. A code opens something, so guessing one is the attack;
and a run of mistyped codes should not cost anybody their sign-in.

## Sign in with Google — creating the iOS client id

The server needs one value, the OAuth client id Google issues for the iOS app; the app needs the
same id and its reversed form as a URL scheme. In Google Cloud Console (<https://console.cloud.google.com>):

1. **Project.** Create one named `THRO` (or use an existing one); the project's name is never
   shown to players.
2. **OAuth consent screen** (APIs & Services → OAuth consent screen): user type **External**, app
   name `THRØ`, your support email, developer contact email; scopes `openid`, `email`, `profile`
   only. While the app is in **Testing**, add your own Google account under *Test users*; publish
   the consent screen when the app goes to TestFlight for other people.
3. **Credentials** (APIs & Services → Credentials → Create credentials → **OAuth client ID**):
   application type **iOS**, name `THRØ iOS`, bundle ID `app.thro.darts`, Team ID `2XM324WPD5`.
   Create. Copy two values from the result: the **Client ID** (`…apps.googleusercontent.com`)
   and the **iOS URL scheme** (`com.googleusercontent.apps.…`, the client id reversed).
4. **Server.** In Render → `thro-api-staging` → Environment, set `THRO_GOOGLE_CLIENT_ID` to the
   client id, save, and **Manual Deploy**. `POST /v1/auth/google` stops answering 503.
5. **App.** The client id goes in the app's `Info.plist` under `THROGoogleClientID`, and the iOS
   URL scheme is added under URL Types; the sign-in flow opens Google in a system web session,
   receives the authorization code on that scheme, exchanges it for an ID token (an iOS client
   has no secret), and posts the ID token to the server. Nothing else changes.
