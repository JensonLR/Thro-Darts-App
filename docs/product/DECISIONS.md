# THRØ — Production Decision Register

Decisions that have been **made**. Precedence rank 2: below an explicit current founder decision,
above the design system on matters of product behaviour.

Each entry records what was decided, why, what it costs, and **how to reverse it**. A decision taken
on delegated authority that cannot be cheaply reversed would be a bad decision, so the reversal path
is part of the record.

---

## PD-001 — Statistics honesty, and capturing darts at a double

> **Revised on founder correction.** The first version asked for the dart count **only on a visit
> that won a leg**, and concluded from that that checkout percentage was permanently uncomputable.
> That conclusion was wrong, and it was wrong because the capture rule was too narrow: a player who
> is on a finish and *misses* has still thrown darts at a double. Asking only on a successful
> checkout never records those attempts, so the denominator is missing — not unknowable.
>
> Every premium darts scorer asks on the miss as well. Corrected below.

**Resolves blocker B1.** Taken on delegated authority. **Reversible via configuration and copy.**

### Decided

1. **Capture darts at a double on every visit that *began* on a finish** — whether or not it ended in
   one. The trigger is verified rather than assumed: enumeration shows that "a double could have
   been thrown at during this visit" is exactly equivalent to "the remaining at the start of the
   visit is a checkout number", with no exceptions across the whole range.
2. **Capture `dartsUsed ∈ {1,2,3}` additionally on a visit that wins the leg**, since that is the
   only visit whose total dart count is ambiguous. The two are independent: finishing 100 as
   T20 then D20 is two darts with one at a double; missing twice first is three darts with three at
   a double. Neither number implies the other.

   Both are optional. Absent means **unknown** — never zero, never inferred.
3. **The following are exact and ship as exact:** 180s, 140+ and 100+ counts, highest checkout, leg
   win rate, deciding-leg percentage, and — with `dartsUsed` — 3-dart average and best leg in darts.
4. **First 9 average ships with a disclosed denominator**, excluding legs that did not reach nine
   darts, and the exclusion is stated rather than hidden.
5. **Checkout percentage ships, and is exact** where the attempts were recorded — doubles hit over
   doubles thrown at, the broadcast definition. Under double-out every leg is won on a double, so
   hits equal legs won and attempts are the only unknown. Where some checkable visit did not record
   its attempts the figure is **bounded, not guessed**: unrecorded attempts can only lower the true
   percentage, so the recorded figure is its upper bound.
6. **Doubles hit rate is the same quantity** under its other name, and ships on the same basis.
7. **Finish rate from a checkable position is retained as a separate measure** — legs won over
   visits that opened on a finish. It is a *visit-level* measure where checkout percentage is
   dart-level; they are both real and they are not the same number.
8. **Every statistic crosses the API as `{value, basis, evidenceLevel, sampleSize}`** where basis is
   `EXACT`, `BOUNDED` or `UNAVAILABLE`. A statistic that cannot be computed says so.

### Why

THRØ never invents dart-level evidence. From visit totals, checkout % and doubles hit rate are not
merely imprecise — they are **not computable at all**, because nothing distinguishes one dart thrown
at a double from three. Displaying them would mean fabricating dart-level evidence and then feeding
it into ratings, league tables and public profiles.

`dartsUsed` is the minimum honest addition: the leg-winning visit is the *only* visit whose dart count
is ambiguous, so one field removes the ambiguity entirely and converts the 3-dart average from ~13%
biased to exact. Every specialist who examined this converged on it independently.

The design has already reached the honest framing itself — the Coach surface says *"you convert 31%
**of visits**"*. Point 4 generalises that phrasing rather than inventing a metric.

### What it costs

More taps than the first version: one question on every visit that opens on a finish, and two on a
visit that wins the leg. In a typical leg that is one or two extra prompts, not five.

**Whether that breaks the rhythm at a real board is the open question**, and it is the main thing
the playtest harness exists to answer. If it does, the fallback is not to guess — it is to record
fewer attempts and let the figure report as bounded, which the statistics layer already does.

