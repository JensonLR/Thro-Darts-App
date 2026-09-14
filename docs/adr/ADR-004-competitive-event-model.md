# ADR-004 — Competitive event model

**Status:** Accepted (revision 2) · **Date:** 2026-09-03
**Supersedes revision 1**, which was rejected by hostile architecture review. Revision 1's schema
**could not store the two-device corroboration case** that ADR-006 depends on; this was proved
against a live PostgreSQL 16 instance, not argued. See "What revision 1 got wrong" below.

The crown jewels. Everything else in the platform is derived from this, and it is the only decision
here whose cost of being wrong is measured in "every match ever recorded".

## Options considered

Revision 1 presented one design with no alternatives, which is where its rigour failed.

- **Full event sourcing with a per-aggregate stream** — one stream per match. Rejected: a match has
  **two independent authors**, so a single stream cannot represent corroboration (see below).
- **Per-(aggregate, device) streams, projected into read models** — chosen.
- **CRUD with an audit table** — rejected: corrections and disputes need the original evidence to
  remain first-class and independently readable, not reconstructable from a diff log.
- **Partial event sourcing** (events only for scoring, CRUD elsewhere) — rejected for the competitive
  core, accepted in effect elsewhere: identity, competition setup and payments are not event-sourced.
- **Logical decoding for projections** instead of polling — **partially adopted**, see ordering.

## Decision — schema contract

```sql
CREATE TABLE evidence.event (
  event_id        uuid PRIMARY KEY,          -- UUIDv7, writer-generated
  match_id        uuid NOT NULL,             -- the aggregate
  device_id       uuid NOT NULL,             -- the author
  device_seq      bigint NOT NULL,           -- gapless, per (match_id, device_id)
  commit_xid      xid8 NOT NULL DEFAULT pg_current_xact_id(),
  global_seq      bigint GENERATED ALWAYS AS IDENTITY,
  event_type      text NOT NULL,
  schema_version  int  NOT NULL,
  rules_version   text,
  engine_version  text,
  correlation_id  uuid NOT NULL,             -- survives device -> server -> traces
  actor_id        uuid NOT NULL,
  actor_role      text NOT NULL,
  occurred_at     timestamptz NOT NULL,      -- device clock: EVIDENCE ONLY
  occurred_tz     text NOT NULL,             -- IANA zone id
  received_at     timestamptz NOT NULL DEFAULT clock_timestamp(),  -- arrival, NOT order
  corrects_event_id uuid REFERENCES evidence.event,
  payload         jsonb NOT NULL,
  UNIQUE (match_id, device_id, device_seq)
);
CREATE INDEX ON evidence.event (commit_xid);
```

### 1 — Two authors, two streams. This is the correction.

A match has **two independent accounts of what happened**, and the difference between them is the
product's most important signal. The uniqueness key is therefore
`(match_id, device_id, device_seq)`, so each device writes its own gapless sequence and neither can
collide with the other. `device_seq` is also what ADR-006's gap check compares against — revision 1
had no column for it.

**Verified:** under revision 1's `UNIQUE (stream_id, stream_seq)`, a second device syncing its own
stream for the same match is rejected outright —
`duplicate key … Key (stream_id, stream_seq)=(match:X, 1) already exists`. The mechanism that
produces corroboration was rejected by the concurrency control.

Per-device uniqueness still gives compare-and-swap on append: a writer inserts at its expected next
`device_seq` and a conflict means it must re-read.

### 2 — One ordering authority, stated once

Revision 1 named three, which is worse than naming none.

- **Within a device:** `device_seq`. Total, gapless, authoritative.
- **Across devices:** `(commit_xid, global_seq)`. This is a **composite**, not a scalar.
- **`received_at` is arrival evidence, never order.** It is assigned at statement time, so ordering
  by it carries exactly the hazard described next.
- **`occurred_at` is the device's claim.** Evidence, never order. A wrong clock is not a cheating
  signal and must never reject an event.

### 3 — The projection watermark, and its operational cost

`global_seq` is assigned at insert, not at commit, so a reader polling above a high-water mark
**silently skips** events from transactions that started earlier and committed later. Revision 1
identified this correctly and then prescribed a mitigation that its own schema could not evaluate —
there was no column relating a row to its transaction. Hence `commit_xid`.

**But the mitigation has a cost revision 1 did not state, and it is serious.** Consuming only below
`pg_snapshot_xmin(pg_current_snapshot())` means **any long-running write transaction anywhere in the
database stalls every projector and the realtime dispatcher** — silently, with no error.

**Verified:** with a six-second bulk write open, a live scoring visit that had already committed and
was visible in the table showed **0 rows safe to dispatch**; it became dispatchable only once the
unrelated bulk writer committed.

