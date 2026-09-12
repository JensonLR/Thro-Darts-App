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

### Amendment, the same day — the founder's first look, and the second version

The founder watched the first version on the phone: "too fast & looks very generic & basic / faulty
in animation, ugly design & overlaps, doesn't look like a dart … needs to feel fluid & dynamic with
sound when sound is activated … go big or go home". Each point was true, and each is answered by a
change of choreography, not of numbers:

1. **A dart that is a dart.** Needle, knurled barrel, shaft, flights, drawn as parts. It rolls in
   flight (the flights foreshorten and the far pair shows), grows as it closes, trails a streak, and
   comes in on an arc that straightens onto the mark's axis, accelerating into the board on the token
   layer's exit curve. Its length is the mark's bar, tip to tail, so the landed dart lies exactly where
   the bar will be.
2. **The strike first; the ring as its echo.** The loop-then-strike path forced two right-angle
   corners — that was the faulty motion. Now: thud, a heavy haptic, dust thrown forward and falling,
   a shockwave, a breath of lighter green; the flights quiver and settle (a damped 6.5 Hz swing about
   the point, decaying over a quarter second), which is the one motion everyone knows from a board.
   Then the ring blooms clockwise from where the dart crossed it, glowing, with chalk grain fixed to
   it, and pulses once as it closes.
3. **Slower.** Field to 350 ms, flight to 1250, the strike's beat to 1650, the ring to 2450, the
   resolve to 3350, a hold to 4200, the cross-fade to 4600. The letters wait until the mark has shrunk
   clear of the word band, so nothing overlaps. Skippable by a tap at any moment.
4. **Sound.** Three sounds synthesised from the sequence's own physics — a whoosh whose centre rises
   as the dart closes and cuts at impact, a thud with a bright click, two low resonances and fibre
   noise, and a chalk scratch gated like grit — played through the ambient audio session, so the phone's
   silent switch silences them and other audio keeps playing. A Sound switch and a Haptic switch under
   Settings → Opening, both on by default, and *Play the opening again* there so it can be judged
   without relaunching. Reduce Motion plays nothing.
5. The letters T, H, R rise into place one after another; the dart's detail dissolves into the plain
   bar as the mark shrinks to its place; the tagline tracks in.

The cost, stated plainly: the sounds are synthesised, physically shaped and mixed for the sequence,
and they are placeholders in the honest sense — recorded foley under the same filenames replaces them
without a code change. A haptic on the opening is a decision taken here; haptics on the scoring keypad
remain the founder's open decision. The motion has again been judged from stills and arithmetic; the
phone is where it moves.

### Amendment, the next day — the founder's second look, and the third version

The founder watched the second version on the phone: "Thats better but I think you can improve &
upgrade it even further. its the first thing people will see opening the app so it needs to be utterly
beautiful & perfect, keep going until there is no more to work on, dont just be a yes man. harshly
critique it. no regressions always improvements." The critique was made against the frame function
and against frames rendered from a line-for-line port of it, at full size, which is where three of the
faults below were first seen. Each point, and what it became:

1. **The strike hit nothing.** The dart stopped in empty green; there was no target for the eye before
   the throw and nothing for the point to cut. A faint chalk ring now waits on the field from the first
   half-second as the target. The point cuts it twice on the way in, at the lower left and the upper
   right; each cut puffs chalk off the line and lights it where it was cut, and the bloom thickens from
   exactly those two places, both ways round, until the four strokes meet and the ring is whole.
2. **The dart was rigid at impact.** It rotated about its point like a stick. Now the barrel stops
   dead; the shaft pivots where it meets the barrel and the flights pivot again where they meet the
   shaft, a beat behind (8 Hz, decaying over a fifth of a second); and the whole dart squashes 3.5%
   along its length for the first four frames.
3. **Nothing else reacted.** The frame now shakes with the strike, mostly along the line of the throw,
   four points dying in a fifth of a second.
4. **The streak was wrong.** The ghosts trailed by a fixed distance, so the blur was the same at any
   speed and vanished the instant the dart stopped. They now trail by one, two and three frames of
   time: far apart at speed, bunched when slow, and catching the dart up in the frames after it stops.
5. **The roll was tied to distance**, so the flights flickered fastest in the last frames. It is now a
   steady 1.6 turns over the flight.
6. **The dart became the bar by a plain cross-fade.** It now folds: the flights fold flat, every part
   narrows to the bar's width, the shaft runs on to the tail and tapers to the bar's point, and only
   then does the bar take over.
7. **The bloom looked machined** — round-capped strokes with a dotted grain, which at full size read as
   glowing sausages with spots. It is now four strokes of chalk that thin to a point at their leading
   ends, as chalk thins where the stick lifts; the grain is gone; the glow fades through the resolve
   so the finished mark is crisp. The lit cuts, first drawn at the ring's full width, were near-circles
   sitting exactly where the dart's body passed and read as glitches; they are thin lengths of the line.
8. **The Ø just appeared** while the three letters rose. Its ring now draws itself from the top,
   clockwise, as the big ring bloomed, and its bar follows.
9. **The R was dimmer than the T.** The letters' stagger ran past the end of the resolve, so the third
   letter reached 87% opacity and no more — a fault in the build the founder was looking at. The
   stagger now fits inside the resolve.
10. **The first frame did not match the launch screen.** The vignette was already part-drawn, a small
    jump. It fades in with the target, so the first frame is the launch screen's flat green.
11. **Touch.** A light haptic tick at each cut, then the heavy one at the strike: tick, tick, thud, in
    the last third of a second of the flight (at 1044 and 1252 ms on the nominal layout). The cut times come from the flight path's own geometry.

Also: the barrel and shaft carry a shadow side for roundness; a fixed scatter of faint chalk dust
settles on the field; the letters keep the face's kerning; and Reduce Motion is now truly still — the
strike's flash, its shockwave, the dust and the ring's pulse had been running from their own clocks
with every segment at zero length, and now run only when the timeline is animated.

Timing: field and target to 450 ms, flight to 1350, the strike's beat to 1750, the ring to 2450, the
resolve to 3350, the hold to 4200, the cross-fade to 4600 — the same total, a tenth of a second moved
from the ring to the target. The dart's growth from 55% stays as it was, because the founder called
the second version better and that is part of what they saw. Eleven tests hold the timeline, the cues
(tick, tick, thud, in order and before the strike), the easings and the flight curve's inverse, the
mark's geometry, the path's two cuts, the chalk stroke's taper and the fold.

The cost, again plainly: still a choice against Apple's launch-screen guidance, still 4.6 seconds,
still skippable. The browser port used to see the frames is a scratch tool, not part of the app; it
shares the maths but not the renderer, so the phone is still where the motion is judged.

### Amendment, the same day — the founder's third look, and the fourth version

The founder watched the third version and gave two directions, both decisions about what the opening
is. First: "the final screen before loading shows the logo then name under with logo as the O which is
correct but think we need a cool transition for the text with the logo as the O to be the transformation
after the darts been. think the dart should look like its been thrown and is travelling distance via
the screen not just coming from corner of the screen, thrown cinematically and reaching its destination
then transitioning, keep the cinematic camera angles in mind, make it utterly beautiful, incredibly
precise & entirely unique to the app and brand." Then, on the plan for that: "I dont think we need that
bit where it goes from the full name to logo above full name under. We should have it just got into the
full text logo. Then show they sub text then load the app main homepage. dart should really feel like
its been thrown and is flying then hit with purpose the weird circle bit is a bit basic & boring."

**Decided by the founder:**

1. **The opening ends on the name.** THRØ across the width, with the mark as its Ø, then the tagline
   beneath it, then Home. The export's Splash composition — the mark above a smaller wordmark — is no
   longer the opening's last frame; the mark's only place at the end is as the Ø. (Home and the rest of
   the app are unchanged.)
2. **No target drawn before the throw.** The faint chalk ring that waited on the field, and the cuts
   through it, are gone — "the weird circle bit". The dart's destination is a pool of light on the wall.
3. **The throw is a shot, not an entrance.** The dart must be seen to fly a distance, cinematically, and
   hit with purpose.

**How the fourth version does it:**

- **A tracking shot.** The camera flies with the dart. The dart holds in the middle of the frame in
  profile — it slides in over the first quarter of the flight as the camera catches it, bobs once across
  its line, flies nose-up (5°) and flattens onto the axis as it arrives, and rolls at a steady 1.6 turns
  — while the world comes to it. The chalk dust settled on the wall streams past, each speck a streak in
  proportion to the camera's speed, and stops dead at the strike. The camera rolls from a flat throw
  (25° off the mark's angle) to the mark's 45°, settling before the hit. The pool of light — far, small,
  up and to the right — grows along a power curve (slow, then fast, as an approaching thing does) and
  arrives, full size and centred, at the instant of the strike. The flight is 1.2 seconds; the whoosh is
  1.2 seconds to match.
- **The strike.** The world stops. Thud and the heavy haptic; the light breathes; the frame shakes along
  the line of the throw; a burst of fourteen chalk specks off the point; the dart squashes 3.5% for four
  frames and its shaft and flights whip and settle while the barrel stays dead still. The generic
  expanding circle of a shockwave is gone.
- **The ring, earned.** From either side of the dart, four strokes of chalk run round where the light
  was, thinning at their leading ends, until the ring is whole; the light is spent as they close; the
  chalk sound; one pulse. The glow fades as the mark becomes type.
- **The name.** The mark shrinks and slides into the last slot of THRØ, its ring and bar taking the
  letters' weight (the wordmark's own Ø proportions, mixed in over the second half of the move) while T,
  H and R stamp in beside it — each landing at 130% and settling to size, a puff of chalk and a firm
  haptic each. The word spans 84% of the width. The tagline tracks in beneath it over the first third of
  the hold. That is the finished composition; Home fades up under it.
- **Timing.** The field and the far light to 400 ms; the flight to 1600; the strike's beat to 2000; the
  ring to 2550; the word to 3400; the hold, with the tagline, to 4300; the cross-fade to 4700. Total 4.7
  seconds, skippable. Reduce Motion shows the name and the tagline, still.

**Method, and what it is not.** The choreography was built and judged in a browser port of the frame
function first — a tracking-shot draft that framed a point ahead of the dart, so the dart's tail was
off-screen for the whole flight, was caught there and reframed; a first pass at the founder's earlier
idea, the word printing down under a lifted mark, was built, seen, and then removed on their second
message. Eleven tests hold the timeline, the cues (whoosh, thud, chalk, three stamps in order), the
throw as the camera sees it (the approach's shape and ends, the roll settled before the strike, the
entry, the bob, the pitch), the geometry and its mixing into the wordmark's Ø, the chalk stroke's taper
and the fold. The frame is drawn, not tested; the phone is where it moves.

**Costs, plainly.** The opening's last frame no longer matches the export's Splash; that is the founder's
decision and the export is not changed. The final wordmark is drawn live from Archivo ExtraBold on the
reading that the supplied wordmark is that face, and the mark's ring, at the letters' weight, is the
measured wordmark Ø rather than the mark's own proportions; the master vector files replace both when
they arrive. Still a choice against Apple's launch-screen guidance; 4.7 seconds.

### Amendment, the same day — the founder's fourth look, and the fifth version

The founder watched the fourth version on the phone: "The angle needs to be consistent throughout for
darts flight path it looks awkward how it changes angle mid flight in an unnatural direction. It's much
better though, let's upgrade & improve it even more to be as engaging & utterly beautiful as possible
including the design of the dart & every other detail too."

**Decided by the founder:** the dart's angle is constant from the first frame to the strike. The camera
roll (25° to 0) and the nose-up pitch that flattened onto the axis are gone; the dart flies at the
mark's 45° throughout. The camera-roll idea was mine and it read as the dart changing direction; it is
withdrawn.

**Upgraded, every detail:**

1. **The dart is a real dart.** Point 0.24, barrel 0.30, shaft 0.22, flights 0.24 of its length (it
   had been 0.28 / 0.24 / 0.20 / 0.28, a needle too long and a barrel too short). A fine point with a
   bright core. A tapered tungsten barrel — a nose narrower than its grip, eleven grip rings, two deeper
   grooves, a collar where the shaft seats — 0.027 of the length at its widest, slimmer than the 0.036
   it was. A slim shaft with a ring where the flights seat. Standard flights: a swelling leading edge, a
   rounded top corner, a near-vertical trailing edge, taller than before (0.105), and carrying the mark
   as flights carry a maker's mark. The material is the token palette: chalk for the body,
   chalk-raised for a highlight along the top and the point's core, chalk-hairline for the shaded lower
   half and the far pair of flights, the field's green for the grip rings and ink for the grooves.
2. **The catch, not an entrance.** The dart no longer slides in from the corner. The camera catches it
   mid-flight: it resolves out of a motion smear along its own line — 0.9 of its length at the first
   frame, gone by a quarter of the flight — already in its place. Then it holds, rolling, with one bob
   across its line and a slow drift forward (0.06 of its length) that closes at the strike.
3. **A stage light.** The pool of light on the wall is now the foot of a beam from above — a soft
   column, 5% chalk at its brightest, blurred — and the chalk dust streaming past is lit brighter
   inside it. "From the pub board to the world stage" is the tagline; the light is that.
4. **The speed lines**, thinned: fewer, shorter, fainter, so the rush reads as speed and not as rain.

