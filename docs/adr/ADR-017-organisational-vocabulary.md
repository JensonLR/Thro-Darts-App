# ADR-017 — Organisational vocabulary: Team, Venue, League, Tournament, Series

**Status:** Accepted · **Date:** 2026-09-09 · **Founder instruction** recorded as PD-028

## Context

Grassroots darts uses words inconsistently. The same competitive organisation calls itself a *darts
team*, a *darts club*, a *pub team* or a *social club side*; the building it plays in is a *pub*, a
*working men's club*, a *social club* or a *club*. The approved design carries both usages in its
fixture data: "Riverside Club" and "Boro Legion Club" are the **venues** of teams called
"Riverside A" and "Boro Legion", while a settings row reads "Team and venue · Your club affiliation",
where *club* means the **team**.

The repository, audited on 2026-09-09, contains no `Club` type, table, column or route. What it
contains is thinner than the word suggests: a match-time `Competitor.Team` (a lineup), an `event`
table that is really one tournament edition, an `entry` whose entrant kind is unrecoverable, a
free-text `venue`, a table called `fixture` that is a knockout bracket tie, and an authorization
vocabulary (`TEAM`, `VENUE`, `LEAGUE`, `SEASON`, `DIVISION`, `ORGANISATION`) that nothing backs.

The next fifty features — rosters, registrations, league seasons, tournament discovery, the map,
the Secretary — will each be built on whichever of these concepts exists first. This record fixes
the vocabulary before that happens.

## Decision

**`Club` is not a canonical entity.** It is a word people use, sometimes for a Team and sometimes
for a Venue, and it resolves to one of them every time. THRØ never carries two organisation
concepts because the vocabulary at the board is inconsistent.

| Canonical term | Meaning | Not to be confused with |
|---|---|---|
| **Player** | one persistent sporting identity; may exist before it is claimed by an account | an account (credentials, personal data) |
| **Team** | the competitive organisation, whatever it calls itself | the lineup a team fields in one match (`Competitor.Team`) |
| **Venue** | the physical place darts is played; hosts many teams and events | a team; a team's identity does not change when its venue does |
| **Team venue tenure** | the dated relationship between a team and a venue (home, training, registered) | ownership — a venue never owns a team |
| **Team membership** | a dated relationship between a player and a team, with a role and a status | league registration |
| **League** | the recurring competition authority | a season of it |
| **League season** | one occurrence of a league, with dates, divisions, affiliated teams and registered players | the league's identity; the design's "Season" |
| **Division** | an optional subdivision of a league season | a league |
| **Team affiliation** | a team's dated registration to a league season and optionally a division | membership, which is about a player |
| **Player registration** | a player's dated eligibility record in a league season, optionally naming the team it was made for | membership; being a member does not make a player registered or eligible |
| **Tournament** | the persistent identity of a discrete competition that may recur ("The Riverside Open") | a league; a single edition |
| **Event** | one edition of a tournament: entries, check-in, draw, boards, bracket ties | a league fixture night |
| **Entry** | a typed entrant (player, pair or team) in an event | a membership or a registration |
| **Bracket tie** | a pairing in a knockout round, possibly a bye | a fixture |
| **Fixture** (`league_fixture`) | a scheduled meeting between two teams in a league season, with a rearrangement lifecycle, that may be awarded unplayed | a bracket tie; a match |
| **Match** | the contest itself, in `evidence.match` | the fixture or tie that scheduled it |
| **Series** | a linked collection of tournaments | a league |
| **Series season** | a dated occurrence of a series, linking specific events | a league season |
| **Policy** | a versioned, approved rule body belonging to an authority (league season, event, series season) | code; a flag |

### Rules that follow

1. **Identity is the row; place is a tenure.** A team that moves venue closes one tenure row and
   opens another. Its history, roster, results, honours and followers are keyed to `team_id` and do
   not move.
2. **Dated relationships are appended, never edited away.** Tenure, membership, affiliation and
   registration rows carry `valid_from` and `valid_until`. Closing one sets `valid_until` once;
   nothing deletes it. A trigger refuses moving `valid_until` earlier than `valid_from`, and no
   application role holds `DELETE`.
3. **Membership and registration share no key.** A player may be a member with no registration, or
   registered for a season with a team they later left. Eligibility is derived from registration
   under the season's approved policy, never from membership.
4. **Tournaments and leagues share no table.** Nothing lets an event reference a league season or a
   league fixture reference an event; the schema property test asserts it.
5. **Entrants are typed.** An entry names exactly one of a player, a pair or a team, and the
   database refuses anything else. The Kotlin domain mirrors it with a sealed `Entrant`.
6. **Policy is data with provenance.** A policy row names its authority, version, effective period,
   provenance (`manual`, `imported`, `extracted` — the last meaning an AI-assisted extraction that
   a human reviewed), an approval state and the approving actor. Only an approved policy may be
   cited by anything executable; an approved body is immutable and change is a new version. A
   historical decision cites the version that applied.
