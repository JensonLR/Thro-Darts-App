# THRØ — Connected Platform Execution Plan

**Date:** 2026-09-09 · **Status:** Phases A, B2, D, E's read model and C's store (availability, lineups, the result-card gate) delivered; B3 and C's surface wait on FB-1, E's surface and F on the client · **Precedence:** rank 4 (product/domain
specification), below the founder's instructions and the decision register, above the ADRs it cites.

This plan reconciles the repository as it stands with the founder's product conclusions for the
connected platform: Team → Venue → League → Tournament → Series → Fixture → Match → Result →
Evidence. It is written so that a contributor with no other context can tell what exists, what is
wrong, what changes, in what order, and what "done" means mechanically.

It is **not** a feature brainstorm and it does not redesign THRØ. Every ADR remains in force unless
this document names an amendment.

---

## 1. Current state — what actually exists

The repository is a **modular-monolith foundation, not a product**. Verified by reading every
migration, every Kotlin domain package and every ADR, and by running the whole suite on this Mac
against a local PostgreSQL 16 (71 schema properties and every Gradle suite green, 2026-09-09).

| Layer | What exists | What does not |
|---|---|---|
| **Database** | Eight schemas: `evidence` (append-only event log, match aggregate), `trust` (grants, attestations, disputes, quarantine), `rating` (snapshots, singleton published model), `read`, `audit` (hash-chained), `authz` (relation tuples), `identity` (account, device, age band), `competition` (event, entry, check-in, board, and a table called `fixture`) | Team, Venue, League, League season, Division, Membership, Registration, Affiliation, Tournament identity, Series, any policy table, any external identity |
| **Domain (Kotlin)** | `engine` (scoring, 86k exhaustive transitions), `statistics`, `competition` (`Competitor = Player \| Pair \| Team`, `Slot`, bracket maths, standings with declared tie-breaks, `FixtureOutcome`), `trust`, `authz` (relationship algebra with `Except`), `rating` (replayable projection) | Any organisational aggregate. `Competitor.Team(id, players)` is a **match-time lineup**, not a persistent organisation |
| **Command path** | One tested handler: idempotent receipt, gap check, rehydrate, engine revalidation, append and receipt in one transaction; two-device corroboration proved against Postgres | **No HTTP layer.** `PlaytestServer` is a browser harness, not an API |
| **Clients** | Swift engine port (same corpus, zero divergences); an iOS durability probe measured on a physical iPhone (P95 1.6 ms, kill test passed) | **No iOS application, no Android application, no on-device journal, no deep links, no widgets, no Spotlight, no MapKit.** Gate 5's on-device journal is blocked on the SE-class and Android measurements |
| **Authentication** | Mechanism decided (ADR-008): passkeys primary, per-request relationship authorization, device binding, offline grants | **No surface** (blocker B4), no account creation, no session, no claim flow |
| **Design** | 61 components, 42 screens, token pipeline, contrast and component audits | No auth screens, no team-management screens beyond an organiser roster panel, no participant attestation surface |

Consequence for this plan: the founder's brief assumes an iOS client with stored device data and a
`Club` type. **Neither exists.** Phase A is therefore server-and-domain work with no device-storage
migration, and the "rename" is a vocabulary correction, not a refactor.

## 2. Terminology conflicts

Each conflict is stated with where it lives and what it actually means. `Club` first, because the
founder asked.

