# ADR-012 — Competition model: competitor, competition and fixture

**Status:** Accepted · **Date:** 2026-09-03

## Context

Gate 0 identified this as rewrite-forcing and ADRs 001–011 did not address it.

The approved design contains a **complete league surface** that is easy to overlook because the
flagship slice is a tournament: divisions and seasons, a fixture list with rearrangement, the ability
to **award** a fixture that was never played, captains, and a published table with points, legs for
and against, and a team rating column. It also contains **Pairs** events.

Two assumptions would each force a rewrite:

- **That the competitive entity is a player.** If the match aggregate is built with home and away
  *player* identifiers, introducing `Competitor = Player | Pair | Team` later is precisely the
  leg-flat-aggregate rewrite that ADR-004 avoids for sets.
- **That a slot graph generalises all competition.** It generalises brackets. It does **not**
  generalise a league fixture, which has no parent-child dependency, has a scheduled window and a
  rearrangement lifecycle, can be awarded with no match played, and aggregates into a table rather
  than advancing a competitor.

## Decision

**Introduce `Competitor`, split `Competition` by kind, and keep `Fixture` and `Slot` as distinct
types — now, regardless of first-release scope.**

```
Competitor = Player | Pair | Team          -- the entity that contests a match
Competition = Tournament | LeagueSeason    -- the structure that produces matches
Tournament  -> Stage -> Slot               -- a slot graph
LeagueSeason -> Division -> Fixture        -- a scheduled fixture list
```

**`Competitor` is the participant of a match.** A `Player` competitor resolves to one THRØ ID; a
`Pair` and a `Team` resolve to several. Rating remains a property of the **player**, not of the
competitor — a team rating is a derived, separately-specified aggregate (see below), never a stored
rating on a team row.

**`Slot`** is a bracket position with an explicit state, because the design currently renders four
different competitive facts identically as "TBC":

```
Slot { state: PLAYER | UNDETERMINED | BYE | WALKOVER | WITHDRAWN, competitor?, seed?,
       sourceWinnerOf?, sourceLoserOf? }
```

The two source edges mean single elimination, double elimination and groups-into-knockout are all
*generators* of one slot graph rather than three structures. Double elimination in particular cannot
be expressed by an ordered list of rounds at all, and its bracket-reset rule is the one naive
implementations omit.

**`Fixture`** is a scheduled meeting between two competitors within a division, with its own
lifecycle: scheduled → rearranged → played, or → **awarded**. An awarded fixture is a distinct,
auditable outcome type carrying an organiser decision — **never a synthetic scoreline**, which would
pollute leg-difference tie-breaks and reward an unplayed match in any rating model.

## Consequences that must be built in from the start

**Byes are computed, never carried by the UI.** For N entrants and bracket size B = 2^⌈log₂N⌉:
byes = B − N, preliminary matches = (N − byes) / 2. The approved design gets this wrong (74 entrants
shown as "10 byes" where 10 is the preliminary-match count and the true bye count is 54), which is
exactly why the domain owns the arithmetic. Property test: for all N in 2…1024, the identity holds
and every entrant appears exactly once.

**A bye is not a win** — the design's own best domain decision, stated in its copy: a bye creates no
match aggregate, produces no statistics, and is not rating-eligible.

**Field size is only known at draw time.** Closing check-in withdraws outstanding and unpaid entrants,
so bracket size and bye count cannot be computed before it. This is also where founder decision B1's
neighbour bites: if payment is out of the first release, something else must gate check-in.

**Tie-breaks are declared, ordered, per-competition configuration**, and every standings row carries
the **applied tie-break chain** so a published table can justify its own ordering. The design's table
exposes legs for and against but has no head-to-head column — so if the ordering used head-to-head,
the table could not explain itself. Also required: a deterministic fallback for circular head-to-head
among three or more competitors, and correct handling of unequal fixtures played.

**Draws do not assume no draws.** The design's format makes drawn fixtures structurally impossible
(odd leg counts), and the table has no drawn column. That must not become an invariant of the league
aggregate, or the first even-leg competition breaks it.

**Per-round format override.** Real tournaments escalate — a shorter format early, longer for the
final. The design shows one format throughout; that must not be encoded as an invariant.

## Team rating is deferred, deliberately

The design publishes a team rating column. That is an entire rating product with its own methodology,
its own gaming surface (resting a strong player), and its own dignity considerations. It is **out of
scope until player rating is settled** (ADR-009), and the schema simply does not carry it yet. Adding
a derived aggregate later is cheap; adding a *stored* team rating now would be a second undecided
model competing with the first.

## First-release scope

**Single elimination tournaments only.** Leagues, pairs and team fixtures are modelled but not built.
The cost of modelling them now is a type and two tables; the cost of not doing so is the rewrite this
record exists to prevent.

## Revisit trigger

The first competition that is neither a single-elimination tournament nor a round-robin league —
group stages with qualification are the likely first, and should be a generator over the existing slot
graph rather than a new structure. Also revisit when team rating becomes a product requirement.
