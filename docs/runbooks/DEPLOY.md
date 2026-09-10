# Runbook — deploying to Fly.io (PD-031)

One image, London, migrations as the release step. You have installed `fly` and signed in as the
account owner; everything below runs from the repository root on this Mac. Nothing in the
repository holds a secret.

## Names, fixed here so nothing has to be renamed

| Thing | Staging | Production (when you get there) |
|---|---|---|
| Fly app | `thro-api-staging` | `thro-api` |
| Public host | `thro-api-staging.fly.dev` | `thro-api.fly.dev`, later your own domain |
| Fly Postgres app (staging only) | `thro-db-staging` | a PITR-capable managed Postgres in London — see below |
| Database name (what `attach` creates) | `thro_api_staging` | — |
| Passkey relying party (`THRO_RP_ID`) | `thro-api-staging.fly.dev` (the default) | the production host |
| Apple app id for passkeys | `2XM324WPD5.app.thro.darts` | the same |
| Fly organisation | `personal` | `personal` |

If `fly apps create thro-api-staging` says the name is taken, add a short suffix (for example
`thro-api-staging-jl`) and use that name everywhere below. ADR-011 prefers permanent identifiers
without the product name; a Fly app name is not permanent — your own domain will front it — so
these are chosen for clarity.

## Staging, step by step

**1. The app.**
```bash
fly apps create thro-api-staging --org personal
```

**2. The database.** Fly Postgres is fine for staging (synthetic data only, ADR-011):
```bash
fly postgres create --name thro-db-staging --org personal --region lhr \
  --initial-cluster-size 1 --vm-size shared-cpu-1x --volume-size 3
```
It prints a `postgres` superuser password once. Copy it; you need it in step 4.

**3. Attach the database to the app.** This creates the database `thro_api_staging`, a user
`thro_api_staging`, and sets the app's `DATABASE_URL` secret:
```bash
fly postgres attach thro-db-staging --app thro-api-staging
```

**4. Secrets.** The release step migrates as the superuser and then grants the app's user the
application roles; the server runs as the app's user through `DATABASE_URL` from step 3.
```bash
fly secrets set --app thro-api-staging \
  MIGRATE_DATABASE_URL='postgres://postgres:<password from step 2>@thro-db-staging.flycast:5432/thro_api_staging?sslmode=disable' \
  THRO_APPLE_CLIENT_ID='app.thro.darts' \
  THRO_APPLE_APP_IDS='2XM324WPD5.app.thro.darts' \
  THRO_GOOGLE_CLIENT_ID='<your Google iOS OAuth client id>.apps.googleusercontent.com'
```
The Google id comes from Google Cloud Console → APIs & Services → Credentials → Create
credentials → OAuth client ID → type **iOS**, bundle `app.thro.darts`. If you do not have it yet,
leave that line out: Sign in with Google answers 503 until it is set, and everything else works.
`THRO_DEV_AUTH` is never set on Fly; the server refuses it against a remote database anyway.

**5. Deploy.** From the repository root (the Dockerfile builds the API with the packages beside it):
```bash
fly deploy --app thro-api-staging
```
`fly deploy` builds the image, runs the release command — the same image with `migrate`, which
brings the database to the image's version through the ledger (ADR-013), refuses a database it
cannot reason about, and grants the app's user the application roles — and only then starts the
machine. A failed migration stops the deploy before the new image serves a request.

**6. Check it.**
```bash
fly status --app thro-api-staging
fly logs --app thro-api-staging
curl -s https://thro-api-staging.fly.dev/healthz
curl -s https://thro-api-staging.fly.dev/openapi.json | head -c 300
curl -s https://thro-api-staging.fly.dev/.well-known/apple-app-site-association
```
Expected: `{"database":"ok","schemaVersion":"V025"}` (or later), the contract, and
`{"webcredentials":{"apps":["2XM324WPD5.app.thro.darts"]}}`. The log's first lines say which
authenticator is on ("passkeys: relying party thro-api-staging.fly.dev …", no development warning).

**7. Point the iOS app at it.** In Xcode, the app's **Associated Domains** entitlement gains
`webcredentials:thro-api-staging.fly.dev`, and the app's API base URL is
`https://thro-api-staging.fly.dev`. Sign in with Apple needs the capability on the app id in the
Apple Developer portal; the ID token's audience is the bundle id, which is what step 4 set.

## Every later deploy

```bash
fly deploy --app thro-api-staging
```
Then the same checks. Migrations that are new run in the release step; the ledger refuses an edited
applied migration, which is the intended cost of editing one (ADR-013).

## Production, when staging has earned it

Production is the same image against a database with **point-in-time recovery** in London (ADR-011,
PD-031). Fly Postgres as created above does not promise PITR, so production's database is either
Fly's Managed Postgres in `lhr` if your account offers it, or a managed provider with a London
region such as Neon (`eu-west-2`). When you choose, this section gains its exact commands; the
app-side steps are identical to staging with `thro-api` in place of `thro-api-staging`, the
production host as the relying party, and `DATABASE_URL` / `MIGRATE_DATABASE_URL` set by hand
from the provider's connection strings instead of `fly postgres attach`.

## Rolling back

Migrations are forward-only (ADR-013); the image rolls back, the schema does not. `fly releases
--app <name>` lists images; `fly deploy --image <previous image> --app <name>` returns to one.
Because every migration must be compatible with the previous image, this is safe by construction.

## Not done yet, and said so

- Nothing is deployed until you run the steps above; CI builds the image (`image` workflow) but
  never deploys.
- The API connects as one database user holding the union of the application roles (granted by
  the release step). ADR-011's per-module connections are a follow-up before production traffic.
- Rate limiting on the sign-in routes, object storage (media), push (APNs) and the scheduled
  restore drill are not configured.
