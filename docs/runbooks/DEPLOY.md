# Runbook — deploying to Fly.io (PD-031)

One image, London, managed PostgreSQL with point-in-time recovery, migrations as the release step.
Everything below is run by a person with the Fly account; nothing in the repository holds a secret.

## Once: accounts and tools

1. Install the Fly CLI and sign in: `brew install flyctl && fly auth login`.
2. Create two apps from the repository root, staging first. Pick names without the product name
   (ADR-011: permanent identifiers outlive a rename):
   ```bash
   fly apps create <company>-api-staging --org personal
   fly apps create <company>-api --org personal
   ```
3. Provision PostgreSQL 16 in London **with point-in-time recovery**. Two databases, one per app;
   staging holds synthetic data only, never a copy of production (ADR-011). Either Fly's Managed
   Postgres in `lhr` if it is offered on your account, or a managed provider with a London region
   (for example Neon, `eu-west-2`). Whichever you choose, note the host, database, and a superuser
   or `thro_owner`-member credential for migrations, and create the application roles the
   migrations expect by running V001 once (the release step does this on first deploy).
4. Sign-in providers (PD-030):
   - **Apple:** in the Apple Developer portal, the app's bundle identifier is the client id for
     tokens from the iOS SDK. Note it.
   - **Google:** in Google Cloud Console → APIs & Services → Credentials, create an OAuth client of
     type iOS; the client id is the audience of the ID tokens the SDK returns. Note it.
5. Set the secrets for each app (the values never touch the repository):
   ```bash
   fly secrets set --app <company>-api-staging \
     PGHOST=<host> PGPORT=5432 PGDATABASE=<db> PGUSER=<deploy user> PGPASSWORD=<password> \
     THRO_APPLE_CLIENT_ID=<bundle id> THRO_GOOGLE_CLIENT_ID=<google client id>
   ```
   `THRO_DEV_AUTH` is never set on Fly. The server refuses it against a remote database anyway.

## Every deploy

```bash
fly deploy --app <company>-api-staging          # staging first, always
# check /healthz reports the new schema version, exercise the client against staging
fly deploy --app <company>-api                  # then production
```

`fly deploy` builds the Dockerfile, runs the release command — the same image with `migrate`,
which brings the database to the image's version through the ledger (ADR-013) and refuses a
database it cannot reason about — and only then rolls the machines. A failed migration stops the
deploy before the new image serves a request.

## Checking it

```bash
fly status --app <name>
fly logs --app <name>
curl -s https://<name>.fly.dev/healthz        # {"database":"ok","schemaVersion":"V0xx"}
curl -s https://<name>.fly.dev/openapi.json | head -c 300
```

## Rolling back

Migrations are forward-only (ADR-013); the image rolls back, the schema does not. `fly releases
--app <name>` lists images; `fly deploy --image <previous image>` returns to one. Because every
migration must be compatible with the previous image, this is safe by construction.

## Not done yet, and said so

- The image is built in CI (`image` workflow) but has not been deployed anywhere: that needs the
  Fly account and the database, which are yours to create.
- The API connects to the database as one role. ADR-011's per-module least-privilege roles exist in
  the schema and are held by the schema tests; connecting each module through its own role is a
  follow-up before production traffic.
- Object storage (media), push (APNs) and the scheduled restore drill are not configured.
