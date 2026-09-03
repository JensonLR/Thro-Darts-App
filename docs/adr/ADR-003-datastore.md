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

The document stores lose the two things this system most needs: the relational queries the
competitive graph is made of, and — decisively — the ability to **append an event, advance a
projection, and release an idempotency key in a single transaction**. ADR-004 and ADR-006 both depend
on that transaction; without it, a crash between two writes either double-applies a visit or loses
one, and both corrupt a match.

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

## Consequences

- One backup story, one restore drill, one connection pool.
- **A restore drill is scheduled, not assumed.** A backup never restored is not a backup.
- Scaling path, in order: vertical → read replicas for the rating harness and organiser reporting →
  partition the event log by month → only then consider a specialised store.

## Revisit trigger

Sustained write rate beyond ~2k events/sec; **or** projection rebuild exceeding 30 minutes; **or**
search relevance and typo tolerance becoming a genuine user complaint — in which case add a search
index, not a new primary store.
