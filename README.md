# THRØ

**The digital home of competitive darts.**
From the pub board to the world stage.

THRØ doesn't decide how good you are. It gives you the evidence to understand where you
are, the tools to improve, and the competition to prove it.

---

## What this repository is

THRØ is a competitive infrastructure platform for darts — not a scorer, not a tournament
app, not a statistics app. It connects players, matches, visits, legs, sets, teams,
leagues, seasons, tournaments, venues, boards, ratings, trust and evidence into a single
competitive graph.

The product exists to help a player answer four questions:

> **Where am I? Why am I here? What can I do next? Where could I go?**

## Current state — read this first

The build follows a gated process in which foundations are established and **attacked** before
features are written. Gate 0's and Gate 1's first drafts were both rejected by hostile review and
corrected rather than defended — in Gate 1's case after the defect was reproduced against a live
database.

| Gate | | |
|---|---|---|
| 0 | Foundation ingestion | Closed — design authority recovered and inspected |
| 1 | Architecture | Closed — 15 decision records, hostile-reviewed and corrected |
| 2 | Repository foundation | Event schema and the command path, proved against a real Postgres |
| 3 | Design ingestion | Token pipeline generating Swift, Kotlin and CSS from one source |
| 4 | Competitive core | Scoring engine passing 86,000 exhaustive transitions |
| 5 | Offline match lifecycle | Domain core closed — grants, per-device streams, reconciliation. On-device journal built on iOS under the measured configuration (`ThroJournal`); Android not started |
| 6 | Vertical slice | An iOS slice exists for a match between two people on one phone — setup, scoring, result, journaled. **The slice with identity is still blocked** on the authentication *surface* (B4); ADR-008's mechanism is built |
| 7 | Trust and provenance | Closed — attestation, disputes, adjudication, quarantine, eligibility |
| 8 | Rating | Architecture closed — a replayable projection. **The model is OD-001 and stays open** |
| 9 | Organiser | Correction and adjudication closed, both under the conflict-of-interest rule |
| 10+ | Live, notifications, payments | Not started — each waits on a product decision |

**What is verified, and how:**

| | |
|---|---|
| Scoring rules | 436 property checks against independent darts facts |
| Scoring engine | 86,000 exhaustive transitions + 64 corpus cases, **on two independent implementations** |
| Statistics honesty | 20 tests — an uncomputable figure says so; an approximate one is never a point value |
| Trust and eligibility | 30 tests — a label can never disagree with the provenance under it |
| Authorization | 21 tests — the conflict-of-interest rule, and age as a dimension |
| Rating projection | 14 tests — reproducible from a watermark pair; OD-001 stays open |
| Competition structure | 13 tests — bracket identities exhaustive for every field size to 1024 |
| Schema and privileges | 71 property assertions against a real PostgreSQL |
| Command path | 9 integration suites, 132 properties end to end against a real PostgreSQL |
| Design tokens | 50 contrast pairs, absolute thresholds, 0 unrecorded breaches |
| Design components | 61 components audited mechanically against a baseline ratchet |
| Statistics honesty, Swift | The same 20 tests, ported case for case, on Linux |
| On-device journal | 15 tests — configuration read back on open, append-only by trigger, replay throws on a corrupt row, a retraction supersedes and never deletes, an old journal upgrades on open |
| Scoring session | 27 tests — every PD-001 branch; engine → journal commit → screen, never another order; undo as a retraction, including of the visit that ended a match; a bust or a won leg holds the keypad until both players have seen it (PD-005) |
| Type faces | 4 tests — every type role resolves to one of the ten embedded faces; weights the families lack land on their nearest face |
| iOS app | Builds for the iOS simulator on every push that touches it. Run on the founder's phone three times (2026-09-05 / 06), setup to result, each run's findings fixed and confirmed on the next (see the runbook). Carries the founder's mark as icon and launch screen and embeds the two type families under the SIL Open Font License (PD-006); `apps/ios/check_fonts.py` holds the fonts, licences and assets to the code on every push |

