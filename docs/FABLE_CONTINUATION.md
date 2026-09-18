# Continuation ledger

A resilience mechanism for a session that stops at a usage boundary, so the next one resumes without repeating the
audit. Kept current during the build; **not** a deliverable, and never a substitute for `docs/CHANGE_RECORD.md`
(what happened, and how it was proven) or `docs/product/DECISIONS.md` (what was decided, and why).

## 18 September 2026 — all four phases done, and both chosen builds shipped

**Thirty-two decisions, PD-131 to PD-162**, all pushed and CI-green on `claude/thro-production-build-je2mkf`.
Production API at **V057**; thro.uk carries the dark-mode fix, the skeletons, the type scale and — for the
first time — THRØ's own face.

**Phase 1 (the five known issues): done.** PD-131 dates · PD-132 no decision numbers · PD-133 pair order
(V057) · PD-134 colour scheme · PD-135 waiting and giving up · PD-136 the desk reads as itself ·
PD-137 a failed read is not an empty one.

**Phase 2 (research): done.** `docs/design/RESEARCH_2026.md`, 190 lines, 47 cited sources, two adversarial
passes.

**The known issues left open at that checkpoint: all closed.** PD-142 every inbox card has an act, and the
three sentences that lived in views are testable · PD-143 the export is everything or an error.

**Phase 3 (screens): all ten of the research's ranked changes addressed.** PD-140 the chrome grows and
the bar stays a bar · PD-141 blocking exists, where the person is read · PD-144 one row, one card ·
PD-145 two faces, one gap · PD-146 the screen that commits has a floor · PD-147 one primary per screen ·
PD-148 fewer words and a state that is not a claim · PD-149 the web on the design system · PD-150 no page
sends a reader nowhere · PD-151 what THRØ says when there is nothing to show · PD-152 one field per place
· PD-153 a fixture list opens where the reader is.

**Founder's answers (do not re-ask).** Phase 3 as two parallel change sets — both done. Blocking: build
the control — done. The league privacy default stays ticked.

**Left, and why.**
- **Phase 4 is finished, and the headline is that the model was not needed.** The founder chose builds 1
  and 3 and the queue's code fixes. All shipped: PD-155 (the moderation queue cannot be ordered by the
  reporter — a child-safety band at 0.5, a one-per-reporter cap on promotion, an injection guard that
  sets aside severity and never a child), PD-156 (Live shortened), PD-157 (the no-model floor:
  `pick()` returns `confidence`, a `SURE_ENOUGH` = 0.6 gate on `ready`, 254 options, `jev-1.13.0`
  pinned, and input tokens counted), PD-158 (`ProductionDesk` + `TeamNames` + `fixturesNamed`),
  PD-159 (`ResultsSheet`), PD-160 (the route and the organiser's paste pane).
- **Two premises in the ranking were wrong, and checking them changed the plan.** The fixture Choice
  **already had a `none` option**, so build 1's two proposed Nouls had nothing to win; and on the
  production-size desk the code floor refuses **20 of 20** sealed "no fixture" sentences while still
  finding **11 of 11** real ones. The results sheet then scored **0 wrong while ready, 40 of 45 ready and
  right** with no model at all. **So none of the nine proposed questions was built.** That is the phase's
  real finding: write the `for` loop first and publish its number.
- **What Jev costs, now measurable.** $42 per billion input tokens, output free. `Reader.kt` discarded
  `usage.input_tokens`; it counts them now and prints the running dollar figure. Jev **is** live in
  production (every boot logs `reader: TypeSafe …`), and at current volume the spend is a fraction of a
  cent — but it was unmeasured until PD-157.
- **PD-161 and PD-162 closed the loose ends.** The seed's venue collision (`IS NOT DISTINCT FROM` made
  two Red Lions one row — **latent, not live**: all 18 seeded venues carry an OSM id and a locality);
  `Discovery.sameLocality` so a town written two ways is one town (**still dead code** — no shipped
  caller sends `locality`); and the last of PD-147's three abandoned changes. **That entry was wrong**:
  it says the applier "invented a `SegmentedControl` that does not exist", and it exists in
  `ThroDesign/Forms.swift`, public, since PD-066. Three changes were dropped on an unchecked claim.
