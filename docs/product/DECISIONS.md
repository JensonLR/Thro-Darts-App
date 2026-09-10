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