**Unchanged:** the timing (4.7 seconds), the strike, the ring, the name and the tagline as the finish,
the sounds, the haptics. Eleven tests hold the timeline, the cues, the throw (the approach's shape
and ends, the catch's smear, the drift, the bob), the geometry and its mixing, the chalk stroke, and
the dart — its four parts summing to its length, the barrel's nose, grip and collar radii, the
flights face-on and edge-on, the mark on the flights, and the fold into the bar.

**Cost.** The dart's design is a drawing in the brand's palette and not a rendering of any product; it
should not be read as a particular manufacturer's barrel. The beam is a few points of chalk over the
field and disappears with the light. The phone is still where motion, sound and touch are judged.

### Amendment, the next day — the founder's fifth look, and the sixth version

The founder watched the fifth version on the phone: "Feels like the end screen with the bottom text
should be visible just a little bit longer so people can read it properly. Also any further visual
upgrades to the intro."

**Decided by the founder:** the tagline must be readable, not glimpsed.

**What that cost, stated plainly.** The tagline had been still, at full strength and alone with the
name for 0.53 seconds. It now has 1.37. The hold grew from 0.90 s to 1.54 s, and the tagline arrives
earlier — as the last letter sets rather than after the mark has finished moving — so the composition
assembles as one gesture instead of two. The opening is **5.36 seconds**, up from 4.70.

The tests had held the opening under five seconds with the message "an opening is a door, not a wait".
That rule was engineering's, not the founder's. It is restated at 5.5 seconds with the founder's reason
recorded here, rather than deleted, and a new test holds the thing they actually asked for: the tagline
must be settled and alone for at least 1.2 seconds. Every added millisecond is in the hold, where the
reading happens; nothing before it was slowed.

**The upgrades.** Each of these is a fault found by rendering the frame function at full phone size and
looking at it, or by a critic reading the code against the frames — not a preference:

1. **The flight had no flight in it.** The dart hung in the middle of the frame for 1.2 seconds while
   what read as diagonal rain fell behind it. It now enters from the lower left and crosses a screen and
   a half, at the mark's 45° throughout, smeared by exactly its own speed, still closing at the strike.
2. **The wall never approached.** Its growth was a power curve that did nothing for the first quarter of
   the flight and everything in the last. It is now perspective: apparent size is one over distance, and
   the distance closes at a constant proportional rate, so the wall doubles every 0.43 of the flight and
   no part of the throw is without approach in it. The chalk dust sits at fixed places on the wall and is
   drawn through the same perspective, so every speck slides outward from the spot being aimed at and
   draws itself into a streak. Nothing else looks like flying at a surface, and it is why the dust no
   longer reads as rain: it also falls away from the lit spot, so the corners stay dark.
3. **The light was aimed at the dart's grip**, not at the spot the point enters — and the chalk it
   knocked off erupted 180 points from where the light flared. The aim is now the spot, and it hands off
   to the ring's centre as the chalk takes over: the light that lit the spot becomes the light the ring
   is drawn in.
4. **The strike was the emptiest frame in the film**, and measurably darker than the frame before it.
   It now flashes on the frame of the thud rather than easing in a tenth of a second late, throws chalk
   dust with grit in it, leaves a scuff on the board, and the dart casts a shadow, so it stands out of
   the board instead of lying on it like a decal.
5. **The tungsten squashed.** It does not. The board gives and holds — the point drives in and comes back
   a little — while the shaft and the flights whip and the barrel stays dead still.
6. **The forming ring read as two fat crescents.** Chalk is now laid the way a hand lays it: a thin line
   runs out from each crossing, both ways, and the stroke fills in behind it, with a bright head where the
   stick is touching, dust off that head, and an edge roughness that is the same at the same angle on
   every frame so it never crawls. The chalk starts at full speed the instant the thud lands.
7. **Half of every roll drew the far pair of flights in front of the near pair**, so the tail flipped
   light and dark as it turned. Which pair is in front is the sign of the roll, not its size. The roll is
   half a turn over the flight instead of 1.6, so the flights no longer strobe, and the far pair is now
   the opaque shaded side of a flight rather than a see-through one.
8. **The Ø was 17% lighter in stroke than the letters it stands in.** Its proportions are now measured off
   Archivo ExtraBold itself rather than chosen: rendered at 300 pt the face's cap is 206 px, its H stem
   0.261 cap, its O 0.524 cap in outer radius with a side stroke of 0.269 cap, and its Ø's slash 0.130 cap.
   The wordmark's Ø is those numbers. **The founder's own mark is untouched** — 0.364 / 0.250 / 0.040 /
   0.643, the reconstruction of their artwork — and a test holds it that way. Only the Ø-for-the-wordmark,
   which was engineering's, has changed.
9. **The letters faded in through a sage grey the palette does not contain.** They are struck on now, over
   50 ms, and they land after the mark is home in its slot rather than against a mark still in transit.
10. **The tagline's size was hardcoded at 13 pt** and at the widest moment of its track-in would have run
    off the edge of a phone narrower than 375 pt. It is a seventeenth of the name's cap height now, capped
    to what the screen will hold at the widest tracking it reaches.
11. **Dynamic Type could pull the composition apart**, because the wordmark's geometry is measured against
    letters that would scale while the geometry did not. The opening's type is `fixedSize`.
12. **A tap skipped into the full-length cross-fade.** A skip now fades in 0.22 s, and Reduce Motion's fade
    is its own rather than the standard timeline's.
13. Smaller: the camera breathes through the flight as a carried camera does; the impact shake moved off
    16 and 23 Hz, which a 60 Hz clock aliases, to 11 and 17; the vignette closes a little as the name
    settles; and a few chalk motes drift down through the hold, so the end of the film is quiet rather
    than frozen.

**Unchanged:** the shot itself — one constant angle, the strike, the ring earned from it, the mark
becoming the Ø of the name as the finish — the sounds, the haptics, the tagline's words, the palette, the
mark, and Reduce Motion's stillness. Thirteen tests hold it, up from eleven.

**Cost, again plainly.** 5.36 seconds is a longer choice against Apple's launch-screen guidance than 4.70
was; it is still skippable by a tap and still once per cold launch. The dart's design remains a drawing in
the brand's palette and not a rendering of any manufacturer's barrel. Every judgement above was made from
frames rendered at 430×932 from a line-for-line port of the frame function; **the phone is still where
motion, sound and touch are judged**, and the founder's eye on the device is the only test that counts.

### Amendment, the next day — the founder's sixth look, and the seventh version

The founder watched the sixth version on the phone: "Thats better maybe half a second shorter at the
end. the creation of the O with line through logo needs work as you can see breakage at the bottom
right & doesnt feel very dynamic or cinematic or engaging, need a fresh idea. apply any other upgrades
that arent a regression."

**Decided by the founder:** half a second off the end, and a fresh idea for how the Ø comes into being.

**The breakage was structural, not a tuning error.** Two chalk strokes ran out from the dart's
crossings at 135° and 315° and met at 45° and 225°. A stroke thins to a point where it leads, so the
ring closed on two hairline pinches that never filled; the bottom-right one is the one the founder
saw. Two tapered ends cannot meet in a whole ring, and no amount of overlap would have fixed it.

**The fresh idea: the ring is not drawn at all.** The strike sends a shock out through the board, and
it is not round — it is stretched along the dart's own line, so it reaches the mark's radius first
exactly where the dart crosses it and last square to that. Where it crosses, the chalk is **set**, at
full width, on the frame it arrives. The ring lights up from the dart's line and races round both ways
until two lit fronts merge. Nothing tapers anywhere, so the fronts can only overlap; 45° cannot break
again, and a test holds the band at full width along its whole length so nothing can put a taper back.

What that buys beyond the fix:

1. The shock leaves the point on the frame of the thud and reaches the ring exactly as the ring's
   segment begins, so the 0.38 s between the hit and the mark — previously the emptiest stretch in the
   film — is now the shock travelling.
2. It is seen as what it throws: chalk off the board, riding the same front that sets the ring, so the
   dust arriving and the chalk lighting are one event. Dust rather than a drawn wave, because a stroked
   ring at these radii traces the dart's own barrel and reads as an outline round it; and only outside
   0.72 of the ring's radius, because closer in it reads as bristles on the dart. Both were built,
   looked at, and rejected.
3. The leading edge falls off in **strength** over eleven degrees, never in width, and closes up as the
   fronts converge, so the ring arrives whole rather than popping.
4. The ring becoming whole lands as light: a flare around the whole ring, gone in a sixth of a second.
   That is the difference between a mark appearing and a mark being made.

**The timing.** The half second comes out of the hold and nothing else — every other cut is where it
was — so the opening is **4.86 s** and the tagline still has **0.87 s** of stillness. That is two
thirds again what the fifth version gave it, which was the version the founder could not read. The
ceiling in the test is the founder's number in both directions and is back under five seconds.

**Cost, plainly.** The tagline has less time than the sixth version gave it; that is the founder's
call, and 0.87 s is still above the floor the test defends. The frame is drawn, not tested: judged at
430×932 from a line-for-line browser port, and **the phone is where motion, sound and touch are
judged**.

## PD-008 — Under double-in, a visit records what counted, from the opening dart

**Status: decided on the founder's instruction, 2026-09-07.**

The founder: *"yes want double in option as theres leagues & tournaments that are double in."*

### The problem this settles

The engine scores a visit, not a dart. Under double-in the darts before the opening one score nothing,
so a visit total alone cannot say what counted: T20, T20, D10 while unopened scores 20, not 140. That
was **OD-015**, and until it was decided the engine refused double-in and master-in at construction
rather than score them as straight-in and be silently wrong.

### Decided

**What a visit records while the player has not opened is the score from the opening dart onward.
Zero means they did not open.**

- It is what the scorer calls at the oche: "not in… not in… forty" means the forty counted.
- It costs no statistic. A visit is three darts whether it opened or not, so darts thrown and the
  3-dart average are untouched, and a visit that did not open correctly drags the average down.
- The only thing not recorded is how many darts preceded the opener, and nothing in this repository
  computes anything from that.
- A non-zero total that no sequence beginning with a legal opener can make is refused, under its own
  reason (`IMPOSSIBLE_OPENING_TOTAL`) rather than the impossible-visit one — because 180 is a
  perfectly possible visit and an impossible opening, and the two want different words on screen.

The table is enumerated from the dartboard, never listed, and enumeration corrected two things that
looked obvious: **the bull opens**, so the largest double-in opening total is D25 + T20 + T20 = **170**
and not 160; and **41 is openable** (D1, then 19 and 20).

Master-in is implemented at the same time and by the same rule, because it is the same mechanism with
a different opener set, and leaving it refused would have been an arbitrary hole. Match setup offers
*Any* and *Double in* only, because no one asks for master-in at a pub board; the domain still carries
it for a competition that defines it.

### What it costs, stated plainly

A player who opens on their third dart and scores nothing more has a visit of, say, 40 recorded
against three darts thrown. That is correct. But if a scorer enters the **whole visit** rather than
what counted — 140 for T20, T20, D10 — the app will take it, because 140 is a legal opening total
(D20, T20, 40). Nothing can catch that at visit granularity; it is the same class of trust the app
already places in the scorer for every other number they key. The screen says what to enter, on the
frame it matters, which is the mitigation available.

### How to reverse

Record darts individually for unopened visits instead. That is a bigger capture change (three entries
per visit rather than one) and it is what a dart-level client would do anyway; the journal's rows
would carry it without a schema change to the engine's contract.

### Two defects this found, both older than it

- **The generated checkout table was built from a hardcoded floor of 2**, so 1 was missing from the
  straight-out set. A single 1 finishes a straight-out leg, so both engines would have busted a player
  who did. The floor is now the rule's own, carried from the spec.
- That was invisible because **the exhaustive transition table only ever covered double-out**, from a
  remaining of 2. "86,000 exhaustive transitions on two independent implementations" was true of one
  out-rule in three. It now covers all three from a remaining of 1: **258,516** transitions.

## PD-009 — Clubs and leagues: what is public, who may be reached, and how a fixture is agreed

**Status: decided by the founder, 2026-09-07.** Closes OD-016, OD-017 and OD-018.

### Decided

**A public front, a private inside** (OD-016). A club's name, badge, kind and *published* fixtures are
public, so a league can advertise a new season. Members, results and announcements are members-only.
**A member recorded as a minor is never listed to anyone but an admin** — that is not a separate
decision, it is the same one applied to the one case where getting it wrong matters.

**Announcements only** (OD-017). A club reaches its members by broadcast, from an official or admin,
with an author on the record and no private channel anywhere. Member-to-member messaging is not
built, and is not to be built until the founder has taken safeguarding advice. `packages/organisation`
already enforces the rest: an announcement reaches nobody recorded as a minor, or whose age is not
established, until OD-010 is answered. Both refusals stay.

**The official's list** (OD-018). An official schedules, moves and cancels fixtures; agreeing them
happens off the app. It is what the model already supports, it matches how most small leagues run,
and it is reversible — propose-and-accept can be added on top without changing what is stored.

### Why these, in the founder's words and mine

The founder chose all three from the shortlist engineering recommended, which is worth writing down
plainly: the recommendations were engineering's reading, the decisions are the founder's, and if the
reading was wrong the decision is still theirs to change.

### What each costs

- **Public front.** A club page is a page anyone can find, so a club's name and badge are published
  the moment it exists. There is no takedown flow and no claim process; a club that objects to
  another club's name has nowhere to go yet.
- **Announcements only.** A player who wants a private word with a captain uses a phone. That is a
  real gap and it is the right gap to have while OD-010 is open.
- **The official's list.** A postponement agreed between two captains is not on the record, so a
  league decided by a walkover has nothing in the app to point at. Propose-and-accept is the fix and
  it is deferred, not refused.

## PD-010 — The club, league and profile screens are designed from the existing system

**Status: commissioned by the founder, 2026-09-07.**

The founder: *"id want you to use the design system & /design to build the screens."*

`docs/design/DESIGN_UNSPECIFIED.md` says the screens the export does not draw may not be invented by
engineering. This is the founder lifting that for one named set — the club, league, tournament and
profile screens — and directing that they be designed **from the approved system rather than from
scratch**. That is a narrower authority than it sounds, and the narrowness is the point:

1. **Tokens only.** Every colour, size, radius, weight and duration comes from the generated token
   layer. No new value is introduced, and the contrast gate applies as it does everywhere.
2. **Approved components first.** A screen is assembled from the components already extracted from
   the export. Where the system genuinely lacks something, a new component is drawn *in the system's
   own idiom*, recorded in `DESIGN_INVENTORY.md` as engineering-drawn rather than exported, and put
   in front of the founder as a proposal — not slipped in.
3. **The canvas is the review surface.** The screens are published as artboards the founder can look
   at and change before any of them is built, so a design decision is taken by looking rather than by
   reading a diff.
4. **This does not extend.** It covers the club, league, tournament and profile screens named here.
   Every other unspecified screen — the participant attestation flow, the abandoned-match state, the
   authentication surface — stays where it was, and B3 still stands for them.

### How to reverse

The founder replaces any of it with a commissioned design. Nothing here is load-bearing on anything
else; the components are Swift files and the canvas is a record of what was proposed and when.


---

## PD-013 — THRØ shows one checkout route, and says so

**Status: decided by the founder, 2026-09-07.**

Asked whether the app should suggest a finish, and told plainly that most finishes have several
legal routes and that players genuinely disagree — so showing one asserts a preference rather than
a fact — the founder chose **show the conventional route always**.

### Decided

Whenever the thrower is on a finish, the route appears under the remaining score. It is one route.
THRØ takes a position on which.

### What is a fact and what is a preference

The distinction is the whole of this entry, because only one half is defensible:

- **A preference:** which of several legal routes is best. Nobody can settle that, and THRØ is not
  going to pretend to. The rule that picks one is written down in `packages/domain-spec/generate.py`
  in full, so anybody can read what THRØ prefers and why, and disagree with it specifically.
- **A fact:** whether a route is a legal finish of exactly that number under exactly that match's
  out-rule. That is arithmetic, and it is checked for **every route in every rule** — 2,988 property
  checks in the spec validator, and again in both engines: the darts sum to the remaining, the last
  one lands on a legal finishing segment, no earlier dart finishes it, and nothing is longer than
  three darts. A number with no finish gets no route rather than an unthrowable one.

### The rule, in one paragraph

Fewest darts. On the last dart, prefer the finishing double by a stated order — 32 and 40 first
because they are the two doubles the game is taught around, then the rest of the even doubles, then
the odd ones (a missed odd double leaves an odd number), then the bull, because it is the smallest
target on the board. On every dart before it, prefer the highest-scoring single or treble, and where
a single and a treble score the same, the single — nobody aiming for nine aims at treble three. On a
three-dart finish, pick the first dart that way among those leaving a two-dart finish, then repeat.

Derived, that rule produces the conventional chart for the finishes people actually look up: 170 is
T20 T20 Bull, 167 is T20 T19 Bull, 160 is T20 T20 D20, 141 is T20 T19 D12, 100 is T20 D20, 90 is
T18 D18, 81 is T19 D12, 60 is 20 D20, 41 is 9 D16. Where it differs from a chart somebody has seen,
both routes are legal — this one is derived, so it can be checked rather than argued about.

### What it cost

Nothing in the export had to be invented: **`CheckoutCard` already draws a route** and had simply
never been given one. The engine is untouched — a route is a display, not a rule, and no outcome
anywhere depends on it.

### How to reverse

Stop passing `session.throwerRoute` to `CheckoutCard` and the card is exactly what it was. The table
stays generated and costs nothing.

---

## PD-011 — Both players confirm the result, on the one phone

**Status: decided by the founder, 2026-09-07.** Extends PD-010's design authority to this one screen.

`docs/design/DESIGN_UNSPECIFIED.md` item 7 called participant attestation **the single highest-value
item** on the missing list: PD-002 says one player's word never moves a rating, and the participant
app had no way for the second player to say anything at all. Both players stand at the same phone,
so it is buildable today. The founder chose to build it.

### Decided

When a match finishes, each player is asked in turn — by name, so the phone gets handed to the right
hand — whether the result is right. Their answer is appended to the journal with the match.

- **Both agree** → the result is `participant-confirmed`.
- **Either refuses** → the result is `disputed`, and a refusal outranks the other player's agreement,
  because a result one competitor does not accept is disputed whatever the other said.
- **Neither has answered** → `self-reported`, as before.

### What it is honest about, which is the point of it

**Two people at one phone is not two devices.** It is the weakest form of `participant-confirmed`:
an assertion by somebody standing there, under names typed at setup rather than accounts, with no
independent second record. The trust model's strongest corroboration — two devices with their own
streams — is a different and better thing, and this is not it. Every screen that shows the label
says so in words rather than leaving the label to imply more than it means.

It is still the difference between one person's word and two, which is exactly what PD-002 asks for
before a result can ever count.

**Both are asked, not one.** The trust model lets the player who *entered* a result count as one of
its backers, so ordinarily only the opponent need confirm. On a single phone nothing records who was
keeping score, so a confirmation from whoever happened to be holding it would be one person's word
twice. Asking both costs one extra tap and removes the ambiguity entirely.

**A refusal deletes nothing.** The result stands exactly as recorded and is marked. The way to change
it is the retraction PD-004 already defines. An app where a disagreement erased evidence would be
worse than one that recorded no disagreement at all.

**An agreement does not survive the result changing under it.** If a visit is added or undone after
somebody agreed, what they agreed to is no longer what is recorded, so the label drops back to
self-reported. The answers are not deleted — nothing here ever is — they simply stop applying, and
the screen says why. Decided by `device_seq` alone, which is monotonic per device and therefore a
total order on the one phone that scored the match.

### A defect this found

The journal read an unrecognised row kind as `?? .visit`. Adding two new kinds is exactly the change
that makes that fire: a row written by a later build would have been replayed as a nil-scoring visit
and quietly entered the match, changing the score and every statistic derived from it, with nothing
anywhere saying so. An unreadable kind is now `unknown`, replay throws on it, and a test holds the
direction — the same shape as the age band that must never default to *adult*.

### How to reverse

Stop offering the confirm action; the label falls back to `self-reported` and every row already
written stays where it is.

---

## PD-012 — Local first, with the path to accounts designed now

**Status: decided by the founder, 2026-09-07.** Architecture recorded as **ADR-016**.

Asked what the first release is, the founder chose **local first, with the migration path designed
now**: ship the phone app with no accounts and no server, but build the identity-claim path so a
person's local history can be attached to an account later without losing a leg.

### What was built for it

The device keeps a **book of the people who play on it**, and a match records who each of its two
names referred to. That is the whole mechanism, and it is worth having for its own sake: nobody wants
to retype their opponent's name every Tuesday, and a name typed the same way every time is what makes
a person's matches theirs rather than three strangers'.

It also makes the profile screen real. A person's visits can be pooled across every match they played
here — through the same audited honesty layer a single match's figures go through, not a second
arithmetic written for profiles — so *matches, legs won, 3-dart average, checkout %, 180s, highest
checkout* are computed rather than dashed out.

### Three things it refuses to do

- **It does not pool a checkout percentage across out-rules.** Whether a visit began on a finish
  depends on the rule, so a person who has played double-out and straight-out gets a dash and the
  reason, not a number that is a checkout percentage of nothing.
- **It does not merge legs across matches.** Leg 1 of one match and leg 1 of another are different
  legs; they are renumbered when pooled. Skipping that would put six visits in a first-nine average,
  which is the same class of defect as sharing visit ordinals between competitors — already made once
  in this repository, and not again.
- **It does not guess who an old match belonged to.** Matches written before this carry nulls, read
  perfectly, and can be named later. Guessing is how one person's history becomes another's.

### What claiming will and will not buy

ADR-016 states it: a claim attaches a history, it does not corroborate one. A local journal lives in
a file its owner can edit, so its rows are **attributable, never verified**. Claiming gives a player
their history, their figures and their clubs — not a rated record they did not earn. Anything that
presented a claimed local history as verified would be exactly the fake completion this repository
refuses.

### How to reverse

Stop writing the player ids. Matches keep their names, the book is ignorable, and every figure on a
profile falls back to a dash with a reason.

---

## PD-014 — What happens to an image somebody supplies (OD-019 closed)

**Status: decided by the founder, 2026-09-07.** Closes **OD-019**.

The founder chose to decide the moderation questions now rather than defer images or ship them
undecided. Four answers, recorded here and enforced as code in `packages/organisation`
(`ImagePolicy`) and in the client (`ThroJournal/Images.swift`).

**Which of these shapes is legally available to THRØ is not a question this repository answers.**
What follows is product intent expressed as behaviour, and it needs a solicitor's eye before it
reaches anyone but its owner.

### Decided

1. **Screening: automated on the way in, plus report-and-remove.** Every image goes through a
   classifier; anything flagged waits for a person; every image carries a report route and a
   takedown path. This happens **where an image is published**, and there is nowhere to publish to
   yet — so the part that exists today is the takedown mechanism's shape and the refusal that
   nothing unscreened may be published.
2. **A member recorded as under 18 has no picture at all** — and neither does one whose age has not
   been established, treated the same way for the same reason the announcements are: what is not
   known is whether this is a child. The control is not shown rather than shown and refused, and the
   refusal is **at the write, not at the render**, so there is no image of a child in the file to
   leak whatever any screen later decides to draw.
3. **Deleting stops it being served immediately; the bytes go within 30 days.** The gap covers
   backups and an accidental-deletion window. It is a promise that has to be stated in a privacy
   notice rather than discovered, and the number is written down so it can be.
4. **The uploader warrants the right; THRØ removes on notice.** This one needs terms of service that
   actually say it, which do not exist and are not engineering's to write. The takedown mechanism is
   built regardless, because every answer to that question needs one.

### The fifth thing, which was engineering's and not asked

**Every image is decoded and written out again, and carries nothing it came with.** A phone
photograph carries the place it was taken; a club badge picked by a fifteen-year-old carries their
house. It is done with ImageIO and an explicitly empty property dictionary, so metadata is dropped
*by construction* rather than by remembering to remove each kind — and a test builds a real JPEG
with GPS and EXIF in it, puts it through the intake, and reads the bytes back to prove it is gone.

### What exists today

A club can have a badge, picked from the photo library, resized to badge size, stripped, and stored
on the device. It is drawn wherever the initials would be. Removing it removes the file. **Nothing
has left the phone**, and the screen says so rather than implying an image has been checked when
nothing has checked it.

Member pictures are refused for everybody the app does not know to be an adult, which today is
everybody a club has not recorded an age for. That is the rule working, not a gap.

### How to reverse

Stop offering the picker. Every badge falls back to initials, and the images folder can be deleted.

## PD-015 — Four design commissions come off the B3 list

**Asked** 2026-09-07. **Answered** 2026-09-07: all four.

`docs/design/DESIGN_UNSPECIFIED.md` forbids engineering from inventing what the export does not
draw, and B3 lists what a designer still owes. Four of those items are things engineering can draw
under PD-010's terms; two — the master vector files and recorded foley — need a person and stay on
the list.

The four commissioned: **the `Stat` variant** for bounded and unavailable values (the honesty
layer's visual form, and the most-used unspecified thing in the app); **pressed, focus and keypad
haptics** (the control touched sixty times a leg); **the Dynamic Type contract** (what the scoring
screen does at the largest accessibility sizes); and **the state for a match ended short**, which
PD-016 creates.

PD-010's four conditions carry over unchanged: tokens only, approved components first, anything
genuinely missing drawn in the system's own idiom and recorded in `DESIGN_INVENTORY.md` as
engineering-drawn, and the canvas as the review surface.

### How to reverse

Each is a component or a modifier; removing one returns that surface to what SwiftUI does by
default. The `Stat` variant is the one with a cost: without it, an unavailable figure has no drawn
form and every screen invents its own.

## PD-016 — A match may be retired or abandoned, and the player picks which

**Asked** 2026-09-07. **Answered** 2026-09-07: both, and the player picks.

Somebody leaves, the pub shuts, a player is injured. The app had no answer at all: a half-played
match sat on Home for ever.

**They are two different things and the app does not choose between them.**

- **A retirement is a concession.** Somebody stops; the other player wins. That is how darts has
  always handled a walk-off, and it is a result that should count. The legs stand as they were.
- **An abandonment has no winner**, and none is invented. The match counts for nobody.

Collapsing them into one word would force exactly one of two errors — inventing a winner where
there was none, or throwing away a real one — which is why there are two.

**The darts are real either way.** Every visit thrown is kept and counts towards both players'
figures, in an abandoned match as much as any other. Only the *result* differs. A person's history
counts abandoned and retired matches apart from matches played out, because "played 12" meaning
"nine played out and three walked away from" is a different claim to the one it looks like.

**An ending is final.** Nothing undoes it: no more visits, no retractions, no second ending. That is
a deliberate departure from PD-004, which makes a mis-keyed *visit* undoable — a visit is a
transcription, and an ending is a declaration taken behind a confirmation that states its
consequence and says outright that it cannot be undone. If an ending could be undone, the match
could un-end and "the result" would be a claim that moves, which is precisely what PD-011's
attestation exists to pin down.

**An ending makes an earlier agreement stale.** Retiring after both players confirmed a scoreline
would hand the match to somebody neither of them agreed had won it, so the label drops back and both
are asked again — the same rule a visit or a retraction already triggers.

**An abandoned match is never labelled.** There is no result, so there is nothing to confirm and
nothing to dispute: no verification badge, no attestation flow. "Self-reported" on a match nobody
claimed to have won would be attesting to a claim that was never made.

### How to reverse

Stop offering the two buttons. Rows already written stay readable, because the journal reads a kind
it does not know as `unknown` and refuses to replay rather than guessing — which is also what an
older build does with these rows today.

## PD-027 — Every screen has an entrance, and Home has something to say

**Asked** 2026-09-07 by the founder. **Answered** 2026-09-07.

> *"home page feels very bare & basic, all screens feel bare & basic ... all screens & features &
> unveilings or reveals including intro must be incredibly beautiful, clean, dynamic & fluid, no
> clunkyness or generic slop anywhere"*

Two different faults, and neither is fixed by decoration.

**Home had nothing to say.** It was a system title bar, a list of rows, and a button. Everything on
it was reachable from it and nothing on it was *known* by it. A darts app's first screen should
answer three questions before a finger moves — *is there a match I walked away from*, *what have I
been throwing*, *what happened lately* — and it now answers them in that order, because that is the
order they matter in.

- **The masthead** is the mark on the board's own dark surface, not a large title in a system bar.
  A large title bar is what every app on the phone opens with, and *generic* was the founder's word.
  The line under it is a fact, never a greeting: how many matches this phone has watched this week.
- **The match still going** is the largest object on the screen when there is one. It was a row in a
  list, distinguished from thirty finished matches by a small blue tag.
- **The last seven days** are figures from the audited honesty layer — the same `Statistics`
  functions the result screen uses, over the same `VisitRecord` shape. **A figure it cannot support
  comes back as a dash and a reason**, so a new phone shows three dashes and says why. Filling that
  strip with zeroes to make the screen look fuller was the one thing that could not be done, and the
  reason is PD-018's: a number without its sample is a claim rather than a description.
- **The window is in the label.** *Last 7 days*, on the screen, not only in a comment.
- **Both players' darts are in it**, because that is what the phone has seen, and the strip says so.
  A person's own figures are on their own page, where `PersonSummary` pools only the visits they
  threw.

**Nothing arrived.** A screen that is simply *there* the instant it is pushed has no craft in it
however good its typography is. `throEntrance` gives each block of a screen a 12-point rise and a
45-millisecond beat after the one above it — the design's own `motionTravelMedium` and its own
`motionEasingSet`, which were in the tokens all along and which nothing but the opening sequence
could reach as an `Animation`. That is what "generic" looked like from the inside: an app whose
motion was Apple's rather than its own. `Animation.throEnter/throResolve/throExit` fix that for
every transition, not only for entrances.

**It withdraws completely under Reduce Motion**, and withdrawing means the content is present at
full opacity on the first frame — never a gentler version of the same animation. **The stagger is
capped at six blocks**, because the eighth section of a long screen arriving a third of a second
late is a wait rather than choreography.

### How to reverse

`throEntrance` becoming the identity modifier removes every entrance in the app at once. Home's
strip and card are `WeekStrip` and `ContinueCard`; deleting the two calls in `HomeScreen.sections`
returns Home to the list it was.

## PD-026 — A match can be put on a shelf, and a match can be taken off the phone

**Asked** 2026-09-07 by the founder. **Answered** 2026-09-07.

> *"option to delete or achive games."*

Two asks, and only one of them touched anything difficult.

**Archiving is a shelf.** A match is taken off Home and out of nothing else: it is in the journal, in
the export, on the person's page and in every figure derived from it, because it happened.
Reversible, and reversible is the point — this is the right answer for almost everybody who wants a
match gone from their screen. It is a column on `local_match`, which is a mutable table and always
was.

**Deleting collided with the append-only trigger**, which aborted every `DELETE` on `journal`
unconditionally. That trigger is the whole of the journal's trustworthiness and the temptation was
to weaken it quietly. What settles it is a distinction the trigger was not making:

> Append-only exists so that **what a visit says cannot be changed**. It does not exist to make a
> person keep a match they never wanted recorded.

A journal that will not let you edit a visit is honest. A journal that will not let you throw away a
match you started by mistake is not principled, it is stubborn — and on a phone in the United
Kingdom it is also a person being refused erasure of their own record.

So the rule is **narrowed, not removed**, and narrowed in a way a test can hold:

- `journal_append_only_update` is **unchanged and unconditional**. Nothing may ever edit a row.
- `journal_append_only_delete` now aborts unless the row's match is the one a purge is currently
  naming in `meta`. Only `deleteMatch` sets that key, only inside its own transaction, and it clears
  it in the same transaction — so a crash mid-purge rolls the key back with the rows.
- With no purge running the subquery is NULL, `OLD.match_id IS NOT NULL` is true, and every delete
  raises exactly as before. **A bare `DELETE FROM journal` still aborts**, and so does a delete of
  another match's rows *while a purge is running*. Both are asserted.

**One delete is refused outright, and it is not about tidiness.** A league result scored in THRØ
cites its match by id, and that citation is the whole of its provenance — it is what makes the
result *scored* rather than *somebody typed it in*. Deleting the match would leave a table resting
on evidence nobody could produce. `AppStore.deletionRefusal` says so, names how many fixtures, and
offers the shelf, which does everything the person wanted and keeps all of it.

**The warning before a delete names what is lost**, not "this cannot be undone" — which every app
says and nobody reads. The two names, the date, the visits, and the one thing the person cannot know
from the row: *an export or a backup written before now still has it, and nothing this app can do
reaches those.*

**The controls are in an edit mode**, not on every row. A delete button permanently under the thumb
of somebody reaching to open a match is a trap; a delete hidden behind a long press is hidden from
everybody who has never discovered a long press.

### How to reverse

Dropping `archived_at` and restoring the unconditional delete trigger returns the journal exactly to
what it was; `deleteMatch` then fails, loudly, which is the correct failure. There is no state to
migrate back — an archived match is a match with a date in one column.

## PD-025 — Undo belongs to the match, not to the result

**Asked** 2026-09-07 by the founder. **Answered** 2026-09-07.

> *"undo last visit shouldn't be on results page as thats when its all done."*

Right, and the reason is sharper than clutter. The result screen is the moment a match becomes a
record. Offering to unpick the last visit there invites a player to reopen something they have just
watched close — and PD-004's argument for undo, *the mis-key that ends a match is the one that most
needs undoing*, is already answered by the confirm step that comes **before** this screen, not by a
third button on it.

So the finished result screen has two actions and both of them finish: **Done** and **Play again**.

**One case keeps it, and keeps it somewhere else.** Where a result is disputed the screen already
says, in its own words, *"Undo the visit that is wrong and confirm again."* A screen that gives an
instruction and no way to follow it is worse than either. The undo now sits directly under that
sentence, in Evidence, worded as what that sentence asked for — and it is not there on an ended
match, where the journal refuses a retraction (PD-016) and the sentence is still true of the record.

### How to reverse

Moving the button back into the action block restores the old screen exactly; nothing about the
retraction itself changed.

## PD-024 — The scoring screen reflows instead of capping a player's text

**Asked** 2026-09-07. **Answered** 2026-09-07: the upper region scrolls above a pinned keypad.

PD-015 wrote down a real accessibility limit rather than hiding it: reading screens scale to
`.accessibility5`, and **the scoring screen stopped at `.accessibility1`**, because it must fit
without scrolling and holds a keypad whose targets are already at the minimum. A player who needs the
largest text got smaller text at the oche.

`DYNAMIC_TYPE.md` named two shapes that would serve that player properly and said choosing between
them was a design commission, not engineering's. The founder chose the first.

**Above the keypad, the screen scrolls and the text grows all the way.** The remaining score, the leg
state, the checkout route and the turn indicator go to `.accessibility5` like every reading screen.

**The keypad does not move.** It keeps `.accessibility1` at every text size, and that is not a
leftover of the old cap — it is the whole reason the cap existed:

> A keypad that moves under the player's thumb mid-visit turns a mis-key into a wrong number in an
> evidence journal, which is worse than a small key.

So the two halves of the screen answer two different questions. Above: *can the player read this?* —
and it scales. At the keypad: *is the key where their thumb expects it?* — and it does not move.

**The threshold is the old ceiling itself**, so the screen changes shape at exactly the size text used
to stop growing. No size loses anything it had, and no size below it gains a scrolling region it never
needed — which matters, because a scroll view under the thumb of somebody scoring at an ordinary text
size is the thing PD-015's cap existed to prevent. A test holds both ends of that.

The cards that stand in the keypad's place — the PD-001 question, a retraction proposal, the
end-a-match choice — **do** grow, because they are things to be read rather than things to be tapped
at speed.

### How to reverse

`ThroDynamicType.reflows(at:)` returning false everywhere restores PD-015's behaviour exactly, and the
limit goes back to being stated rather than solved.

## PD-023 — A player's picture arrives with their account, and not before (closing OD-021)

**Asked** 2026-09-07. **Answered** 2026-09-07: a picture arrives with an account.

PD-014 settled that nobody under 18, and nobody of unestablished age, has a picture. A club member
has an age band because an admin was asked for one. A **person on this phone** — one of the two names
typed at an oche before a match — has none, and there is nowhere in the app that asks. So by PD-014
applied honestly they have no picture, which is what the app does and what their page says.

The founder chose the third of the three ways out, and it is the one that widens nothing:

> **The person in the photograph is the one who answers for their own age.**

A club admin answering for a member is a compromise PD-014 already accepted, because a roster has to
work before anybody has an account. Extending it to *whoever is holding the phone answers for whoever
is playing* would widen that on the surface where THRØ has the least idea who anybody is — and it
would put a safeguarding question in the middle of setting up a game of darts, asked about somebody
standing next to them.

So nothing changes on this phone until **B4** (accounts and identity). What changes today is the
sentence: the person's page says the picture arrives with an account rather than leaving it open.

### How to reverse

Nothing to reverse — this is a decision not to build something. If it is ever revisited, the thing to
revisit is *who is asked*, not whether the rule applies.

## PD-022 — A league declares what its results are counted in

**Asked** 2026-09-07. **Answered** 2026-09-07: the league declares its unit.

A league result is stored as two numbers. **`3–1` on its own does not mean anything**: three legs,
three matches and three points are three different claims, and one league's table cannot be compared
with another's — or joined to it, or ranked against it — unless both say which.

This was asked now rather than later for one reason: **it cannot be answered retroactively.** A
stored `3–1` with no unit on it cannot be reinterpreted afterwards; somebody has to be asked what they
meant, and by then they will not remember. There is currently no league data anywhere, which makes
today the only cheap moment this decision will ever have.

Three units, because these are the three ways darts leagues actually run:

| Unit | What a result counts |
|---|---|
| **Legs** | Legs won across the night. A 7–2 is nine legs played |
| **Matches** | Individual matches won within the fixture. A 5–4 is a nine-match card |
| **Points** | Whatever the league's own points system awards for the fixture |

**Chosen once, and then fixed.** The unit may be changed only while the league has **no results at
all** — an admin who picked wrong on day one can fix it before anything depends on it, and after the
first result is in, changing it would silently reinterpret every number already entered. The store
refuses it rather than the screen remembering to.

A league created before this decision has **no unit**. It is not guessed at: the league says so, and
an admin may set one, and the same refusal applies once results exist.

The unit travels with the number everywhere it is shown — the table's columns, the result screen's
boxes, the sentence under the table. A figure without its unit is the same failure as a figure
without its provenance (PD-020), and this repository already has a name for that.

**What is still not decided (OD-022 remains open on its other halves):** whether THRØ has a *standard*
a league may override, and whether the tie-break — points, then difference, then scored — is the
league's to change. Neither becomes unanswerable later, which is why they waited and this did not.

### How to reverse

Stop asking, and treat every league as unitless. Every league that declared one keeps it, because a
record of what somebody meant is not made false by a later change of policy.

## PD-021 — A tournament is one of four shapes, chosen when it is made

**Asked** 2026-09-07. **Answered** 2026-09-07: all four — knockout with byes, group then knockout,
round robin, and double elimination.

The founder took the whole set rather than a starting subset, which is the harder answer and the
right one: a tournament's shape decides what every screen shows, so a shape added later is not a
feature bolted on, it is a second design of the same screens. Building all four at once means the
tournament screen is written against *shape* from the first line instead of against knockout with
the others imagined.

What each shape actually changes on the screen:

| Shape | What it draws | The thing it must not get wrong |
|---|---|---|
| Knockout | Rounds, halving. A field that is not a power of two gets **byes in the first round**, distributed so the strongest seeds get them | A bye is not a win. It advances a player and appears in no record of results |
| Group then knockout | Groups with their own tables, then a bracket seeded from them | Which group positions qualify is stated *before* the groups are played, never decided by who came through |
| Round robin | One table; everybody plays everybody | The number of rounds and the fixture count are arithmetic, not a guess: n(n−1)/2 |
| Double elimination | A winners' side and a losers' side, and a final that may need playing twice | Where a player *drops to* is a rule, not a placement — and losing twice is out |

`packages/competition` already holds bracket identities proved exhaustively for every field size to
1024, so the shapes are not being invented here; the client renders what that model defines.

**Nothing about a shape implies a result.** PD-009 stands: a fixture, a bracket slot and a group row
are all schedule, and none of them may assert who won. What fills them is PD-020.

### How to reverse

A shape is stored on the tournament. Removing one means refusing to create new tournaments of that
shape; existing ones keep rendering, because the record of what was played must not change when the
product's mind does.

## PD-020 — A league table's results come from two places, and it always says which

**Asked** 2026-09-07. **Answered** 2026-09-07: both a scored match and an official's record, clearly
told apart.

A league table needs results. PD-009 forbids a fixture from asserting one. Both are right, and the
resolution is that a result is **evidence with a source attached**, never a bare number:

1. **A linked match.** A fixture is linked to a match scored in THRØ. The result comes from the
   journal — every visit, every dart, whatever confirmation the players gave it (PD-011). This is
   the strong case and the one the product is for.
2. **An official's record.** An official types what happened. That is their word, it is **marked as
   their word on every screen it reaches**, and it can never move a rating (OD-001), because a
   rating built on typed numbers is a rating built on nothing.

The two are never averaged, never merged, and never drawn the same way. A table where the reader
cannot tell which rows are evidenced is a table that launders the weaker source through the stronger,
and it would be worse than having no table.

**Both count for the table.** A league has to produce standings — an official's record that did not
count would mean a league that cannot run without every player using THRØ, which is not a product,
it is a demand. So it counts for points and position, and it is labelled everywhere.

### How to reverse

Stop offering the second source. Every row that used it keeps its label and its provenance; nothing
is rewritten, because a record of what was claimed is not made false by a later change of policy.

## PD-019 — A league is made of teams, and a team is made of players

**Asked** 2026-09-07. **Answered** 2026-09-07: teams, made of players.

The screens had treated a league as a club with a different word on it — the same roster of people,
the same fixture list — which is what the founder called *"wrong, lazy & ugly"*, and they were right
about the cause: nobody had decided what a league **is**.

A league's unit of competition is a **team**. Teams play fixtures; players play for teams. That is
how pub and county darts actually works, and it changes what every league screen shows:

- The roster of a league is a list of **teams**, not of people. A person appears inside a team.
- A fixture is **team v team**, and its result is a team result.
- The table's rows are teams.
- A player's page, seen from a league, says which team they play for — a fact a club's page has no
  equivalent of.

**A team is not a club**, though it usually belongs to one. "The Feathers A" and "The Feathers B" are
two teams from one club, and a league that could not tell them apart would be a league that cannot
run a fixture list. This is why `Club.initials` already keeps the trailing letter.

### How to reverse

A league with one team per player is a league of individuals, so nothing needs removing to support
individual leagues later — the shape already covers it.

## PD-018 — A descriptive form figure, never called a rating

**Asked** 2026-09-07. **Answered** 2026-09-07: a descriptive form figure, never called a rating.

**OD-001 stays open.** No rating model in this repository has been validated against real matches,
and PD-002 says no unvalidated model may be published. That leaves a profile with nothing on it
that says how somebody has been playing, which the founder chose to fix without touching OD-001.

**Recent form** is a player's three-dart average over their most recent completed legs, computed by
the same audited `Statistics.threeDartAverage` a single match uses, through the same honesty layer.
It is a description of what somebody has actually scored. It is **not** a claim about strength
relative to other players, it is never labelled a rating, and nothing seeds a rating from it.

Four choices inside it, each with a reason rather than a number picked to feel right:

1. **The window is legs, not matches or days.** A match runs from three legs to twenty-one, so
   "your last five matches" is not a fixed amount of darts; and a player who plays once a month
   would have no form at all under a time window. Ten legs.
2. **Below three completed legs there is no figure**, only a note saying how many more are needed.
   One leg is a performance. The shortest thing anybody in darts calls a match is a best of three,
   which is the smallest sample this is willing to describe as form. **That floor is a stated
   position, not a statistical result**, and it is the number to argue with.
3. **A leg counts only when somebody has won it.** A leg still being thrown is a snapshot mid-flight,
   and counting it would move the figure between visits of the same leg.
4. **The window travels with the figure.** "58.4" is a claim; "58.4 over your last 10 completed
   legs" is a description. The screen shows both, and the words "Not a rating" with them.

Where the underlying average is bounded — a leg-winning visit that did not record its darts — the
form figure is a range too. It inherits the honesty layer rather than escaping it, which is the
whole reason it is computed there and not in the view.

### How to reverse

Delete the line from the profile. `Statistics.recentForm` has no other caller, and nothing is
derived from it.

## PD-017 — An export the player controls, and iCloud backup

**Asked** 2026-09-07. **Answered** 2026-09-07: both.

PD-012 put everything on the phone. A lost, broken or wiped phone therefore loses every match ever
played on it, and the app did not even warn about it.

- **iCloud** is what actually saves people, because it needs no discipline. The journal and the club
  book ride the ordinary device backup, so restoring a phone restores the history. It also means a
  player's darts history is in Apple's backup, which is a thing to say out loud in the app rather
  than leave for somebody to discover.
- **An export** is what makes it theirs: a file they can keep, move to a new phone, or hand to a
  league secretary. Nothing leaves the phone unless they send it.

Neither alone covers the real cases, which is why the founder chose both.

**An import never merges into an existing journal.** A journal is append-only with a gapless
per-device sequence, and merging two of them is the reconciliation problem ADR-006 specifies for
sync — which is not built. An import that pretended to do it would produce a journal whose sequence
lies. So an import is read-only until sync exists: it opens the file, shows what is in it, and does
not write it into the live journal.

### How to reverse

Remove the export from Settings and stop marking the container for backup. Files already exported
stay readable, because the format is the journal's own rows and is documented.

---

## PD-028 — Canonical organisational vocabulary: Club is not an entity

**Founder instruction, 2026-09-09.** Recorded as ADR-017. **Amends PD-009, PD-010 and PD-019**, which were taken on the founder's 7 September brief and modelled a standing *club* distinct from a league's *team*; the 9 September instruction is explicit that the competitive organisation is the Team whatever it calls itself, that a venue is a place and not an organisation, and that THRØ must not carry two organisation concepts. What PD-009 decided about public front, announcements and the official's list stands, applied to Teams; what PD-019 decided about a league being made of teams stands and is now the whole story: a "club" with an A and a B side is two Teams sharing a venue and, usually, their administrators.

### Decided

THRØ carries one competitive organisation, **Team**, and one physical place, **Venue**. "Club" is a
word people use for either and is never a separate concept. A Team's venue is a dated tenure, so a
Team that moves keeps its identity, history, roster, results, honours and followers. Team membership
and league registration are different facts in different tables. League and league season are
distinct. Tournament (persistent identity) and event (one edition) are distinct from a league, and a
series links events without becoming a league. Entrants are typed as player, pair or team.
Competition policy is versioned data with authority, effective period, provenance and approval.

### Why

Grassroots darts terminology is inconsistent and the next fifty features would each have been built
on whichever concept existed first. The repository had no `Club` type; it had a bracket tie called a
fixture, a free-text venue, an untyped entrant and an authorization vocabulary that nothing backed.

### How to reverse

The tables are new and empty. The rename of the bracket tie is one statement. Nothing in `evidence`
changed.

---

## PD-029 — Unclaimed player records

**Taken on delegated authority, 2026-09-09.** Reversible by a policy flag.

### Decided

A team admin or organiser may create a **player** — a sporting identity — for a person who has no
THRØ account, because a captain enters a roster before every member has installed anything. Such a
player is *unclaimed*. Its personal data, if any was entered, lives in an `identity.account` row
marked as created by a third party with no recorded consent basis, and the player is treated as a
**minor** by every exposure rule until an account with a known age band claims it.

Claiming is an appended, revocable `identity.player_claim`, never a foreign key updated in place. A
wrong claim is revoked with a reason and both identities stand. A merge of two players is a later,
separate identity event with a stated basis; a name is never a basis.

### The consequence that must be stated plainly

A submission to a league (Phase D) that carries an unclaimed player, or any account whose age band is
not `adult`, may **not** leave `READY` until a consent artefact — self or guardian, with an actor —
is recorded against it. THRØ must not email a third party's details to a league secretary on a
captain's say-so.

### How to reverse

A policy flag refusing third-party creation. Existing records stay, with their provenance.

### Escalate back to the founder if

OD-010's research concludes that holding third-party-entered data about a possible minor, even
privately and pending consent, is not permissible in the target jurisdictions.

## PD-030 — Sign-in: Google and Apple first, self-hosted passkeys as the fallback

**Founder decision, 2026-09-10.** Closes FB-1 (execution plan §9).

### Decided

THRØ accounts are created and signed into with **Sign in with Apple and Sign in with Google** as
the primary methods, because that is what most players already have on the phone in their hand,
and with **self-hosted passkeys** (WebAuthn in the Kotlin service) as the fallback for anyone who
has neither or wants neither. There is no password anywhere. Email is not a sign-in method; it may
be a recovery channel for the passkey path and is decided with that path.

The provider proves who is holding the phone; THRØ decides everything else. A sign-in yields an
`identity.credential` (provider, provider subject) bound to one live `identity.account`; the
account holds a THRØ ID through a live `identity.player_claim`; every authorization decision is
made per request against relationships, never carried in a token (ADR-008 stands). Sessions are
THRØ's own — short-lived access tokens looked up server-side, refresh tokens rotated with reuse
detection revoking the family — so a provider outage or a provider policy change cannot revoke a
player's history, and leaving a provider is a credential re-binding, not a migration.

### Why this ordering

Adoption. A grassroots player asked to "create a passkey" at the oche abandons the flow; the same
player taps the Apple or Google button without thinking. Passkeys remain the fallback because
ADR-008's reasoning still holds — a competitive identity should not depend on a third party's
account policy — and because a player without either provider must still be able to join.

### What it amends

ADR-008 named passkeys as primary with platform sign-in as bootstrap. The order is reversed; the
rest of ADR-008 (identity in the token never permissions, per-request relation checks, device
binding, the offline grant as the bounded exception) is unchanged. ADR-008 carries a dated note.

### Reversal

Low. Credentials are rows keyed by provider and subject; adding a provider or promoting passkeys to
primary is a product setting and a screen, not a migration.

## PD-031 — Hosting: Fly.io with managed PostgreSQL in London

**Founder decision, 2026-09-10.** Closes FB-2 (execution plan §9).

### Decided

The single container (ADR-011) runs on **Fly.io** in the London region, against a **managed
PostgreSQL with point-in-time recovery in London**. The topology ADR-011 fixed is unchanged: one
image, one database, migrations as a deploy step run by the owner role (ADR-013), the application
connecting as the module roles and never as the owner.

### Why

It is the cheapest option that meets every ADR-011 requirement — UK residency, PITR, HTTP/2 to
origin for SSE — with the smallest infrastructure-as-code footprint for a one-person team.

### What it blocks and does not

It unblocks staging and the two-device sync release check. Local and CI work never depended on it.

### Reversal

Low: one image and one database dump move to any of the alternatives considered (Render, Railway,
AWS App Runner with RDS).

### Amendment, 2026-09-10 — the database is Neon; staging without a card

Fly requires a card on file for every organisation, and the founder does not wish to add one yet.
The decision's substance stands — one container, London, a managed Postgres with point-in-time
recovery — and its parts are now named separately:

- **Database: Neon, region London (`aws-eu-west-2`).** It is the managed Postgres with PITR the
  record asked for, it has a London region, and its free plan (0.5 GB, a six-hour restore window,
  autosuspend after five idle minutes) needs no card and is enough for staging. Before real players,
  the project moves to the pay-as-you-go plan for a seven-day restore window; nothing else changes.
  Every migration was run against a database where the deploy user is *not* a superuser, which is
  Neon's model, and V001 now grants that user membership of the owner role so that it can.
- **Compute, staging: Render's free web service** (Frankfurt, no card; spins down after fifteen
  idle minutes and wakes in about a minute). Staging holds synthetic data, so EU rather than UK is
  within ADR-011, and the wake-up delay is a staging cost, not a product one. `render.yaml` is the
  blueprint. Migrations run from a developer's machine (`gradle -p services/api migrate`) because the
  free tier has no release hook — still a deploy step, still before the image serves.
- **Compute, production: Fly.io in London** as decided (about $3.50 a month for the smallest
  machine), or a paid Render instance; both need a card, which is unavoidable for a host that is
  always on. The image, the migrations and the runbook are the same either way.

**Reversal:** low, unchanged — one image, one database dump; Neon exports as plain PostgreSQL.

## PD-032 — Recovery for the passkey path is a second way in

**Taken on delegated authority, 2026-09-10.** Reversible by adding a channel.

### Decided

A person who signed up with a passkey recovers access by having **more than one credential on the
account**: a second passkey (which iCloud Keychain gives most people for free, across their devices),
or Sign in with Apple or Google added to the same account. Adding is done from a signed-in session —
`POST /v1/auth/passkey/register/options` with a bearer token adds a passkey to that account, and
`POST /v1/auth/apple` or `/google` with a bearer token binds an unclaimed provider subject to it —
and the profile reports how many ways in the person has, so the client can say "you have one way
into this account" and offer a second before it is needed.

There is **no email or SMS recovery**. Neither channel exists in the platform (no mail provider is
chosen, phone is a poor sole factor per ADR-008), and a recovery channel weaker than the credential
it recovers is the account-takeover surface passkeys were meant to remove. A person with a single
passkey and no provider who loses every device has lost the account, and the client says so at the
moment they decline a second credential.

### Reversal

Adding an email magic-link as a recovery channel is a mail provider, a `recovery` credential kind
and one route; nothing here forecloses it. It is a founder decision when it comes, because it
lowers the bar the passkey set.

## PD-033 — The local leagues come in from their own public pages, with their provenance on every row

**Taken by the founder, 2026-09-10** ("you have permission to remove the current teams & players and
autofill with correct data … start with the local area leagues"). Reversible: an imported row is
marked as imported and can be replaced by a secretary's own record.

### Decided

THRØ imports the **organisational graph** of local pub leagues — league, season, division, team,
home venue — from the leagues' own published pages (today: three LeagueRepublic sites — Stockton and
District Thursday Night, Stockton & District Monday Night Mixed, Redcar and District) and places
venues from OpenStreetMap. **Nothing about a person is imported.** The team pages list players by
name and the import does not open them; a player is in THRØ because they chose to be (a claim, with
consent, and with a minor's consent being a guardian's), never because a website listed them.

Every imported row carries a **source record** (V027): the source, the page, the date it was read and
the *basis* — "stated by the source", "inferred from the team's name" (a team called *Blue Bell*
plays at *The Blue Bell*; a strong inference in pub darts and still an inference), or "approximate:
read from the season label" (LeagueRepublic publishes no season dates on its free tier). The app
shows the basis. A secretary's own record replaces an inferred one, and the import never overwrites
a row a person has recorded: a team that already has a home keeps it.

The import is `gradle -p services/api seed`, run after `migrate` as the deploy user, from the seed
file `tools/pull_leaguerepublic.py` writes; it is idempotent by natural key. The public front is
`GET /v1/leagues`, which needs no account, and the Discover tab's **Local leagues** screen draws it
on a map.

### Not decided

Whether to pay for LeagueRepublic's Gold plan (its JSON web services, including fixtures and
results) or to ask each league's secretary for a data-sharing agreement. The honest route to
fixtures and results is the secretary: the seed carries names only until one exists.

