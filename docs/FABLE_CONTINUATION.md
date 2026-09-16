# Continuation ledger

A resilience mechanism for a session that stops at a usage boundary, so the next one resumes without repeating the
audit. Kept current during the build; **not** a deliverable, and never a substitute for `docs/CHANGE_RECORD.md`
(what happened, and how it was proven) or `docs/product/DECISIONS.md` (what was decided, and why).

## Where things are (16 September 2026, morning)

**Live** — actually reachable in the intended environment:

- `https://thro.uk` (Render static site, auto-deploys `apps/web/**` from branch `claude/thro-production-build-je2mkf`,
  fronted by Cloudflare): leagues, tables, fixtures, wall (`/tv`), organiser (`organiser.html`), moderation
  (`moderation.html`), privacy, terms, deletion, notices.
- `https://api.thro.uk` (Render web service `thro-api-staging`, free instance, Frankfurt): production at **V050**,
  commit **91b92b2** (PD-107; PD-108 follows). `/healthz` reports database, schema version, code version and commit.
- Neon production branch `br-icy-leaf-zaq0grqg` (project `round-darkness-99300686`), at V050. Restore points are
  branches: the pipeline's `pipeline-restore-point-before-<sha>-<stamp>` (newest three kept) and the founder's
  hand-made `restore-point-before-*` (never removed).
- iPhone on TestFlight: build 10 VALID (V049 code); build 11 uploading at the time of writing (V050: the rating card).
  Internal group *Founders*: the founder and the cofounder (Ethan).

**Deploy pipeline** — `.github/workflows/deploy-api.yml` on every push touching the API or its packages: checks →
Neon restore point → migrate → seeds → Render deploy hook `?ref=<sha>` → wait for `/healthz` to answer at the new
schema on the service's own hostname. Secrets `MIGRATE_DATABASE_URL`, `NEON_API_KEY`, `RENDER_DEPLOY_HOOK_URL` are set.
TestFlight: `testflight.yml` by `workflow_dispatch`; build number = run number; the archive is stamped with its
entitlements and refused if the signed app lacks Sign in with Apple or the passkey domain (PD-098).

## Completed this programme (each has a PD and a CHANGE_RECORD entry)

PD-095 deploy pipeline · PD-096 retention sweep · PD-097 Android notice · PD-098 TestFlight entitlements ·
PD-099 fixtures · PD-100 start a league · PD-101 moderation page · PD-102 ways in · PD-103 decisions enforce +
league management · PD-104 organiser email · PD-105 provisional rating · PD-106 the team's fixture · PD-107 registrations · PD-108 moving a fixture by agreement.

## Completion matrix (from four read-only audits, 16 September; details in PD-106 and CHANGE_RECORD)

| Area | State | Evidence |
|---|---|---|
| Identity, sessions, passkeys, erasure, suspension | Complete | AuthTest, PasskeyTest, SafetyTest, ModerationHttpTest |
| Team OS on the phone: create/claim, venue, roster, invite, roles, say-league | Complete | Teams routes + TeamScreens |
| Team OS: availability, lineup, the fixture as the side reads it, citing the match | **Complete (PD-106)** | TeamFixtureTest (24), TeamFixtureScreens.swift |
| League OS: start league, seasons, divisions, accept teams, fixtures, results, award, void, rearrange, table, private/end | Complete | PD-099..PD-106; organiser web |
| League OS: player registration (policy, reconcile, assess, confirm, send, answer) | **Complete (PD-107)** — routes, organiser web *Registrations*, phone inbox actions | RegistrationHttpTest (35) |
| League OS: points-policy approval, transfers, division moves, audit view | **Missing routes** — domain in `Organisations.kt` with tests, no HTTP, no UI | audit §2 |
| Secretary: rearrangement *proposals* (propose, answer, apply) | **Complete (PD-108)** — routes, phone fixture screen + inbox, organiser web *Requests* | RearrangementHttpTest (26) |
| Tournament OS on the server (`Competitions.kt`: openEvent/enter/checkIn/draw; tournament, pair, series tables) | **Missing routes** — whole class unreachable; phone tournaments are local-only | audit §2/§3 |
| Friendly challenge between teams | **Missing entirely** | audit |
| Discovery (leagues, events, nearby on-device) and the map | Complete for what is written; no server-side tournament entry | audit |
| Moderation | Complete (PD-101, PD-103) | ModerationHttpTest |
| Rating | Complete as provisional (PD-105); laboratory/validation open (OD-001) | Glicko2ModelTest, RatingHttpTest |
| Organiser email | Complete (PD-104); hand-over open (OD-025, needs outbound mail) | OrganiserContactTest |
| Web: organiser, moderation, public pages | Complete for the routes above; no `@media` breakpoints; `fail()` replaces the page on one bad read | audit §4 |
| Private league leak on season pages | **Fixed (PD-106)** | LeagueStartingTest |
| Development artefacts | Clean after PD-106 (Neon scaffold removed; dev proxy/README out of the publish root). NEEDS-DECISION: deploy branch named `claude/…`; `PlaytestServer` compiled into the image (entrypoint runs `MainKt`) | audit |
| "Club" wording | Only in the local on-phone book, export summary, and deep-link aliases | audit §6 |