| # | Where | What it says | What it actually is | Resolution |
|---|---|---|---|---|
| C1 | `docs/design/extracted/**` (7 occurrences) | "Riverside Club", "Boro Legion Club" as venue names; "Your club affiliation" in settings copy; "Club protection · First round only" in draw setup | (a) proper nouns of **Venues**; (b) a synonym for **Team** affiliation; (c) a **draw policy** that keeps players of the same Team apart in round one | ADR-017: `Club` is never an entity. (a) stays as user-authored names; (b) is Team; (c) becomes a versioned competition policy named *team separation* |
| C2 | `competition.fixture` (V013), `Competitions.draw`, `CompetitionTest` | "fixture" | A **knockout bracket tie**: `round_number`, `position`, `is_bye`. GLOSSARY and ADR-012 define Fixture as a league scheduled meeting and say "Not a slot" | Rename to `competition.bracket_tie`; introduce `competition.fixture` with the league lifecycle |
| C3 | `competition.event.venue text` | free-text venue | A Venue is meant to be an entity (`authz` has `VENUE`; ADR-005 gives `competition` ownership of venues) | Add `competition.venue`, `event.venue_id`; keep the text as `venue_label` until every writer sends an id |
| C4 | `competition.event` | "event" | A **TournamentEdition** — one occurrence with entries, check-in and draw. No persistent Tournament identity, no Series | Add `competition.tournament` (persistent, optional) and `event.tournament_id`; add Series tables |
| C5 | `thro.competition.Competitor.Team` | "Team" | The **lineup** a Team fields in one match | Keep as the match-time competitor; the organisation is `competition.team`. The ADR names both and the difference |
| C6 | `competition.entry.competitor_id uuid` | untyped | Entrant kind (player, pair, team) is unrecoverable from the row | Add `entrant_kind` and typed references with a CHECK; add `competition.pair` |
| C7 | `authz.relation.object_type` CHECK, `ObjectType` | `SEASON`, no `TOURNAMENT`, no `SERIES` | `SEASON` is ambiguous between a league season and a series season | Add `league_season`, `series`, `series_season`, `tournament`; `season` stays as an alias until Phase C removes it |
| C8 | `docs/product/GLOSSARY.md` | "Fixture" defined twice; "Competition = a tournament, a league season, or a division" | Series is missing; Team/Venue/Membership/Registration are undefined | Rewrite the Competition section |
| C9 | `docs/adr/ADR-005`, `README.md` | `competition` "owns venues, boards, teams, leagues, divisions, seasons" | Only events, entries, check-in, boards and bracket ties exist | README states what exists; ADR-005 stands as the target ownership |
| C10 | `docs/design/.../screens-account.jsx` | "Team and venue · Your club affiliation" | Team affiliation | Copy is rank 3 design; noted in DESIGN_UNSPECIFIED as a term to correct at implementation, not a domain concept |

### 2b. The client's `Club`, found on merge (2026-09-09)

While this plan was being executed, a parallel session working from the founder's **7 September**
brief built an iOS client (`packages/client-ios`, `apps/ios`) and a Kotlin `packages/organisation`
around a standing **club** — one type with a kind (`club`, `league`, `tournament`) — plus a league's
own **team** rows (PD-009, PD-010, PD-019). That is the two-concept model the **9 September**
instruction forbids, and the newer instruction wins (source precedence, rank 1). The correction is
recorded as PD-028, amending those decisions rather than erasing them.

What each of theirs actually is, and what it becomes:

| # | Theirs | What it actually is | Canonical |
|---|---|---|---|
| C11 | `club` row, `kind='club'` | the standing competitive organisation with a roster, badge, colour and fixtures | **Team** |
| C12 | `club` row, `kind='league'` | a league with its table rules (unit, points, groups) — league and season not yet distinguished | League + LeagueSeason |
| C13 | `club` row, `kind='tournament'` with a shape | one edition of a tournament | Event (of a Tournament) |
| C14 | `club_team` row under a league | a side the league fields in its fixtures — an organisation in its own right, named by the league admin | **Team**, affiliated to the league season |
| C15 | `club_member` | a person's dated place in the organisation | Team membership |
| C16 | `club_fixture` with home/away team ids | a league fixture | League fixture |
| C17 | `fixture_result` with `source` | an outcome with provenance (PD-020) | League fixture outcome |
| C18 | `person` (ADR-016) | a player on this device, claimable later | Player + claim |
| C19 | copy: "Club", "Clubs you keep", "Start a club", "Club TV mode" | the team; the venue's television | "Team", "Teams you keep", "Start a team", "Venue TV mode" |

**Minimum safe client migration — delivered** (`ClubBook.migrate`, deterministic, additive, no row lost, four book tests):
`kind='club'` rows are normalised to `kind='team'` in place — a vocabulary token, not data; every
`club_team` row gains a `club` row of kind `team` with the **same identifier**, so every fixture's
`home_team_id`/`away_team_id` keeps its meaning and the `club_team` table becomes the league's
affiliation list; `OrgKind` reads the legacy token and writes the new one; the `thro://club/<id>`
deep link and the Spotlight domain keep resolving. A league's "Feathers A" and a standing "The
Feathers" are **two Teams until a person links them** — never merged on the name.

## 3. Target domain

The canonical vocabulary (ADR-017), as V014 builds it. Every table is in the `competition` schema
unless stated. Every relationship that changes over time carries `valid_from`/`valid_until`, is
frozen once closed, and is never deleted. Hostile review before implementation changed this section
in seven places; each is marked †.