## PD-034 — Both keypads read the way every keypad reads

**Taken by the founder, 2026-09-10** ("zero learning layout for both per dart & total score layouts;
keep the big scores"). Reversible: a layout constant.

### Decided

The **visit keypad** keeps its six quick totals — 180, 140, 100, 60, 45, 26 — above a phone-dialler
grid (1 2 3 / 4 5 6 / 7 8 9 / Miss 0 Undo / Enter); it already read that way and does not change.
The **per-dart keypad**'s twenty sectors now count in four rows of five. The founder set the
direction: **20 down to 1**, `20 19 18 17 16` first, `5 4 3 2 1` last, above 25 · BULL · MISS · ENTER.
The board's clockwise order — `20 1 18 4 13` first — is withdrawn: it had to be learned and it split
four board neighbours across row ends anyway.

### Why

Zero learning: a counted grid is the one grid nobody has to be taught, and reading down from 20 puts
the numbers a scorer says most on the first row in the order they are said. The alternative — 1 to
20 ascending, so the big five sit on the bottom row nearest the thumb — was recommended on reach and
not taken; it is one constant if the thumb argument wins on the phone.

## PD-035 — Friends start with a code given in person, and only between adults for now

**Taken on delegated authority, 2026-09-10**, from the founder's "actual profiles able to add friends".
Reversible: a guardian-confirmed path for under-18s can be added without changing what exists.

### Decided

There is **no directory and no search**: a search is how a stranger finds a child. A friendship starts
with an eight-character code one person makes and says or shows to the other, who enters it. A code
lasts seven days and is spent by one use. Only an account that has **said it is an adult** may make or
use a code; an account whose age is unknown is refused with the sentence that says what to do, never
guessed at; a minor's friends are a guardian's business (OD-010) and are refused for now with a
sentence that says so. Both rules are enforced by trigger in the database (V028) as well as in the
service, so no route can forget them. A friendship ends from either side and is recorded as ended,
never deleted. What a friend sees today is your display name and that you are friends; anything more
is a further decision and the screen says so.

The account's age band becomes something a person can say about themselves: *I am 18 or over* under
Account and profile sets `adult, self_declared`; under 18 may be said too. Never back to unknown.

## PD-036 — A team on THRØ starts with one person and fills by a code the side is told

**Taken on delegated authority, 2026-09-10**, from plan §6's first rows and the founder's "keep going".
Reversible: invitations by name or by link can be added beside the code.

### Decided

Anyone signed in may **start a team** and is its first member and admin. Getting the side in is a
**team code** — eight characters, thirty days, up to twenty people — made by the admin or captain and
said across the bar, for the reasons friends work that way (PD-035): no directory, no search, consent
from both sides. Joining makes a real membership (V014) as a player; roles beyond that are the
admin's to give later. A team's **front is public** — name, town, home venue, seasons — and its
roster is **named only where the disclosure rule allows** (`identity.player_may_be_disclosed`): an
adult who has said so, or a guardian's consent. Everyone else is counted and not named, so a public
front never shows a child. A private team is nobody's business but its members'.

## PD-037 — Every league the directory places is on the map before its teams are, and says so

**Taken on delegated authority, 2026-09-11**, from the founder: *"for leagues I think it would be
good to gradually add more & more leagues, teams & tournaments so people outside of the north east
can use the app."* Reversible: the directory rows can be withdrawn by source.

### Decided

THRØ imports the **LeagueRepublic darts directory** — every darts league it places in the British
Isles, with the position each league gave it and the address of its own pages — as league rows with
a **point of their own** (V030) and nothing else: no season, no team, no venue, no person. Three
hundred and twenty-nine leagues on 11 September 2026. A league already imported from its own pages
is found by that address and given its point, never made twice. The Discover slate measures a
league from its own point when none of its pubs is placed, so *around you* is true in Salisbury and
Peterhead as it is in Stockton; and it says, of every such league, that its **teams are not on THRØ
yet** — the row never claims nought teams, the pin is drawn as a league and not as a pub, and the
slate under the pin offers the league's own website. Discover lists six leagues and points at the
map for the rest; the map's list of teams is for the leagues that have them, with a line counting
the ones that do not.

### Why

A player outside Teesside opened a map with three pins on it and a slate that said *nothing near
you*. The directory is public, places its leagues, and names no person — the same tests PD-033 set
for a source. Importing it as points is the honest first step of "gradually": the league is real,
its position is what it said, and everything THRØ does not know is said to be unknown rather than
filled in. Teams follow league by league, by the same importer, from each league's own pages; a
tournament follows when a league publishes one as a competition and not as a cup on a page.

### What this does not decide

Leagues abroad (forty-two on the directory) wait until distances there can be stated truthfully.
Names shouted in capitals are read down to title case for display; the name as listed is on the
row's source record.

## PD-038 — The app asks for an account once, straight after the opening, on the board

**Taken on delegated authority, 2026-09-11**, from the founder: *"sign in should be at the loading
page before main screen, should encourage people to sign up / sign in if that makes sense. need a
beautiful way to do this that matches our brand identity."* Reversible: the screen is one flag.

### Decided

After the opening, and **once ever**, a signed-out player is shown the ways in: Continue with Apple,
Continue with Google, Use a passkey, and *Not now, just score*. It is drawn on **the board** — the
same lamp, dust and chalk the dart landed in a second earlier — with the wordmark on a chalk rule
and the three ways in as the chalk keys the scoring screen is made of. Signing in dismisses it with
no second tap. "Not now" dismisses it and is never shown again; sign-in stays where it was, on the
You tab. The screen carries one promise, in small print under the door out: **matches scored on this
phone stay on this phone, signed in or not**, which is true of this build and is asserted by a test
so it cannot quietly stop being true.

### Why

Sign-in was four taps in — You, SIGN IN, then a settings list of buttons under a paragraph — so
almost nobody had a THRØ ID, and everything that needs one (a name in a team's lineup, a friend by
code, a league registration) could not reach them. The opening exists to make the first five seconds
worth watching; handing that to a white settings form is throwing it away. And the board is already
the app's own argument about what a scoreboard is, so the screen that asks for a name should be one.

### What this does not decide

It is **not a gate**. PD-012 is local-first: two people score a match on one phone with no account,
no network and no permission, and that is the product rather than a trial. So the way past is plain
text, plainly placed, and says what staying out costs, which is nothing. Encouraging is not
cornering. Nor does it decide anything about a *second* ask later; a player who says not now is not
asked again by this screen.

## PD-039 — A person can take themselves out of THRØ, and what is left names nobody

**Taken on delegated authority, 2026-09-11**, from the founder: *"need option to delete account &
account data etc that matches legal standards we dont want to be sued when live."* Not reversible in
the sense that matters: an erasure cannot be undone, which is the point of it.

### Decided

**Deleting an account is in the app, two taps from the profile, and needs nobody's permission.** It
destroys everything that identifies the person: the display name, the age band, every Apple, Google
and passkey credential, every session on every device, the device labels, live friendships and any
friend code given out, the claim on their competitor row, and the consent that let anything about
them be shown. It **keeps the matches they played**, because a leg is the other player's record too
and a league's table stands on it — and after the erasure those rows carry a competitor id that
resolves to no person, which is the shape V018 already established when it took the names out of
match evidence and left the seats.

The screen says both halves before it asks, names the finality (signing in again makes a brand new
account), and asks a second time in a dialog that repeats the consequence rather than saying *Are
you sure?*.

### Why it is redaction rather than DELETE

Every application role has DELETE revoked (ADR-013). That is not an obstacle to erasure, it is why
erasure can be trusted: a row the running service can remove is a row a bug can remove, and one
person cannot be allowed to silently rewrite another's leg. So V031 does the work in one
`SECURITY DEFINER` function owned by `thro_owner` — the service may erase an account and may do
nothing else to those columns — and a test asserts that the service still cannot reach them any
other way. After it runs, no text column anywhere in the identity schema holds that person's name or
provider subject; a test sweeps every one of them, so a column added later is covered without
anybody remembering this decision.

### Why this is also an App Store requirement

Guideline 5.1.1(v): an app that lets an account be created must let it be deleted from inside the
app. THRØ would have been rejected without it.

### What this does not decide

Whether an erasure should be offered a grace period, and what a league secretary is told when a
registered player erases themselves. Neither is needed for a person to exercise the right today.
Nothing here is legal advice, and the privacy policy still wants a lawyer's eye before launch.

## PD-040 — A match is sent to THRØ as the journal wrote it, and arrives self-reported

**Taken on delegated authority, 2026-09-11**, from the standing brief and the Play tab's own note,
which has said *"sending results to THRØ is not built"* since the app shipped. Reversible in the
sense that matters: nothing uploaded can be edited, only added to.

### Decided

**The phone sends its journal, not a summary.** One call, `POST /v1/matches`, carrying the match's
format, the two seats, and every row the device wrote in `deviceSeq` order — visits *and the
retractions that struck them*. The server appends them to `evidence.event` in that order, a
retraction as a `VisitRetracted` event whose `corrects_event_id` names the visit it undid. Sending a
replayed total instead would be the app deciding what happened and throwing away the record PD-004
exists to keep; a screen that shows a struck row and a server that never heard of it are two
different accounts of one night.

**It is idempotent and resumable by construction.** `evidence.event` is unique on
`(match_id, device_id, device_seq)`, so the same upload twice is the same rows; a phone that lost
signal half way sends the lot again and the second half lands. Nothing is last-write-wins because
nothing is ever written twice.

**The opponent is a competitor with no name.** On a phone the other player is usually a local name
and nothing more — no account, no consent. THRØ mints an unclaimed `competition.player` for that
seat and stores **no name for them at all**, because a name is the person's to give (PD-009,
PD-014). They can claim that competitor later by a code, which is machinery V014 already has. Until
they do, the match names one person and one seat.

