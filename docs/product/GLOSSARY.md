# THRØ — Domain Glossary

One canonical meaning per term. Where two parts of the system would use a word differently, that is
a defect, not a style choice.

Terms marked **(design)** are taken verbatim from the approved design system and must not be
redefined. Terms marked **(open)** are not yet decided — see `OPEN_DECISIONS.md`.

---

## Competitive evidence

**Visit** — one player's turn at the board: up to three darts, recorded as a single **visit total**.
The visit is THRØ's primary unit of scoring evidence.

**Visit total** — the number of points scored across the darts thrown in a visit (0–180, excluding
the nine unachievable values 163, 166, 169, 172, 173, 175, 176, 178, 179). This is what the approved
keypad captures. **It does not tell you which darts were thrown.**

**Dart-level evidence** — the individual segments struck. THRØ has this only when a capture mode
explicitly records it. It is **optional, nullable, and never inferred from a visit total.** Absence
means unknown — never zero.

**`dartsUsed`** — how many darts (1, 2 or 3) were thrown on a visit. Only ambiguous on the visit
that wins a leg; every other visit uses three. Capture on the leg-winning visit is what makes 3-dart
average exact. **(open — B1)**

**Throw** — a single dart. Used only when discussing dart-level evidence; never as a synonym for
visit.

**Leg** — one game from the starting score to zero under the format's in and out rules. **The leg is
the unit of participant confirmation and of dispute** — established by the approved organiser design.

**Set** — a group of legs won under the format's set structure. In scope from the start.

**Match** — the full contest between two participants under one format, composed of legs (and sets).

**Bust** — a visit that cannot legally be scored: it takes the remaining score below zero, leaves 1
under double-out, or reaches exactly zero on a number the out-rule cannot finish. The remaining score
**reverts to the pre-visit total** and the turn passes. A bust visit is recorded, not discarded: it
consumed three darts and scored zero, so it correctly enters the average denominator.

**Checkout** — the visit that finishes a leg, and by extension the score finished from. A *checkout
suggestion* (the route THRØ displays, e.g. T20 · T11 · D14) is **advice, never evidence**, and must
live in a separate namespace that no statistic reads.

**Bogey number** — a remaining score that cannot be finished under the out-rule. Under double-out at
or below the 170 maximum: 159, 162, 163, 165, 166, 168, 169.

**Correction** — an appended event that supersedes earlier evidence, carrying actor, authority,
reason and a causal reference to what it corrects. **Corrections never overwrite.**

**Undo** — reserved for *clearing an uncommitted entry buffer*. It emits no event. Revoking a
committed visit is a **correction**, not an undo. These must never share one affordance.

## Trust and provenance

**Provenance** — the composite record of how a result came to exist: capture channel, entering
actor, confirming actors and times, device, connectivity, organiser authority, submission and
occurrence times, corrections, and integrity signals. **The verification label is derived from
provenance, never stored in its place.**

