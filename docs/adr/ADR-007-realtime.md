# ADR-007 — Realtime transport

**Status:** Accepted · **Date:** 2026-09-03

## Decision

**Server-sent events for server-to-client fan-out. Plain HTTPS POST to the single idempotent command
endpoint for every client-to-server state change. Push notifications for out-of-app alerts. No
WebSocket. No managed realtime service.**

## Rationale

The load-bearing reason is not performance. If scoring commands could travel over a socket there
would be **two command paths with different reliability semantics** — one online, one offline — and
the online one would be under-tested precisely because it usually works. Forcing all state change
through one HTTP command endpoint means **the offline path *is* the online path, just with a shorter
queue**. That eliminates a whole class of bug and makes ADR-006 testable.

A managed realtime service is rejected on correctness rather than cost: it becomes a second delivery
path for competitive truth, with its own authorization domain and ordering semantics. That is how you
end up with "the live feed said I won."

SSE also survives venue proxies and NAT better than WebSocket, needs no sticky sessions, and has
resumption built into the protocol rather than hand-rolled.

## Delivery semantics

- **Streams:** `match:{id}`, `event:{id}:public`, `event:{id}:queue`, `event:{id}:organiser`,
  `player:{id}:inbox`. Each carries a monotonic per-stream sequence.
- **Reconnect:** the event id is `{stream}:{seq}`; on reconnect the client sends the last id it saw
  and the server replays from the log. **Missed events are solved by replay, not by hope.**
- **Beyond the retained window:** the server emits a resync instruction and the client re-fetches a
  snapshot. Every client has exactly one defined recovery path.
- **Ordering:** total per stream. **No cross-stream ordering guarantee** — stated explicitly so
  nobody builds logic assuming it.
- **Duplicates:** at-least-once; clients deduplicate on `(stream, seq)` and every apply is idempotent.
- **Authorization:** re-authorised on privilege change, and **a stream never carries data the
  least-privileged subscriber may not see** — hence the hard split between the public and organiser
  streams, since the integrity surface carries dispute detail a spectator must never receive.
- **Backpressure:** bounded per-connection queue; on overflow, drop and resync rather than buffering
  unboundedly. **A slow consumer must never slow a writer.**
- **Internal fan-out** carries only `(stream, seq)` — never the event body. The notification is a hint
  to re-read, never the transport of truth, which is also why the horizontal scaling path needs no
  redesign.

## What is deliberately not built yet

No WebSocket. No presence or typing indicators. No collaborative live-merge scoring UI — ADR-006
makes it unnecessary. **No video or broadcast infrastructure**: the design's stream view is a
rendering of live competitive state, and must not be read as an ingest requirement. No live rating
ticker — rating movement is a discrete post-match record, not a stream.

## Consequences

- iOS has no built-in event-source client, so budget a small hand-rolled parser. Worth it against a
  socket stack.
- Zero marginal infrastructure cost; the same process and database serve it.

## Revisit trigger

A genuine need for low-latency bidirectional interaction (a referee console, live commentary
tooling); or concurrent connections approaching the single-process ceiling.
