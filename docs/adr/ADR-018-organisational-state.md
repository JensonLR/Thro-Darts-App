# ADR-018 — Organisational state: server-authoritative versioned rows beside the evidence log

**Status:** Accepted · **Date:** 2026-09-09

## Context

ADR-004 and ADR-006 settle how **competitive evidence** moves: per-device append-only streams, a
gapless sequence per author, reconciliation at outcome level, never last-write-wins. That model is
right for a visit and wrong for a roster. A roster, a fixture list, tonight's availability and a
captain's lineup are **organisational state**: few writers, human-paced, correctable by the same
people who wrote them, and read by many. Modelling a captain's rename of a team as an evidence
stream would give it the wrong invariants (nothing to corroborate) and the wrong cost (a projector
for every table).

The founder's brief for the connected platform is explicit about the failure to avoid: a later
upload from another phone must never silently replace what another admin did. Phase A already put
`row_version` on `team`, `venue`, `league_season` and `league_fixture`, and a trigger on two of
them refuses a write that does not carry the version it saw. This record makes the rule general
before Phase C builds the Team OS slice on it.

## Decision

**Two kinds of state, two models, and a client that keeps the difference.**

| | Competitive evidence | Organisational state |
|---|---|---|
| Examples | visits, legs, attestations, disputes, corrections | team, venue, tenure, membership, registration, fixture schedule, availability, lineup, admin tasks |
| Truth | the append-only per-device streams (ADR-004) | the server's current row, plus append-only history tables where the domain needs them |
| Write | command → journal → server revalidates → append | command carrying `expected_version` → server applies or refuses |
| Conflict | never; two accounts are corroboration or a dispute | **refused, with the current row returned** — never merged, never overwritten |
| Offline | scores without a server for hours (ADR-006) | reads from a local cache; edits queue as commands and apply on reconnect under the same rule |
| History | the log is the history | dated relationships (`valid_from`/`valid_until`), change logs by trigger, appended decisions |

### The rule, precisely

1. Every mutable organisational row carries `row_version int NOT NULL DEFAULT 1`.
2. Every command that changes such a row carries the `expected_version` the client last saw. The
   server applies the change with `WHERE row_version = expected_version` and sets
   `row_version = expected_version + 1`. Zero rows updated is a **refusal**, and the response carries
   the current row so the client can show the person what changed under them.
3. A trigger on the table refuses any update whose new version is not exactly old + 1, so the rule
   holds for SQL written outside the command path as well.
4. What must never be lost is not kept in the mutable row at all: a fixture's original date lives
   in `league_fixture_change`; an outcome is a row in `league_fixture_outcome` that a later decision
   supersedes; a team's former names live in `team_name`; a membership's end is `valid_until`. The
   versioned row is the **current** view, not the record.
5. A queued offline command that is refused on reconnect is **kept, with the refusal and the
   current row**, and shown to the person as a decision to make — never dropped, never retried
   blindly, never applied over the newer state. This is ADR-006's "rejected batch is never
   discarded" rule, applied to the second kind of state.

### What a client caches, and what it may not

The client keeps a **read cache** of the organisational state its person is entitled to see, so a
captain in a basement can open tonight's fixture, the roster and the lineup with no signal. The
cache is a projection with a `synced_at`; it is never the source of truth and it is never merged
into. Edits made against it are commands in a queue with the versions they saw. Two devices of one
captain are two writers, and the second one loses on reconnect and is told so.

The cache is filtered **server-side by the person's relations** (ADR-008) before it is sent. A team
admin's device holds the private interior of that team and the public front of others; nothing on
the device is a superset of what the server would show that person online.

### What this does not do

- It does not make organisational writes event-sourced. History that matters is kept by tables
  designed for it (rule 4), not by replaying a log.
- It does not resolve conflicts. A refused write is a person's decision. The one automatic merge
  is the trivial one: two commands that carry the same expected version and produce byte-identical
  rows are a duplicate, and the second is idempotent.
- It does not carry evidence. A lineup names who is expected to play; the match aggregate, opened
  from the fixture, is what records who did. `league_fixture.match_id` is set once and the
  evidence log takes over.

## Options considered

- **Last-write-wins with timestamps.** Rejected: it is exactly the silent overwrite the brief
  forbids, and device clocks are evidence, never order (ADR-004).
- **Event-source everything.** Rejected: a projector per organisational table, a replay cost per
  roster read, and invariants (per-device corroboration) that mean nothing for a rename. The
  competitive core needs it; the roster does not.
- **CRDTs for organisational state.** Rejected: automatic merge is the wrong answer when two admins
  disagree about who is playing on Thursday. The correct outcome is that one of them is told.
- **A managed sync service (Firestore, Realm, PowerSync).** Rejected on ADR-003 and ADR-007
  grounds: a second store, a second authorization domain, and a second delivery path for state.

## Consequences

- Phase B's command endpoint gains a second command family beside visits, with the same receipt
  table semantics (ADR-006 step 1) and the version rule above.
- Every organisational table Phase C adds — availability, lineup, admin task, submission — carries
  `row_version` and the trigger from the first migration that creates it. A table without one is a
  review defect.
- The client's cache schema is derived from the server's read models, not designed separately, so
  that the map, the Secretary inbox and the roster are three views of one cache.
- A conflict test is required at every gate: two writers, same expected version, one refused with
  the other's row returned, nothing overwritten. It is on the acceptance table for Phase C.

## Revisit trigger

A real organisational workflow where a refused write is the *wrong* outcome and an automatic merge
would have been right — availability marked by two devices of one player is the candidate — at
which point that table, and only that table, may adopt a documented merge rule.