```
PLAYER            player (no personal data, no free text)            one sporting identity; may be unclaimed
CLAIM †           identity.player_claim (player, account, method, confirmed_by, claimed_at, revoked_at)
                                                                    appended and revocable — never a repointed key
TEAM              team (+ team_name history †, dissolved_at †, row_version)
VENUE             venue                                             the physical place; hosts many teams
TEAM VENUE TENURE team_venue_tenure (team, venue, kind, period)     home periods never overlap †
TEAM MEMBERSHIP   team_membership (player, team, role, status, period)
LEAGUE            league
LEAGUE SEASON     league_season (league, label, dates, registration_kind †, standings_policy_id †)
DIVISION          division (league_season, name, ordinal)
TEAM AFFILIATION  team_affiliation (team, league_season, division?, status, period)
PLAYER REGISTRATION player_registration (player, league_season, kind, team?, status, policy, supersedes †, period)
                                                                    DISTINCT from membership; overlap refused unless a policy permits
TOURNAMENT        tournament                                        persistent identity of a recurring open
EVENT (edition)   event (tournament?, venue?, entrant_kind, access, starts, session_ends, state)
PAIR              pair (player_a < player_b)
ENTRY             entry (event, entrant_kind FK→event kind †, player|pair|team, competitor_id GENERATED †)
BRACKET TIE       bracket_tie (event, round, position, home, away, is_bye, board, match)
LEAGUE FIXTURE †  league_fixture (season, division?, home, away, scheduled_at, venue copied, schedule_state, match?, row_version)
                  league_fixture_change (append-only, by trigger)
                  league_fixture_outcome (append-only decisions: played|awarded|walkover|void, actor, time, policy, supersedes)
SERIES            series · series_season · series_event (season, event, ordinal)
POLICY            policy (typed authority FK †, kind, version, effective period, provenance, approval, body)
                                                                    approved versions never overlap †; frozen once approved
AUTHZ             authz.relation gains revoked_at/revoked_by †; `season` → `league_season`; + tournament, series, series_season
MATCH             evidence.match — unchanged; a fixture or bracket tie points at it, never the reverse
```

Rules the graph enforces, each with a test in §12:

- **A Team's identity is its row; its Venue is a tenure.** Moving venue closes one tenure and opens
  another. The team row is untouched. A rename keeps the old name and its period.
- **One Venue, many Teams.** No uniqueness on venue.
- **Membership ≠ registration.** No shared key. A registration names the team it was made for and
  outlives the membership; a transfer supersedes rather than edits.
- **LeagueSeason ≠ League.** Policies, affiliations, registrations and fixtures attach to seasons.
- **Tournament ≠ League.** No event, entry, check-in or bracket tie references a league season; no
  league fixture, affiliation or registration references an event. Asserted from
  `information_schema`.
- **Series contains events, never fixtures.** No standings table lives in `competition`.
- **Entrant is typed.** Exactly one of player, pair, team; its kind is the event's kind by foreign
  key; the resolved competitor id is generated and cannot disagree.
- **Policy is data with provenance and approval.** Typed authority, unique version, no overlapping
  approved periods, frozen once approved, state moves forward only.
- **Fixture outcomes are decisions, not columns.** Appended with actor, time and policy; a later
  decision supersedes and the earlier one stays. Schedule changes are logged with the original date.
- **Authorization relations are revoked, never deleted.**

## 4. Safe migration — V014, as executed

There is no production data and no device data ("THRØ has never run"), stated in the migration. It
is still written and tested as if there were: `MigrationTest` migrates to V013, populates an event
with a free-text venue, five bare-identifier entries, a draw with byes, a check-in with its grant
and an authorization tuple, applies V014, and reads every row back (14 properties).

1. `CREATE EXTENSION btree_gist` as the connecting user (a trusted extension; the owner role holds
   no CREATE on the database), for the exclusion constraints on tenure, registration and policy.
2. Create `venue`, `team`, `team_name`, `team_venue_tenure`, `player`, `identity.player_claim`,
   `team_membership`, `league`, `league_season`, `division`, `tournament`, `series`, `series_season`,
   `policy`, `team_affiliation`, `player_registration`, `pair`, `league_fixture`,
   `league_fixture_change`, `league_fixture_outcome`, `series_event`.
3. `identity.account` gains `created_via` and `consent_basis` (PD-029).
4. `event`: rename `venue` → `venue_label`; add `venue_id`, `tournament_id`, `entrant_kind`
   (default `player`), `access` (default `open`); `UNIQUE (event_id, entrant_kind)` so entries can
   reference the kind.
5. `entry`: add `entrant_kind`, `player_id`, `pair_id`, `team_id`; create a `legacy` player row per
   existing bare `competitor_id`; backfill `player_id`; **drop and re-add `competitor_id` as a
   generated column** over the typed columns; re-add the uniqueness and seed index; add the
   exactly-one CHECK and the composite FK onto the event's kind.
6. `check_in` gains `player_id` (the person present), backfilled where the competitor is a player.
   Making it the key and the grant actor is V015's expand-then-contract.
7. `ALTER TABLE competition.fixture RENAME TO bracket_tie`, with its constraints and index renamed.
   The league concept is `league_fixture`, a different name on purpose (ADR-017).
