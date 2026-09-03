# ADR-005 — Module boundaries and data ownership

**Status:** Accepted · **Date:** 2026-09-03

## Decision

**A modular monolith: one deployable, one database, module-owned schemas, no cross-module table
access.**

Microservices are rejected for the reason the brief anticipates: a service split is an
*organisational* solution to a coordination problem a one-person team does not have. It would buy
independent deployment and scaling we do not need, in exchange for distributed transactions, N
pipelines, N observability setups, and the loss of the single transaction ADR-004 depends on.

## Modules and ownership

| Module | Owns |
|---|---|
| **identity** | Accounts, credentials, devices, consent, display names — **all personal data** |
| **competition** | Venues, boards, teams, leagues, divisions, seasons, fixtures, events, entries, check-in, draws, brackets |
| **match** | The match aggregate and its evidence streams. **The only module that may append to the evidence log.** |
| **trust** | Evidence states, per-leg confirmations, disputes, adjudications, quarantine |
| **rating** | Rating, form, rank, confidence, model versions, snapshots. **Pure downstream consumer** |
| **live** | Subscriptions, board state, match queue, calling, presence |
| **notifications** | Device tokens, preferences, delivery log |
| **payments** | Entry fees, refunds, payout state |

Confining all personal data to one module is what makes the design's export and deletion promises
tractable, and it is why `identity` is a module rather than a table.

`rating` never writes to `match` or `trust`. That one-way dependency is what makes it safely
re-runnable, which ADR-009 requires.

## The rules that make it modular rather than aspirational

- Each module splits into `api` (interfaces and data transfer types) and `impl`. Only `api` is on
  other modules' compile classpath, so **the build graph enforces the boundary** — neither a human
  nor an agent can import another module's internals by accident.
- **No cross-schema joins.** Cross-module reads go through the owner's interface or a read model the
  owner explicitly publishes. The organiser entry list showing paid status is exactly this: it renders
  a projection published by `payments`, not a join into its tables.
- **Cross-module writes are events**, consumed asynchronously. Synchronous calls are permitted only
  where a user is waiting.

Dispute resolution demonstrates the pattern end to end: `trust` appends a resolution event,
`competition` reacts by advancing or retracting the bracket, `notifications` reacts by informing both
players, and the "Undo" the design offers becomes a compensating event rather than a delete.

## The argument against, and the phasing it forces

Eight modules with interface splits is real ceremony that a solo founder will resent, and for several
modules it is premature. So it is phased honestly:

- **From the first commit:** schema ownership and the no-cross-schema-join rule (nearly free, and the
  part that genuinely cannot be retrofitted), plus **compile-time walls for `match`, `trust` and
  `rating`** — the three where a boundary violation would be unrecoverable.
- **Later:** the remaining modules start as packages and graduate to separate projects when they earn
  it.

## What would justify extracting a service

**Precondition: more than one engineer.** Below that a split is a net loss. Then: `live` if
concurrent connections outgrow one process or fan-out affects scoring latency; `rating` if research
backfills contend with production; `payments` only to narrow a compliance audit boundary, never for
scale.

**Explicit anti-triggers:** "the match module is getting big"; "we want another language for rating";
"microservices are best practice"; a single slow endpoint.

## Revisit trigger

The extraction conditions above, or a second engineer joining — at which point the phasing schedule
should be revisited rather than the architecture.
