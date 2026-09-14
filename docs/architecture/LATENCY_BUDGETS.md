# THRØ — Performance budgets

Budgets, not aspirations: each is measurable, and the scoring figures are derived from the approved
design's own motion tokens rather than invented.

Measure at P50/P95/P99 on named low-end reference devices — an iPhone SE-class device and a
~£150 A-series Android. Pub players do not carry flagships; benchmarking on a Pro model is
self-deception.

## Scoring — the path that must never be network-bound

| Path | Budget | Basis |
|---|---|---|
| Key press → digit visible in the entry field | **P99 ≤ 80 ms** | `--motion-duration-instant: 80ms` |
| Visit committed → remaining score and turn indicator updated | P95 ≤ 100 ms, P99 ≤ 150 ms | includes durable acknowledgement |
| Event flushed to durable storage | P95 ≤ 20 ms, P99 ≤ 50 ms | **must be measured, not assumed** |
| Match ready → scoring, first meaningful paint | P95 ≤ 300 ms | under `--motion-duration-emphasis: 340ms`, so the transition covers it |
| Cold start → interactive Home | P95 ≤ 1500 ms | |
| Cold start → resumable in-progress match | P95 ≤ 2000 ms | snapshotting is what holds this as journals grow |

**The ordering rule is not negotiable:** the event is flushed to the journal *before* the visit is
acknowledged. Paint optimistically first; acknowledge only once durable. If durability P99 breaches
budget, the fallback is a raw append-only write-ahead file as the durability primitive, with the
database demoted to a queryable projection.

**Enforce network-independence structurally.** The scoring module must have no compile-time
dependency on the network layer, checked in CI via the module dependency graph. This is the only
durable guarantee; discipline alone will fail.

## Backend

| Path | Budget |
|---|---|
| Command endpoint (validate, append, receipt) | P95 ≤ 150 ms |
| Read of a match aggregate | P95 ≤ 100 ms |
| Realtime propagation, server receipt → subscriber delivery | P95 ≤ 500 ms |
| Projection lag behind the write watermark | P95 ≤ 2 s |
| Draw generation for a 128 bracket | ≤ 2 s |

## What must be instrumented from the first release

Scoring input latency and durability latency as distributions, not averages; sync queue depth and
age; command rejection rate by reason code; **engine divergence between client and server**, which
should page someone; projection lag; and realtime reconnect rate. Competitive events carry
correlation IDs.
