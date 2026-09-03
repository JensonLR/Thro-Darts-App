# ADR-009 — Rating service boundary

**Status:** Accepted · **Date:** 2026-09-03

## Context

The rating model is explicitly undecided and must be chosen scientifically later. The architecture's
job is to make that possible without a rewrite — and to stop an arbitrary rating being shipped to
fill the UI.

The approved design supplies the decisive constraint itself: the organiser dispute screen states
*"Ratings are recalculated from the corrected result."*

## Decision

**Rating is a versioned, replayable projection over eligible evidence. It is never an incrementally
mutated number, and the rating module never writes to match or trust.**

```
rating.snapshot(player_id, model_id, model_version, parameter_hash, scale_epoch,
                as_of_evidence_seq, rating, confidence, matches_counted, computed_at, published bool)
```

Four consequences follow from that row shape.

**Corrections are implementable.** An incrementally updated rating cannot honour the design's own
sentence, because reversing one match must ripple to every opponent downstream of it. A projection
can simply be recomputed.

**Multiple models run concurrently, exactly one published.** This is the single change that keeps the
algorithm decision genuinely open: candidates run in shadow against live evidence while nothing is
shown to players. Without it we would be forced either to ship an unvalidated model or to migrate the
rating store later.

**The scale is anchored.** The design uses absolute rating values as fixed semantic landmarks —
pathway thresholds, field averages, division averages. An unanchored model inflates or deflates and
every landmark silently rots, so `scale_epoch` is recorded on every snapshot and recentring is an
explicit, visible event.

**Explanations are frozen at rating time, not reconstructed on read.** Persist the causing evidence,
**both participants' published ratings and confidence at that instant**, competition, round, format,
predicted probability, realised outcome, the eligibility decision, the delta, and the model version.
Ratings drift; a regenerated explanation would quote a past opponent at their present rating and be
false.

## Four separate concepts, four separate stores

Rating, Form, Rank and Confidence are distinct in domain, storage, API and UI, and none is computed
from another's cache. Rank is never a stored attribute of a player and **never a model input**, which
would be circular. Inactivity **raises uncertainty; it never lowers the estimate** — the published
number holds, confidence falls, and a player may return to "Rating establishing" with their last
value retained internally.

## Eligibility

Eligibility is an **orthogonal axis**, not a value of the provenance enum, carried as its own events
with reason codes and actors. Overloading the enum would overwrite the pre-quarantine provenance
irrecoverably.

The eligibility *rule* is **configurable policy**, because founder decision B2 — whether a unilateral
self-report moves rating — is open, and the answer must not require a migration. Quarantine retains
the result, its provenance, its bracket place and its visibility, while suspending rating
eligibility, form contribution, rank denominators and cohort averages. It is reversible, and reversal
re-derives with a **visible ledger line**.

**Ledger invariant:** the per-match ledger must reconcile exactly to the net change over the same
period. Any non-match adjustment — recomputation, correction, decay, eligibility change — appears as
its own visible line and is never silently absorbed.

## What ships first

**Every player provisional.** The design already renders a provisional rating as an em dash with a
"Rating establishing" tag, so the entire flagship slice can ship with no rating integer published,
candidates running in shadow, and the confidence surface honestly saying the system is still learning.
That is not a placeholder — it is the truthful state of the world at launch.

The research laboratory ([`../product/RATING_HARNESS.md`](../product/RATING_HARNESS.md)) is built
**during** the slice, not promised after it. A laboratory deferred is a laboratory never built, and by
the time anyone wants it the schema is already wrong.

## Revisit trigger

A model passing the harness gates on held-out real data from two structurally different pools **plus**
a prospective shadow period — at which point publication becomes a product decision, not an
engineering one.
