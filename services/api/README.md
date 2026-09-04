# THRØ API — schema

Migrations and the property tests that hold them honest.

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
