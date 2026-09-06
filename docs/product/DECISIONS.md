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

---

## PD-003 — Appearance is the player's choice

**Founder decision, 2026-09-06.** Not delegated. Resolves `DESIGN_UNSPECIFIED.md` item 20.

### Decided

1. The app offers **System / Light / Dark**, on the You tab, stored on the device.
2. The choice governs every screen the export draws light: Home, Play, Match ready, Result, You,
   and the placeholder tabs.
3. **Match setup and Scoring stay dark** whatever the choice, as the export draws them. Extending the
   choice to them would need a light scoring screen the export does not have.

### Why

The founder ran the app twice on the same evening — once in dark mode, when the light screens
followed the phone and rendered dark, and once after they were pinned light — and asked for the
option to choose.

### The cost that must be stated plainly

The dark rendering of Home, ready, result and You is the token layer's dark values applied to layouts
the export draws only in light. No designer has looked at those screens in dark. The tokens carry a
dark value for every semantic colour, so the result is coherent, but it is the tokens' word and not a
designer's; the contrast matrix covers the pairs, not the compositions.

### How to reverse

Delete `Appearance` and the Settings control; the screens return to the export's light and dark as
drawn. Stored values are ignored, not migrated.

### Amendment, the same day

The founder extended the choice to **every screen, Match setup and Scoring included**, and moved the
control into a **Settings** screen reached from the You tab's settings action, as the export places
it. Point 3 above is void. The cost grows accordingly: a light scoring screen is the token layer's
light values on a screen the export draws only dark, unreviewed by design.

---

## PD-004 — A mis-keyed visit is corrected by retraction, never by edit

**Founder decision, 2026-09-06.** Not delegated.

### Decided

1. A player can **undo the last visit**. Undoing again walks one further back. The undo is a
   **retraction event appended to the journal** that supersedes the visit it strikes — the shape the
   server already gives corrections (`AccountedVisit.correctsSeq`): the struck row is never deleted,
   replay skips it, the statistics never see it, and an investigator reads both.
2. In a **local match** — two people, one phone — the undo needs **no one's approval**.
3. In an **online match**, a retraction is a **proposal until the opponent approves it**. That flow
   does not exist yet: there are no online matches in the client, and the server's evidence model
   has `VisitCorrected` (an official's correction) but no participant-proposed, opponent-approved
   retraction. It is built when sync is.
4. On the phone: the keypad's undo key clears a typed entry first; with nothing typed it proposes
   the undo, which the player confirms or keeps. The result screen offers the same, because the
   mis-key that ends a match is the one that most needs undoing; confirming reopens the match.

### Why

Mis-keys happen at every board. Without a correction path a wrong visit stands for the match, and
a self-reported result that cannot be corrected is worse evidence, not better.

### The cost that must be stated plainly

A self-reported result with retractions is still self-reported; the retraction changes what the
record says, not how far it can be trusted. The approval rule for online matches is the whole
difference between a correction and a rewrite, and it is not built.

### How to reverse

Remove the undo key's second meaning and the result screen's button; the journal's retraction rows
stay valid and replay keeps honouring them. Nothing in the record has to change.

---

## PD-005 — Busts and won legs are announced to both players

**Founder decision, 2026-09-06.** Not delegated.

### Decided

1. When a visit **busts**, or a **leg is won**, a card appears over the scoring screen and stays until
   someone taps **Continue** (or the scrim). Scoring is paused while it shows.
2. The bust card leads with the **score the player is left on**, in the sport hero face, in the
   error colour — the number the opponent needs to read from across the oche — with the engine's
   reason when it gives one beyond "below zero", and who throws now.
3. The leg card leads with the **legs as they now stand**, names the winner, and says who throws
   first in the next leg.
4. A **won match** is not announced this way: the result screen is the announcement.
5. Refusals stay a snackbar over the top of the scoring area, and clear on the next key.

### Why

The phone is one device between two players. A snackbar under the score is for the scorer; the
opponent, standing at the board, needs a moment and a large number.

### The cost that must be stated plainly

The export has no such card. It is composed from the export's Dialog surface (raised background,
card radius, hairline, elevation-3, 340 points wide) and its type roles; the scrim is the token
layer's `--color-scrim`, which the generator now emits. Modal behaviour is DESIGN_UNSPECIFIED item 16;
this card dismisses on its button or a tap on the scrim, traps nothing, and animates nothing.

### How to reverse

Drop the announcement state and the overlay; the bust and leg information return to the snackbar,
whose copy is still in `Copy`.

## PD-006 — The mark, the wordmark and the two type families are supplied, and the app carries them

**Decided by:** the founder, 2026-09-06 — "all the fonts logos & designs are all already attached &
relevant". **Recorded by:** engineering, the same day.

### Decided

1. The mark is a ring with a dart through it, lower-left to upper-right, both ends drawn to a point
   beyond the ring. The wordmark is THRØ with that mark as its Ø. The founder supplied both, in black
   and in the brand green, as images.
2. The app icon carries the mark alone, and the launch screen carries the mark with the wordmark
   28 points beneath it, both in chalk on the brand green — the one composition the export gives them,
   its Splash screen (mark 104 wide, wordmark 150 wide). The wordmark's letters are Archivo ExtraBold's
   own outlines, the face the supplied wordmark matches, with the Ø drawn from the mark's geometry at
   the heavier proportions the wordmark gives it; no master vector file is in the repository, so this
   is the brand's own face standing in for the founder's file until the file arrives.
