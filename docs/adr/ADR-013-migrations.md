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

## Amendments — 2026-09-09

Written after the connected-platform build (V014–V021) had run into three things this record
described and nothing enforced.

**1. The mechanism has a name.** Applying is done by a ledger runner — `Migrations.kt` in the API
service, and the same logic in bash at the top of `services/api/test/schema_properties.sh` — which
keeps `thro.schema_migration (version, filename, sha256, applied_at)`. Every file the ledger does
not hold is applied in its own transaction together with its ledger row; a file that fails leaves
neither. Three databases are refused rather than guessed at: one with THRØ's schemas and no ledger
(migrated before the ledger existed; its version cannot be known, so it is rebuilt); one whose
recorded file has different content on disk (migrations are forward-only, so an edit to an applied
one is a new migration or a rebuild); one recording a version this checkout has no file for (the
database is ahead of the code). The application roles hold nothing on the ledger. Until this
existed every runner applied migrations only when the `evidence` schema was absent, so a database
behind the code sat silently behind it — after V018 it could not open a match at all.

**2. The discipline is enforced.** `tools/check_migrations.py` runs first in the `schema` workflow
and fails on: a file that does not run as `thro_owner` from its first owned statement to `RESET
ROLE`; a `DROP`, `TRUNCATE` or column type change without an `-- APPROVED-DESTRUCTIVE: <reason>`
line in the file; `UPDATE` or `DELETE` against `evidence` without the marker in §3; a file name
the ledger cannot parse; versions that are not unique and contiguous. A marker with no reason fails
too. The narrowing-`ALTER TYPE` rule is held as "any column type change needs a marker", because a
script cannot tell narrowing from widening and the reviewer can. The digest is over the file's
bytes, comments included, so adding a marker to an applied file changes its digest and the ledger
refuses the database until it is rebuilt: before the first deployment that is the intended cost of
editing an applied file at all, and the markers on V014, V018 and V020 were added in one commit for
that reason.

**3. The one permitted rewrite of evidence: removing personal data.** The rule stands — evidence
is never rewritten, a change of shape is a read-time upcast — with one exception the data-protection
promise forces: when the thing that must change *is personal data that must cease to be stored*
(rectification or erasure under UK GDPR; ADR-011's pseudonymisation gate), a read-time upcast cannot
do it, because the data would still be there. Such a migration is permitted when it (a) replaces a
personal value with a label that carries none, (b) changes no competitive fact — no score, sequence,
seat, actor or row count, (c) refuses to run if any row would be left carrying the data or would
have to be guessed at, (d) is performed once by the owner role, and (e) carries
`-- APPROVED-EVIDENCE-REWRITE (pseudonymisation|erasure): <reason>` and a test that populates the
old shape and reads every row back. V018 (display names in visit payloads become the seat they
labelled) is the first and the model.

**4. Expand-then-contract before the first deployment.** "Each a separate deployment" presumes a
running image to stay compatible with. Until THRØ's first production deployment there is none and
there is no production data, so V014, V018 and V020 expand and contract in one file, each marked
and each held by `MigrationTest` over a populated earlier schema. From the first deployment the
rule applies as written.

**5. Recorded as not yet built.** The frozen payload corpus and read-time upcast chain this record
requires do not exist, because no event type has yet had a second `schema_version`. The first
migration or code change that introduces one must bring the corpus with it; this line is here so
that the omission is a known debt rather than a discovery.