- **Three live defects found in passing, of which two are now closed**: `Safety.kt` child-safety band (fixed in
  PD-155), `Seed.kt:86` NULL-matches-NULL, `Discovery.kt:96` exact locality compare (dead in production
  — no shipped caller passes `homeLocality`).
- **The duplicate Render static site is gone** (checked 18 September 2026 — only `THRO-web` remains), so the
  note asking the founder to suspend it is closed.
- **The API is still on Render's free plan** (`plan: "free"`, checked 18 September 2026). PD-135/136's skeletons
  hide the cold start; they do not remove it. The honest fix is the paid instance, ~$7/mo, and it is the founder's.
- **TypeSafe has no Art 28 processor terms and the key is set.** Recorded in `docs/legal/ROPA.md` and
  cross-referenced from the DPIA on 18 September 2026. Either obtain the terms or unset `THRO_TYPESAFE_API_KEY`;
  unsetting degrades safely to `note: no reader`.
- **The contact address.** PD-150 stopped every page instructing a reader to write to one. What the
  address will be is still the founder's: three legal pages, the children's page and the App Store
  listing wait on it.
- **Twenty full-width primaries** outside `ThroBottomAction`, listed in PD-146. Most are in-card buttons
  rather than screen floors; which want one is a judgement per screen.
- **Three `TeamFixtureScreens.swift` changes** from the PD-147 survey were prose, not substitutions, and
  are not done.
- **Six line-height moves** in PD-149 were under-disclosed by the change list and are recorded in it.
- **The `h1` line-height** is unset in `apps/web`; no page has an `<h1>` today.

**Lessons this session, worth not relearning.**
- **Local green is not CI green.** Three tests asserting locale-formatted date literals passed here and
  failed on a US-locale runner. Assert what a function composes, never a formatted date.
- **A change list is only mechanical where every entry is a substitution.** An applier took three prose
  descriptions literally and mangled a file, inventing a component that does not exist.
- **A screenshot harness that reuses a Chrome profile photographs cached CSS** and reports it as the
  change. Only the measured contrast failing to move gave it away.
- **Verify a theme or a token by reading computed custom properties**, not by comparing PNG bytes.
- **Production is empty**: 329 leagues, all listed, none run here, no events. The empty state is the
  product, not an edge case.

## Where things are (16 September 2026, morning)

**Live** — actually reachable in the intended environment:

- `https://thro.uk` (Render static site, auto-deploys `apps/web/**` from branch `claude/thro-production-build-je2mkf`,
  fronted by Cloudflare): leagues, tables, fixtures, wall (`/tv`), organiser (`organiser.html`), moderation
  (`moderation.html`), privacy, terms, deletion, notices.
- `https://api.thro.uk` (Render web service `thro-api-staging`, free instance, Frankfurt): production at **V056**,
  commit **76b8927** (PD-117 to PD-130; deploy-api green, `/healthz` read by hand; the association file serves
  `applinks` for `/link/*`, `/league/*`, `/event/*` and `/team/*`; TestFlight builds 20 and 21 VALID; `/v1/auth/providers` says `reads:true` — the founder set the TypeSafe key on 17 Sep); the web at
  3b25dcd (Tell THRØ leads the season desk, the list is pasted into the scheduler, *Who changed what* folds at the
  foot, the laptop's sign-in panel draws a QR; Open THRØ on a phone, `link.html`; the `/link/*` rewrite was added to THRO-web by the dashboard on 17 Sep and `thro.uk/link/<code>` answers 200; the Apple/Google buttons and THRØ's readings are dormant until the
  founder sets their keys). `/healthz` reports database, schema version, code version and commit.
