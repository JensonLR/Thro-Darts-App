# thro-rating

Rating as a versioned, replayable projection. Pure Kotlin, no dependencies, no I/O.

**The rating model is not decided.** OD-001 is open and must be settled by evidence from the research
laboratory. This module is the machinery that keeps that decision genuinely open rather than
nominally open — and one test asserts that no model in this repository claims to be validated. If
that test ever fails, someone has decided OD-001 by writing `validated = true` instead of by
producing evidence.

## Why a projection

The approved organiser dispute screen states *"Ratings are recalculated from the corrected result."*
An incrementally mutated number cannot honour that sentence, because reversing one match must ripple
to every opponent downstream of it. A projection is simply recomputed.

## The watermark is a pair

`(commit_xid, global_seq)` — never a scalar. `global_seq` alone is assigned at insert rather than at
commit, so a reader above a high-water mark silently skips rows from transactions that started
earlier and committed later. Per-device sequences are not comparable across devices at all.
Reproducibility is the primary key of the whole rating programme, so both travel everywhere.

A replay is materialised **as of a stated watermark**, never "as of now": the projections its
evidence is assembled from lag independently, so "now" is not a reproducible input.

## Properties held

- **Reproducible.** The same watermark and model produce the same result regardless of the order
  rows arrive in.
- **Exactly one model published.** Enforced in the domain and again by the database, where
  `rating.published_model` is a singleton table. Two live models make "a player's rating"
  ambiguous.
- **Nothing unvalidated can be published**, and the refusal names OD-001.
- **The ledger reconciles exactly.** A test builds a deliberately dishonest model that moves a
  rating by 10 while declaring 6, and asserts the invariant catches the missing 4. Any adjustment
  that is not a match — recomputation, correction, decay, an eligibility change — must appear as
  its own visible line.
- **Explanations are frozen at rating time.** Ratings drift, so a regenerated explanation would
  quote a past opponent at their present rating and be false.
- **Rank is never a model input.** A rating computed from rank and a rank computed from rating is a
  loop.

## What ships first

Every player provisional. `ProvisionalModel` computes no rating at all — confidence moves, because
"how much has this player been observed" is answerable without a model, but the rating is null and
renders as the em dash the design already draws beside "Rating establishing".

That is not a placeholder. It is the truthful state of the world at launch, and the schema enforces
it: `rating.published_model` is empty, and a published snapshot without an actual rating is refused.

```bash
gradle -p packages/rating test
```