**Nothing here is production ready**, and no claim of security, offline reliability or rating
validity is made anywhere in this repository. There is an iOS client that scores a match between two people on
one phone and keeps it there — built and tested on CI and run three times on the founder's phone ([`docs/runbooks/CLIENT_IOS.md`](docs/runbooks/CLIENT_IOS.md)).
It talks to nothing. There is no HTTP layer and no deployment — the command path is a tested handler, not a running service.
Claims are made only where evidence exists — see [`FOUNDATION_ACCEPTANCE.md`](FOUNDATION_ACCEPTANCE.md).

**Two decisions are recorded as taken on delegated authority** ([`docs/product/DECISIONS.md`](docs/product/DECISIONS.md)),
each with its reversal path. Two remain open and need design work only the founder can commission:
the authentication surface, and participant result confirmation — without which nothing outside an
organised competition can be rated.

## Repository layout

```
packages/
  domain-spec/    Rule tables and the conformance corpus, derived from the dartboard
  engine/         The deterministic scoring engine (Kotlin, zero dependencies)
  engine-swift/   The same engine in Swift — ADR-002's spike, same corpus
  durability-probe/  Measures the cost of ADR-006's durability rule, on device
  statistics/     Figures that say when they cannot be computed honestly
  statistics-swift/  The same figures in Swift, the same twenty tests
  client-ios/     The iOS client as packages: ThroDesign, ThroJournal, ThroPlay, ThroApp
  competition/    Bracket structure — byes, rounds, walkovers
  trust/          Provenance, derived verification, rating eligibility, reconciliation
  authz/          Relationship-based authorization, and age as a dimension
  rating/         Rating as a versioned replayable projection
  design-tokens/  One token source generating Swift, Kotlin and CSS
apps/
  ios/            The Xcode app target — a few lines that mount ThroApp, plus the icon, launch screen and embedded fonts
services/
  api/            Migrations, the command path, and the playtest harness
docs/
  adr/            15 architecture decision records
  architecture/   Conformance corpus spec, latency budgets
  design/         Design authority — provenance, inventory, contrast matrix,
                  token health, what the system does not specify
    extracted/    Token layer, 61 components, 33 participant + 9 organiser screens
  product/        Glossary, decisions taken, decisions open, rating research harness
  runbooks/       Durability measurement and kill test; running the iOS client
FOUNDATION_ACCEPTANCE.md   Gate 0 report
```

## Running the checks

```bash
python3 packages/domain-spec/generate.py --full && python3 packages/domain-spec/validate.py
gradle -p packages/engine check
gradle -p packages/statistics test
gradle -p packages/competition test
gradle -p packages/trust test
swift test --package-path packages/engine-swift   # needs a Swift toolchain
swift test --package-path packages/statistics-swift
swift test --package-path packages/client-ios      # macOS: design, journal and scoring-session tests
xcodebuild -project apps/ios/ThroDarts.xcodeproj -scheme ThroDarts \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
gradle -p packages/authz test
gradle -p packages/rating test
python3 packages/design-tokens/build.py --check
python3 docs/design/audit_components.py --check

# these need a PostgreSQL 16; set PGHOST, and PGPORT/PGUSER/PGDATABASE if not the defaults
export PGHOST=localhost
bash services/api/test/schema_properties.sh
gradle -p services/api test
```

The database-backed checks skip cleanly and say so when `PGHOST` is unset, rather than
passing silently.

## Playing a match

There is a playtest harness — the real engine and the real command path behind a browser,
so the competitive core can be played before the clients exist. It is **not the product**:
online only, no accounts, no rating, and it says so at the top of every screen.

```bash
PGHOST=localhost gradle -p services/api run
```

Then open `http://localhost:8080`. Enter a visit total the way a chalker would; the app asks
for darts at a double whenever the player **began** the visit on a finish, whether or not they
took it, and additionally for darts used on the visit that wins a leg. Leaving a prompt blank
records *unknown*, which is a different fact from zero — **Stats** in the header then shows the
figure as a range instead of a number.

## Design authority

The approved THRØ Design System is the visual and interaction authority for this build.
It is committed under `docs/design/extracted/` with a full provenance record in
[`docs/design/DESIGN_SOURCE_PROVENANCE.md`](docs/design/DESIGN_SOURCE_PROVENANCE.md).