**So it arrives self-reported, and says so.** PD-011 wants both players to confirm a result. An
upload from one phone is one player's word, so it is recorded as exactly that — the same sentence
the app has always shown at the oche — and it is not evidence of anything more until the other side
confirms. Nothing about an uploaded match is attested, rated or ranked.

### Why not a command per row

The command path (`POST /v1/commands`) takes one visit at a time with a gapless per-device sequence,
which is right for a live match being scored against the server. A match already played is a
finished record, and sending it row by row means a hundred round trips, a hundred chances to stop
half way, and a match that exists on the server in a state the phone never had. One call that either
applies the whole journal or none of it is the honest shape for a thing that already happened.

### What this does not decide

Watching a live match from another phone (the server already streams; the client does not tune in),
and what a league does with a self-reported result. Neither is needed for a person to get the match
they played off their phone and onto their account.

## PD-041 — Who is signed in is known at launch, and the opening waits for it only when it must

**Taken on delegated authority, 2026-09-11**, on the founder's report: *"Loaded me to home screen and
when i checked profile tab it said checking, shouldn't load past the checking screen until checked
in."* Reversible: it is a cache on the phone and a hold in the opening; nothing on the server changed.

### Decided

**The phone knows who is signed in without asking.** A held session and the last profile THRØ gave for
that account — kept beside the session in the keychain — are enough to show the person as themselves
from the first frame, offline in a pub or while the free server wakes. THRØ is asked behind it and can
only correct it: a changed name, or a session it no longer honours, which signs the phone out and
forgets the person. The cache is never an authority, and it is never shown for any account but the one
the held session names.

**The opening waits only for a phone that cannot know.** A phone holding a session and no profile for
it — the first launch of a build that keeps one, or after a reinstall — holds the opening on its last
frame and says *Checking your sign-in* until THRØ answers. Everybody else is known at once, and the
opening hands over on its own clock as PD-007 has it.

**It never traps anybody.** PD-012 says scoring needs no account and no network, so after four seconds
the hold offers *Just score*, and after eight it says why it is slow. A tap skips the throw but never
the check.

**A change to an account never takes its page away.** Saving a name, adding a way in, erasing the
account: the state stays *signed in* while it happens, the page says what is happening, and a failure
is said on the page that asked. The state changes only when who is signed in changes.

### What this does not decide

How long a cached profile may be trusted without the server confirming it. Today it is shown until the
server says otherwise, which is the offline-first answer; an account that was suspended or restricted
would need the server to reach the phone first, and nothing in THRØ suspends an account yet.

## PD-042 — A match that ended short is sent as it ended

**Taken on delegated authority, 2026-09-11**, closing the gap PD-040 left open: its upload refused a
retired or abandoned match, because the server had no event for an ending and the visits alone would
have said the match was still going. Reversible in the sense that matters: nothing sent can be edited,
only added to, and nothing is added after an ending.

### Decided

**One event, `MatchEndedShort`, on the match stream (V034, V035).** The phone's retirement or
abandonment row (PD-016) is sent last, as the rest of the journal is sent; the server stores it in the
same device sequence as the visits before it, written by the same role. Its payload says how the match
ended and, for a retirement, which seat retired. **The winner is not stored**: it is the other seat, and
a stored copy of an inference is a second thing that can disagree with the first. An abandonment names
nobody and has no winner.