- Neon production branch `br-icy-leaf-zaq0grqg` (project `round-darkness-99300686`), at V053. Restore points are
  branches: the pipeline's `pipeline-restore-point-before-<sha>-<stamp>` (newest three kept) and the founder's
  hand-made `restore-point-before-*` (never removed).
- iPhone on TestFlight: build 19 **VALID** (from 6731c31: the board says *A screen is waiting*). Build 18 (VALID; from 3b25dcd: a signed-out phone opening a sign-in link is shown the way in). Build 16 **VALID** (from 30896e4: the applinks entitlement, the profile opened by a link)
  and build 17 (VALID; from 76e9c2d: the readiness row says links work), in the *Founders* group. Build 15 before them.
  Internal group *Founders*: the founder and the cofounder (Ethan).

**Deploy pipeline** — `.github/workflows/deploy-api.yml` on every push touching the API or its packages: checks →
Neon restore point → migrate → seeds → Render deploy hook `?ref=<sha>` → wait for `/healthz` to answer at the new
schema on the service's own hostname. Secrets `MIGRATE_DATABASE_URL`, `NEON_API_KEY`, `RENDER_DEPLOY_HOOK_URL` are set.
TestFlight: `testflight.yml` by `workflow_dispatch`; build number = run number; the archive is stamped with its
entitlements and refused if the signed app lacks Sign in with Apple or the passkey domain (PD-098).

## Completed this programme (each has a PD and a CHANGE_RECORD entry)