8. `authz.relation`: replace `season` with `league_season` in the CHECK (zero rows existed); add
   `tournament`, `series`, `series_season`; add the same CHECK to `hierarchy`; surrogate primary
   key, `revoked_at`/`revoked_by`, partial uniqueness over live tuples, revocation trigger; DELETE
   revoked from the competition role.
9. Triggers: team name history and row-version; closed relationships frozen and parties fixed;
   status moves forward only; policy frozen once approved; fixture change log and stale-write
   refusal; outcome must supersede its predecessor; claim history immutable.
10. Grants: SELECT to every app role; INSERT/UPDATE to `app_competition` on the mutable tables;
    INSERT only on the append-only tables; **no DELETE or TRUNCATE for any app role on any
    competition table, present or future** (default privileges).

Kotlin: `Competitions.draw` writes `bracket_tie`; `enter` takes a sealed `Entrant`; `checkIn`
records the player present; `Relations.revoke` is an UPDATE; `ObjectType.SEASON` is
`LEAGUE_SEASON`. No route names, deep links or device journals exist to migrate; the README says
so.

## 5. Network architecture — what must change for multi-user THRØ

Decided already and unchanged: Kotlin/Ktor (ADR-001), one Postgres (ADR-003), per-device evidence
streams (ADR-004), modular monolith (ADR-005), offline grants and the server algorithm (ADR-006),
SSE fan-out and one HTTP command endpoint (ADR-007), relationship authorization (ADR-008), single
container on a PaaS in UK/EU (ADR-011), three kinds of configuration (ADR-014).

What does not exist and must be built, in this order:

