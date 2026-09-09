# THRØ API

The command path — the one route by which competitive evidence enters the system — plus the
migrations and property tests that hold it honest.

## Running the tests locally

```bash
# any Postgres 16; the tests create their own roles and schemas
export PGHOST=… PGPORT=… PGUSER=… PGDATABASE=…
bash test/schema_properties.sh
```

## Why these tests exist

The first version of this schema keyed events on `(stream_id, stream_seq)`. That reads sensibly and
is wrong: a match has **two independent authors**, and the difference between their accounts is the
most important signal in the product. Under that key, the second device syncing its own stream for
the same match was rejected outright by the unique constraint — so the corroboration case the whole
trust model rests on could not be stored at all.

Nobody noticed until it was executed against a real database. Hence: assertions about a database
belong in a database.

The suite covers the properties that would be unrecoverable if wrong:

- **Two devices can both author one match**, and each account stays separately readable.
- **A device cannot reuse its own sequence number** — the compare-and-swap that makes concurrent
  append safe without locks.
- **Append-only holds**, including `TRUNCATE`, and including on **a table created by a later
  migration** — which the original control did not cover, and which would have left the visit and
  dart tables freely mutable.
- **A replayed command cannot create a second receipt**, and the stored response comes back unchanged.
- **Cross-device order** is total under `(commit_xid, global_seq)`.
- **`darts_used` is unknown, not zero** — a visit cannot use zero darts, and a total above 180 is
  rejected at the boundary rather than trusted.

## Roles

`thro_owner` owns every object and is used only by migrations. The application roles own nothing —
which matters because a table's owner can `TRUNCATE` it regardless of what has been revoked, so
ownership separation is what makes the append-only guarantee real rather than decorative.


## The command handler

Everything the architecture claims about integrity converges on one function. A client's assertion
of an outcome is never trusted: the server rehydrates the match from **its own** event log,
revalidates through the same engine the client ran, and appends *its* result.

```
1  idempotency      a replay returns the stored response, including a stored refusal
2  sequence gap     refused with the expected value, never applied past
3  rehydrate        fold this device's own stream — accounts are never merged here
4  revalidate       the engine decides, not the client
5  append + receipt in ONE transaction
```

Step 5 is not a detail. Written as two transactions, a crash between them either double-applies a
visit or loses the receipt, and both corrupt a match.

### What the integration tests prove

Run against a real PostgreSQL, because a mocked event store cannot tell you that a replayed command
created a second event — which is exactly the failure that would corrupt a match.

| | |
|---|---|
| A replayed command is not re-applied, and creates no second event | |
| A sequence gap is refused with the expected value, and writes nothing | |
| An unreachable visit total is refused and **produces no evidence** | |
| A visit from the wrong player is refused | |
| A second device can author the same match, and each account stays separately readable | |
| **The server derives the outcome rather than trusting the client's claim** | |

14 properties, run end to end.

```bash
export PGHOST=… PGPORT=… PGUSER=… PGDATABASE=…
gradle test        # skips cleanly, rather than passing silently, when no database is configured
```

## The organisational graph

V014 adds Team, Venue, League, League season, Division, Tournament, Series and the dated
relationships between them, renames the bracket tie that was called `fixture`, and types every
entry (ADR-017). `Organisations` is the store-side API; `OrganisationTest` asserts against a real
PostgreSQL that a team keeps its identity across a venue move, that one venue hosts several teams,
that a player may belong to several teams, that membership and registration are independent, that
closed relationships are frozen and undeletable, that a league season is not a league and a
tournament is not a league (by schema shape), that entrants are exactly one kind, that a series
holds events and nothing else, that an approved policy is frozen and two approved versions never
overlap, that a fixture's schedule changes are logged and its outcomes appended, and that an
authorization relation is revoked rather than deleted.

`MigrationTest` migrates a database only as far as V013, populates it the way the world looked
then — free-text venue, bare competitor identifiers, a draw with byes, a check-in and its grant, an
authorization tuple — applies V014, and reads every row back. THRØ has never run, and the habit is
formed before it does.

## THRØ Secretary

V016 and `Secretary`: an administrator enters a sporting fact once — a player joined a team, a
fixture was played, a date was proposed — and THRØ derives the tasks that follow and carries the
submissions, with the evidence for every move. `SecretaryTest` proves 62 properties end to end,
most of them refusals: THRØ alone cannot submit, deliver-by-assertion, acknowledge or accept; the
team that sent a registration cannot accept it; a placeholder the captain typed in never leaves
THRØ; a minor's own consent does not open the gate; a draft policy registers nobody; a played
outcome that is voided supersedes the result card that carried it; a rearrangement is a proposal
the opponent answers and the league applies. The same engine, the same tables, for all three.

## Discovery

`Discovery.forPlayer` answers "what can I play next?" from facts, and every card carries the
reasons it appears. Eligibility is claimed only where THRØ can check it — open entry, singles,
entries still open, a place if a capacity was stated — and an event whose access THRØ cannot yet
check says so rather than being called eligible. Capacity and closing dates are what the organiser
declared; "not stated" is a value, never "unlimited". Nothing reads a person's location: "near you"
is the locality of the venue the player's team plays at. 16 properties.