## Frontier (what is next, in order)

1. ~~Secretary HTTP surface: registrations (PD-107), rearrangement proposals (PD-108)~~ **done**. Left of the
   League OS: points-policy approval, transfers, division moves as routes; withdrawing a proposal; a proposed venue.
2. **Tournament OS on the server**: routes over `Competitions.kt` (open an event, enter, check in, draw, results), then a
   web organiser page for events and the phone's Discover → enter.
3. **Friendly challenge** between teams (propose → accept/counter → fixture outside any season).
4. Web polish: breakpoints, a non-destructive `fail()`, fixtures page back-link.
5. NEEDS-DECISION (founder): the deploy branch's name; moving `PlaytestServer` out of the image.

## Founder's stated positions (do not re-ask)

Mailbox: later (iCloud+ custom domain recommended). Render stays for now; Cloudflare later. ICO and solicitor parked
until near submission. No Apple TV box needed — `thro.uk/tv`. Android: emulator only, no device. Email: organisers
only, never phone (PD-104). Rating: public, marked provisional (PD-105).

## Git lesson (16 September)

`git add -A -- <paths…>` aborts the whole add when one pathspec matches nothing, and `git commit` then commits only what
was already staged. Two PD-106 commits went out with a fraction of the work and CI red. Stage in one `git add` per
file group, and read `git status --short` before `git commit`, every time.

## How to resume

```bash
export PATH="/opt/homebrew/opt/openjdk@21/bin:$PATH" JAVA_HOME=/opt/homebrew/opt/openjdk@21
# API tests (local Postgres 16 on 5432; the `postgres` database holds thro_owner's objects):
PGHOST=localhost PGPORT=5432 PGUSER=jensonlr PGDATABASE=postgres THRO_REQUIRE_DB=1 gradle -p services/api test
# `gradle -p services/api clean` first if iCloud has left "* 2.class" duplicates in build/.
# Schema properties need a SCRATCH cluster (thro_owner is cluster-global):
#   initdb -D <scratch> -U jensonlr; pg_ctl -D <scratch> -o "-p 5433 -c unix_socket_directories='' -c listen_addresses=localhost" start
#   PGHOST=localhost PGPORT=5433 PGUSER=jensonlr PGDATABASE=postgres bash services/api/test/schema_properties.sh
# iPhone: cd packages/client-ios && swift test --filter 'AccountProfileTests|AccountTests|NetTests'
# Every repo check: for c in tools/check_*.py; do THRO_HOST_SKIP_DNS=1 python3 "$c"; done
# Commit by explicit paths only; push; read CI: gh run list --repo JensonLR/Thro-Darts-App --commit <sha>
```

Rules that hold: commit by explicit paths, never stash or sweep; a Neon restore point before any production change
(the pipeline takes one); never delete a Neon branch or run destructive SQL without asking; never set GitHub secrets;
record decisions in DECISIONS.md and CHANGE_RECORD.md; review as a hostile reviewer would; claim nothing unchecked.