**Read the design source before implementing any significant screen.** Do not implement
from memory, from screenshots, or from design instinct. Where a component and a design
token disagree, the token wins.

## Source precedence

A lower source may never silently override a higher one:

1. Explicit current founder decisions
2. Approved production decision / authority register
3. Approved THRØ Claude Design System
4. Current THRØ product / domain specifications
5. Founding dossier
6. Approved architectural decisions
7. Reference implementations / prototype code
8. Sample data

Sample player names, ratings, band labels and statistics inside the design export are
rank 8. They are fixtures and must never become product truth by implementation
convenience.

## Non-negotiables

These constraints shape the architecture and are not open to convenience:

- **THRØ never invents dart-level evidence.** A visit total of 100 does not tell you which
  three darts were thrown. Visit totals and dart-level evidence are distinct in domain,
  storage, API and UI.
- **Scoring is deterministic and shared.** The scoring engine is independent of UI,
  network and database, and must produce identical results on iOS, Android and server.
- **Offline-first is not a banner.** Venues have poor signal. Scoring continues without a
  network, on a durable local event journal, and survives process death and device restart.
- **The server validates competitive evidence.** A client cannot simply assert a result.
- **Competitive evidence is append-oriented and auditable.** Corrections create history;
  they never overwrite it.
- **Rating, Form, Rank and Confidence are four separate concepts** — in domain, API,
  storage and UI. The rating model is not yet decided and will not be chosen by
  implementation convenience.
- **Money is never floating point. Timestamps always carry timezone context.**

## Voice

THRØ speaks as a competition official: calm, specific, factual, British English. No emoji
in product UI. No hype. A player at any level is told where they are and what would help —
never that they are bad.

## What is enforced, and where

The competitive properties are not conventions. Each one is asserted by something that fails when it
is removed.

| Property | Enforced by |
|---|---|
| A visit total can be achieved with three darts | Engine, against a corpus derived from the dartboard |
| Two devices may both author one match | `UNIQUE (match_id, device_id, device_seq)` |
| Evidence is never edited or deleted | Append-only grants, including on tables added by later migrations |
| Evidence exists only for a real match | Foreign key to the match aggregate |
| Who is playing cannot be rewritten | No application role holds `UPDATE` on `evidence.match` |
| A module appends only to streams it owns | Trigger mapping each event type to its owning role |
| Authority is recorded, never used to destroy evidence | `authority` column; a revoked scorer's visit still writes |
| A revocation cannot be undone | Trigger on `trust.scoring_grant` and `identity.device` |
| An official cannot correct their own match | `Rule.Except` in the one decision point, before any handler |
| Every decision is on the record | Hash chain computed by the database, not the application |
| The audit log cannot be read by its writers | `REVOKE SELECT` from every appending role |
| One player's word never moves a rating | `EligibilityPolicy.minimumAttestation` (PD-002) |
| No unvalidated rating model can be published | `Publication.check`, plus a singleton table |
| A statistic that cannot be computed says so | `Basis.EXACT` / `BOUNDED` / `UNAVAILABLE` |
| Personal data lives in one place | `identity` schema; match, trust and rating cannot read it |
| Age is available at every decision | A parameter of `Authorizer.check`, not a lookup inside it |
| A visit is durable before it is shown | `MatchSession.submit`: engine decides, journal commits, then the state changes |
| The journal runs only under the configuration that was measured | `Journal.verifyInForce` reads every pragma back on open and refuses anything else |
| Scoring has no compile-time path to a network | The client package graph has no network target to depend on |
| A mis-keyed visit is corrected, never edited | A retraction row in the append-only journal supersedes it (PD-004); replay skips what it strikes and the struck row stays |

## What is deliberately not decided here

`docs/product/OPEN_DECISIONS.md` is the register. The two that shape the most code:

- **OD-001 — the rating model.** No model in this repository claims to be validated, and a test
  fails if one ever does. Every player is provisional and nothing is published.
- **OD-010 — safeguarding obligations.** The age *dimension* exists at every decision; no action
  carries an age requirement, because the thresholds are a legal question this repository does not
  answer.
