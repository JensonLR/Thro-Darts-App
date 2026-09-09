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

It refuses to start without an authenticator. The only one that exists is the **development**
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
| `POST /v1/commands` | principal + `X-Thro-Device` | The one command endpoint (ADR-007): `RecordVisit`, `RenameTeam`, `RearrangeFixture`, `SetAvailability`, `NameLineup`. Applied 200; replay returns what it returned; stale 409 with the current row; refused 422 in the store's words; sequence gap 409; not this match — or not in it — 404; body over 64 KiB 413 |
| `GET /v1/me/inbox` | principal | The caller's own Secretary tasks by section |
| `GET /v1/teams/{teamId}/inbox` | principal with `team.manage` | The team's Secretary inbox; anyone else is 403 and the refusal is on the audit record |
| `GET /v1/me/discovery?from&to&locality` | principal | Discovery cards with their reasons |
| `GET /healthz` | anyone | Liveness and the schema version |
| `GET /openapi.json` | anyone | This contract |

## Changing the contract

Add or change an `Endpoint` in `Api.kt` and its handler in `Server.kt`; the server refuses to start
if the two disagree. Regenerate the committed file and review the diff:

```bash
THRO_WRITE_OPENAPI=1 gradle -p services/api test --tests 'thro.api.HttpTest'
```

## Not built

SSE fan-out (ADR-007 streams and heartbeat), accounts and sessions (FB-1), a client generated from
the schema (ADR-001's acceptance condition, waiting on the organiser console).
