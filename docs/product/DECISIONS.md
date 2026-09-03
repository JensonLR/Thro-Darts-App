# THRØ — Production Decision Register

Decisions that have been **made**. Precedence rank 2: below an explicit current founder decision,
above the design system on matters of product behaviour.

Each entry records what was decided, why, what it costs, and **how to reverse it**. A decision taken
on delegated authority that cannot be cheaply reversed would be a bad decision, so the reversal path
is part of the record.

---

## PD-001 — Statistics honesty, and capturing darts-used

**Resolves blocker B1.** Taken on delegated authority. **Reversible via configuration and copy.**

### Decided

1. **Capture `dartsUsed ∈ {1,2,3}` on the leg-winning visit only.** One tap per leg, roughly five per
   match. It is optional: absent means unknown, never inferred.
2. **The following are exact and ship as exact:** 180s, 140+ and 100+ counts, highest checkout, leg
   win rate, deciding-leg percentage, and — with `dartsUsed` — 3-dart average and best leg in darts.
3. **First 9 average ships with a disclosed denominator**, excluding legs that did not reach nine
   darts, and the exclusion is stated rather than hidden.
4. **Checkout % is not shipped under that name.** It is replaced by **finish rate from a checkable
   position**: legs won on the first visit that opened on a finishable number, over all such
   opportunities. Exactly computable from visit totals, genuinely informative, and a different
   quantity — so it carries a different name and a different API field.
5. **Doubles hit rate is withheld** until a dart-level capture mode exists. It is not approximated.
6. **Every statistic crosses the API as `{value, basis, evidenceLevel, sampleSize}`** where basis is
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

One extra tap per leg at the board, and a `Stat` variant that can render an unavailable value (a
design commission). Two figures currently on the approved surfaces change: one is renamed, one is
withheld. The **broadcast overlay** is affected, since it carries both for both players.

### How to reverse

Points 4 and 5 are copy and API-field decisions with no schema consequence. Point 1 is a nullable
column that exists whether or not the client prompts for it — turning the prompt off is a flag.
Nothing here requires a migration to undo.

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
