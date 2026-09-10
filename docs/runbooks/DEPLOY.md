# Runbook — deploying THRØ (PD-031, amended 2026-09-10)

One image, a managed Postgres in London with point-in-time recovery, migrations as a deploy step
before the image serves. Two paths share everything but the compute host:

| | Path A — staging without a card | Path B — Fly.io (production, or staging if you add a card) |
|---|---|---|
| Database | **Neon**, London (`aws-eu-west-2`), free plan | **Neon**, London, pay-as-you-go (7-day restore) |
| Compute | **Render** free web service, Frankfurt | **Fly.io** `shared-cpu-1x`, London (`lhr`) |
| Card needed | no | yes (Fly requires one for every organisation) |
| Migrations run | from your Mac: `gradle -p services/api migrate` | by Fly's release command, from the image |
| Cost | £0 | about $3.50 a month for the machine |
| Public host | `thro-api-staging.onrender.com` | `thro-api-staging.fly.dev` / your domain |

Nothing in the repository holds a secret. Everything below runs from the repository root.

## Names, fixed here so nothing has to be renamed

| Thing | Value |
|---|---|
| Neon project | **`THRØ`** (`round-darkness-99300686`), London, PostgreSQL 18 — created by the founder 2026-09-10; one branch, `production`, used for staging until real players arrive, when a `staging` branch is forked from it |
| Neon database | `neondb` |
| Neon roles | `neondb_owner` (runs migrations) and **`thro_app`** (the API connects as this; a plain role created by SQL — not by the console, whose roles are members of `neon_superuser` and could write evidence — holding only the application roles) |
| Neon endpoint | `ep-small-mountain-zavde3ff.c-2.eu-west-2.aws.neon.tech` for the API and for migrations; the `-pooler` host Neon also offers is PgBouncer and cannot carry the migration's role switches or advisory lock |
| Render service / Fly app | `thro-api-staging` (production: `thro-api`) |
| Apple app id for passkeys | `2XM324WPD5.app.thro.darts` |
| Passkey relying party | the public host of the environment — see the warning below |

**Passkeys are bound to the host.** A passkey is created for a relying party id and cannot move:
change the host and every passkey registered against the old one stops working. Staging on a
provider hostname is fine because staging holds no real people. For production, choose the final
host — your own domain — **before** any real person registers a passkey, and set `THRO_RP_ID` to it
from the first production deploy.

## Path A — Neon + Render, no card

**A1. The database (Neon) — done, 2026-09-10.** The project `THRØ` exists in London; `thro_app`
was created by SQL as a plain role; all migrations through V026 were applied as `neondb_owner`
from this repository's `migrate` task, `thro_app` was granted exactly the application roles, and a
second run reported nothing to apply. Verified as `thro_app`: it reads the ledger (`/healthz`
needs that) and the tables, and `DELETE` on a competition table and `UPDATE` on evidence are
refused. The `thro_app` password was handed to the founder in the session that created it and is
written nowhere in this repository; rotate it any time with `ALTER ROLE thro_app PASSWORD '…'` in
Neon's SQL editor and update Render's `DATABASE_URL`.

