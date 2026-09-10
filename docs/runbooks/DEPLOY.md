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
| Neon project | `thro` (one project; a branch per environment: `staging`, later `production`) |
| Neon database | `thro` |
| Neon roles | `thro_deploy` (runs migrations; Neon's default owner role, renamed or kept as `neondb_owner`) and `thro_app` (the API connects as this; it holds only the application roles) |
| Render service / Fly app | `thro-api-staging` (production: `thro-api`) |
| Apple app id for passkeys | `2XM324WPD5.app.thro.darts` |
| Passkey relying party | the public host of the environment — see the warning below |

**Passkeys are bound to the host.** A passkey is created for a relying party id and cannot move:
change the host and every passkey registered against the old one stops working. Staging on a
provider hostname is fine because staging holds no real people. For production, choose the final
host — your own domain — **before** any real person registers a passkey, and set `THRO_RP_ID` to it
from the first production deploy.

## Path A — Neon + Render, no card

**A1. The database (Neon).** At <https://console.neon.tech>: create a project named `thro`, region
**Europe (London)**, Postgres 16 or 17, database name `thro`. Neon gives you an owner role (its
name is shown; it can create roles, which the first migration needs). Then, in the project's
**Roles** page, add a second role `thro_app` and keep its password. Copy two connection strings
from the **Connect** panel, both with `?sslmode=require`:

- the owner role's → this is `MIGRATE_DATABASE_URL`
- `thro_app`'s → this is `DATABASE_URL`

**A2. Migrate from your Mac.** The migrations create the owner and application roles, every
schema, and grant `thro_app` exactly the application roles (nothing else). The ledger records what
was applied; running it again applies only what is new.
```bash
export MIGRATE_DATABASE_URL='postgres://<owner role>:<password>@<host>/thro?sslmode=require'
export APP_DB_USER='thro_app'
gradle -p services/api migrate
```
Expected: `migrated V--- -> V026: V001__... V002__... ...` then `application roles granted to
thro_app`. Run it again and it says `schema already at V026; nothing applied`.

**A3. The web service (Render).** At <https://dashboard.render.com>: **New → Blueprint**, connect
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

- Nothing is deployed until you run the steps above; CI builds the image (`image` workflow) but
  never deploys.
- The API connects as one database role, `thro_app`, holding the union of the application roles.
  ADR-011's per-module connections are a follow-up before production traffic.
- Rate limiting on the sign-in routes, object storage (media), push (APNs) and the scheduled
  restore drill are not configured.
- Production needs a card wherever it runs, and a domain before the first real passkey.