PD-095 deploy pipeline · PD-096 retention sweep · PD-097 Android notice · PD-098 TestFlight entitlements ·
PD-099 fixtures · PD-100 start a league · PD-101 moderation page · PD-102 ways in · PD-103 decisions enforce +
league management · PD-104 organiser email · PD-105 provisional rating · PD-106 the team's fixture · PD-107 registrations · PD-108 moving a fixture by agreement · PD-109 a knockout · PD-110 a friendly · PD-111 rounds · PD-112 the organiser's remaining acts · PD-113 invitationals · PD-114 sign in by the phone · PD-115 pairs, teams, seeds, boards · PD-116 Apple and Google on the web (**done** — `api.thro.uk/v1/auth/providers` answers `apple: uk.thro.web` and a Google web client id, checked 18 Sep 2026) · PD-117 the phone that is already here (Open THRØ from the web's sign-in, `/link/<code>`) · PD-118 THRØ reads reports and names with TypeSafe's System One model (V054) · PD-119 Tell THRØ, the desk reads a sentence into an act (the key was set 17 Sep: production says `reads:true`) · PD-120 who changed what (V055) · PD-121 the sign-in code as a QR · PD-122 paste the fixture list · PD-124 walk-ups (V056) · PD-125 the desk reads the points rules; the model read twice · PD-123 the model measured (`JevEvaluationTest`; key in the git-ignored `.env.local`; held out 11 of 12, list 10 of 10, scorecard in `docs/product/JEV_SCORECARD.md`) · two design passes (web, phone).

## Completion matrix (from four read-only audits, 16 September; details in PD-106 and CHANGE_RECORD)

| Area | State | Evidence |
|---|---|---|
| Identity, sessions, passkeys, erasure, suspension | Complete | AuthTest, PasskeyTest, SafetyTest, ModerationHttpTest |
| Team OS on the phone: create/claim, venue, roster, invite, roles, say-league | Complete | Teams routes + TeamScreens |
| Team OS: availability, lineup, the fixture as the side reads it, citing the match | **Complete (PD-106)** | TeamFixtureTest (24), TeamFixtureScreens.swift |
| League OS: start league, seasons, divisions, accept teams, fixtures, results, award, void, rearrange, table, private/end | Complete | PD-099..PD-106; organiser web |
| League OS: player registration (policy, reconcile, assess, confirm, send, answer) | **Complete (PD-107)** — routes, organiser web *Registrations*, phone inbox actions | RegistrationHttpTest (35) |
| League OS: points rules, division moves, transfers | **Complete (PD-112)** — routes + organiser web | LeagueActsHttpTest (22) |
| League OS: who changed what | **Complete (PD-120, V055)** — `/v1/seasons/{id}/history`, the desk's folded section; a move now names its actor | SeasonHistoryTest, LeagueActsHttpTest |
| Secretary: rearrangement *proposals* (propose, answer, apply) | **Complete (PD-108)** — routes, phone fixture screen + inbox, organiser web *Requests* | RearrangementHttpTest (26) |
| Tournament OS on the server: open, enter, withdraw, check in, close, draw round one | **Complete (PD-109)** — routes, `events.html`, Discover card actions | EventHttpTest (32) |
| Tournament OS: later rounds, a tie decided (played or declared), the event's winner, citing from the phone | **Complete (PD-111, V052)** | EventHttpTest (47) |
| Tournament OS: invitational access, the organiser's entries | **Complete (PD-113)** | EventHttpTest (61) |
| Tournament OS: pairs/teams as entrants, seeding, boards | **Complete (PD-115)** | EntrantsHttpTest (30) |
| Tournament OS: walk-up entrants without accounts | **Complete (PD-124, V056)** — by name, singles nights; named publicly only on the organiser's attestation; forgotten after thirty days | GuestsHttpTest (14) |
| Tournament OS: pairs or teams of walk-ups; a walk-up claiming their player; a pair from friends | **Missing** | PD-124 |
| Friendly challenge between teams | **Complete (PD-110, V051)** — challenge, answer, withdraw, cite; phone team front | FriendlyHttpTest (31) |
| Discovery (leagues, events, nearby on-device) and the map | Complete for what is written; no server-side tournament entry | audit |
| Moderation | Complete (PD-101, PD-103) | ModerationHttpTest |
| Rating | Complete as provisional (PD-105); laboratory/validation open (OD-001) | Glicko2ModelTest, RatingHttpTest |
| Organiser email | Complete (PD-104); hand-over open (OD-025, needs outbound mail) | OrganiserContactTest |
| Web: organiser, moderation, events, public pages | Complete for the routes above; one breakpoint at 420px; `fail()` keeps the page | audit §4, closed |
| Private league leak on season pages | **Fixed (PD-106)** | LeagueStartingTest |
| Development artefacts | Clean after PD-106 (Neon scaffold removed; dev proxy/README out of the publish root). NEEDS-DECISION: deploy branch named `claude/…`; `PlaytestServer` compiled into the image (entrypoint runs `MainKt`) | audit |
| "Club" wording | Only in the local on-phone book, export summary, and deep-link aliases | audit §6 |

## 17 September, evening: PD-126 and PD-127

The founder: *league and Discover still feel disconnected and false; so does the link between web and app.* Production
held 329 leagues, none started here, none with a named administrator, no fixtures (checked by a read-only query). Done:
`/v1/leagues` says `standing` and per-season `fixtures`/`results`; app and web word a league as run here, teams listed,
or on the map only, and count them apart; no TABLE without fixtures; every *tell THRØ* replaced by something a player
can do; a tournament row opens `EventScreen`; `thro.uk/league|event|team/<id>` is one address on the web and in the app,
shared from the app, with *Open in THRØ* or a QR on each page. **External after deploy:** three rewrites on the static
site's dashboard (`/league/*` → `/league.html`, `/event/*` → `/event.html`, `/team/*` → `/team.html`). Left on the list:
a team of walk-ups, and a walk-up claiming their player (both deliberately left: PD-130 says why; pairs with a walk-up are PD-130, done). (The captain's *say it* is PD-129, done the same evening: held-out about two in three first time, misses failing safe.) (A proposed
venue on a rearrangement is PD-128, done the same evening.) (The single-league read, `GET /v1/leagues/{id}`, followed the same evening.)

## Frontier (what is next, in order)

1. ~~Secretary HTTP surface (PD-107, PD-108), points rules / division moves / transfers (PD-112), withdrawing a
   proposal~~ **done**. Left of the League OS: an audit page; a proposed venue on the wire.
2. ~~Tournament OS on the server~~ **done through the final, open and invitational (PD-109, PD-111, PD-113)**. Left:
   pairs and teams as entrants, seeding, boards, players without accounts.
3. ~~Friendly challenge~~ **done (PD-110)**. Left: rearranging an accepted friendly; a venue on the wire.
4. ~~Web polish~~ **done**: a 420px breakpoint, `fail()` keeps the page and offers *Try again*, fixtures → table.
5. ~~NEEDS-DECISION~~: the founder keeps the deploy branch's name (16 Sep); `PlaytestServer` is out of the image
   (PD-114's commit). ~~Next for "a whole new level of UI standard"~~ looked at 16 September night: the table and
   fixtures pages already wear the home page's field header and nav (left as they are); Home, Play and Live are cards;
   You on the iPad sits in two columns; the iPhone in landscape renders side by side. Nothing changed there.
6. PD-117: on a phone the web's sign-in leads with *Open THRØ*; `https://thro.uk/link/<code>` is a universal link
   (needs TestFlight build 16 on the phone for the entitlement). Not done: a QR code on the laptop's panel.
7. PD-118: the moderation queue carries THRØ's reading of each report, and a chosen name that reads as abuse is put on
   the queue by THRØ itself — once the founder creates a TypeSafe key, reads its terms, and sets
   `THRO_TYPESAFE_API_KEY` on Render (steps in PD-118).
7a. PD-119 Tell THRØ: the secretary's desk reads a sentence into a result, an award, an annulment or a new fixture, on
   a card the person confirms (function calling, fan-out, date extraction, confidence-gated routing — the shape
   TypeSafe's cookbooks describe). Same key. Next, in the order they pay: the fixture screen's *say it* for a captain
   (a proposal card); a typed player name matched to a registered one at registration (entity alignment); a league's
   typed rules read into a points policy.
8. ~~PD-116 waits on the founder's console work.~~ **Done, checked 18 September 2026.** The Services ID and the
   Web OAuth client exist and both variables are set on Render: `GET /v1/auth/providers` answers
   `{"apple":"uk.thro.web","google":"5826…apps.googleusercontent.com","reads":true}`. The web offers Apple and
   Google beside the phone code and the passkey. This item was still being reported as outstanding three days
   after it was finished, which is the cost of a ledger line nobody re-checks.

## Known gaps after PD-113 (small, recorded rather than hidden)

- ~~cite's other seat~~, ~~sentAt~~: closed 16 September (PD-108 addendum commit).
- ~~The PD-108 and PD-110 HTTP tests were written before their routes but their first red run was not watched.~~
  **Closed by PD-165**: eight mutations, 7 caught, and the one survivor is a guard duplicated a layer down in
  `Secretary` rather than a gap. `tools/mutate.py` is kept so the next doubted suite is a minute's work.
- Not looked at in the simulator: ~~the challenge form on another team's front~~ (**looked at 18 September**,
  PD-168 — it was unreachable: the stage had no team you do not run); *Name the match* with matches present;
  the desk cards in landscape (You was looked at on the iPad and in landscape, 16 September). **Looked at 18 September** (PD-166): it was unreachable, not unlooked-at — the dev authenticator never named
  an account, so every account-shaped route 403'd locally. Fixed, looked at, and the looking found PD-167.
- How to look again: `THRO_DEV_AUTH=1 PGHOST=localhost … gradle -p services/api serve`, `python3 tools/web_serve.py`,
  a browser at 375 points with `sessionStorage.thro.session` set and `fetch` patched to add `X-Thro-Dev-Subject`;
  on the phone, `xcrun simctl launch <device> app.thro.darts -ThroScreenshotAccount adult -ThroScreen tab/you`.

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
