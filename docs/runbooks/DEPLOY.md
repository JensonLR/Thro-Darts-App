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

## The web, and the domain (PD-056, PD-057)

`render.yaml` carries two services now: the API, and **`thro-web`**, a free static site serving `apps/web`.
Deploying it is the same Blueprint — Render picks the new service up. Two rewrites make the pages and the
API one origin:

| Path | Goes to | Why |
|---|---|---|
| `/v1/*` | the API service | `thro.js` calls `/v1/...` with no host, so the browser never makes a cross-origin request: no CORS, no preflight, no second host to configure, no token in a query string |
| `/.well-known/apple-app-site-association` | the API service | iOS offers a passkey for a domain only when **that** domain serves the association file. The moment the pages live at a domain, the domain has to serve it |

### They are two different things

Render and the domain are not alternatives, and it is worth saying plainly because the question came up:

- **Render is the machine.** It serves the pages and runs the API. It is free for the web, and it gives you
  an address of its own — `thro-web.onrender.com` — the moment you deploy.
- **The domain is the address people type.** You buy it from a registrar, once a year, and point it at
  Render.

So you can be live today with no domain at all. The domain buys three things: an address that looks like a
company rather than a hosting account, the address a store's account-deletion requirement will be checked
against, and a stable home for passkeys and universal links.

**Buy it before anybody has a passkey.** A passkey is bound to the domain it was created under, so the day
the host changes, every existing passkey stops working. Today that costs nothing, because nobody has one.
After a hundred people have signed in it costs each of them a sign-in.

> **The day you buy the domain, follow [GOING_LIVE.md](GOING_LIVE.md)** — it is the ordered list, and the
> switch itself is `python3 tools/host.py --set thro.uk`. Do not do it by hand: the relying party and the
> app's base URL become different names, and a find-and-replace breaks passkeys silently (PD-058).

### Web Service or Static Site?

Render offers both and they are different jobs, not two ways of doing one:

- A **Web Service** is a process that runs. That is the API: a JVM holding connections, answering `/v1`.
- A **Static Site** is files on a CDN. That is the pages: no process, nothing to wake, free, and fast from
  the first request whatever the API is doing.

**Take the Static Site.** The pages have no server in them — that was the point of building them without a
framework — and a static site never sleeps, which matters when the page a store checks is a deletion URL.

### What buying the domain later actually costs

Nothing is thrown away, and nothing is re-architected. The web client hardcodes no host at all: it calls
`/v1/...` with no origin in front, so it is already correct for whatever name it is served under. When the
domain arrives:

1. Add `thro.uk` to the static site in Render (Step 3), and point the DNS.
2. Change three values: `THRO_RP_ID` in the API's environment, `webcredentials:` in the app's entitlement,
   and the base URL in the app's `Info.plist`. Rebuild the app.

That is the whole migration. Ten minutes, and no code the web depends on moves.

### Step 1 — Put the web on Render (no domain needed)

**Do not apply the Blueprint a second time.** The API is already deployed and belongs to an earlier Blueprint
instance, and Render will not let a new one adopt it: the *Associate existing services* option is greyed out
and the only choice left is **Create all as new services**, which makes a duplicate API — `thro-api-staging-gbbk`
beside the real one — and asks for `DATABASE_URL` again. `render.yaml` stays as the record of both services;
the site is created on its own:

1. <https://dashboard.render.com> → **New → Static Site**.
2. Connect `JensonLR/Thro-Darts-App`; branch **`claude/thro-production-build-je2mkf`**.
3. Name `thro-web`. **Build Command:** leave empty — there is nothing to build. **Publish Directory:**
   `apps/web`. Create it; the free plan is enough.
4. **Settings → Redirects and Rewrites**, and add two rules, both with Action **Rewrite**. Render's rule
   syntax allows a full URL as a destination, which is what makes one origin possible:

   | Source | Destination |
   |---|---|
   | `/v1/*` | `https://thro-api-staging.onrender.com/v1/*` |
   | `/.well-known/apple-app-site-association` | `https://thro-api-staging.onrender.com/.well-known/apple-app-site-association` |

   Render does not apply a rule to a path where a file already exists, so these cannot shadow the pages.

5. When it goes green, check both halves — the pages, and the API through the same origin:

```bash
curl -s -o /dev/null -w "pages %{http_code}\n" https://thro-web.onrender.com/delete-account.html
curl -s -o /dev/null -w "api   %{http_code}\n" https://thro-web.onrender.com/v1/leagues
```

Two 200s means the rewrite is working and the site is done until the domain arrives.

### What the free `onrender.com` address does and does not give you

Everything public works on it, today, with TLS and no card: the leagues, a season's table, its fixtures, and
the account-deletion page. A store checking that deletion URL only needs it to load, so **Android is not
blocked by the lack of a domain**.

