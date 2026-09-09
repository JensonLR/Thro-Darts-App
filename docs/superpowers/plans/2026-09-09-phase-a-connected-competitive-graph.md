# Phase A — Connected Competitive Graph: task record

> **For agentic workers:** this plan was executed inline in the session that wrote it. Steps use
> checkbox syntax; every box below is ticked because the step ran and its check passed. The
> authoritative statement of scope and acceptance is
> `docs/product/CONNECTED_PLATFORM_EXECUTION_PLAN.md` §3, §4 and §12; this file is the task-level
> record the writing-plans discipline asks for.

**Goal:** Make the repository's organisational vocabulary canonical — Team, Venue, League,
LeagueSeason, Tournament, Event, Series, Membership, Registration, Affiliation, Policy — so the next
fifty features are not built on a misnamed bracket tie, a free-text venue and an untyped entrant.

**Architecture:** One forward-only migration (V014) over the existing `competition`, `identity` and
`authz` schemas; pure Kotlin types in `packages/competition`; a store-side API in `services/api`;
tests at three levels (pure, database, migration-over-populated-database).

**Tech stack:** PostgreSQL 16 (btree_gist), Kotlin 2.0 / JUnit 5, psql shell properties.

## Global constraints

- `Club` is not an entity (founder instruction PD-003). Team is the organisation; Venue is the place.
- No history is deleted: dated relationships are closed once and frozen; no app role holds DELETE.
- Migrations are forward-only and lose nothing; `MigrationTest` proves it over populated V013 data.
- No personal data outside `identity` (ADR-005); `competition.player` carries no free text.
- Never weaken a test to make a build green. Never invent product behaviour to fill a screen.

---

### Task 1: Semantic audit and execution plan
- [x] Read every migration, ADR, domain package and design reference to Club/Team/Venue/League/Tournament.
- [x] Record the ten terminology conflicts (plan §2) and the current state (plan §1).
- [x] Write `docs/product/CONNECTED_PLATFORM_EXECUTION_PLAN.md`.

### Task 2: Hostile review before implementation
- [x] Dispatch a read-only critic over plan §3/§4 with the founder's constraints.
- [x] Accept: claim table instead of FK update; policy exclusion + typed authority + freeze; append-only fixture outcomes; `league_fixture` naming; composite FK entry typing + generated competitor id; drop the `season` alias; revoked-not-deleted relations; frozen closed rows; non-overlapping home tenures; team name history; consent basis.
- [x] Defer with written reasons: names in `evidence.match` (OD-015); player merge alias (Phase B).

### Task 3: ADR-016 and decision registers
- [x] Write `docs/adr/ADR-016-organisational-vocabulary.md`; index it in `docs/adr/README.md`.
- [x] Record PD-003 and PD-004 in `docs/product/DECISIONS.md`; OD-015 in `OPEN_DECISIONS.md`.

### Task 4: Migration V014
**Files:** `services/api/migrations/V014__organisations.sql`
- [x] Write the migration (plan §4 lists every step).
- [x] Apply over a populated V013 database via `MigrationTest`; fix the after-insert ordering of the team-name trigger and the generated-column comparison in the policy trigger, both found by tests.

### Task 5: Pure domain types
**Files:** `packages/competition/src/main/kotlin/thro/competition/Organisation.kt`,
`packages/competition/src/test/kotlin/thro/competition/OrganisationTest.kt`
- [x] `Period`, `Team`, `Venue`, `Tenure`, `Membership`, `League`, `LeagueSeason`, `Affiliation`, `Registration`, `Tournament`, `Event`, sealed `Entrant`, `Entry`, `Series`, `SeriesSeason`, sealed `Competition`, `TeamHistory`, `Eligibility`.
- [x] Eleven tests; run `gradle -p packages/competition test` → green.

### Task 6: Store-side API and database tests
**Files:** `services/api/src/main/kotlin/thro/api/Organisations.kt`, `Competitions.kt`, `Relations.kt`,
`packages/authz/.../Model.kt`, tests `OrganisationTest.kt`, `MigrationTest.kt`, `CompetitionTest.kt`, `TestDatabase.kt`
- [x] `Competitions.draw` → `bracket_tie`; `enter(Entrant)`; `checkIn` records the player present.
- [x] `Relations.revoke` is an UPDATE; tuple source reads live tuples only; `ObjectType.LEAGUE_SEASON`, `TOURNAMENT`, `SERIES`, `SERIES_SEASON`.
- [x] `TestDatabase.migratedUpTo` / `apply` for the migration test.
- [x] Run `gradle -p services/api test` → green (11 suites).

### Task 7: Schema properties
**Files:** `services/api/test/schema_properties.sh`
- [x] Add the organisational section (13 properties) and the stale-schema sentinel.
- [x] Run → 85 passed, 0 failed.

### Task 8: Documentation
- [x] GLOSSARY competition section rewritten; README layout, gates and tables; package READMEs; DESIGN_UNSPECIFIED item 26.

### Task 9: Commit
- [x] One commit per coherent change set, messages in the repository's voice.