1. **The HTTP layer.** Ktor routes over the existing handlers; OpenAPI emitted by the server and
   gated in CI (ADR-001's unproven mitigation, proved here).
2. **Accounts and sessions.** `identity.account` exists; credentials, sessions and refresh-token
   families do not. The *mechanism* is decided; the *surface* is B4.
3. **Player ⇄ account.** `competition.player` may exist unclaimed (created by a captain). Claiming
   binds it to an account through an audited flow with organiser confirmation or a claim code —
   that is `identity.player_claim` (V014): one live claim per player and per account, fixed when
   made, revocable, never rewritten. Merging two players is an appended, reversible identity event,
   never an UPDATE of foreign keys.
   ADR-016's claim is the other half and the two meet here: ADR-016 binds a **device's local
   person**, and every seat that person occupied in that device's journal, to an account, carrying
   a per-match digest over the journal rows so a history cannot be quietly rewritten after it was
   claimed. On the server that lands as: the account's live `player_claim` names the THRØ ID the
   local person becomes (created unclaimed by the claim if none exists), and each claimed match's
   seat is recorded as `local_match_claim (match_id, seat, player_id, device_id, digest, claimed_at)`
   — self-reported evidence that attaches a history and never corroborates one (ADR-016 §3, PD-002),
   claimable once per seat, enforced by the server. The table does not exist yet because the claim
   flow it needs is FB-1's; the shape is fixed now so that V016's consent gate, V018's seats and
   ADR-016's digest attach to it without a migration.
4. **Two kinds of state, two sync models.**
   - *Competitive evidence* stays per-device append-only streams with the ADR-006 algorithm.
   - *Organisational state* (roster, fixtures, availability, tasks) is **server-authoritative
     versioned rows** with a `row_version`; clients send commands carrying the version they saw,
     and a stale version is a refusal with the current row, never a silent overwrite. Two admins
     cannot clobber each other because the second write fails closed.
   - Clients keep a local read cache of organisational state so a captain can see tonight's
     fixture and lineup in a basement; **edits queue as commands** and are applied on reconnect
     under the same version rule.
   *A dependency to carry into the HTTP layer:* today every authorization subject is a THRØ ID,
   and `SetAvailability`'s "the player's own word" is `actorId == playerId`. When actors become
   accounts, the API boundary resolves an account to its live `player_claim` before any command
   handler runs — the handlers keep speaking THRØ IDs — or self-recording silently stops holding.
5. **Media.** Object storage behind signed URLs; badge and crest uploads only in Phase C, with the
   safeguarding image policy from OD-010 gating anything showing people.
6. **Push.** ADR-015 stands; APNs first, with the delivery record it requires.

Founder-level decisions inside this are in §9. Everything else proceeds.

## 6. First vertical slice — Team OS (Phase C)

Runs against the real database and the real HTTP layer. Nothing is static data.

| Step | Module | Persisted where | Authorization |
|---|---|---|---|
| Create a Team | competition | `team`, `authz.relation team#admin` | any account |
| Configure identity | competition | `team` columns; `team_venue_tenure` for home venue | `team#admin` |
| Associate a public Venue | competition | `venue` (create or pick), `team_venue_tenure` | `team#admin` |
| Invite players | competition + identity | `player` (unclaimed allowed), `team_membership status=invited` | `team#admin` |
| Assign captain / admin | competition + authz | `team_membership.role`, `team#captain`, `team#admin` | `team#admin` |
| See roster | read model | `read.team_roster` projection | `team#member` private, public front otherwise |
| League season affiliation | competition | `team_affiliation` | `team#admin`, accepted by `league_season#admin` |
| Fixtures | competition | `fixture` rows created by the league admin or agreed friendlies | `league_season#admin`; friendlies later |
| Availability | competition | `availability (fixture, player, team, status, recorded_by, row_version)` + append-only `availability_change` — **store level delivered** (V021, `OrganisationCommands.SetAvailability`) | the player, or `team#captain`/`team#admin` on their behalf; `recorded_by` is the provenance |
| Lineup | competition | `lineup (fixture, team, row_version)` + `lineup_entry` per version, old sides kept as history; fixed once the fixture has a live outcome — **store level delivered** (V021, `OrganisationCommands.NameLineup`) | `team#captain` or `team#admin` |
| Score / connect match | match | `evidence.match` opened from the fixture; `fixture.match_id` set once | existing grants |
| Result with provenance | trust | existing attestation, capture channel and outcome | unchanged |
| Team history | read model | seasons, honours, tenures, past rosters, from the tables above | public front / private inside |

## 7. Secretary wedge — player registration (Phase D)

The administrator enters a sporting fact once — *Sam joined Riverside A* — and THRØ carries the
administration that legitimately follows, without ever becoming the authority that says Sam is
registered. Concrete design, V016:

```
admin_task            (task_id, kind, owner team_id | league_season_id (typed, exactly one),
                       source_kind + source_id, subject player_id? fixture_id? registration_id?,
                       reason, due_at, state, policy_id?, row_version, created_by)
admin_task_event      append-only by trigger: (task_id, from_state, to_state, at, by, note)
submission            (submission_id, kind, league_season_id, registration_id? | fixture_id? | outcome_id?
                       (typed, exactly one), task_id?, transport, state, policy_id, row_version)
submission_transition append-only: (submission_id, from_state, to_state, at, by, evidence_kind,
                       evidence_ref, note) — the trigger validates the graph and the evidence,
                       then projects the new state onto the submission row
```

Task states: `open`, `waiting_player`, `waiting_opponent`, `waiting_league`, `done`, `cancelled`.
Task kinds in this slice: `registration_required`, `registration_incomplete`,
`result_submission_due`, `rearrangement_acknowledgement_due`. The inbox is a read over
`admin_task` by owner and `due_at`: ACTION REQUIRED, DUE TODAY, UPCOMING, WAITING FOR …, COMPLETED.
No task is created when the fact it would chase is already true (a registered player gets no
registration task); tasks are derived from facts and policy, never manufactured to fill a list.

Submission states and the evidence each transition demands:

| From → to | Who | Evidence required |
|---|---|---|
| `draft → ready` | THRØ, when nothing is missing | none |
| `ready → submitted` | a team admin, naming the transport | none; **refused** if the subject player is unclaimed or has no recorded consent basis (PD-029) |
| `submitted → delivered` | THRØ or the admin | transport evidence: `message_id`, `upload_receipt`, `api_response`, or `human_confirmation` with the actor |
| `delivered → acknowledged` | a named person | `counterparty_message`, `api_response`, or `human_confirmation` |
| `acknowledged → accepted` / `rejected` / `action_required` | a named person | as above; `accepted` on a `player_registration` sets the registration `registered` under the cited policy |
| `action_required → ready` | a team admin | none |
| anything → `withdrawn` | a team admin | none |

THRØ never moves a submission past `submitted` on its own. `accepted` is a fact about the league's
answer, and the row records who said so and how. A transition without the evidence its kind
requires is refused by the trigger, not by convention.

Registration requirements come from the season's **approved** `registration` policy, parsed by
`RegistrationPolicy` into facts THRØ can check — a display name, a known age band, a bound account,
a recorded consent basis, a deadline (an absolute date or days before the team's first fixture) —
and nothing else; an unknown requirement key is refused at parse, so a league's "passport photo"
never silently passes. Missing facts make a `registration_incomplete` task listing them; none
missing makes the submission `ready`.

Generalisation, proved by the same tests: a `league_fixture_outcome` creates a
`result_submission_due` task and a `result` submission for the league — a **draft** until both
sides have a lineup named (V021), with the task's missing facts naming the side that has none, and
`ready` the moment `onLineupNamed` finds both; a `league_fixture_change`
creates a `rearrangement_acknowledgement_due` task waiting on the opponent and a
`fixture_rearrangement` submission. Same task table, same transition table, same evidence rule.

The example league policy is a fixture in the test suite, not a real league's rules, and every task
and submission cites the policy version it was produced under.

## 8. Tournament model

`tournament` is the recurring identity ("The Riverside Open"); `event` is one edition. An event
declares `entry_kind ∈ {singles, pairs, team}` and `access ∈ {open, invitational, qualified,
restricted, member_only}`. Entries are typed (§3). Draw, check-in, boards and bracket ties are the
existing lifecycle. A `series_season` links editions across venues with an ordinal; points and
standings are a policy of the series season, computed as a projection, and are **not** built until
the entities exist. Discovery (Phase E) reads `event` × `venue` × `access` × the caller's
registrations and memberships, and every card can state why it appears.

A tournament cannot behave like a league because no fixture, affiliation or registration references
an event, and no entry, check-in or bracket tie references a league season.

## 9. Founder blockers — genuine product decisions only

Two are genuine. Two more are recorded as delegated decisions with reversal paths so work continues.

**FB-1 — Identity provider and the claim policy (extends B4).**
*Why it matters:* an account is a competitive identity; recovery and claiming are account-takeover
surfaces.
*Option A:* self-hosted WebAuthn/passkeys in the Kotlin service, email magic-link bootstrap, own
session store. *Option B:* a managed identity provider (Auth0, Clerk, Cognito, Firebase Auth)
fronting the same API. *Option C:* Sign in with Apple and Google only, plus own passkeys later.
*Recommendation:* A. ADR-008 already forbids permissions in tokens and requires per-request
relation checks, which leaves a managed provider doing only credential storage; the WebAuthn
libraries on the JVM are mature; and identity data stays in the one `identity` schema ADR-005
depends on for deletion and export. *Cost of reversing:* moderate — credential export from a
managed provider is possible but recovery flows are rewritten. *Blocks:* Phase B's account surface,
every authenticated route, the claim flow.

**FB-2 — Hosting vendor for the single container and managed Postgres.**
*Why:* ADR-011 fixes the topology, not the vendor; point-in-time recovery, UK/EU residency and
HTTP/2 to origin (ADR-007) must be confirmed against a real provider. *Options:* Fly.io + Neon or
Fly Postgres; Render; Railway; a single AWS account with App Runner + RDS. *Recommendation:* Fly.io
with a managed Postgres provider offering PITR in London, because it is the cheapest that meets
every ADR-011 requirement and the infrastructure-as-code footprint is smallest. *Cost of reversing:*
low — one image, one database dump. *Blocks:* staging and the two-device sync release check only;
local and CI work is not blocked.

**Delegated, reversal path recorded (see DECISIONS.md PD-028, PD-029):**

- **PD-028 — Canonical organisational vocabulary.** ADR-017. Reversal: the tables are new and the
  rename is one statement.
- **PD-029 — Unclaimed player records.** A team admin may create a player who has no account. The
  record is private, carries `age_band='unknown'` and is treated as a minor for every exposure rule
  until claimed. Reversal: a policy flag refusing unclaimed creation; existing records stay.

## 10. Implementation sequence

| Order | Work | Depends on | Blocked by |
|---|---|---|---|
| A1–A6 | Audit, ADR-017, V014, Kotlin organisational domain, tests, docs | nothing | nothing |
| B1 | Ktor HTTP layer over existing handlers; OpenAPI in CI | A | nothing |
| B2 | Organisational command model with row versions (**delivered**: V015, `OrganisationCommands`, two-writer conflict test); local cache contract | A | nothing |
| B3 | Accounts, sessions, passkeys, claim flow | B1 | **FB-1** |
| B4 | Push delivery record; media storage contract | B1 | FB-2 for staging only |
| C | Team OS slice end to end | B1–B3 | FB-1 |
| D | Secretary: registration, then result submission and rearrangement (**delivered at the domain and store level**: V016, `Secretary`, 62 properties; the HTTP and client surfaces wait on B1/B3) | A, B2 | nothing further |
| E | Tournament editions, series, discovery (**store-level read delivered**: V017 + V019 + V022, `Discovery`, 26 properties — every card explains itself, nothing is called eligible that THRØ cannot check; the consumer surface waits on the client) | A, B1 | client for the surface |
| F | Map (MapKit on iOS, when the client exists); friendly request loop | C, E, iOS client | Gate 5 (device journal) for the client |

The iOS client itself is a separate stream gated by ADR-006's outstanding SE-class and Android
measurements, and by B3 (design commission for auth screens).

## 11. Risks

**Technical.** Organisational sync is a second consistency model beside the evidence log; the
row-version rule must be tested with two concurrent writers or it will drift into last-write-wins.
The `season` object type alias in `authz` is a temporary dual concept and has a removal task.
Migrations run as `thro_owner` and the new tables must inherit the same no-DELETE stance or history
becomes deletable.

**Sporting.** Registration ≠ eligibility: a task pipeline that marks a player registered because a
form was sent would make THRØ the authority it must not be. Team separation in draws
(design's "club protection") is a policy and must be versioned or a draw cannot justify itself later.
Identity resolution: a captain typing "J. Smith" twice must produce two players until a human merges
them.

**Commercial.** The Secretary wedge only earns revenue if leagues accept THRØ's submissions; the
adapter priority (API → structured → export → document → email → human) must show provenance or an
organiser will not trust the green tick. Building the map before Teams exist would produce an empty
map.

## 12. Acceptance criteria — Phase A

Mechanical. Each is a test that fails when the property is removed. **All green on 2026-09-09**
against PostgreSQL 16 locally; CI runs the same suites.

| # | Criterion | Enforced by |
|---|---|---|
| 1 | Team identity survives a venue change: same `team_id`, two tenures, first closed, row untouched | `OrganisationTest` (API) · `OrganisationTest` (competition, pure) |
| 2 | One venue hosts several teams at once | both |
| 3 | A player holds two concurrent active team memberships; a policy cap is respected | both |
| 4 | Membership and registration are independent: member with no registration; registration for a team the player has left; transfer supersedes | both |
| 5 | Closing a membership never deletes it; a closed row is frozen; parties and start are fixed; no app role can delete | API test + `schema_properties.sh` |
| 6 | Two seasons of one league coexist; a division cannot attach to another season | API test |
| 7 | No event, entry, check-in or bracket tie references a league season; no league fixture, affiliation or registration references an event; no standings table in `competition` | API test + `schema_properties.sh` |
| 8 | An entry is exactly one of player, pair, team; its kind is its event's; a bare identifier is refused; `(a,b)` = `(b,a)` | both |
| 9 | A series season links events at two venues; ordinals unique | API test |
| 10 | V014 over a populated V013 database preserves every event, entry, check-in, grant, tie and tuple, the venue label, the seeds and the draw | `MigrationTest` (14 properties) |
| 11 | Existing suites remain green, including the 74-entrant draw against `bracket_tie` and a pairs event refusing a singles entry | `CompetitionTest` (16) and every other suite |
| 12 | An approved policy cannot change body, date or be un-approved; two approved versions cannot overlap; a superseded one may be followed; a policy cannot cite a season that does not exist | API test |
| 13 | No DELETE or TRUNCATE on any competition table for any app role, including a table added later; `authz.relation` is revoked not deleted; `season` is gone | `schema_properties.sh` (86 properties) |
| 14 | A fixture's venue is frozen at scheduling; a stale rearrangement is refused; the original date survives in the change log; teams cannot be switched; an award must go to one of the two teams; a second outcome must supersede; outcomes are not editable | API test |
| 15 | A player row carries no free text; a claim is one live per player and per account, fixed when made, revocable; an organiser confirmation names the organiser | API test + `schema_properties.sh` |
| 16 | A team rename keeps the old name with its period | API test |
| 17 | GLOSSARY, README, ADR index, package READMEs and DESIGN_UNSPECIFIED describe the model above and teach no separate Club | review |
| 18 | No display name in `evidence.match` or in any payload: the aggregate binds the seats `home` and `away` to competitor ids, the same two words both on-device journals store; a V013 database's named matches are pseudonymised in place with every other payload field untouched; a visit naming anything but a seat is refused | `MigrationTest` (18 properties) + API tests, **delivered** (V018, closes OD-024) |
| 19 | A check-in is a person: keyed on (event, player, device), for a live entry of the event, by a member of the entrant — the player themself, one of the pair, or a live team member at that moment; the scoring grant is the person's, never the pair's or the team's | `CompetitionTest` (21 properties) + `MigrationTest`, **delivered** (V020) |
| 20 | Match night at the store level: a player records their own availability with no relation, a captain records it on their behalf and the row says so, every word is kept with who said it, a stale write is refused with the current row; a lineup is the captain's, versioned, its old sides kept, a non-member or a team not in the fixture refused by the store in its own words, a change after a live outcome refused; a result card is a draft until both sides are named; every command, refused or applied, leaves a receipt | `OrganisationCommandTest` (20 match-night properties) + `SecretaryTest`, **delivered** (V021) |

Also required before Phase C opens a match from a fixture: the Phase D rule that no submission
carrying an unclaimed or non-adult player leaves `READY` without a recorded consent artefact
(PD-029). OD-024, the other precondition, is closed by V018 above.

Phases B–F carry their own acceptance tables, written when each phase opens and before its code.

## 12b. Acceptance criteria — Phase D (Secretary), delivered

All green on 2026-09-09. `SecretaryTest` (62 properties), `SecretaryTest` in the competition
package (pure, 5), and `schema_properties.sh`. Hostile review of the §7 design produced eighteen
findings before implementation; the schema closes the four blockers in the database itself.

| # | Criterion | Enforced by |
|---|---|---|
| D1 | A member of an affiliated team under an approved policy owes exactly one registration; reconciling again manufactures nothing; a hand-inserted duplicate is refused | `reconcileTeam` + partial unique index |
| D2 | Nothing is owed without an affiliation, or without an approved policy in force | test |
| D3 | The task cites the policy version it was made under; a later version does not rewrite it; a new member after v2 is assessed under v2 | test |
| D4 | Deadline is derived from the rule, recomputed when the anchor fixture moves, and the old deadline survives in the task's history against the change that caused it | `refreshDeadlines` + `admin_task_event` |
| D5 | THRØ alone cannot submit; a replay with a stale version is refused; a message id typed by hand is not delivery evidence; a failed attempt is `delivery_failed`, never `delivered` | trigger + CHECK |
| D6 | Acknowledged, accepted, conditionally accepted, rejected and action-required require a named person who administers the receiving side; the team admin who sent it cannot; THRØ alone cannot; every such transition names the league | trigger (`administers_recipient`) |
| D7 | An acceptance names the date registered from; conditions make it conditional and register nobody; the registration is created from that date under the policy in force on it | trigger + `answer` |
| D8 | No application role may update a submission row; transitions, deliveries, artefacts and task events are append-only | grants + `schema_properties.sh` |
| D9 | A placeholder the captain typed in starts with no consent basis whatever was passed; nothing about an unclaimed player leaves THRØ; a minor's own consent does not open the gate, a guardian's does and closes the player's own consent task | `player_may_be_disclosed`, `account_consent_starts_honest` |
| D10 | A requirement THRØ cannot check is a manual step satisfied only by a named confirmation with a note | `manual_requirements` + `admin_task_manual_confirmation` |
| D11 | A registration under a draft policy is refused at the row, whoever writes it; a registration's status never moves backwards | trigger |
| D12 | A played outcome makes the home team owe a result card; recording it twice creates nothing; an outcome the league decided itself creates nothing; voiding the outcome supersedes the submission that carried it | `onFixtureOutcome` + trigger |
| D13 | A rearrangement is a proposal to the opponent, delivered in-app with a delivery row; the proposer cannot answer it; the opponent's admin can; the fixture does not move until the league applies it, and the change cites the proposal | `proposeRearrangement`, `applyProposal` |
| D14 | The league sees nothing before it was sent; the captain's inbox groups by state and deadline | `submissionsForLeague`, `inbox` |

Deferred, recorded: a payload gate for result submissions that carry lineups (no lineup exists
until Phase C); a `transport_evidence_rule` table when the second adapter arrives; `lapsed` as a
league decision with a reason, not a payment flag (OD-009).

## 12c. Acceptance criteria — Phase E read model, delivered

`DiscoveryTest`, 26 properties, green 2026-09-09. A past event is not offered; every card carries
a date, a kind and an access reason; THIS WEEKEND is Saturday and Sunday; NEAR YOU is the locality
of the team's venue, never the person's location; CLOSING SOON is a stated closing date within a
week and an unstated one is said to be unstated; YOU ARE ELIGIBLE means open, singles, still open
to entries, with a place if a capacity was stated — a pairs event and a full event are never called
eligible; an unstated capacity is null, never unlimited; places are counted from live entries; a
series the player already plays in surfaces its other legs and says why; an entered event appears
only as entered.

**Gated events (V019, `competition.event_eligibility`).** An organiser states what a `member_only`,
`qualified`, `restricted` or `invitational` event requires in the five terms THRØ can check against
its own records — a live team membership, a live league-season registration, a live entry to a named
qualifier, the claimed account's age band, or an invitation by name. Rows in one group are
alternatives (the A side or the B side); every group must hold (a member *and* an adult). The store
answers through one predicate, `requirement_holds_for`, so the card and `player_satisfies_event`
cannot disagree. Held by test: an event with no stated requirement says "requirement not stated in
terms THRØ can check" and is never eligible; a met requirement is named on the card ("you qualify:
member of Riverside A"); an unmet one names the missing group ("requires membership of Grange B");
an unclaimed player's age band is unknown and unknown satisfies neither `adult` nor `minor`; an open
event refuses a requirement; a withdrawn requirement leaves the event unstated, not the player
eligible; the application role may withdraw a row and change nothing else in it, and the owner
cannot rewrite one either. What THRØ cannot check — qualification by result, residence, anything
outside the five — is not a row, and stays unsaid.