**Verification state (design)** — the eight labels the design defines, with its own wording:
`self-reported` ("Entered by a player. Not independently confirmed.") · `participant-confirmed`
("Both players confirmed this result.") · `thro-recorded` ("Scored live in the THRØ app.") ·
`organiser-confirmed` ("Confirmed by the competition organiser.") · `thro-verified` ("Recorded in
THRØ **and** confirmed by the organiser.") · `pending` · `disputed` · `corrected`.

Verification expresses **evidence quality, not prestige**. A player is not better because their
result is verified.

**Quarantine** — suspension of a result's *eligibility* pending review, without accusation.
Quarantine **retains** the result, its provenance, its place in the bracket and its visibility;
it **suspends** rating eligibility, form contribution, rank denominators and cohort averages. It is
reversible. It is an **orthogonal axis, not a ninth verification state** — overloading the enum
destroys the provenance underneath. A device fault triggers it as readily as fraud. **(open — OD-006)**

**Eligible** — permitted to inform the rating model at all.

**Qualifying** — counts toward establishing a rating. Strictly narrower than eligible.

**Dispute** — a participant's assertion that the recorded result is wrong. Localises to a leg.

**Outcome type** — how a match concluded: `played`, `walkover`, `forfeit`, `retired`, `awarded`,
`void`, `replayed`. First-class, because a walkover stored as a scoreline is indistinguishable from
a played one forever.

**Bye** — advancement without playing, because the bracket is larger than the field. A bye creates
no match, produces no statistics and **is not a win**. For N entrants and bracket size B: byes =
B − N; preliminary matches = (N − byes) / 2.

**Walkover** — advancement because the opponent did not play. Recorded as a progression, never as a
scoreline.

## Competitive standing

**THRØ ID** — one persistent competitive identity, following a player across teams, leagues, venues,
events, regions and seasons. Not owned by any organiser.

**THRØ Rating** — an estimate of long-term competitive strength, expressed as a single unitless
integer on a scale shared by players, fields and pathway thresholds. It is **not** the 3-dart
average, and the model is **not decided**. It is a **derived, replayable projection over eligible
evidence** — never a stored mutable number. **(open — OD-001)**

**Form** — recent competitive performance over a short trailing window, expressed **in the same
units as Rating**. Never used for seeding, matchmaking or rank. **(open — OD-003)**

**Rank** — ordinal position within a **named population at an instant**. Always carries its scope.
Never a stored attribute of a player, and never a model input. THRØ's global rank is never the
official PDC World Ranking.

**Confidence** — how certain the model is, shown as `low` / `medium` / `high` with the design's
wording: "Still learning your level" · "Building confidence" · "High confidence". Never a numeric
interval in player-facing UI.

**Provisional** — uncertainty above the publication threshold. **The rating number is suppressed
entirely** (the design renders an em dash with a "Rating establishing" tag).

**Established** — uncertainty below the publication threshold with enough qualifying matches.

**Inactivity** raises **uncertainty**; it never lowers the rating estimate.

**Band** — an optional descriptive label beside a rating. The design supports one; **no taxonomy is
approved.** **(open — OD-002)**

## Statistics

Each statistic must cross the API as a discriminated value carrying whether it is exact, bounded, or
unavailable — never a bare number.

**3-dart average** — points scored per three darts thrown. **Biased low** unless `dartsUsed` is
captured, because it otherwise assumes three darts on the leg-winning visit.

**First 9 average** — average over the first three visits of a leg. Exact for legs of three visits
or more; the denominator must be disclosed.

**Checkout %** — doubles hit ÷ doubles attempted. **Not computable from visit totals.** Any figure
presented under this name without dart-level evidence is fabricated. **(open — B1)**

**Finish rate from a checkable position** — legs won on the first visit that opened on a finishable
number, over all such opportunities. Exact from visit totals, genuinely informative, and **not**
checkout percentage. Must never reuse that label.

**180** — a maximum visit. Uniquely decomposable (three treble 20s), so a 180 visit total *is*
dart-level proof. The only such case.

**Highest checkout** — the remaining score at the start of a winning visit. Exact.

## Competition

**Competition** — any structure producing matches: a tournament, a league season, or a division.

**Event** — a discrete competitive occasion players discover, register for and check in to.

**Fixture** — a scheduled match within a league or division.

**Board** — a physical playing position. States (design): `free`, `called`, `playing`, `awaiting`,
`disputed`, `closed`.

**Called** — the organiser has summoned players to a board. **This outranks everything else in the
product**, including notifications and coaching insight.

**Draw** — the assignment of entrants to bracket slots. Reversible only through a recorded
correction.

**Slot** — a bracket position, which may hold a player, be undetermined, be a bye, or be vacated by
walkover or withdrawal. These are four different facts and must not share a rendering.

## Development

**Passport** — a player's durable competitive history, measured in years. Not an activity feed.

**Coach** — an evidence-driven insight layer. Not a chatbot, not an assistant, not "Ask AI".

**Shadow** — a statistical opponent model built from a player's own real evidence. **A mathematical
mirror**, never an avatar, face or character. Shadow matches never affect Rating or Form.

**Transfer** — whether improvement observed in training later appears under competitive conditions.
Practice evidence and competitive evidence remain permanently distinguishable.

**Pathway** — the next appropriate competitive opportunities. Opportunity-led, never a career
prediction. Darts is a constellation, not a pyramid.

## Voice

THRØ speaks as a **competition official**: calm, specific, factual, British English, no emoji, no
hype. Never "too easy" or "too hard" — use *good competitive fit*, *strong challenge*, *stretch
field*. Never reduce a player to "bad" or "beginner". A rating fall is never rendered in red.
