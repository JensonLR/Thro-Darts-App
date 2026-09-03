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

This repository is at **Gate 0: foundation ingestion**. There is no product code yet, and
that is deliberate. The build follows a gated process in which foundations are established
and challenged before features are written.

| | |
|---|---|
| Repository at session start | Empty — no branches, no commits, no prior code. Greenfield. |
| Design authority | Recovered and committed — see `docs/design/` |
| Architecture | Not yet decided — Gate 1 |
| Product code | None yet |

**Nothing in this repository should be described as production ready.** Claims of
readiness, test coverage, security, offline reliability or rating validity are only made
where evidence exists to support them.

## Repository layout

```
docs/
  adr/           Architecture decision records
  architecture/   Conformance corpus spec, latency budgets
  design/         Design authority — provenance, inventory, contrast matrix,
                  token health, what the system does not specify
    extracted/    Token layer, 61 components, 33 participant + 9 organiser screens
  product/        Glossary, open decisions, rating research harness
FOUNDATION_ACCEPTANCE.md   Gate 0 report
```

`docs/runbooks/` will appear when there is something to operate.

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