The two connection strings have this shape (passwords from the Neon console → Connect, or from
the founder's notes):
- `MIGRATE_DATABASE_URL` = `postgres://neondb_owner:<password>@ep-small-mountain-zavde3ff.c-2.eu-west-2.aws.neon.tech/neondb?sslmode=require`
- `DATABASE_URL` = `postgres://thro_app:<password>@ep-small-mountain-zavde3ff.c-2.eu-west-2.aws.neon.tech/neondb?sslmode=require`

**A2. Migrate from your Mac — whenever a new migration lands.** The ledger applies only what is
new; running it with nothing new is harmless and says so.
```bash
export MIGRATE_DATABASE_URL='postgres://neondb_owner:<password>@ep-small-mountain-zavde3ff.c-2.eu-west-2.aws.neon.tech/neondb?sslmode=require'
export APP_DB_USER='thro_app'
gradle -p services/api migrate
```
Expected on a fresh migration: `migrated V026 -> V027: V027__...` then `application roles granted
to thro_app`; otherwise `schema already at V026; nothing applied`.

**A3. The web service (Render) — live since 2026-09-10** at <https://thro-api-staging.onrender.com>:
`/healthz` reports the database ok at V026, `/openapi.json` is byte-for-byte the committed contract,
the Apple association file names the app, and the sign-in routes refuse and 503 exactly as the
tests say. The first deploy exited 128 because `render.yaml` carried a `dockerCommand`, which on
Render replaces the entrypoint too; it is gone. What follows is how it was set up, for the next
environment. At <https://dashboard.render.com>: **New → Blueprint**, connect
the GitHub repository `JensonLR/Thro-Darts-App`, branch `claude/thro-production-build-je2mkf`. Render
reads `render.yaml` and creates `thro-api-staging` (free instance, Frankfurt, built from the
Dockerfile). It will ask for the two values marked `sync: false`:

- `DATABASE_URL` — `thro_app`'s connection string from A1
- `THRO_GOOGLE_CLIENT_ID` — leave empty until you have it (Sign in with Google answers 503 until then)

Deploy. The first build takes several minutes (it compiles the Kotlin packages). `THRO_DEV_AUTH` is
never set here; the server refuses it against a remote database anyway.

**A4. Check it.**
```bash
curl -s https://thro-api-staging.onrender.com/healthz
curl -s https://thro-api-staging.onrender.com/openapi.json | head -c 300
curl -s https://thro-api-staging.onrender.com/.well-known/apple-app-site-association
```
Expected: `{"database":"ok","schemaVersion":"V026"}` (or later), the contract, and
`{"webcredentials":{"apps":["2XM324WPD5.app.thro.darts"]}}`. The first request after fifteen quiet
minutes takes about a minute while the free instance wakes; that is the free tier, not a fault.

**A5. Point the iOS app at it.** In Xcode, the app's **Associated Domains** entitlement gains
`webcredentials:thro-api-staging.onrender.com`, and the app's API base URL is
`https://thro-api-staging.onrender.com`. Sign in with Apple needs the capability on the app id in
the Apple Developer portal; the ID token's audience is the bundle id, which `render.yaml` sets.

**Every later deploy on path A:** push to the branch, run A2 if there are new migrations (the
ledger makes it safe to run every time), then **Manual Deploy → Deploy latest commit** in Render.
Migrate first, deploy second: a migration must be compatible with the image that is still running.

## Why not Cloudflare?

Asked on 2026-09-10. Cloudflare has two ways to run code. **Workers** are a JavaScript and WASM
edge runtime, free at small scale, and cannot run this server: THRØ's API is a Kotlin/JVM
container, and moving it to Workers means rewriting the server in TypeScript — the foundations the
brief said not to throw away. **Containers** (2025) do run a Docker image, but they need the $5 a
month Workers Paid plan (a card), and Cloudflare chooses where an instance runs — "the nearest
location with a pre-fetched image", which "could be routed to a different location" after a
restart, with no region or jurisdiction setting. ADR-011 fixes the container to the UK/EU for
personal data, and a host that will not say where it runs cannot meet that. So for THRØ's API,
Cloudflare is neither the free option (Render is) nor the London one (Fly is). Where Cloudflare
does fit later is in front of the API — its free DNS and proxy for the production domain, and
`services/links` (the static association files) on Pages — none of which touches the data.

## Path B — Neon + Fly.io

When a card is on file. The database is the same Neon project (use the `production` branch for
production); the difference is where the image runs and that Fly runs the migration for you.

```bash
fly apps create thro-api-staging --org personal          # fly.toml already names this app
fly secrets set --app thro-api-staging \
  DATABASE_URL='<thro_app connection string>?sslmode=require' \
  MIGRATE_DATABASE_URL='<owner role connection string>?sslmode=require' \
  APP_DB_USER='thro_app' \
  THRO_APPLE_CLIENT_ID='app.thro.darts' THRO_APPLE_APP_IDS='2XM324WPD5.app.thro.darts'
fly deploy --app thro-api-staging
curl -s https://thro-api-staging.fly.dev/healthz
```
`fly deploy` builds the image, runs the release command (the same image with `migrate`, which
brings the database to the image's version through the ledger and grants `thro_app` the
application roles) and only then starts the machine. For production, copy `fly.toml` to a file
with `app = "thro-api"` and `THRO_RP_ID` set to your domain in `[env]`, and deploy with
`--config` and `--app thro-api`.

## Rolling back

Migrations are forward-only (ADR-013); the image rolls back, the schema does not. On Render, redeploy
an earlier commit from the dashboard; on Fly, `fly releases` then `fly deploy --image <previous>`.
Because every migration must be compatible with the previous image, this is safe by construction.
Neon's restore window (six hours free, seven days paid) covers the database itself.

## Not done yet, and said so

- Staging is deployed on path A; production is not. CI builds the image (`image` workflow) but
  never deploys, and Render redeploys only on **Manual Deploy** (`autoDeploy: false`).
- The API connects as one database user, `thro_app`, which holds the application roles and uses
  none of them directly: every request runs `SET ROLE` to its module's role before touching a
  table (ADR-011's per-module roles, at the request rather than the connection pool).
- Rate limiting on the sign-in routes, object storage (media), push (APNs) and the scheduled
  restore drill are not configured.
- Production needs a card wherever it runs, and a domain before the first real passkey.
