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
| [013](ADR-013-migrations.md) | Migrations and schema evolution | Accepted |
| [014](ADR-014-configuration-and-policy.md) | Configuration and policy versioning | Accepted |
| [015](ADR-015-notifications.md) | Notifications | Accepted |
| [016](ADR-016-local-history-and-the-claim.md) | A local history, and how it is claimed by an account later | Accepted |
| [017](ADR-017-organisational-vocabulary.md) | Organisational vocabulary: Team, Venue, League, Tournament, Series — Club is not an entity (founder, 2026-09-09) | Accepted |
| [018](ADR-018-organisational-state.md) | Organisational state: server-authoritative versioned rows beside the evidence log; refused, never overwritten | Accepted |

## Standing constraint on all of them

Founder decisions **B1** (which statistics THRØ shows, and whether `dartsUsed` is captured) and
**B2** (whether a unilateral self-report moves rating) have both since been **decided** — see PD-001
and PD-002 in [`../product/DECISIONS.md`](../product/DECISIONS.md). **B3** (the participant
attestation and error surfaces) and **B4** (the authentication surface) remain open, and are design
commissions rather than decisions engineering may take. Every decision here is required to
keep **both answers reachable without a data migration**. Where that costs something, the cost is
stated in the record.