A `Stat` variant that can render bounded and unavailable values is still required (a design
commission). No figure is now withheld outright.

### How to reverse

Both captured fields are nullable columns that exist whether or not the client prompts for them, so
turning either prompt off is a capability flag (ADR-014) and not a migration. Statistics degrade
from exact to bounded to unavailable as the evidence thins, which is the behaviour the layer was
built for. Nothing here requires a migration to undo.

---

## PD-002 — Rating eligibility floor

**Resolves blocker B2.** Taken on delegated authority. **Reversible by changing one policy value.**

### Decided

**The minimum attestation for rating eligibility is `participant-confirmed`.** One player's unilateral
claim never moves either player's rating.

Self-reported results **still count** in every other sense: they progress the bracket, appear in the
competition record, appear on both players' match histories, and are shown with honest provenance.
They simply do not move the number.

Additionally, **`outcome_type` must be `played`** — walkovers, awards, forfeits and voids are
recorded but never rate.

### Why

This is the highest-leverage anti-gaming decision available and it costs nothing structurally. It
defeats fabricated results and unilateral inflation outright, without any statistical detection. The
design already supplies the intended remedy in its own copy: assigning a venue scorer raises a whole
round to participant-confirmed or better.

### The consequence that must be stated plainly

**A match played entirely offline is self-reported until it syncs and the opponent confirms.** So this
decision means offline play is not rateable *until confirmation arrives* — in a product whose premise
is that venues have poor signal.

That is a real cost and it is accepted for a specific reason: the alternative is that a single device,
with no corroboration, can move two players' competitive standing. That is precisely the property an
evidence platform cannot have. Confirmation is asynchronous — it can arrive hours later, when either
player reaches signal — so the practical effect is a delay in rating movement, **not a loss of the
result**.

Three mitigations are in scope for the first release: the opponent's device confirms per leg as soon
as either device reaches a network; an organiser-assigned venue scorer raises an entire round without
either player acting; and the result itself is never at risk, only its rating eligibility.

### How to reverse

The eligibility rule is configurable policy evaluated over a stored provenance record, not a hardcoded
predicate and not a stored enum. Lowering the floor to `self-reported`, or weighting self-reported
results at a reduced factor rather than excluding them, is a policy change plus a rating recomputation
— which the architecture supports by design, because rating is a replayable projection. **No migration,
no data loss, and historical ratings can be re-derived under the new rule.**

### Amendment — the participant confirmation surface does not exist

**Added after hostile architecture review, which was right to catch this.**

PD-002 requires evidence to reach `participant-confirmed`. Verified by reading all 33 participant
screens: **there is no way for a player to confirm a result.** The match result screen's only action
is "Back to tournament" — no confirm, no attest, no dispute. The "confirm" affordances that do exist
are for *match-ready* ("Both players must confirm before scoring opens") and for *check-in*, neither
of which attests to a result.

The only attestation surface in the entire design is the **organiser's** per-leg `Confirmed` column,
which reads from an event no participant client can author.

**What this changes.** The decision stands, but its first-release path is different from what the
record implied:

- **Organiser-confirmed is authorable today.** The organiser kit has result verification and a bulk
  "Confirm all THRØ-recorded" action. So in an organised competition — which is the flagship slice —
  evidence reaches the eligibility floor through the organiser, without any new design.
- **Player-to-player confirmation is not authorable at all** until the surface is designed. So a
  casual or league match with no organiser present has no route to eligibility in the first release.

**Consequence, stated plainly:** with the design as it stands, results outside an organised
competition would not rate. That is a narrower product than "THRØ rates your darts", and it is a
direct argument for commissioning the participant attestation surface early rather than treating it
as a later refinement.

**Added to the design commissions** as the item that gates this decision's full value.

### Escalate back to the founder if

Field evidence shows a material share of competitive matches never receiving a second confirmation.
That would mean the floor is costing real competitive history rather than merely delaying it, and the
trade-off should be re-taken with data.