This matters because ADR-009 mandates building the rating harness during the slice, and the harness
ingests historical archives — a long bulk write. Under this rule that ingest freezes the live
scoreboard for its duration. Three consequences follow, all now required:

- **Harness and bulk-ingest writes run against a separate database**, not merely a replica (replicas
  cannot take writes). ADR-003 is amended accordingly.
- **Every writer role carries `statement_timeout` and `idle_in_transaction_session_timeout`**, so an
  unbounded transaction cannot exist.
- **Watermark lag is an instrumented, alerted metric.** It is the failure that is otherwise invisible.

**Preferred alternative where available:** logical decoding delivers in commit order by construction
and sidesteps the whole problem. It is the right long-term answer for the projector; the watermark
rule is the interim, and its cost is now on the record rather than discovered in production.

### 4 — Append-only is a grant *plus ownership*, and the CI gate must attack it

Revision 1 said "revoke UPDATE and DELETE, and CI asserts the grant". Both halves were wrong.

**Verified:** revoking UPDATE and DELETE does **not** protect a table created afterwards. A table
added by a later migration, granted the module's normal privileges, was freely mutable — an UPDATE
changed a recorded visit total from 180 to 1. Since `evidence.visit` and `evidence.dart` are in this
very schema contract and will be created by a later migration, revision 1's control would not have
covered the tables that matter most.

Required, in full:

```sql
REVOKE UPDATE, DELETE, TRUNCATE ON ALL TABLES IN SCHEMA evidence FROM app_match;
ALTER DEFAULT PRIVILEGES IN SCHEMA evidence
  REVOKE UPDATE, DELETE, TRUNCATE ON TABLES FROM app_match;
```

- **`TRUNCATE` is a separate privilege** and must be named. It is additionally reachable by a table's
  **owner** regardless of grants, so **migrations run as an owner role the application never holds**,
  and the application role owns nothing.
- **The CI gate must attempt an UPDATE, a DELETE and a TRUNCATE as the application role and assert
  all three fail** — on a table created *by a migration*, not only on one created by the test.
  Asserting privilege metadata is a different test, and it passes in exactly the cases that are
  broken.

### 5 — Evidence and projections are different things

Revision 1 placed `evidence.visit(… bust, checkout, remaining_after)` inside the append-only schema.
That is **derived engine output**: it cannot be updated when a visit is corrected, cannot be marked
superseded, and yet revision 1 also required read models to be rebuildable by truncation. It cannot
be both immutable evidence and a rebuildable projection.

- `evidence.event` — immutable, append-only, the source of truth.
- `read.visit`, `read.leg`, `read.match` — projections, in a separate schema, written only by
  projectors, freely rebuildable, carrying a `projection_version`.

### 6 — Visit totals and dart-level evidence stay structurally distinct

Dart-level facts live in the event payload as **optional and explicitly nullable**. Absence means
**unknown** — never zero, never inferred.

`darts_used` exists in schema v1 whether or not the first release prompts for it. **Revision 1 gave
the wrong reason** for this and wrong reasons get cited later: a nullable column with nothing in it
produces exactly the same unknown cohort as no column. What the column actually buys is **the absence
of a migration**, and the ability to switch capture on per release without one. The cohort is created
by not capturing, not by not having the column.

**CI gate:** run the full statistics and rating suite against a corpus with zero dart-level data and
assert every dart-level metric returns unavailable rather than a number.

## Provenance, trust and outcome

The verification label is **derived, never stored** — the design proves the labels are compositions
(`thro-verified` = recorded in THRØ **and** organiser-confirmed). Store the composite: capture
channel, entering actor, each confirming actor with time and role, competition and board context,
organiser authority with the named individual, device and connectivity, submission and occurrence
times, corrections, and integrity signals.

**Confirmation attaches to the leg**, per participant. **Outcome type is first-class** (`played`,
`walkover`, `forfeit`, `retired`, `awarded`, `void`, `replayed`).

## How this keeps B1 and B2 open

- **B1** — `darts_used` is nullable from v1; statistics cross the API as
  `{value, basis, evidenceLevel, sampleSize}`. **Schema-wise this is genuinely open.**
- **B2** — eligibility is an orthogonal axis with a configurable rule. **Schema-wise open; but see
  the honest caveat**: the stricter answer additionally requires a participant attestation surface
  that does not exist in the approved design and had not been commissioned. That is a design and
  client-release dependency, not a migration, and it is now tracked as a design commission.

## Revisit trigger

Watermark lag exceeding its alert threshold under normal load (which would move the projector to
logical decoding); or the event table beyond ~200M rows, which at realistic volume is many years away
— so this trigger is a scale marker, not an expected event.