7. **The design's "Club protection"** in draw setup is a **team separation** draw policy: keep
   entrants from the same team apart in the first round. It is a policy row, not a flag.
8. **Copy may still say "club"** where the user typed it as a name. THRØ's own copy says *team*
   and *venue*.

## What was considered and rejected

- **A separate `Club` entity above Team** ("Grange WMC has Grange A and Grange B"). Rejected: what
  those two teams share is a venue, and sometimes a committee; the committee is a set of admin
  relations on two teams, which the authorization graph already expresses. A parent entity would
  reappear as the thing that "owns" both teams' history, and a team leaving its club would then
  face the very history loss this record forbids.
- **An `Organisation` supertype** for team, league, venue and tournament. Rejected for now: the
  authorization vocabulary already has `organisation` as an object type for a future federation or
  county body, and nothing needs polymorphic ownership yet. Revisit if a governing-body integration
  needs one owner over several leagues.
- **Renaming `Competitor.Team`** to avoid two things called Team. Rejected: it is the lineup that
  contests a match and rating is per player (ADR-012). The distinction is recorded here and in the
  glossary; the type gains a doc comment naming its team of origin.
- **Keeping `competition.fixture` for the bracket tie.** Rejected: the glossary and ADR-012 already
  define Fixture as the league concept and say "not a slot"; the table is the thing that was
  misnamed. It is renamed `bracket_tie`.
- **Re-using the name `competition.fixture` for the league concept in the same migration.** Rejected
  on hostile review: SQL written against the old shape would compile against a table of the same
  name and a different meaning. The league table is `league_fixture`; the domain term is still
  Fixture.
- **A `season` alias in the authorization vocabulary "until Phase C".** Rejected on hostile review:
  no row has ever been written with it and no code writes it, so a dated dual concept would have
  been pure cost with nothing enforcing its removal. It is replaced by `league_season` outright.

## Consequences

- Migration V014 (`services/api/migrations/V014__organisations.sql`) creates the tables and renames
  the bracket tie. No production or device data exists; the migration test still applies it over a
  populated V013 database and asserts nothing is lost.
- `authz` replaces `season` with `league_season` and gains `series`, `series_season` and
  `tournament`. Relations are **revoked, never deleted**: who was captain last season is team
  history, and ADR-008's "who could have done this" needs the tuple that existed then.
- `competition.player` holds **no personal data and no free text**: an identifier, a provenance
  vocabulary and a creation record. Its binding to an account is `identity.player_claim` —
  appended and revocable, never a column updated in place — so a wrong claim is revoked and both
  identities stand. Display names stay in `identity` (ADR-005) and the read models join them at
  publication, which is what keeps export and deletion tractable. A schema property asserts the
  table carries no text but its vocabulary.
- **Dated relationships are frozen once closed**, not merely their end date. A status may only move
  forward while open (`invited → active`, `applied → accepted`); the parties are fixed at recording.
  Home tenures may not overlap in time at all, past or present, by an exclusion constraint.
- **Policy** carries a typed authority (a foreign key, not a bare identifier), a unique version per
  authority and kind, and an exclusion constraint so two *approved* versions of one rule can never
  be in force on the same day. Once approved, every column but the closing date and the forward
  transition of its state is frozen. ADR-014's `rules_version` on a match is to become a
  `policy_id`, so there are not two policy systems.
- **A league fixture's schedule is versioned and logged; its outcomes are appended.** A stale write
  is refused by row version, every schedule change is written to `league_fixture_change` by trigger,
  and an outcome is a decision row with an actor, a time and a policy that a later decision may
  supersede but never edit. The venue is copied from the home team's tenure at scheduling, never
  derived at read time, or a venue move would relocate every past fixture.
- **Teams keep their names.** A rename writes the previous name and its period to `team_name`;
  dissolution is recorded once.
- `check_in` gains the player who was physically present, nullable for now. Making the grant actor
  a player rather than a competitor — which a pair or team entry requires — is V015's
  expand-then-contract and is listed in the execution plan.

## Deferred from hostile review, with reasons

- **`evidence.match.home_name` / `away_name` are personal data in an append-only table.** Correct,
  and pre-existing (V006). Resolving it means the command handler and engine working in
  identifiers with names joined at render, and a pseudonymous label for a non-adult account.
  That is Phase B work on the command path, tracked as OD-024, and this migration does not walk
  an unclaimed player into `evidence.match` because nothing yet opens a match from a fixture.
- **A merge of two players** (`identity.player_alias`) is not created here. It depends on the
  claim flow that B4 gates. The rule is recorded now: a merge is an appended, reversible identity
  event with a stated basis, never a name match and never a repointed claim; every projection
  resolves through it; a merge with no basis is refused.

## Revisit trigger

A real organisation that genuinely cannot be expressed as team, venue, league, tournament or series
— a county board that enters teams into a national inter-county competition is the likely first
case, and should be tried as an `organisation` object holding admin relations over teams before any
new entity is proposed.
