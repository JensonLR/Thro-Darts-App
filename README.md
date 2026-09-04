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
| 5 | Offline match lifecycle | **Blocked** — needs iOS and Android toolchains |
| 6 | Vertical slice | **Blocked** — needs the authentication surface (B4) |
| 7+ | Trust, rating, organiser, live | Not started |

**What is verified, and how:**

| | |
|---|---|
| Scoring rules | 395 property checks against independent darts facts |
| Scoring engine | 86,000 exhaustive transitions + 58 corpus cases |
| Statistics honesty | 14 tests — an uncomputable figure says so; an approximate one is never a point value |
| Competition structure | 13 tests — bracket identities exhaustive for every field size to 1024 |
| Event schema | 21 property assertions against a real PostgreSQL |
| Command path | 14 integrity properties, end to end against a real PostgreSQL |
| Design tokens | 50 contrast pairs, absolute thresholds, 0 unrecorded breaches |

**Nothing here is production ready**, and no claim of security, offline reliability or rating
validity is made anywhere in this repository. There is no client application, no HTTP layer and no deployment — the command path is a tested
handler, not a running service.
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
  design-tokens/  One token source generating Swift, Kotlin and CSS
services/
  api/            Migrations and event-model property tests
docs/
  adr/            15 architecture decision records
  architecture/   Conformance corpus spec, latency budgets
  design/         Design authority — provenance, inventory, contrast matrix,
                  token health, what the system does not specify
    extracted/    Token layer, 61 components, 33 participant + 9 organiser screens
  product/        Glossary, decisions taken, decisions open, rating research harness
FOUNDATION_ACCEPTANCE.md   Gate 0 report
```

## Running the checks

```bash
python3 packages/domain-spec/generate.py --full && python3 packages/domain-spec/validate.py
gradle -p packages/engine check
gradle -p packages/statistics test
gradle -p packages/competition test
gradle -p packages/trust test
python3 packages/design-tokens/build.py --check

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
