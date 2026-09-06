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