**Nothing is added after it.** The table refuses a visit, a retraction or a second ending for a match
that has ended, except a row it already holds, so a phone that resends the whole match still lands as
nothing (PD-040's idempotence). An official's correction and the trust events are not refused: they are
about the record, and a match that has ended is exactly when they happen.

### What this does not decide

Whether a retirement counts towards anything a rating would read (OD-013), and what a league does with
a retirement in a fixture; both read the ending this stores, and neither is decided by storing it.

## PD-043 — The other player takes their seat with a code, and answers for the result

**Taken on delegated authority, 2026-09-11**, the half of PD-040 it left for later: a sent match names
one person and a competitor THRØ minted for the other seat, "claimable later by a code", and stays one
player's word until the other confirms it (PD-011). Reversible in the sense that matters: a claim and
an answer are both added, never edited, and nothing under the match is rewritten.

### Decided

**The sender makes a code for the other seat, and the other player enters it.** Eight characters from
the alphabet a code is said in, seven days, one use (V037). Only the player who sent the match may make
one, only for a match sent from a phone, and only while the other seat is nobody's; asking twice hands
back the same live code rather than a second one. A code is how THRØ always lets two people agree they
know each other — there is no directory to search — and one handed over across a table is consent from
both sides.

**A seat is claimed; the competitor is not.** The other player already has a competitor of their own
(V014) and an account holds one live claim, so entering the code records `competition.seat_claim`: this
seat of this match was theirs. The match still names the competitor it was sent with and no evidence is
rewritten. It is V014's deferred identity event, scoped to one seat of one match.

**The other player answers; the sender cannot.** `ResultConfirmed` or `ResultContested`, on the trust
stream beside attestations and disputes, naming the seat that answered. Every answer is kept and the
latest stands. The sender's word is the match, so they cannot confirm it; an abandoned match has no
result to confirm. **An answer stands only for the record it answered**: when the sender sends more of
the match, the other player is asked again, because agreeing to two legs is not agreeing to three.

**Standing is read, not stored.** Self-reported; confirmed, when the other seat's standing answer agrees;
disputed, when a standing answer contests; or recorded, for a match scored on THRØ as it was played.
Derived from the log on every read, like the legs and the winner, which the server replays through the
engine with struck visits left out.

**A seat shows a name only through the disclosure gate** (`identity.player_may_be_disclosed`): an adult
who has consented, or a guardian's consent. An age THRØ does not know shows no name.

**Entering a code is rationed** per address and per device, from allowances separate from signing in —
the match code, and the friend and team codes, which were not rationed before.

### What this does not decide

What happens to a disputed match next — who looks at it, and whether a league may count it (PD-011's
adjudication, OD-013). Whether a claimed seat ever merges the minted competitor into the claimer's own,
which would be a whole-person identity event and stays deferred. Whether a confirmed friendly counts
towards a rating (OD-013).

## PD-044 — The other player can follow a match live, when the player scoring it shares it

**Taken on delegated authority, 2026-09-11**, for the Live tab the founder asked for. The server has
streamed a match as it is scored since ADR-007, woken on commit since V036, and nothing on a phone
tuned in. Reversible: sharing is off unless switched on, one match at a time, and switching it off
stops it.

### Decided

**Sharing is the player's choice, one match at a time.** On the Live tab, under a match still being
scored: *Share it live on THRØ*. While it is on, the phone sends the match's journal as it grows —
PD-040's upload, the whole journal each time and idempotent — so a send that fails is made good by the
next. It stops itself once the match is over and all of it is on THRØ.

**Only the two players follow it.** The one who sent it, and the one who took the other seat with a code
(PD-043): the stream's door now asks for a seat claim as well as the two competitors, the grants and the
officials it asked before. No spectators and no friends — PD-035 said nothing else is shared with a
friend yet, and this does not change that.

**The page of a match still going is its board.** What each side needs, their legs, who is throwing and
the last visit, replayed on the watching phone through the same engine the scoring phone used, from the
stream's events — each of which now carries its own id, so a retraction names the visit it struck. It
says *Connecting*, *Live*, *Reconnecting* or *Not following* as the stream is, and never calls a frozen
feed live (ADR-007's forty-five seconds).

### What this does not decide

Watching by anybody but the two players — friends, a team, a screen in the pub — which needs its own
decision about who may see a match as it happens, and the stream filtered for such a reader that ADR-007
names and nobody has built. A notification when a shared match starts.

## PD-045 — The team's admin names its captain and vice-captain

**Taken on delegated authority, 2026-09-11**, the Team OS row after starting a team and filling it by
code (PD-036): a team had an admin and players and no way to name a captain, though the captain is who
runs a side on the night. Reversible: a role change is recorded, never rewritten, and can be changed back.

### Decided

**The admin names them, one of each.** From the team's roster, the admin makes somebody captain,
vice-captain, or a player again. Naming a captain when there is one makes the old captain a player, and
the same for vice-captain. Only the admin does this, and the admin's own role is not on offer: handing a
team over is a different decision.

**The captain runs the team with the admin.** A captain makes the team's code and sets its home, as
PD-036 already allowed, and holds `team.manage` on the command path — granted with the captaincy and
revoked with it, revoked and never deleted, because who could have done something is asked months later
(ADR-008). A vice-captain is named and holds nothing more.

**Who held what is the side's history.** A change ends the membership row and opens another (V014), so
who was captain in March can be read back in September.

**Only the admin sees a roster entry's handle** — the membership's own id, never a person's — to name
somebody with. A public front and a member's front carry none.

### What this does not decide

Handing a team to a new admin, a second admin, taking somebody off the team, and whether a captain has
any say over the roster.

## PD-046 — The leagues are a board over a map, and each league is drawn in its own chalk

**Taken on delegated authority, 2026-09-11**, on the founder's word that the map should say which league a
team is in when it is chosen, and that how players reach leagues and teams should be creative, unique and
beautiful. Reversible: it is a screen and six colour tokens, and nothing on the server changed.

### Decided

**The map is the screen.** The leagues open full-bleed, with a board rising from the bottom — the lamp at
its top edge, chalk dust, a chalk dash to take hold of — carrying a search for a team, a pub or a league,
a chalk key for each league with teams, and a card for whatever is chosen.

**A league is drawn in a chalk of its own.** Six league-chalk tokens (`--color-league-1-on-board` to `-6`:
yellow, blue, pink, lilac, peach and mint chalk), dealt by a league's place and round again after the
sixth. Identity and not status, so the status inks are not borrowed for it. Each clears 4.5:1 against its
own trait's `board-lit`, and the contrast gate holds all twelve pairings. Colour is never the only thing
that says which league: its name is written wherever its chalk is. A pub is ringed in the chalk of every
league that plays there, one arc each.

**A team chosen says its league, on the map and on the board.** The map writes the team and its league
over its pub, chalks a line from its pub to every other pub in its division, and lights those pubs while
the rest sink — the bottom stop and grey chalk, never faded. The board heads the team with its league and
division in the league's chalk, says where and when it plays, whether anybody plays for it on THRØ, lists
its division nearest first with the distance between pubs, and opens the team's page (which the server
already serves for a league's team) and, for a signed-in player, joining by a code.

**A pub chosen lists who plays there and in which league. A league chosen lights its pubs**, lays out its
divisions' teams to touch, and says where it came from.

**The map opens on the pubs of the leagues with teams** when the phone does not know where it is, not on
every league pin in the country: 326 of the 329 leagues listed have no teams yet, and opening on the whole
of Britain showed nothing to touch. Located, it opens around the player as before; sent from Discover for
a league, on that league.

**Your team on Discover says its league** when it is a team in a league THRØ lists.

**OpenStreetMap is credited as its licence asks** — "© OpenStreetMap contributors" — wherever the source
of a venue is said.

**Somebody THRØ may not name is drawn with the person glyph** on a roster, never with initials made from
the words standing in for a name ("A player" drew "Ap").

### What this does not decide

A player saying a listed team is theirs and running it on THRØ; reading more leagues' teams, which is
PD-033's open question (a data agreement, LeagueRepublic's paid plan, or each league's secretary); and a
"your team" mark on the map, which waits for the first of those.

## PD-047 — A player says a listed team is theirs, and runs it on THRØ

**The founder's decision, 2026-09-11**, asked as the leagues board left it open: *"Yes — adults only, own
say."* The board (PD-046) shows a player their own side and then offers nothing, because a team read out
of a league's pages has no members: nobody runs it, so there is no code to give the side and no roster to
fill. This is the door between the two, and it is the one thing a player can do about their own team today.

### Decided

**A player takes on a team nobody runs, and becomes its admin.** Only a team THRØ read from a league's
pages — a row with provenance (V027) — and only one with nobody on it. The first to say it takes it; a
second is refused in words and told to ask for that person's code. A team started on THRØ is never taken
on: it is joined with its code (PD-036).

**By their own say, and the team's page says so.** Nobody has told THRØ that this person plays for this
side; they have said it themselves. So the front carries "run on THRØ by one of its own players, by their
own say. Nobody appointed them", and the board says the same where it says who is on a team. The claim is
recorded as what it is — an adoption, by a player, on a date, with that basis and no other.

**Adults only, and an age nobody has said is not adult.** A minor and an unclaimed player are both
refused, by a function that answers false unless an account behind the player says adult. The competition
role may ask that one question and nothing else about a person; nothing that reads a team may ask it at all.

**Eight teams to a player.** A club secretary runs several sides and a script should not run fifty.

**Nothing is rewritten.** The team keeps the name and the pub the league published, and the adoption is
kept: it records who took the side on, and that does not change.

### What this does not decide

Handing a team to somebody else, or giving it back; a league or a side disputing an adoption (today the
answer is that the front says whose say it was); and whether a league that arrives on THRØ later inherits
the teams its players took on.

## PD-048 — Twenty more leagues' teams, read slowly and under THRØ's own name

**The founder's decision, 2026-09-11**, on a recommendation: *"Yes — pilot 20 as described."* PD-033 allowed
teams to be imported from the leagues' own published pages and PD-037 said a source must be public, place
its leagues, and name no person. What neither settled is the question of scale, and it is now a live one:
329 leagues are on the map and three have their teams.

### Decided

**Twenty leagues first, not three hundred.** The nearest twenty by their own point, read, reviewed as a
diff, and seeded. What that pilot teaches — how many pubs match, how stale the seasons are, how many teams
are really people — decides whether the rest follow.

**Under THRØ's own name, slowly, and never past a block.** The importer identifies itself as THRØ, obeys
`robots.txt` (which allows the standings pages and disallows the fixture and player ones), waits at least
five seconds between requests, and stops the run if it is refused. It does not pose as a browser: the
existing tool sends a Safari user agent, and that goes. If identifying honestly gets us blocked, that is an
answer, and the answer is to ask rather than to disguise the asking.

**No singles, pairs or online leagues.** Sixteen of the listed leagues run individuals, so their "teams"
are people's names, and PD-033's rule that nothing about a person is imported decides it.

**And we ask.** The founder writes to LeagueRepublic about a data agreement or their API in parallel,
because it is the only sustainable route to all of them, and because their terms are behind a page that
refuses automated readers — nobody has read them. A league or a secretary that asks to be removed is
removed the same day.

### What this does not decide

The other 285 leagues; whether to pay for LeagueRepublic's plan; and whether league secretaries are written
to before or after their league appears.

### What happened, the same night

**Identifying honestly is refused, so the pilot stopped before it read a page.** `robots.txt` answers 200 to
a client calling itself THRØ and allows exactly the pages the pilot wanted (`/fg/`, and the league's front
page; fixtures, matches, players and live are disallowed and were never wanted). Every content page then
answers **403 from CloudFront** — "Request blocked", generated at the edge, not by LeagueRepublic's own
application. So the sites serve browsers and refuse everything else, and the tool that worked before worked
because it called itself Safari.

That is the answer this decision said it would take: the importer is not given a browser's name, no league
page was read, and nothing was seeded. The email to LeagueRepublic is now the whole of the plan — with one
question added, which is whether they will allow-list an identified THRØ agent at the CDN. Teams reach the
map by the players who play in them (PD-047, PD-049) until they answer.

## PD-050 — Anything a person wrote can be reported, and anyone can be blocked

**Taken on delegated authority, 2026-09-11**, from the launch review: Apple's guideline 1.2 and Google Play's
user-generated-content policy both require four things of any app carrying what people write — filtering,
in-app reporting, blocking, and a published way to reach us — and THRØ has none of them. It is the largest
blocking item between here and a public release, and it is not paperwork: it is a screen, a queue and a duty.

### Decided

**Everything a person wrote can be reported, from where it is read.** Display names, team names, venue names,
league names and profile pictures. A report names the thing, not the person who owns it, and takes one
sentence of reason. It is answered inside 24 hours, which is the promise the stores hold us to and the one
the moderation queue is built to keep.

**Blocking is between accounts and it is mutual in effect.** A blocked account cannot invite, befriend, claim
a seat against, or watch the blocker; neither sees the other named anywhere THRØ can help it. Blocking is not
a report and needs no reason: a player may simply want to be left alone.

**A report is a record, not a deletion.** It is kept with who reported it, when, and what was decided; the
decision is a row of its own. Nothing a player wrote is destroyed by a report — it is hidden, corrected or
left, and the record says which and why. Erasure (PD-039) still erases.

**Nobody posts before agreeing.** A player accepts the terms — which say plainly that objectionable content
is not tolerated — before they can first write anything anyone else will read. Accepting is recorded once,
with the version accepted.

**A minor's report goes to the front of the queue**, and a report about a minor's safety is never left to a
24-hour clock.

### What this does not decide

Automated filtering (a word list is a decision of its own and a bad one taken hastily); appeals against a
decision; and what happens to a team whose admin is suspended.

### Outcome, 2026-09-12 — who answers the queue

The queue was built and had no door: `Safety.queue()` and `Safety.decide()` existed in Kotlin, reachable by
nothing. Closing that needed an authority THRØ does not have — there is no staff, no admin role, and an
event's officials are officials of that event and nothing else.

**The people who answer reports are named at boot**, as a list of account ids in `THRO_MODERATORS`, and the
two routes (`GET /v1/reports`, `POST /v1/reports/{reportId}/decisions`) refuse everybody else. A table was
the obvious alternative and is the wrong one: a list in the database is a list that somebody holding a
session can eventually add themselves to, and the queue holds what people said about each other. A server
that names nobody refuses everybody — including the first caller, which is what an empty table would have
admitted.

This is deliberately the smallest thing that can be true. A real moderation console, appeals, and a way for
a league to moderate its own members are all still undecided, and none of them should be inferred from an
environment variable.

## PD-049 — A team says which league it plays in

**Taken on delegated authority, 2026-09-11**, the same night PD-048 was refused at a CDN. THRØ lists 329
leagues and three of them have teams, because teams come from a league's own published pages and those
pages are closed to a reader that gives its own name. So the other direction, which needs nobody's
permission but the team's own: the people who play in a league put their team on it.

### Decided

**The team's admin or captain says it, and it is carried as their say.** A league THRØ already lists, no
new league invented, and one live claim per team and league — a side may say it plays in two, because sides
do. Saying it twice is saying it once.

**Never inside the league's listing.** A division is what a league published (PD-033) and is filled from
the league's own pages and nothing else; a claim is what a team said about itself. They sit apart
everywhere: `team_league_claim` beside `team_affiliation` in the database, `saidTeams` beside `seasons` on
the public front, and separate words in the app. Saying it gives the league no season, no division and no
affiliation.

**Withdrawable, and kept.** A team moves leagues and a captain mistypes, so a claim can be withdrawn —
marked, never deleted, because who said their team played there in September is still true of September.
Saying it again afterwards is a new claim with its own date.

### What this does not decide

Whether a league can confirm or refuse what a team says about it (a league arriving on THRØ is its own
decision); whether a claimed team shows in a league's standings, which it does not and should not; and
whether two teams claiming the same name in one league is worth resolving.

## PD-052 — A screen is a column, not a phone pulled apart

**Taken on delegated authority, 2026-09-12.** The founder's standing requirement is that every screen is
beautiful on every device and every screen size, with the person's journey through it the priority. The app
already builds for iPad and for landscape — `TARGETED_DEVICE_FAMILY = "1,2"`, both iPhone landscape
orientations, all four iPad ones — so those screens are being shipped today whether or not they were designed.

**This decision was being cited in code before it existed.** `ThroReadable` and five screens referenced
PD-050, which is the reporting and blocking decision; the width rule had no record of its own. That is what
this entry is, and the citations now point here.

### Decided

**One measure, named once.** `ThroReadable` holds content to 560 points and centres it. A screen asks for it;
no view invents its own maximum width, so there is one number to change and one place it is written.

**The board bleeds, and what is read sits in the column.** A map, a slate, a brand field and the scoring
stage run to the edges of whatever glass they are given, because those are the product being looked at. Prose,
rows, forms and tables sit in the measure. A settings list a foot wide is not a tablet layout, it is a phone
layout that nobody stopped.

**Never by stretching.** A phone screen scaled up to fill an iPad is the failure this rule exists to prevent,
and it is why the measure is applied by the screen rather than by the window: the fix for a wide screen is a
column with air around it, not bigger type or longer lines.

**Verified where it is claimed.** The scoring stage is the model — a pure geometry function walked across
eleven devices, both orientations, all twelve type sizes — and the rest of the app is held to the same standard
by looking at it on the device rather than by asserting it in prose.

### Where this stands

**Forty-three call sites**, from ten when the audit ran: every screen in the tab set, and the club, league,
tournament, team, match, account, profile, settings, welcome, readiness and safety screens, the league table,
and the Play flow's setup, result and confirmation.

What is deliberately **not** held to the measure, written down so nobody adds it later believing it was
missed: the components inside the scoring stage, which owns its own width by arithmetic and is walked across
eleven devices to prove it; the top bars and page bars, which belong to the screen's edge rather than to the
column; Home's masthead, where the measure made the board float and was reverted the first time it was tried;
the announcement card, already capped at 340 points by the approved design; and the pinned footers, which are
not content.

Fixed the same night, because each of these was worth more than the one screen it sat on: the five shared
components that truncated long names now shrink them first — an organisation row, a top bar's eyebrow and
title, a player's name, a button's label, and the league table's team column — which reaches dozens of screens
from five edits. The organisation row's meta is a three-part join that never fitted one line of a phone, so it
wraps rather than shrinking to nothing. And the league table's seven number columns now scale with the
reader's text size, where they were literals that stayed put while the numerals inside them grew.

**Looked at, on an iPad Pro 11-inch, rather than assumed.** The measure holds: Home and the Welcome both put
their content in a centred column of about 560 points on an 834-point screen, with the brand field and the
board still running the full width behind it. Two things that looking found and reading could not:

- **The tab bar spread**, exactly as the audit said — five small marks a hand's width apart across a tablet.
  The bar is the screen's edge and keeps the width of it; the tabs now sit in the same measure the content
  does. Fixed and looked at again.
- **Width was the easier half.** A tablet screen is also *tall*, and a phone's vertical rhythm leaves large
  voids down the middle of one. The founder's words: *we don't want a ridiculous amount of negative space.*

### What a screen does with height it does not need

**Centring the content in the room was tried and rejected.** A `ThroRoom` container held short content in the
middle of the page instead of under the bar. Built, looked at, and worse: the same emptiness redistributed,
an island with voids above *and* below. The component was deleted rather than left lying about.

**What works is body, and Settings already had it.** Settings is the screen that reads as designed on a
tablet, and the reason is not its length — it is that its content sits in cards with substance rather than
sentences on bare paper. Play's *how this works* and You's *teams you keep* are cards now, in the same
vocabulary, and both read as composed rather than adrift.

**And the honest part: most of the remaining void is an empty state, not a layout.** The screens that look
emptiest are the ones with nothing in them — no matches scored, no teams kept. Discover fills its page with
the map and Settings fills its page with rows. A screen with something to say fills; the work was making
*nothing yet* look like a decision rather than a page that failed to load. What a tablet should do with the
room when there is genuinely little to say — a second column, a larger board — is still open, and is a
design question rather than a rule to be written here.

**Not fixed, and deliberately not guessed at**: the 400-point brand band behind Home, You and your own profile
is 60% of an iPhone SE's height. On the iPad it is harmless — the page's own paper covers it from the header
down — but that says nothing about a phone in landscape, which is the case the audit flagged and which has
not been looked at. It is a visual constant, and the right number for it comes from looking at it on a
device, not from arithmetic in a commit message.

### What this does not decide

Two-column layouts where a screen earns one — a list beside the map on an iPad is a design question, not a
width rule. Split view and Slide Over, which hand a phone-narrow width to an iPad and which nothing in the app
reads a size class to handle. And the watch, television and Android surfaces, which are PD-051's and
PLATFORM.md's.

## PD-051 — Where THRØ runs

**Taken on delegated authority, 2026-09-12**, in answer to the founder's question about Cloudflare's costs
and the best arrangement for iOS, Android and the web. The reasoning and the numbers are in
[PLATFORM.md](PLATFORM.md); this is what was settled and what was not.

### Decided

**THRØ stays a JVM that holds open connections, and the platform is chosen to fit that.** This is the
decision the others follow from. Cloudflare Workers cannot run it — a V8 isolate has no JVM, and Hyperdrive
is reachable only from inside a Worker — so "move to Cloudflare" is a rewrite, not a migration, and is
refused. The same test rules out Cloud Run (bills and caps an open stream), Railway (cuts at 15 minutes) and
Render's free tier (spins down mid-stream, which is what staging does today).

**Cloudflare's job is the edge, and at our size the edge is free.** DNS, CDN, the free WAF ruleset,
Turnstile, Tunnel and R2 come to $0 a month; the Pro plan's managed rulesets are worth $25 at launch and not
before. This is the answer to "what does Cloudflare cost": nothing, for the part of it we can actually use.

**One region, and it is London.** The players are in the UK and the database round trip is the latency that
matters, so the API and its Postgres sit together in London rather than the API being spread thin.

**No serverless rewrite to chase a cheaper idle bill.** THRØ's pool holds connections, so scale-to-zero
pricing never applies to us and every usage quote is read as 730 hours a month. A platform whose discount is
suspension is the wrong shape for an app whose whole point is a live match.

### What this does not decide

**Anything that spends the founder's money.** Moving Render → Fly (~$6.46/mo) and Neon free → Supabase Pro
($25/mo at launch) are both recommended and neither is done: they need a card, and a card is the founder's.
Until then staging stays on Render and the database on Neon's free tier.

**The order of the surfaces**, beyond noting which commitments already force one. Apple Watch, tvOS, Android,
Wear OS, Android TV and the web are laid out in PLATFORM.md with what each would take; the web is nearer than
it looks, because Google Play requires a web account-deletion URL and an organiser subscription is better
sold off-store. Which we build first is a product decision, not an infrastructure one.

## PD-053 — A league's administrator is named, never self-appointed

**Founder decision, 2026-09-12**, asked because nothing in THRØ can grant league ownership today: the
authorisation rule for a league exists over a tuple no user action produces, and PD-049 left the question
open on purpose. Three routes were put to the founder, who chose the one where nobody can appoint
themselves: *"Dont want false people running it or trying to disrupt."*

### Decided

**A league's administrator is granted out of band**, in the shape `THRO_MODERATORS` already set for the
people who answer reports: a named grant, recorded in `authz.relation` with who granted it and when, and
revocable. Nobody becomes a league's administrator by asking to be.

**First-claimant adoption is refused for a league, though it stands for a team.** PD-047 lets an adult claim
a listed team because that is what a pub side does when it puts a name on a board. A league is different in
kind: its administrator publishes a table that a whole town reads as official, sets what a win is worth, and
decides results. Handing that to whoever asks first is handing a stranger authority over other people's
darts — which is the disruption the founder named.

**The grant history is the record.** A revoked relation is kept, so who ran a league in September is still
answerable in December.

### What this does not decide

**How this reaches 329 leagues.** Verification against a league's own published website — it already carries
one, and every league row carries its provenance — is the route to self-service, and it is not built. It also
fits the organiser subscription MONEY.md puts on the web, where a billing relationship is itself evidence.
Until then a league administrator is named one at a time, which is slow and cannot be gamed.

## PD-054 — THRØ has a standard for points, and a league may write its own

**Founder decision, 2026-09-12**: *"Have a well thought out Throw standard but also allow leagues to do their
own custom set up as some leagues are double in leagues etc."* This closes the half of OD-022 that was open —
whether THRØ ships a standard a league may override — and it closes it the other way from the caution
recorded there, with the condition that makes the caution unnecessary.

### Decided

**THRØ's standard: two points a win, one a draw, none for a loss, ordered by points, then leg difference,
then legs for.** It is what most UK darts leagues already play, and a league that has said nothing gets a
table rather than an empty screen.

**A league may write its own, and when it has, the league's own orders the table.** Points per leg, per
match, bonus points, a different tie-break: a league's rules are the league's, held as an approved policy
against that season and versioned, so changing them next season cannot re-order last season's table.

**The standard is never silent — this is the condition, and it is not optional.** Every table says which
policy ordered it and whether that policy is the league's own or THRØ's standard. OD-022's warning was that
*"a constant buried in a table calculation would be THRØ deciding a league's rules for it without saying
so"*; the fault in that sentence is *buried*, not *constant*. A standard that names itself on every table it
orders, beside the way to replace it, decides nothing on a league's behalf.

**Format is not points.** Double-in, sets, best-of and the rest are a match-format policy; a league that
plays double-in still scores its table in points. Keeping them apart is what stops "how we play" and "what a
win is worth" from being one tangled setting.

### What this does not decide

Whether THRØ's standard carries bonus points — it does not, and a league that awards them writes its own.
Whether two leagues' tables may be compared (OD-022 says they may not, and nothing here changes that). And
what unit a league's results are recorded in, which PD-022 decided and the server has not yet implemented:
`legs_home` and `legs_away` will hold legs, matches or match points depending on who typed them, and a table
that heads them *Legs For* without knowing is mislabelling every row.

## PD-055 — A named official may declare a result nobody scored on THRØ

**Founder decision, 2026-09-12**, asked because the server was refusing something the phone has always
allowed. V014 admits a `played` league outcome only where the fixture cites a real match, so a league could
award a fixture but could not record that Grange A won it 5–2 on a Thursday from a paper card. Meanwhile the
phone's own club book keeps both and holds them apart — its constraint "refuses a scored result with no match
and an official's word with nobody's name". A league secretary could therefore keep their season on a phone
and not on THRØ, which is the wrong way round.

### Decided

**A fifth outcome: a result declared by a named official.** It carries a scoreline and no match, and it
counts in the table exactly as a played result does, because it is what happened.

**It is never evidence.** `decided_by` is NOT NULL, so a declared result always has somebody's name behind it
and nothing else does. It can never move a rating, and every table separates the two: the `evidenced` column
counts the fixtures whose result came from a match scored on THRØ, and before this decision that column was
tautological — every played outcome cited a match by construction, so the count was always the whole column
and told nobody anything.

**A fixture that was scored on THRØ cannot have a result declared over the top of it.** Where a match exists
the result is read from the match; an official declaring a different scoreline would be overwriting evidence
with a recollection. Correcting a played result is what superseding is for, and that is untouched.

**The rejected option is recorded because it was tempting.** The third way to make the foreign key happy is
to invent a match from the typed score. That writes a match nobody played, with no visits, into the evidence
schema — the one place this codebase refuses to put anything that did not happen — and every later rating and
statistic would read it as real. It was put to the founder as an option and not chosen.

### What this does not decide

Who may declare one, which is PD-053's named administrator and needs the routes that do not exist yet.
Whether a league may declare a result for a fixture whose match was abandoned. And whether a player whose
match was declared rather than scored should be told — they probably should, and nothing tells them yet.

## PD-056 — The web is the next surface, and it is a public face rather than a second app

**Founder decision, 2026-09-12.** Asked which of four surfaces to build next — the web, Android, Apple
Watch or a television — with everything buildable on iPhone and iPad done. They chose the web, which is
also what the analysis pointed at: two commitments already depend on it, and the other three are easier
after it.

### Decided

**The web is built next**, and it starts as three pages: the leagues THRØ knows, a league season's table,
and how to delete an account.

**It unblocks Android before Android starts.** Google Play will not accept an app that carries accounts
without a web URL where a person can ask for theirs to be deleted. That page exists now and says exactly
what the app says — what goes, what stays, and why the matches stay.

**A table is worth more on the web than anywhere else.** It is the thing a league member sends to the side's
group chat, and a link opens for everybody whether or not they have the app. The same route the phone reads
serves it, so the two cannot disagree about a table, and PD-054's condition holds on the web as it does on
the phone: every table says whose rules ordered it.

**Static, no framework, no build step.** The pages need the generated tokens, one fetch and a little DOM.
The tokens are copied in with a check that fails on drift, because a static host will not follow a link out
of the directory it serves, and an unguarded copy is how a brand forks.

**The API is on the same origin.** The client calls `/v1/...` with no host, so the edge routes `/v1/*` to the
API (PD-051) and the browser never makes a cross-origin request: no CORS, no preflight, no second host, and
no credentials in a query string. A development server mirrors that arrangement rather than working around it.

### What this does not decide

Signing in on the web, and with it the organiser's own surface — entering results from a laptop, which the
routes behind PD-053 already allow and which is the obvious next piece. The privacy policy and terms, which
are founder documents. And where it is hosted: Cloudflare Pages is free and already the plan, but the domain
is the founder's to buy, and until there is one the deletion page has no address to give a store.

## PD-057 — The address THRØ lives at, and what serves it

**Recommendation to the founder, 2026-09-12**, asked for a domain and whether Render could be used. The
purchase is theirs — this is the evidence and the shape that follows from it.

### The domain: `thro.uk`

**Available**, confirmed against Nominet's own register: *"No match for thro.uk. This domain name has not
been registered."* Four letters, the brand exactly, nothing appended, and the country the app is for — every
league in it is British. About £8–10 a year.

What else was checked, so the choice can be read back:

| Domain | State |
|---|---|
| **`thro.uk`** | **free** — the recommendation |
| `thro.app` | taken (2015, GoDaddy nameservers). The obvious one, because the bundle id is `app.thro.darts`, and it is gone |
| `thro.co.uk` | taken since 2014 by a domain broker (`brandselection.co.uk`), so it would cost a negotiation, not a registration |
| `thro.io`, `thro.pub`, `thro.team`, `thro.games`, `thro.club`, `getthro.com` | taken |
| `thro.bar` | free, and not recommended: a British darts player drinks in a pub, not a bar |
| `throdarts.com`, `playthro.com` | free — worth £10 as a defensive second that redirects, not as the address |

**The bundle id does not force `thro.app`.** `app.thro.darts` is only a reverse-DNS-shaped string; what has
to match a domain is the associated-domains entitlement and the relying-party id, and those can be `thro.uk`.

### Render, since the founder asked

**Yes for the web, and it is the better answer than the plan.** A Render static site is free, deploys from
the same repository, and — the part that matters — supports **rewrites**, so `/v1/*` is proxied to the API
service. The pages and the API are then one origin, which is exactly what `thro.js` already assumes: no
CORS, no preflight, no second host in the app's configuration, no token in a query string. One dashboard,
one account they already have. `render.yaml` carries both services now.

**And a second rewrite that is easy to forget**: `/.well-known/apple-app-site-association`. iOS offers a
passkey for a domain only when that domain serves the association file, so the moment the pages live at
`thro.uk`, `thro.uk` must serve it — not the API's own hostname.

**Keep the API on Render for now**, and revise PD-051 accordingly. Fly London is nearer the players, but the
honest difference between Frankfurt and London for this app is tens of milliseconds, and it is not worth a
second platform while there is one developer. The change worth making is **off the free instance**: a free
Render service sleeps after fifteen idle minutes, and a sleeping server drops a live match stream — which is
the one thing in THRØ that cannot tolerate it. Starter is $7 a month.

**Revisit at about a thousand players**, where the curves diverge: Render is roughly $25 a month at that size
against Fly's $7, and $39 against $14 at ten thousand. That is the moment to move, not now.

### What this does not decide

The purchase itself, which needs a card. Whether to take `throdarts.com` defensively. And the switch-over,
which is a short checklist in DEPLOY.md rather than a decision: the relying-party id, the entitlement, and
the association file all name a host, and all three change together or passkeys stop working.

## PD-058 — The domain is the switch, and the app gets its own subdomain

**Founder, 2026-09-12**, on the free Render arrangement: *"the whole free server layout is only while I & a
very small number of people will be testing, once live to public it will have the domain etc. so I wanted
the best way to wire it up where adding the domain is what kicks it all into gear."*

That is the right instinct and it needed one correction, which changes the target arrangement.

### The app talks to `api.thro.uk`, not to `thro.uk`

The earlier sketch (PD-056) put everything behind one name: pages at `thro.uk`, `/v1` rewritten from there to
the API, and the app pointed at `thro.uk` too. One origin, one relying party, no CORS. That is right for the
**browser** and wrong for the **app**, because it puts Render's static CDN in front of every request the app
makes — including the live match stream. A CDN that buffers a `text/event-stream` is exactly how a live
match dies, and ADR-007 exists because that failure is silent and looks like the app being broken.

So with a domain the arrangement is two names:

| Name | Serves | Who calls it |
|---|---|---|
| `thro.uk` | the static pages, with `/v1/*` rewritten to the API | the browser |
| `api.thro.uk` | the API service directly | the app |

**One relying party covers both**, and that is the entire value of owning a domain here. WebAuthn permits an
origin to assert a relying party that is a registrable-domain suffix of itself, so `https://api.thro.uk` may
assert `thro.uk`, and a passkey created on the website works in the app. Two `*.onrender.com` subdomains
cannot do this at any price: `onrender.com` is on the Public Suffix List (line 15457), which makes each
subdomain its own registrable domain. **This is why web sign-in waits for the domain** — not cost, not
effort, a rule.

### The switch is a command, because a find-and-replace would break it

Three files name the host, and after the switch they do not name the same one: the relying party is
`thro.uk` and the app's base URL is `https://api.thro.uk`. A replace-all would set the relying party to
`api.thro.uk` — which still works, silently, for anyone with no passkey yet, and permanently separates the
website's credentials from the app's. It would also drag `render.yaml`'s rewrite destinations, which address
the API *service* and must not move, onto the public name.

`tools/host.py` encodes the two legal arrangements: `--set thro.uk`, `--set-free`, and a bare run that
checks. It refuses a name that cannot be a relying party (`www.` prefixed, or anything under
`onrender.com`), names the api-subdomain mistake specifically rather than reporting it as three unrelated
mismatches, and round-trips to the identity. It runs in CI, so a half-finished switch fails the build.

### Passkeys do not survive the switch, and testers should not be using them

A passkey is bound to one relying party; changing it invalidates every credential registered under the old
one. That is WebAuthn being correct — a credential that followed a hostname across an ownership change would
be one that whoever bought the old name could claim.

Sign in with Apple **is** unaffected: a native app's audience is the bundle id, not a host. So the guidance
for the testing period is to sign in with Apple, and then the domain switch costs nobody an account. This is
recorded because it is a decision about what to tell people, not only about what the code does — the cost of
getting it wrong is a tester locked out of a season they entered.

Order of operations, and what stays on Render's dashboard rather than in the repo:
[docs/runbooks/GOING_LIVE.md](../runbooks/GOING_LIVE.md).

## PD-059 — A result can be corrected, and correcting it cannot overwrite somebody else's correction

**Found in review, 2026-09-12**, while answering a question about hosting. The organiser page said, in
shipped copy: *"A result already in is corrected by a new decision that supersedes it, which this page does
not do yet — the app and the API can."* **Neither could.** The database has taken `supersedes_outcome_id`
since V014 and the store has passed it since PD-055, but no HTTP route ever did, so the only answer a
corrected result could get was a 409 telling the caller to do a thing nothing was able to do. A league
secretary who mistyped 5–2 as 2–5 had no way back.

### Correcting is a second decision that names the first

Both writing routes take an optional `supersedes`: the `outcomeId` of the result standing now. The earlier
decision stays on the record with its author and its time, because a league's results are a history of who
decided what, not a mutable scoreline.

**Naming it is not ceremony — it is the concurrency control.** The V042 trigger refuses an outcome that
leaves any other live outcome unaccounted for, so a correction that names a result somebody else has already
corrected is rejected rather than applied on top. Two officials with the page open cannot silently overwrite
each other, and the one who loses is told to reload rather than being quietly discarded. This is the same
rule the app's own writes obey (`row_version`), reached by a different mechanism, and it is why the answer
had to be "name what you are replacing" rather than "PUT the new score".

The refusal says which case it is, because the trigger cannot: *"already has a result"* when nothing was
named, and *"changed while you were entering one"* when the named one is stale. The handler knows which
because it knows whether the caller sent anything.

### The reader had to name the standing result

A page that can see a fixture has a result and cannot say **which** result has only a blind overwrite
available to it — the thing the database refuses. So `seasons.fixtures` now carries the live outcome's
`outcomeId`. It is public, like the scoreline it identifies.

### And a void reopens the fixture (V043)

Chasing this turned up a second, quieter fault. Every reader in THRØ treats a voided outcome as no result —
the tallies skip it, the fixture list skips it, and a test has asserted since V014 that a voided fixture is
counted unplayed. The **writer** did not: `outcome_is_a_recorded_decision()` counted every unsuperseded
outcome, voids included. So a voided fixture appeared in "still to enter", and entering one was refused with
*"this fixture already has a result"* — about a result the page could not show and therefore could not offer
to correct. A dead end, made of two halves of one system disagreeing about the word "live".

V043 teaches the trigger the rule everything else already followed. A void annuls; the fixture is open; the
next decision is a first decision. Both the voided outcome and the void stay on the record.

**Not done, deliberately:** there is no route that voids a result. The store can (`voidOutcome`) and nothing
over HTTP calls it. Annulment is a different act from correction — it says a fixture should be replayed —
and it wants its own decision about who may do it and what the league sees, rather than being added because
the plumbing happened to be open.

## PD-060 — The brand field is a share of the screen, not a number measured in portrait

**Looked at on a device, 2026-09-12**, closing the one thing PD-052 left open on purpose: the 400-point
brand field behind Home, You and a profile, *"which is 60% of an iPhone SE's height and covers a landscape
phone entirely"*, and whose right number *"comes from looking at it on a device."*

### What the number was

400 points is not a design decision. It is the answer to "how far can this page be dragged down before paper
appears above the field", measured on a phone held upright. That question has a different answer on a screen
of a different height, and the constant carried the portrait answer everywhere: an iPhone 17 Pro is 402
points tall in landscape and an SE is 320, so on its side the field was the whole background.

`ThroBrandField.height(in:)` is now `min(400, height × 0.7)`. **No portrait phone moves** — the shortest,
an SE at 568 points, asks for 398 and would have taken 400 — and no screen is ever covered edge to edge.
Four tests hold both halves against the four phone sizes THRØ runs on.

### What looking at it actually showed, which was not what was expected

**The field is invisible on the screens it sits behind, in both orientations.** It was built with the old
constant restored and photographed beside the new one on the You tab in landscape, and the green in each
case stopped where the page's own card stopped — 156 points in one state, 245 in another — never at 400 and
never at 281. The page paints its own paper over the background, so the only time the field is on show is
during a rubber-band pull.

So this is a correctness fix and not a visible one, and it is recorded that way rather than dressed up: a
background that is larger than the container it backs is wrong whether or not something happens to be
covering it, and the next page that does not paint its own paper would have found out the hard way. The
earlier iPad finding — *"harmless, because the page's own paper covers it from the header down"* — turns out
to hold for a landscape phone too. That is the answer to the open question, and it is a negative result.

### The thing landscape did show

**A landscape phone gives most of its short screen to a header.** On You in landscape the sign-in prompt
takes 61% of the 402 points available and the content it introduces — who plays on this phone — is squeezed
into what is left; on Home the masthead takes 29% before the first card. In portrait these are proportionate;
in landscape they are a phone layout rotated rather than a landscape layout.

That is the same finding as the tablet one recorded in PD-052, in a second place: **a screen with a different
shape needs to spend its room differently, and THRØ currently spends it the same way everywhere.** It is
noted here rather than fixed, because the fix is a design decision about what a masthead does when the screen
is short — compress, move beside the content, or go — and that is worth choosing rather than defaulting into.

## PD-061 — A short screen gets a masthead folded to one line

**Founder, 2026-09-12**, asked what a masthead should do when the screen is short and chose **compress it**,
and separately that a phone on its side is a case THRØ should be *good at* rather than merely not broken at:
people prop a phone on a table beside a board, and the scoring screen already puts the keys beside the board
in landscape, so the app has been promising landscape works for some time.

### What it does

`ThroMasthead.shape(forHeight:)` — below 500 points the mark and its line sit on one row at the heading2
cap; at or above it they stack at the display cap, exactly as they always have. Every phone THRØ runs on is
320 to 440 points tall on its side and 568 to 956 upright, and a tablet is 834 on its side, so the threshold
has forty points of room either way and **a tablet keeps the full mark** — 834 points is taller than an
upright SE and there is nothing to buy by taking it away.

The rule is arithmetic on the screen, in the same shape `ThroStage` chooses between a board above its keys
and a board beside them, because a number that can be tested is a decision that cannot quietly drift. The
view cannot measure the window, so it reads iOS's vertical size class; **a test holds the two to the same
answer on every device**, because two ways of saying one thing is how a rule becomes two rules.

Looked at on an iPhone 17 Pro: Home's green band goes from 116 points to 51 of the 402 available, and the
Continue button — which was off the bottom of the card — is on the screen. Portrait is pixel-identical.

### And the welcome screen was clipping the way out

Chasing this found a worse thing on the first screen of the app. The welcome is a fixed composition with no
scroll view, deliberately — heading, ask, choices, slack shared between them, because the first screen is not
a document. On a phone on its side it did not fit, and SwiftUI clipped **both ends**: the mark went off the
top and *"Not now, just score"* went off the bottom. That is the control that gets a player past sign-in, and
on a landscape phone there was no way to reach it.

It now scrolls **only when it does not fit**: the column is given the viewport height as a minimum, so the
two spacers expand exactly as they did and a portrait phone is unchanged to the pixel, and on a short screen
the column grows past the viewport and the scroll view carries it rather than the layout eating the ends.
The welcome's mark also takes the plain display cap on a short screen instead of 1.35×.

### Still open

What a **tablet** does with genuinely spare room — two columns where a screen earns them, a larger board —
is untouched and stays PD-052's question. Folding a masthead buys back a strip; it does not answer what to do
with a screen that has too much room rather than too little.

## PD-062 — One thing, one column; two things, two columns

**Founder, 2026-09-12**, given three options for what a screen with genuinely spare room should do and shown
a preview of each. They chose **two columns where a screen earns them** — a league's table beside its
fixtures — over scaling everything up or showing more in one column. This closes the question PD-052 left
open, and the founder's own summary of it is the rule: *one thing, one column; two things, two columns.*

### The rule

`ThroReadable` holds a screen to 560 points because a paragraph a thousand points wide is a phone page
pulled apart. That is right for a screen that is one thing and wrong for a screen that is two: a table and
the fixtures it was computed from are separate objects a reader compares, and stacking them on a tablet
leaves half the glass empty and puts the next fixture below the fold of a screen with room for both.

`ThroSpread` is arithmetic on the width available, in the same shape `ThroStage` chooses between a board
above its keys and a board beside them. **The threshold is derived, not picked**: a column must be at least
340 points — an iPhone SE has 280 points of content and every component in THRØ is proven at that, so 340 is
that with margin — and the screen that spreads is the narrowest that fits two of those with a gutter, which
is 712. Past 960 the pair stops widening, so two columns never become two rooms.

**A test asserts the rule against its own stated reason**, and it earned its keep immediately: the first
pair of numbers written — a 700 threshold beside a claim of 400-point columns — disagreed, and the test said
so within a minute. A threshold chosen independently of the justification beside it is a number nobody
checked.

### What it took beyond the rule

The app had no fixtures at all — they existed on the web and nowhere else — so this added `LeagueFixtures`
to the client, the call beside `standings`, and the column that draws them. The two load together, because
they are read from the same rows on the server and a reader compares them; **the fixtures are allowed to
fail on their own** and say so in a quiet note rather than taking the table down with a full-page refusal.

The words carry the rules the drawing cannot, and are tested apart from it: an award reads *"Feathers A
awarded, Riverside A"* and never as a scoreline, because legs an award invented would reward an unplayed
match in every tie-break beneath it (ADR-012); a declared result reads as the result it is and says *"the
league's word"* underneath, because "5–2" cannot carry PD-055's distinction on its own; a team THRØ may not
name is *"A team"* and not a blank; and a scoreline is spoken as *"5 to 2"*, because an en dash between two
numerals is not a word and read out is the same sound as fifty-two.

### And the layout was correct and unreachable

Looked at on an iPad and it stacked. The rule was right and the container was 577 points: this screen is
presented in a sheet, and a sheet at the form's default width is narrower than the threshold. A tablet was
getting a phone page floating in the middle of a map. The table's sheet is now `.presentationSizing(.page)`
— the other two sheets it shares a presenter with are single objects and keep the form width, which is the
right size for them.

Verified on both: an iPad Pro 11 shows the table beside four fixtures to come and five already in; an iPhone
17 Pro shows the table, then the rules, then the fixtures under them.

### Where it applies next

**Discover is done too**, and the split is the one the screen already had in it: what is out there — the
leagues near you and the tournaments taking entries — beside what is yours. On a phone they run one after
the other as they always did.

Doing the second one found the rule's first sharp edge. `yours` carried a section gap of its own to separate
it from the section above, and beside `ThroBeside`'s gutter that became 64 points on a phone and pushed the
right-hand column 32 below the left on a tablet. **One source for the gap, and it is the thing that knows
which arrangement the screen is in** — a half that adds its own spacing is a half that cannot be put
anywhere else.

Home is not a candidate: the Continue card is the one unfinished thing on the screen and halving it would
make it smaller, not clearer.

## PD-063 — THRØ asks a sign-in provider for one thing, and that is the subject

**Found while writing the privacy policy, 2026-09-12.** Writing down what THRØ collects meant reading what
it actually asks for, and the two did not match.

The app's own words to a player, on two screens: *"THRØ has no email or phone."* True of the database —
there is no email column anywhere in `identity` — and **not true of what was being requested**:

| | Asked for | Read | Stored |
|---|---|---|---|
| Google | `openid email profile` | subject only | subject only |
| Apple | `.fullName` | subject only | subject only |

`IdTokenVerifier.Claims` carried `nameHint` and `emailHint`, both parsed out of every token and **read by
nothing**. So on every Google sign-in a person handed over their email address, saw a consent sheet listing
it, and THRØ threw it away — having told them on the previous screen that it has no email.

**Now: `openid` alone, no Apple scopes, and the two hint fields are gone.** Nothing changes about what THRØ
stores, because it never stored them; what changes is what it asks a person to give.

### Why this is a decision and not a tidy-up

**A scope requested is data collected**, whatever happens to it next. It appears on the consent sheet, it
crosses the wire, it is in a log somewhere at the provider, and on Apple's and Google's privacy
questionnaires it is a line THRØ would have to declare, defend and be able to delete. Removing it does not
simplify a form — it makes an entire category of the form *"not collected"*, which is a stronger position
than any wording could buy, and it makes the sentence on the screen true.

It also removes a temptation. A field holding somebody's email address that nothing reads is a field the
next feature reaches for without a decision being made.

**What it costs:** a display name cannot be pre-filled from the provider. It never was — a player types
their name — so this costs nothing today. If pre-filling is wanted later it is a decision to take then,
with the consent sheet it implies, rather than a capability sitting quietly open.

The test asserts the absence as well as the presence: `email`, `profile`, `phone` and `address` must not
appear in the scope. The failure being guarded is somebody adding one back for a feature that never lands.

## PD-064 — Finish what exists, then the rest of Apple, then Android, then the rating

**Founder, 2026-09-12**, asked which large piece to start next and revised the order instead:
*"polish & perfect what exists first and then all apple related products if possible then continue with
android etc. then rating research lab."*

This revises the order PLATFORM.md has carried since PD-057, which put **Android** next after the web.

| | Was | Now |
|---|---|---|
| 1 | Web | **Finish what exists** — the two-column rule across the remaining screens, the iPad and landscape passes, the surfaces a tester will actually touch |
| 2 | Android | **The rest of Apple** — the watch app, then tvOS for a venue |
| 3 | Watch | Android, and Wear OS behind it |
| 4 | TV | The rating research laboratory, and the leaderboard it unblocks |

**Why it is the right revision.** The web went out today and nobody has used any of this yet. A second
platform doubles the surface that has never been in front of a person, and every fault found on Android
would be a fault that was already on iPhone. The three things found by *looking* at what exists — a
masthead eating 61% of a landscape screen, the welcome screen clipping the way past sign-in, a two-column
layout that was correct and unreachable — were all in shipped code, none had a failing test, and none would
have been found by building something new.

And Apple before Android is cheaper than it looks: the watch and tvOS share the design tokens, the pure
Swift engine and the whole client, so they are new surfaces on a known stack. Android is a second
implementation of everything.

**What it costs, said plainly:** Android is half the market and it waits. The deletion URL that unblocked
Play is live and will keep, so nothing expires by waiting — this is a decision about order, not about
whether.

**The rating stays last on purpose.** It is not last because it is least wanted; it is last because
OD-001 cannot close without real matches, and real matches need players on a finished app. Building the
laboratory earlier would produce a harness that could rule candidates out on simulated players and could
not rule one in.

## PD-065 — A result can be annulled, and an annulled fixture says so

**Founder, 2026-09-12**, given three ways to handle a fixture that should not have had a result — played
under protest, abandoned, ordered again — and chose *"annul, with a reason on show"* over leaving it out and
over requiring a second administrator to confirm.

The store has had `voidOutcome` since V014 and nothing over HTTP called it, deliberately: annulment is a
different act from correction and wanted its own decision about who may do it and what a league then sees.

### It is not a correction

A correction says the scoreline was wrong. An annulment says the fixture should not have had a result at
all. So it is its own route, `POST /v1/fixtures/{id}/void`, with the same authority as entering a result —
a league administrator — because inventing a higher tier would be machinery for a need nobody has
demonstrated, and **the two-administrator option is unusable in a league that has only ever named one**,
which is every league on THRØ today.

### The part that makes it safe is not the authority, it is the visibility

Before this, a voided fixture simply reappeared among the ones still to play, indistinguishable from one
nobody had got round to. **A result that vanishes without trace is how a league stops trusting its own
table**, and it is worse than not offering the feature.

So the annulment is carried beside the absence. `seasons.fixtures` gained `annulled` — the reason, which the
database has required of a void since V014, and when — and every surface prints *"annulled, to be replayed
— played under protest"* where a fixture is open for that reason. The old result stays on the record,
superseded; nothing is rubbed out.

**Whoever annulled it is not named.** `decided_by` is NOT NULL so the record can always answer for it, but
that endpoint is public and putting an official's name on a public page is a disclosure decision nobody has
taken. This deliberately departs from the sketch the decision was taken against, which showed a name.

**`annulled` means open, and stops being true the moment a result stands.** A void stays unsuperseded after
a replayed result is entered — V043 lets a decision follow an annulment without superseding it, because an
annulment terminates rather than links — so the row is still there while the fixture is no longer open. The
first version reported both at once and a test caught a fixture showing a scoreline and an annulment side by
side.

A reason is required and refused with a sentence rather than a validation error: *"An annulment says why. A
result withdrawn without a reason is one nobody can answer for."*

## PD-066 — A segmented control is as tall as a segment

**Found by looking, 12 September 2026**, in the polish pass the founder asked for.

The chosen segment's green fill did not reach the top and bottom of its own cell. On an iPad's match setup
it drew a short green block with white above and below it, and the dividers either side ran the full height
past it — a smaller control floating inside a larger one, on the screen where a player picks 501 and best of
five.

**The cause is that a `Rectangle` is greedy.** The dividers between segments are rectangles one point wide
with no height given, so offered more height they take it; the segments carry `minHeight` and no maximum, so
they do not. The control therefore grew to whatever the parent had going spare while the selection stayed at
the touch minimum, and the gap between the two was the white band. It was wrong on a phone as well and
invisible there, because a phone had no spare height to hand it.

Two changes, both true independently: the row reports its ideal height rather than accepting what it is
offered, so a segment sets the height and the dividers follow; and the segment's fill is allowed to reach
the full height of its cell. The first stops the control growing at all, the second means the fill matches
its cell even if some future parent forces a taller row.

**Why this counts as more than a pixel.** The fill *is* the selection — it is the only thing that says which
of 301, 501 and 701 is chosen — and a selection that does not fill the thing it selects reads as a rendering
fault. The setup screen also got shorter, because four rows that were each about twice their proper height
are now the right height.

No test: this is a layout height in SwiftUI and the honest verification was building it, looking at it on an
iPad, and looking again on a phone to be sure nothing moved there.

## PD-067 — A stale annulment is an answer, and it was a server fault

**Found by exercising the route against a real server, 12 September 2026** — not by a test, and not by
reading the code. Annulling a result twice with the same outcome id returned **500**.

`outcome_supersedes_once` is a unique index that stops two decisions both claiming to replace the same one.
It is right and it matters: two outcomes superseding one outcome is a fork in a chain that nothing
downstream could read. What was wrong is that nothing translated it.

**Why a correction never hit this and an annulment does.** For a correction the trigger gets there first: the
newer result is live and unaccounted for, so *"already has an outcome"* is raised and mapped to a 409. For an
annulment the trigger does not fire at all — V043 keeps voids out of the live count, and the result being
named is already superseded by the first void — so the insert reaches the index, which raised a constraint
violation nothing was catching.

It is now the same 409 as every other stale write, with the same instruction: *"That result has already been
dealt with. Reload, and act on the one that is standing now."* The correction path gets it too, as a second
line of defence behind the trigger.

**How it is reachable:** two officials annulling the same result, or one person pressing the button twice.
Both are ordinary. A 500 tells a league secretary that THRØ broke, when what happened is that somebody
else got there first — and the difference between those two sentences is whether they trust the app with
their season.

Worth recording as a method rather than a fix: this class of fault — a real constraint, unmapped — cannot be
found by reading, because the code looks correct at every layer. It was found by calling the route with the
wrong thing twice.

## PD-068 — A page with nothing on it is the board

**Founder, 12 September 2026**, shown the measurements from the polish pass — Home on an iPad with nothing
scored is a card with **77% of the page empty** beneath it, You 56%, Play 54% — and given three answers.
They chose the field.

### Why a card was the wrong shape, having been the right one

PD-052 made every empty state a card, and that was correct: *no tournaments listed yet* sits under Discover
beside leagues that do exist, and reads as one part of a page. It stops being correct when the empty state
**is** the page. On a phone that card is most of the screen and looks like the page; on a tablet it is a
notice in the corner of a sheet of cream. The same pass tried centring the card and rejected it — *"the same
emptiness, redistributed"* — and a bigger card is a bigger empty box, so neither answer was available.

**The field has no size of its own to be too small.** It is a background: it fills a phone, a tablet and a
phone on its side by construction, which is exactly why it answers a question that scaling a box does not.
It is also the surface the app opens on, so a first launch goes welcome → Home without leaving the green.

### What it is

`ThroNothingYet`: the board with its lamp a little above the middle, the invitation chalked under it, and
the action as a chalk key. It uses `ThroBoard`, `ChalkKeyStyle` and the on-board inks that already exist —
no second vocabulary, and no new colours to hold against the contrast floor.

**It is a state and not a size.** The same on a phone as on a tablet, because a screen that changed shape by
device is two designs to keep in step, and the point of the field is that it is one.

**Home keeps its masthead**, which is already green: the wordmark and the board below read as one surface
with a lamp in it rather than a green strip above a green page. And there is no scroll view, because there
is nothing to scroll — a page that scrolls past its own emptiness is how the card came to look like a notice
pinned to the top.

### Where it applies, and where it does not

Only where the page has **nothing at all**: Home with no matches, no archive and no problem. Play and You
are not empty pages — Play has its invitation and its two explainers, You has a profile — so their 54% and
56% are short pages rather than empty ones, and this decision does not cover them. Saying so rather than
applying it everywhere: a page that has something to say and says it in a small space is a different problem
from a page with nothing to say.

Two things were wrong in the first build and are recorded because the fix is not obvious: `ChalkKeyStyle`
sets no ink, so the label came out near-black on lit green until it was given chalk; and a keypad key is
full width because it is one of twenty in a tray, which made one invitation read as a bar until it was sized
to its own words.

## PD-069 — Two columns need two things in them, and Play was not one

**Tried and mostly reverted, 12 September 2026.** PD-062's rule — one thing, one column; two things, two
columns — was applied to the two remaining short pages. One worked conditionally, one did not work at all,
and the failure taught the rule something it was missing.

### Play: reverted

Play looked like two things — what you do, and how the thing you are about to do behaves — and split cleanly.
Then it was looked at. **The void got bigger.** Halving the height of the content on a page whose problem is
that it has little content leaves more empty page, not less; and it cut the one primary button on a screen
whose entire job is *start a match* down to half width. Play's problem was never that it was stacked.

Back to one column. Recorded rather than quietly dropped, because "it is two things" is a tempting reading of
almost any page and this is what it costs when the two things are not comparable in weight.

### You: split only when there is somebody in the left column

You genuinely is two things under its header — the people who play on this phone, and the teams kept on it —
and splitting it was right in principle and wrong on the tablet it was tried on, where nobody had played yet.
The left column was empty and the teams sat to the right of a hole. **A half with nothing in it is worse
than no split at all**: it reads as a page that failed rather than as a page with one thing on it.

So `ThroBeside` takes `split:`, and the caller answers it. SwiftUI cannot ask a view whether it is empty, and
a container that guessed would guess wrong; the screen knows which condition fills its half and says so. You
passes `!people.isEmpty`, and stacks otherwise exactly as a phone does.

### What the rule is now

Two columns need **two things that are both there and comparable in weight**. Width is necessary and not
sufficient: the league table beside its fixtures and Discover's *out there* beside *yours* both hold, because
each half always has something and neither dwarfs the other. Play failed the second test and You could fail
the first.

## PD-070 — A slate's subject is width, so it is not held to the reading measure

**Found by playing a match on a tablet, 12 September 2026.**

*Match ready* is a fixture written on a slate, and the slate is meant to hold the screen — no scroll, no
field of paper under one button. It was also held to `ThroReadable`'s 560 points, so on an iPad it held a
**tablet's height at a phone's width**: a portrait-phone-shaped green box, 430 by 800, with three lines
floating in the middle of it.

The measure exists for prose. **A slate's subject is two names either side of a mark**, which is width, and
PD-052 already carves out exactly this — *"a screen whose subject IS the width says so by not using this"*.
So it uses the width, capped at `ThroSpread.measure` so it does not become a wall on a 13-inch tablet.

At 834 points the slate is now about square, and it reads as a board with the fixture chalked on it rather
than as a phone screen someone stretched. Nothing changes on a phone, where the width was never the
constraint.

### And the scoring screen, looked at and left alone

Same session, same tablet: the scoring screen puts the head at the top, the keys at the bottom and a large
field between them. That is `ThroStage` doing exactly what it is specified to do — a tablet held upright
stays stacked and gets the biggest number on the ladder — and the space between is the board's own field,
which is the surface and not a void. It has 1,056 screens of arithmetic behind it and a written rationale
for every part. **Looked at, behaving as designed, not touched**, recorded so the next pass does not
rediscover it as a fault.

## PD-071 — The scoring screen measures its room, which is why it cannot clip

**Investigated and closed with no change to the layout, 12 September 2026.** Recorded because the
investigation cost an hour and the next person to look at a landscape screenshot will have the same
suspicion.

A match was scored on an iPhone 17 Pro on its side, and the bottom of the screen looked clipped: the ledger
and the **ENTER SCORE** key both appeared cut by the edge. That is the app's core screen, in the orientation
PD-061 just committed to being good at, so it was chased down.

**What the numbers said.** The device was not in `StageTests`' list — it is the simulator this project is
developed against, which is the only reason a doubt about it could not be answered by running the tests. Added
(402 × 874), and the sixteen stage tests pass. Probing further: beside the board the tray clears the height by
exactly **1.0 point**.

One point looks like fitting by luck, and a stricter assertion was written to convert the suspicion into a
failing test. It failed — everywhere, including an iPhone SE — which is what showed the assertion to be wrong
rather than the layout. **Beside the board the tray is given the whole height on purpose**; it clears by
whatever `keyHeight`'s rounding-down leaves, and that is 1.0 point by construction rather than by chance.

**And it cannot clip, for a reason worth naming.** The screen passes `GeometryReader`'s own `proxy.size` into
`ThroStage.choose`. The stage measures the room it actually has rather than a safe-area inset modelled from
published figures, so a tray that fills that height is flush with the bottom of the safe area — which is
exactly what a screenshot of it looks like. The fragility a one-point margin implies would be real if the
height were modelled, and it is not.

**What is kept:** the iPhone 17 Pro in the device list, and a note at the assertion site so the same hour is
not spent twice. **What is not:** any change to the stage, whose arithmetic was right.

## PD-073 — Apple keeps its `.fullName` scope until somebody watches sign-in work

**Reverted the same day it was made, 12 September 2026.** PD-063 removed the sign-in scopes THRØ asks for
and never reads — `openid email profile` from Google, `.fullName` from Apple. Hours later Sign in with Apple
failed on the founder's phone with *"Apple could not finish the sign-in"*, which is
`ASAuthorizationError.unknown`, `Code=1000`.

**The likely cause is not the code.** That exact error is on the record here from a previous occasion, where
it was a build signed before the App ID carried its capabilities, and rebuilding fixed it. The entitlement in
this repository has always been right.

**The Apple half is reverted anyway**, and the reasoning is worth keeping. It was the only change to that
code path that day; **Sign in with Apple cannot be exercised on a simulator**, so it cannot be cleared here;
and the asymmetry is one-sided — being wrong to revert costs a tidier consent sheet, being wrong not to
revert costs the founder an evening chasing a phantom. A working sign-in beats a cleaner sheet.

So `.fullName` is back. **PD-063's Apple half is unproven, not wrong**, and the scope comes off again only
once somebody has watched Sign in with Apple work on a device — at which point it can be removed on its own,
with nothing else moving, and re-tested immediately.

Google's `openid` stays. It is a different flow through a different framework, the failure is specific to
Apple's, and Google's was reported working on the same build.

## PD-074 — A sign-in failure names itself, beside the sentence and never inside it

**Founder, 12 September 2026**, after Sign in with Apple failed on their phone: build the diagnostic rather
than guess again.

`ASAuthorizationError.unknown` — `Code=1000` — is **one code for at least three faults**: no Apple Account
on the phone, a binary signed without the Sign in with Apple capability, and a malformed request. The
sentence a player reads names the most common one and cannot name all three without becoming a support
article. And it cannot be narrowed down by debugging, because Sign in with Apple does not run on a simulator:
the only place the difference exists is the device it failed on.

So a **Debug build** prints, under the chalk box, the domain and code, the build commit, and whether the
running binary's provisioning profile carries `com.apple.developer.applesignin` — read by searching the
embedded profile, which is a signed blob with a plain-text plist inside it, so no CMS parsing is needed. A
build with no profile at all says so, which is itself the answer to *"why does this never fail on the
simulator"*.

### It is an annotation, not the message

The first version appended it to `SignInProblem.words(_:)` and **a test caught it immediately**: no domain
and no code ever reaches the screen. That rule is right and it exists for a reason recorded in the tests
themselves — the founder's phone once showed *"The operation couldn't be completed. (…AuthorizationError
error 1000.)"*, a sentence with no cause and no action in it.

So the diagnosis is carried beside the sentence, in the quiet ink, outside the box, in a separate field on
the failure state. Two tests now hold the boundary: the annotation must not be folded into the sentence, and
the sentence must still not carry the code.

**And only where the code hides something.** A server refusal already carries the server's own sentence,
which knows exactly what it refused; annotating that with a domain and a zero is noise on top of the best
message available. The diagnosis fires for `ASAuthorizationError` and nothing else.

### What it found, before it shipped

The founder's Xcode log answered the question first: `container_create_or_lookup_app_group_path_by_app_group
_identifier: client is not entitled`, and `AKAuthenticationError Code=-7026`. The binary on the phone is
signed with a profile carrying **none** of the entitlements — not only Sign in with Apple but the app group
too, which the Live Activity needs. That is the cause recorded here from the previous occasion, and it is
not code. The diagnostic would have said `profile: applesignin MISSING` on the phone's own screen, which is
the whole point of building it.

## PD-075 — The `Personal` configuration was crippling a paid team's build

**Found, 12 September 2026**, after the founder confirmed every capability was ticked on the App ID and
Sign in with Apple still failed on their phone with `AKAuthenticationError Code=-7026` and
`container_create_or_lookup_app_group_path_by_app_group_identifier: client is not entitled`.

The App ID was right. The provisioning profile was right. **The binary had no entitlements**, because the
`Personal` build configuration signs against `ThroDarts.personal.entitlements`, which is an empty dict — and
the scheme's **Run action uses `Personal`**, so pressing ▶ in Xcode produces exactly that build.

The empty file was correct when it was written, and said so in its own comment: *"a free Apple team cannot
sign Sign in with Apple, Associated Domains or App Groups"*. It even predicted the symptoms — *"Sign in with
Apple and passkeys refuse (Google still works), and the Live Activity's shared container is absent"* — which
is precisely what the founder reported.

**It stopped being correct at enrolment and nobody noticed.** `Personal` carries
`DEVELOPMENT_TEAM = 2XM324WPD5`, the paid team, which can sign all three capabilities. Diffing the two
configurations, the entitlements file is now the **only** difference between `Debug` and `Personal`: same
team, same signing style, same bundle id, same everything. A configuration whose sole remaining purpose was
to work around a limitation that no longer applies, wired to the button everybody presses.

So `Personal` signs with the real entitlements, and the two empty files are deleted. Debug, Personal and
Release all build.

### Why this outlived two investigations

Because every place anyone looks says the right thing. The entitlements file in the repository is correct.
The App ID is correct. The profile is correct. `check_app_group.py` passed throughout — it holds the group's
name in agreement across three places, which it was, and never asked whether the configuration being *run*
grants it. The only artefact that was wrong is the one nobody reads: a build setting pointing at a second
file.

The lesson is narrow and worth keeping: **a build configuration that differs from another in exactly one
setting is a trap wearing a name.** `Personal` should be retired the next time the project file is open;
it now means nothing.

The diagnostic from PD-074 is what will catch the next one, and it was changed to suit: iOS has no API for
reading your own entitlements, so it probes the app-group container instead —
`containerURL(forSecurityApplicationGroupIdentifier:)` is nil exactly when the binary is not entitled, which
is the same fault the phone's log named.

### Proved on the signed binaries, not argued

`codesign -d --entitlements` on three builds of the same source, on the founder's own Mac:

| Build | applesignin | associated-domains | app group |
|---|---|---|---|
| **Personal, 16:59** — theirs, before the fix | missing | missing | missing |
| **Debug, 17:27** — after the fix | present | present | present |
| **Personal, after the fix** | present | present | present |

The first row is the failure, reproduced. The third is the fix, verified: pressing ▶ in Xcode now produces a
properly entitled binary.

**One wrong turn worth recording**, because it nearly sent this the other way: the first `codesign` read was
of a `.app` from a *different* DerivedData directory, dated six days earlier, and reported all three
missing on what looked like a fresh build. Two DerivedData folders exist for this project and `find` returned
the stale one first. The profile embedded in that old artefact was from 5 September, which made a
week-old build look like a live contradiction. **Check the timestamp of any build artefact before believing
what it says about the code that is on disk now.**

The Xcode errors the founder pasted — *"the capability associated with APPLE_ID_AUTH could not be
determined"*, *"doesn't include the Associated Domains capability"* — are stale in the same way. The profile
they name was regenerated at 15:40 and does carry all three; the runbook already warned that these messages
outlive the fault.

## PD-076 — The Apple scope comes off, on its own, now sign-in is proven

**12 September 2026.** PD-063 removed the sign-in scopes THRØ asks for and never reads. PD-073 put Apple's
back the same day, when Sign in with Apple failed on the founder's phone and the scope change was the only
thing that had touched that path — recorded as *unproven rather than wrong*, to come off again once somebody
had watched sign-in work.

Sign-in works. The cause was PD-075: the `Personal` build configuration signing against an empty entitlements
file. Nothing to do with the scope.

So `.fullName` is off again, **on its own, with nothing else moving**, and installed on the founder's phone
in that state — so a single attempt settles it rather than another day of variables. If it fails, one line
goes back and the answer is unambiguous.

**What the revert was worth, given it turned out to be unnecessary.** It cost a line and bought the ability
to say, that evening, "the only change to this path today is not in the build you are testing". That was
worth having while three explanations were live. Reverting under uncertainty and re-applying under evidence
is not indecision — it is the only order that produces an answer, when the thing cannot be tested where the
work happens.

## PD-077 — The watch draws the state the other surfaces already draw

**Started 12 September 2026**, the first piece of PD-064's "rest of Apple" after the polish pass.

### The foundation, and what it cost

Before writing a watch app, the question was whether the design system compiles for watchOS at all — that is
what decides whether a watch is cheap or expensive. It does. **Four errors, all in one file**, both about
choosing a club's accent colour: a `resolvedColor(with: UITraitCollection)` that pins an answer to the light
appearance, which a watch does not have and does not need because every colour reaching it is a fixed hex;
and a `ColorPicker`, which does not exist on watchOS and describes an act nobody performs from a wrist. The
scoring engine and the statistics build untouched, so PLATFORM.md's *"the rules come free"* is now checked
rather than hoped.

CI builds all four for watchOS on every push. A foundation nobody compiles rots, and the bill would arrive
all at once on the day the target exists.

### No fifth shape for two numbers

`ThroLiveState` already answers *"what does a leg look like from outside the app"*. The Lock Screen draws
it, the Dynamic Island draws it, the widgets draw it, an external display draws it; it is `Codable` and
`Sendable` because ActivityKit made it cross a process boundary inside 4 KB, which is exactly what
WatchConnectivity will want. **A watch that invented its own model would be a fifth thing to keep true**, and
the first divergence would be silent.

So `ThroWatchKit` is a view over that state and carries no model of its own. A test holds the boundary: the
state a watch draws is the state that crosses to a widget, round-tripped through JSON.

### What is new is the arrangement, because a wrist is not a banner

The Lock Screen puts the two players side by side, which suits something wider than tall. A watch is nearly
square and read at arm's length with a dart in the other hand. So the sides stack, **the thrower's score is
the largest thing on the screen**, and the checkout sits under it rather than at the end of a caption —
because the route is the one fact a player at the oche actually wants, and it is the thing a watch is better
at than a phone lying on a table across the room.

The route is **carried and never derived**, for the reason `ThroLiveState` already gives: the rule tables
live in the engine, and a wrist that computed a finish would be linking a scoring engine to draw three
words.

### Its own module

Rather than a view inside `ThroLiveKit`, which is documented as *"deliberately the lightest target here"*
because a widget extension links it. An extension carrying a watch layout it can never run is exactly the
weight that comment exists to keep out.

**Not done yet:** the watchOS target in the Xcode project, and WatchConnectivity to feed the state across.
The view and its rules are the part worth getting right first; the target is thirteen lines mounting a
module, which is how the iOS app is built too.

## PD-078 — The watch app: a target, and the link that feeds it

**12 September 2026.** PD-077 built the view; this is the app it lives in and the thing that tells it what to
draw. Together they finish the first of PD-064's "rest of Apple".

### The target is thirteen lines, because everything real is in a package

`apps/ios/ThroWatch/ThroWatchApp.swift` mounts `ThroWatchRoot` and opens the link. That is all of it — the
same shape as the phone's target (nineteen lines) and the widget extension's (twenty-two). A **single-target
watch app**, which is what watchOS 7 and later want; the two-target shape with a WatchKit extension inside an
app bundle is still accepted, is still what most of the internet describes, and exists for watchOS 6 — a
third target to keep true for nothing.

It is a **dependency of the phone app**, embedded through a Copy Files phase at `ThroDarts.app/Watch/`. Not
an optional extra somebody remembers to build: the phone target cannot build without it, so CI cannot go
green while the watch is broken. `dstSubfolderSpec = 16` with `dstPath = $(CONTENTS_FOLDER_PATH)/Watch`, and
the wrong value there — `13`, where extensions go — produces an app that builds, installs, and simply never
puts anything on a watch.

**The whole `xcodebuild` matrix was run before this was called done**, because the founder's phone build had
been broken by a project-file mistake four hours earlier and this touches the same file: Debug, Personal and
Release for the simulator; Debug for a device with automatic provisioning, which registered
`app.thro.darts.watchkitapp` and signed it; and the phone's three entitlements re-read off the signed binary
to prove nothing was disturbed.

### Application context, and why that is not a sync policy

WatchConnectivity offers three ways to move a dictionary. `sendMessage` needs the counterpart reachable at
that instant, which a watch with its screen off is not. `transferUserInfo` is a **FIFO queue** — a wrist that
was out of range walks forward through every dead score in order, and a scoreboard reading 180 because that
is where the replay has got to is worse than one reading nothing. `updateApplicationContext` keeps exactly
one dictionary, replaces it on every write, and hands the latest over the moment the counterpart next runs.

**That is last-write-wins, and it does not touch the rule that sync is never last-write-wins.** Nothing on
the watch is a source of truth: it has no journal, it writes nothing back, and it holds the same projection
the Lock Screen and the widgets hold. There is no second writer to conflict with. The day a watch can
*score*, this transport stops being sufficient and a leg from a wrist becomes journal events like any other —
which is exactly why "scoring from the wrist" is written down as a separate, larger thing and not as the
obvious next commit.

**Staleness is judged on the receiving clock.** The message carries no timestamp; the watch notes when it
arrived. Two devices are two clocks, and a wrist that trusted the sender's would be wrong by the skew — and
the number it is judging is a number somebody is about to believe.

### One line in the one place a leg leaves the app

`LiveBoard` already was *"the one place ThroPlay talks to the outside"* — the Lock Screen, the wall screen.
The wrist is one more of those, so it is one line in each of `start`, `update`, `finish`, and nothing
subscribes to anything. **`finish` is the one asymmetry**: the wall is cleared outright and the wrist is sent
the finished leg. A room reading a decided scoreline as though it were live is the failure the wall exists to
avoid; a watch is on the arm of somebody who was there, and *"Ann wins"* is what they want on it for the walk
back to the table — which is why the Lock Screen lingers too.

The sender holds **one** pending dictionary until the session is up, because activation is asynchronous and
the very first thing a launch says is *"nothing is on"*. Without that, a phone killed mid-leg would leave
that leg on a wrist forever. One dictionary is not a queue; it is the transport's own rule, a moment earlier.

### The words are different because the drawing is

The Lock Screen writes *"Jenson R. to throw · checkout T19 D12"*. **The first build of the wrist showed that
sentence under a route it had already drawn in green, under a numeral already twice the size of the other
player's** — three ways of saying one thing, on the surface with the least room of any of them. It was
obvious in the simulator and invisible in the code.

So the wrist's line says only what the drawing cannot: the leg is decided, the link has gone quiet, nobody is
on the oche. Otherwise it says nothing. The **precedence is `ThroLiveCopy`'s and is held against it by a
test** — decided outranks stale, stale outranks the rest — so this is the same rule with an empty bottom of
the list, not a second opinion. The legs go from two small digits beside two big ones to one scoreline,
`2–1`, taken from `ThroLiveCopy.legs` so three surfaces cannot disagree about the separator.

### `-ThroWristDemo`

A DEBUG-only launch argument that puts a leg on a wrist with no phone attached, so the layout can be looked
at. The phone has had `-ThroScreen` for the same reason from the beginning, and the reason is this entry:
both faults above were found by looking, and neither had a failing test. DEBUG only, because a fictional
score on a release build is a score somebody could believe.

### Three faults found by looking, none of which had a failing test

All three were invisible in the code and obvious on a watch, which is the argument for the demo flag and for
this project's rule about looking before calling something done.

1. **The route was said twice** — drawn in green on its own line and appended to the caption underneath.
2. **A stale score kept its route.** The wrist warned "may be out of date" above a finish it still showed. A
   route is only as true as the remainder it was worked out from. The caption had always dropped it when
   stale — inside its own control flow, so a surface drawing the route on its own line silently got none of
   the rule. It is now `ThroLiveCopy.route(state, stale:)`, which both ask, and which is empty when the leg
   is decided, when **nobody is on the oche**, and when the score may have stopped being current. The third
   of those was a third instance of the same fault, found the same way one screenshot later.
3. **The winner was drawn as the quiet one.** Emphasis followed *is throwing*, and nobody throws once it is
   won, so a decided leg dimmed both numerals — the screen's answer to the only question left, in the
   background colour. The subject of the screen is now the winner, then the thrower, then nobody.

### Proving it, without a script that can tap

The transport was watched carrying a real message between two processes: a watch simulator paired to a phone
simulator, the wrist showing a leg, the phone app launched — and the wrist cleared, because the first thing a
launch says is *nothing is on*. Activation on both ends, the pending write, delivery, the mark being
recognised and the hop to the main thread, all in one observation.

What a script **cannot** do is play a match: every screen here is reached by tapping, which is the reason
`-ThroScreen` exists and the reason it cannot help — it speaks the `thro://` link grammar, and no link starts
a leg. So the last join — a real `MatchSession` reaching the link with a real state and format — is held by
`LiveBoardBridgeTests` instead, which runs on every push and is better than a screenshot anyway. Four tests:
starting a match puts that leg on the wrist with the format the wall was given; a visit reaches it; **the
wall goes dark at the end while the wrist keeps the result**, so the one asymmetry cannot be tidied away into
consistency by somebody who does not know why it is there; and a launch says nothing is on.

### And `Personal` is gone

**It broke this change, in a second and entirely different way from PD-075's.** A custom build
configuration is compiled as **release** by the Swift package build regardless of what
`SWIFT_ACTIVE_COMPILATION_CONDITIONS` the Xcode targets set. So under `Personal`, `#if DEBUG` was *true* in
the app target and *false* in the package it links — and `-ThroWristDemo`, which compiled under Debug and
under Release, failed to compile under Personal alone.

PD-075 had already found that `Personal` signed against an empty entitlements file, made it identical to
`Debug`, and said it should be retired the next time the project file was open. It was open. All three of
its configurations were confirmed byte-identical to their `Debug` counterparts first, so the retirement
changes nothing except that the trap is gone; the scheme's Run action moves to `Debug`, which is the
configuration that was proven to carry all three entitlements.

**Two configurations that must stay identical are one configuration and a trap.** That is the general rule
this leaves behind, and `tools/check_app_group.py` now states the simple version — every configuration of
every target signs with the real entitlements — instead of carrying an exception for a case that ended at
enrolment.

### Not done

Scoring from the wrist. Complications. A watch that shows the *next fixture* when nothing is live, which the
projection already computes for the widgets and which would need the App Group's contents crossing the link
rather than just the leg.

## PD-079 — A league on a wall: the Apple TV app

**12 September 2026**, the second and last of PD-064's "rest of Apple".

### What an Apple TV is actually for, which is not the live board

The obvious tvOS app is the scoreboard. It is the wrong one, for a reason worth writing down: **the live
board on a television already works**, and has since PD-041 — a phone drives an external display by cable or
AirPlay and draws `ThroVenueBoard` at room size. A tvOS app doing the same thing would be a second way to do
the thing that works.

It also **cannot** do it. `stream.match` is authenticated, by design, and there is no good way to sign a pub's
television in — nor should there be, because whose account would it be. A *public* match stream is not
plumbing: an under-18 fixture with names on it, on a pub wall, is exactly the kind of thing that gets decided
before it is built.

So the Apple TV does the thing a phone in somebody's pocket cannot: it is **on all evening**, showing the
league's table, what is still to play and what has just been played, from the routes that are public because
a league's published competition is published (PD-054, PD-056). It signs in to nothing. It is handed a
session store that cannot outlive the process, so a pub television has no credential to leak and nothing for
whoever picks up the remote to reach.

### Three rules, all from "nobody is holding this one"

1. **It never scrolls.** A table that does not fit turns pages, because a page turns by itself and a scroll
   view waits forever for a finger that is not coming. Twelve rows a page, and both pages say which they are.
2. **It never shows an empty panel.** Twenty seconds of "no fixtures" on a wall is twenty seconds of a screen
   that looks broken, so a panel with nothing on it is not in the rotation at all. When *everything* is empty
   that is a screen of its own, not a blank one.
3. **It says when it last heard.** The rule the Lock Screen, the wall board and the wrist already follow, and
   this is the surface most likely to be left on for five hours with nobody to reload it. Two minutes between
   reads against fifteen before it doubts itself — the same shape as the stream's ping against the proxy
   timeout, and held by a test so the two can never cross.

The order is the table, then what is to play, then results: somebody looking up wants to know where their
team is, then whether they are on next, and only then how last week went. A rotation that opened on results
would be showing the least urgent thing to the most people.

### Setup is one screen, once

A league is picked with the remote and the season comes with it — `shownSeason` is the one running today,
else the newest, which is a rule that already exists and is already what the phone shows. A second screen
asking which season would be asking a landlord a question they have no way to get wrong. Only leagues that
have published a season are offered, because offering one that would open on an empty wall is offering
somebody a way to get it wrong. The choice is remembered in `UserDefaults`, so a television unplugged at
closing is the same screen in the morning.

### tvOS cost five edits, four of which were worth making anyway

The whole design system, the network layer, the live surfaces, the engine and the statistics all build for
tvOS. A `ColorPicker` and a `DragGesture` describe acts nobody performs from a sofa and were guarded where
they already were for a watch; a ten-foot interface has no `largeTitle` metric, so it maps to `title1`; and
the haptics guard read *UIKit but not watchOS*, which was true when watchOS was the only other platform and
wrong the moment tvOS was tried — `UIImpactFeedbackGenerator` is an iOS type, so it says `os(iOS)` now and
stops being a list that grows. The engine and the statistics needed nothing, which is the second platform in
a row to *check* "the rules come free" rather than hope it.

### Four faults found by looking at it, none of which had a failing test

Running the thing against a real local API with a seeded season, on a real tvOS simulator, four times:

1. **A chalk rule drawn straight through every league's name.** `ChalkRule` is a single horizontal line and
   `ChalkBox` is the box; both are "a chalk shape" in the code and only one of them is a border.
2. **The phone's type scale on a six-metre screen.** A league table in twenty-point type, legible in a
   screenshot and useless in a pub. It now steps *up* `ThroTypeRole.sized`'s approved ladder — 96, 72, 56,
   40 — which is the same ladder the scoring screen steps down when a phone is short of room. Not a TV scale
   invented for the occasion.
3. **The team name smaller than its own figures.** A table where "Grange A" reads smaller than the "2" beside
   it answers the wrong question first.
4. **A declared result indistinguishable from a played one.** Every other surface in THRØ says where a figure
   came from; a wall is the one place a stranger reads a scoreline with nobody to ask, so it is the last place
   to leave it out. `6–3 · declared`.

### The brand faces, from one folder

A league table on a pub wall in the system font would be *"generic slop"* on the biggest screen the brand
ever gets. The tvOS target references `apps/ios/ThroDarts/Fonts` **as a folder** rather than holding a second
copy — two copies of a typeface are two things to keep true and the drift is silent, because an unregistered
face falls back and the screen just looks like every other app. `tools/check_bundle_faces.py` now holds both
plists against the one folder, reading each PostScript name out of the file rather than trusting the
filename. The paths carry a `Fonts/` prefix on the TV because a folder reference keeps its directory where a
synchronised group flattens it, and the check holds that too.

### Two checks were wrong, and one screen was not

`check_screens_reachable.py` reported `ThroVenueScreen` unreachable. It was not: it is mounted by
`apps/ios/ThroTV`, and the check only ever read the package — so it would have called **every** root screen
unreachable if any had been named `…Screen`. It reads the app targets now, which is where a root is mounted
and nowhere else. `check_controls_react.py` was right about the chooser's rows and the fix was one it
suggested; a remote does not miss, but the module builds for a phone too.

### The artwork, generated rather than drawn (added the same day)

tvOS wants a **layered** icon: 5:3, and it parallaxes, so the subject has to be on its own layer with the
field behind it. There is no way to make a good one by cropping a square, and no reason to draw a second
mark — so `tools/make_tv_artwork.swift` lifts the mark off the phone's icon by keying its own background
out, and lays it over a field drawn the way every board in this app is lit. One source of truth for the
mark; the rest is arithmetic, deterministic, and re-runnable, so a diff means somebody changed the mark.

**Three faults, all of them the same kind** — a generator that produced something plausible and wrong:

1. `NSImage.lockFocus` draws at the **screen's backing scale**, so on a Retina Mac every "1x" image came
   out at twice the pixels and `actool` refused the stack outright. A generator whose output depends on
   which Mac ran it is not a generator; it is CoreGraphics at explicit pixel sizes now.
2. The alpha channel is **premultiplied** and the key wrote straight chalk beside a zero alpha, which is a
   pixel brighter than its own coverage. CoreGraphics clamps it, and the mark came out as an opaque white
   rectangle.
3. The phone's icon was exported with a green **a shade lighter than `throGreen`**, so keying against the
   token left every background pixel at 6% alpha — a pale square behind the mark, uniform and therefore
   invisible in the source, and obvious the moment it was laid on a darker field. The background is read
   off the image's own corner now, which is exact and needs no threshold to fudge.

All three were caught by looking at the output. None would have failed a build except the first.

### Not done

A **device build** needs an Apple TV registered to the team — `xcodebuild` can create the App ID
but cannot create a development profile for a platform with no device on it, which is the founder's step and
not a defect. And the live board on the Apple TV itself, which is the safeguarding decision above.

## PD-080 — The opening's eighth look, and a way to look at it

**12 September 2026.** The founder asked to *"tidy up the intro further… to really make it a utterly
beautiful app intro"*. Every previous version of this film was reviewed by somebody watching it and saying
what they saw, which is the only way an animation has ever been judged here — and it is why the notes have
always been about *feel* rather than about frames.

### First, a way to see a frame

`-ThroOpeningAt 1.9` holds the opening at 1.9 seconds. DEBUG only, like `-ThroScreen`, because an opening a
shipped build could be frozen from the command line is an opening that could be frozen. `LaunchFrame` was
already a pure function of `t`, so this is four lines.

With it, `tools/contact_sheet.swift` lays twenty stills on one sheet. **A single still says almost nothing
about a motion and twenty read one after another say only slightly more**, because by the fourth you have
forgotten the first; side by side, the shape of the film is visible — what holds too long, what is over
before it is seen, where nothing is happening at all.

**It immediately produced a false alarm worth recording.** The first sheet showed the dart *missing* for
0.4 s in the middle of the strike — three consecutive blank frames. It was not: the tell was that the
vignette was missing too, and the vignette is on from 0.28 s to the end. A completely flat green frame is
not this film at any instant; it is the *launch screen*, caught before the app's first draw, because the
capture waited 2.2 s and the simulator was slower than that. Re-captured with a longer settle, the strike is
intact. **A blank frame out of a screenshot harness is a capture artefact until proved otherwise**, and the
proof is whether the things that are always on screen are on it.

### The peak of the film lasted one frame

The chalk ran to the very end of the ring's segment and the mark set off for the name on the next. So the
one image the whole opening is building towards — a whole Ø, glowing, with a real dart through it — was
**never still**. It was the founder's own note about the tagline (*"visible a little bit longer so people can
read it properly"*) applied one beat earlier, and nobody had to give it because nobody can see a frame that
is not there.

The chalk now runs round in **two thirds** of the segment it had and the last third is stillness. A shock
travels fast and looks better for it. **The opening is the same length to the millisecond**, which matters
because five seconds is the founder's ceiling in both directions and a beat that had to be paid for in
length would not have been worth having. The close flash and the settling pulse moved with it — they belong
to the instant the ring becomes whole, which is no longer the instant the clock says.

### A held shot, not a paused one

A still frame with nothing moving anywhere in it is a paused video. The difference is something drifting, so
**chalk comes off the board and falls**: forty-six motes, deterministic like everything else here, brightest
a moment after they come off and away to nothing over about a second. They are the ones the shock did not
throw — the shock's motes fly outward and are spent in a tenth of a second, and these simply come down.

They are anchored to **where the ring was**, not to the mark, because dust does not follow a logo into a
wordmark. That has a second effect worth having: the mark leaves for the name and its dust stays behind
falling, which fills what the contact sheet showed was the emptiest stretch in the film — a single small
glyph alone on a wide field between the mark arriving in its slot and the first letter being struck.

They start **outside** the band. The first version started them on it, where a white mote against pure chalk
is invisible, so the held beat — the one moment they exist for — was the one moment they could not be seen.

### What was looked at and not changed

The flight, the strike and the ring being drawn are left exactly as they were; four sheets of stills gave no
reason to touch them. The dart's flights dissolving as the mark becomes type was considered and left: in
stills it looks like a fade, but the frames either side show it already trailing and smeared, and **a still
is the wrong evidence for a 120 ms motion**. Changing it on that evidence would be tuning to the tool rather
than to the film.