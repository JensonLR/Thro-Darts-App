# Architecture Decision Records

Each record states the context, the options considered, the decision, its consequences, and the
**revisit trigger** — the observation that should reopen it. A decision with no revisit trigger is
a guess wearing a suit.

| # | Decision | Status |
|---|---|---|
| [001](ADR-001-backend-runtime.md) | Backend runtime and language | Accepted |
| [002](ADR-002-shared-scoring-domain.md) | Shared deterministic scoring domain | **Deferred, with criteria** |
| [003](ADR-003-datastore.md) | Primary datastore | Accepted |
| [004](ADR-004-competitive-event-model.md) | Competitive event model | Accepted |
| [005](ADR-005-module-boundaries.md) | Module boundaries and data ownership | Accepted |
| [006](ADR-006-offline-sync.md) | Offline sync protocol and scoring authority | Accepted |
| [007](ADR-007-realtime.md) | Realtime transport | Accepted |
| [008](ADR-008-authentication-authorization.md) | Authentication and authorization | Accepted |
| [009](ADR-009-rating-boundary.md) | Rating service boundary | Accepted |
| [010](ADR-010-design-token-pipeline.md) | Design token pipeline | Accepted |
| [011](ADR-011-deployment-topology.md) | Deployment topology and environments | Accepted |
| [012](ADR-012-competition-model.md) | Competition model: competitor, competition, fixture | Accepted |

## Standing constraint on all of them

Founder decisions **B1** (which statistics THRØ shows, and whether `dartsUsed` is captured) and
**B2** (whether a unilateral self-report moves rating) are open. Every decision here is required to
keep **both answers reachable without a data migration**. Where that costs something, the cost is
stated in the record.
