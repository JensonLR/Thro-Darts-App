# ADR-013 — Migrations and schema evolution

**Status:** Accepted · **Date:** 2026-09-03

## Context

ADR-004 makes the competitive event log append-only and enforces it with grants. Nothing said how
the schema changes, and that omission is dangerous in a specific way: **every migration runs with
privileges the append-only control is designed to withhold**, and a migration is the one moment the
protection is off.

Hostile review verified that the control as originally specified did not cover tables created by
later migrations — including `visit` and `dart`, which are in the schema contract itself.

## Decision

**Versioned, forward-only SQL migrations, applied by a dedicated owner role the application never
holds, run as a deploy step rather than on application boot.**

### Roles

| Role | Owns | May |
|---|---|---|
| `thro_owner` | every schema and table | run DDL; not used by the application, ever |
| `app_<module>` | nothing | `SELECT`/`INSERT` per module; **no** `UPDATE`/`DELETE`/`TRUNCATE` on evidence |

Ownership matters independently of grants: a table's owner can `TRUNCATE` it regardless of what has
been revoked. Separating the roles is what makes the append-only claim true rather than aspirational.

### Discipline

- **Forward-only, expand then contract.** Add the new column, backfill, dual-write, switch reads,
  then drop — each a separate deployment. No migration both adds and removes in one step.
- **Every migration is applied to a restored copy of the previous production schema in CI**, not to
  an empty database. A migration that only works on a fresh schema is not tested.
- **Destructive statements require an explicit approval marker in the file**, and CI fails on an
  unmarked `DROP`, `TRUNCATE` or narrowing `ALTER TYPE`.
- **Deploy order is migration-first**, with migrations required to be backward-compatible with the
  currently-running image. That is what makes a rollback of the image safe without a rollback of the
  schema — which forward-only migrations cannot offer.

### The `evidence` schema is special

- New tables in `evidence` inherit the revocations automatically via `ALTER DEFAULT PRIVILEGES`
  (ADR-004), so a forgotten grant cannot create a mutable evidence table.
- **A migration may never `UPDATE` or `DELETE` rows in `evidence`.** If data must change shape, the
  change is expressed as an upcast at read time, not a rewrite of history. CI greps migrations for
  DML against `evidence` and fails.

### Payload evolution — the upcast chain

`jsonb` payloads are schemaless, so the database cannot reject a malformed event. The defence is an
explicit chain, and it needs an owner and a test or it decays:

- Every event carries `schema_version`. **Owned by the module that owns the stream.**
- Upcasting is **read-time**, never a rewrite: `v1 → v2 → v3`, each step pure and total.
- **CI holds a frozen corpus of one real payload per (event type, version) ever emitted** and asserts
  each upcasts to the current version and round-trips. A version that has ever been written must
  remain readable forever, because its rows are immutable.

## Consequences

- Deployment is two steps, not one. Accepted: the alternative is migrating with application
  privileges, which would undo ADR-004's central control.
- Backfills of large tables are long transactions, which ADR-004 shows stall projectors. Backfills
  are therefore **batched with an explicit bound**, never a single statement.

## Revisit trigger

The first migration that cannot be expressed forward-only without downtime — at which point the
expand/contract discipline needs a documented exception process rather than an ad-hoc one.