**Web sign-in is the one thing that cannot work on it**, and the reason is worth writing down because it
looks like a bug otherwise. `onrender.com` is on the [Public Suffix List](https://publicsuffix.org/), so
`thro-web.onrender.com` and `thro-api-staging.onrender.com` are two *different* registrable domains, the way
`bbc.co.uk` and `itv.co.uk` are. A WebAuthn passkey belongs to one registrable domain, and the only thing
these two share is `onrender.com` itself — which a browser refuses as a relying party, precisely because it
is a public suffix. So a passkey cannot span them. Setting `THRO_RP_ID` to the web host would fix the web and
break the iOS app, whose passkeys are bound to the API host.

**There is exactly one workaround, and it is not worth taking.** Serve the pages from the API service itself
— Ktor serving `apps/web` at `/` — and the browser's origin becomes the API's own host, so one relying party
covers the phone and the laptop and web sign-in works today. What it costs: the public pages inherit the API
service's spin-down, so on the free instance the account-deletion page a store reviewer opens could take a
minute to answer or time out, and every page waits on a JVM instead of a CDN. Trading a fast public site for
a sign-in that nobody needs yet — there is not one named league administrator in existence — is the wrong way
round.

So: ship the public pages on a static site, leave the organiser sign-in switched off, and let the domain fix
it properly. One name, `thro.uk`, pages and API both under it, one relying party for the phone and the laptop
alike.

### Step 2 — Register `thro.uk`

Nominet does not sell direct; you buy `.uk` through a registrar. Namecheap, Porkbun, Gandi and 123-reg all
sell it; **Cloudflare Registrar does not carry `.uk`**, which is worth knowing because it is otherwise the
usual recommendation. Expect roughly £8–12 a year — **compare the renewal price, not the first year**, which
is where the cheap offers make their money.

What matters more than the price: DNS you can edit yourself (all four above have it), and no bundled
"privacy" upsell — `.uk` has its own arrangement. Nominet publishes a registrant's address on the public
register, and lets a **non-trading individual** opt out of that. Whether THRØ counts as trading is worth ten
minutes of your own judgement; if it does, use a business address you are content to have published.

### Step 3 — Point the domain at Render

1. Render → **`thro-web`** → **Settings → Custom Domains → Add Custom Domain** → `thro.uk`.
   Render adds `www.thro.uk` automatically and redirects it to the root.
2. Render then **shows you the exact DNS records**. Use those, not a value from a blog or from me — they are
   provider-specific and Render changes them.
3. At your registrar's DNS page, add what Render showed, and **delete any AAAA records**: Render is IPv4
   only, and a stray AAAA makes the domain fail in ways that look like a Render fault.
4. Back in Render, click **Verify**. If it fails, DNS has not propagated — wait a few minutes and click
   again. TLS is issued automatically and free once it verifies.
5. Once the domain works, **disable the `onrender.com` subdomain** (same settings page), so the site has one
   address rather than two. Two addresses mean two relying parties for passkeys and two of everything for a
   search engine.

### Step 4 — Switching to `thro.uk`

With the domain live on Render, four places in this repository still name the old host, and they change
together or passkeys and universal links stop working. Do them in one sitting, then check two things:

1. **`THRO_RP_ID` → `thro.uk`**, in `render.yaml` and in the API service's environment in the dashboard.
   Redeploy the API so it picks the value up.
2. **`apps/ios/Support/ThroDarts.entitlements`** → `webcredentials:thro.uk`.
3. **`apps/ios/Support/Info.plist`** → the base URL becomes `https://thro.uk`. The API answers there through
   the rewrite, so the app needs no second host either.
4. Rebuild the app and install it, or the phone is still talking to the old address.

Then check both halves from the new host:

```bash
curl -s https://thro.uk/.well-known/apple-app-site-association   # the app id, not the static site's 404
curl -s https://thro.uk/v1/leagues | head -c 80                  # the API, through the same origin
```

**Every existing passkey stops working.** A passkey is bound to the relying-party id it was created under, so
one made against `thro-api-staging.onrender.com` cannot be used against `thro.uk`. Anybody who has made one —
which today is the founder, if anyone — signs in another way and makes a new one. Better now than after a
hundred people have.

**And take the API off the free instance at the same time.** A free Render service sleeps after fifteen idle
minutes, and a sleeping server drops a live match stream (ADR-007), which is the one thing in THRØ that
cannot tolerate it. Starter is $7 a month. PD-057 has the reasoning and the point at which Fly becomes worth
the second platform.

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
# then, when a league seed has changed (PD-033, PD-037) — idempotent, as the same user; both files:
gradle -p services/api seed --args=seed/leagues/directory.json
gradle -p services/api seed --args=seed/leagues/teesside.json
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
