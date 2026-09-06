# ADR-003 — Primary datastore

**Status:** Accepted · **Date:** 2026-09-03

## Context

The system needs an append-oriented competitive event log *and* a genuinely relational competitive
graph (brackets, league tables, head-to-head, rating histories), plus read models, search and a job
queue. Realistic volume is on the order of tens of thousands of events per tournament day.

## Options

- **Single managed Postgres** — one transactional boundary for everything.
- **Postgres plus a dedicated event store** — purpose-built append semantics, at the cost of a second
  durability domain and a second restore story.
- **Postgres plus Kafka** — durable log and fan-out, same costs, plus operational weight.
- **Document/serverless stores (Firestore, DynamoDB)** — managed scale and built-in realtime.
- **Distributed SQL (CockroachDB, Yugabyte)** — geo-distribution.

## Decision

**One managed Postgres holding the event log, competitive graph, read models, full-text search and
job queue. SQLite on the client. Object storage for exports and attachments. No Redis, no Kafka, no
separate search cluster on day one.**

## Rationale

The document stores lose the thing this system most needs: **the relational queries the competitive
graph is made of** — brackets, standings, head-to-head, rating histories over time.

*A correction to revision 1.* It also claimed the discriminator was appending an event, advancing a
projection and releasing an idempotency key in one transaction. **That is not what the architecture
does**: ADR-004 puts only the event and its receipt in the transaction, and projections are
explicitly asynchronous. Two rows written atomically is available in the document stores too, so the
stated discriminator did not discriminate. The decision stands on the relational argument, which is
sound and sufficient; the transactional argument as written was wrong.

Kafka and a dedicated event store break the same transaction and add a second backup-and-restore
story. At our volume Postgres is orders of magnitude from any limit. Distributed SQL solves a
geo-distribution problem we do not have.

For a one-operator team, **a single transactional boundary is worth more than any throughput
advantage**. Every specialised store added is another failure mode to understand personally at 11pm
during a tournament.

## The strongest argument against

JSONB event payloads are schemaless, so Postgres will happily persist a malformed event forever — and
event-sourced systems are unforgiving of bad writes because you cannot go back and fix them.
Mitigation is discipline plus CI: a payload round-trip test per event type, an explicit
`schema_version` on every event, and an upcast chain. Second: full replay to rebuild projections gets
slow as history grows, mitigated by per-stream snapshots and per-module rebuilds rather than global
ones.

## Amendment — bulk and research writes are isolated

ADR-004's projection watermark means **any long-running write transaction stalls every projector and
the realtime dispatcher**, verified empirically. The rating harness ingests historical archives, which
is exactly such a write. Therefore **harness and bulk-ingest writes run against a separate database**
— not a read replica, which cannot take writes. This is a correction to revision 1's "everything on
one Postgres" framing, which would have frozen the live scoreboard during an archive import.

## Consequences

- One backup story for the primary — though **not one durability domain overall**: object storage,
  the append-only audit chain and the clients' own journals are separate. A restore must state its
  ordering, and the audit chain restarts with a recorded discontinuity rather than silently.
- One restore drill. Per-module database roles require per-module pools or role-switching; that is
  the real enforcement of the no-cross-schema-join rule, since a compile-time wall does not constrain
  SQL text.
- **A restore drill is scheduled, not assumed.** A backup never restored is not a backup.
- Scaling path, in order: vertical → read replicas for the rating harness and organiser reporting →
  partition the event log by month → only then consider a specialised store.

## Revisit trigger

Sustained write rate beyond ~2k events/sec; **or** projection rebuild exceeding 30 minutes; **or**
search relevance and typo tolerance becoming a genuine user complaint — in which case add a search
index, not a new primary store.