3. Archivo and IBM Plex Sans Condensed are embedded: ten unmodified static faces, the weights the type
   roles use, with each family's licence text beside the files in the bundle. Both families are
   published under the SIL Open Font License, Version 1.1. Its grant, in its own words: "Permission is hereby granted, free of charge, to any person obtaining a copy of the Font Software, to use, study, copy, merge, embed, modify, redistribute, and sell modified and unmodified copies of the Font Software, subject to the following conditions:"
   "1) Neither the Font Software nor any of its individual components, in Original or Modified Versions, may be sold by itself." "2) Original or Modified Versions of the Font Software may be bundled, redistributed and/or sold with any software, provided that each copy contains the above copyright notice and this license." The faces are unmodified and are not sold by themselves.
4. A weight resolves to a named face, not to the system's guess: the type layer maps each role's
   weight to a PostScript name (`ThroFont.faceName`), and `apps/ios/check_fonts.py` holds that table
   equal to the shipped files, their licences and the launch assets on every push.

### Why

The app had shipped with the blank default icon and the system face, each recorded as waiting on the
founder. The founder supplied the artwork and said the fonts were settled. The Splash screen was the
only place the export composed the mark, so the icon and the launch screen follow it rather than a
colourway invented here.

### The cost that must be stated plainly

The mark in the repository is a geometric reconstruction measured from the supplied image — ring
0.364 and 0.250 of the frame, dart half-width 0.040, tips at 0.643 — not the founder's master file,
and the wordmark is set from Archivo ExtraBold's outlines on the judgement that the supplied wordmark
is that face: the forms match, and the letters in the supplied image run a few percent narrower, which
the founder should confirm or correct on the phone. Both should be replaced by the masters when they
are added under `docs/design/brand/`, and the icon and launch image regenerated from them. The dart-flight variant the founder also supplied is not used: the wordmark's Ø
has plain points and the icon follows the wordmark. IBM Plex Sans Condensed stops at Bold, so a heavy
sport role takes Bold. The licence is quoted, not interpreted: this register records what the text
grants and what the build does to meet its conditions, and a legal sign-off on THRØ's use remains the
founder's (OD-011).

### How to reverse

Delete `apps/ios/ThroDarts/Fonts` and the `UIAppFonts` entries; the type layer falls back to the
system face and Home says so. Delete the asset catalogue entries and the two build settings; the icon
returns to the default.

## PD-007 — The app opens on the throw

**Decided by:** the founder, 2026-09-06 — "I want something really beautiful, dynamic & cool for the
loading screen of the app using the logo … unique & maybe darts related … utterly beautiful & also
makes sense for this app", designed on a Claude Design canvas before it was built. **Recorded by:**
engineering, the same day.

### Decided

1. The static launch screen iOS shows before the app can draw is the brand field alone — `--thro-green`,
   nothing on it. The app's own first frames continue from it, so there is no jump.
2. The opening, Direction A of the design canvas "THRØ Launch Sequence": one chalk dart comes in from
   the lower left along the mark's 45° axis, loops once around the centre leaving the ring as its
   trail, hooks inward, cuts straight through the centre and lands. Its whole path is the mark. The
   ring flexes once and the field breathes lighter behind it; then the mark shrinks and rises to its
   place and THRØ appears beneath it, exactly the export's Splash composition (mark 104 wide, wordmark
   150 wide, the tagline under), and Home fades up.
3. Timings are the spec board's: field to 150 ms, approach to 300, loop to 850, strike to 1030, impact
   to 1150, name to 1600, hold to 2000, cross-fade to 2300. Easings are the token layer's own —
   `--motion-easing-throw` for the strike, `--motion-easing-impact` for the landing,
   `--motion-easing-resolve` for the settle — and the flex is twice `--motion-scale-impact`.
4. Cold launch only; never on return from the background. A tap anywhere skips to Home. With Reduce
   Motion on, the finished composition shows from the first frame and fades. No sound. No progress
   indicator: nothing is loading, and the opening is not allowed to pretend otherwise.
5. Two other directions were sketched beside it on the canvas — B, a scorer's chalk hand drawing the
   ring; C, the ring as a distant target rushing up from the oche — with their costs stated, so the
   founder chose from real alternatives. A is built; B and C remain on the canvas.

### Why

The founder asked for it, and asked for it to be designed rather than improvised. The mark is a dart
frozen mid-throw; showing the throw is the one animation that is about this logo and nothing else.

### The cost that must be stated plainly

Apple's guidance is that a launch screen be the first screen of the app, and an opening of any length
is a choice against that guidance; this one is 2.3 seconds, skippable, once per cold launch. The
chalk-dart loop is physically impossible and meant as a drawn gesture, not a simulation. The
sequence is drawn with the phone's own frames, so what the founder sees is the first time anyone has;
the storyboard is six still frames, and motion judged from stills is a judgement to confirm on the
device. The token generator had been emitting every motion token as zero (the reduced-motion block
overwrote them); that is fixed in the same change, which is why the easings could be the tokens'.

### How to reverse

Delete `opening` from the root view and `LaunchSequence.swift`; the static field remains and Home is
the first frame. To restore the mark on the static launch screen, add an image set back to
`UILaunchScreen`.
