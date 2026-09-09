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

**Match** — the full contest between two **competitors** under one format, composed of legs (and sets).

**Competitor** — the entity that contests a match: a **Player**, a **Pair**, or a **Team**. Rating is
always a property of the *player*, never of the competitor; a team rating would be a separately
specified derived aggregate and does not yet exist.

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

## Competition and organisation

One organisation concept, one place concept, and dated relationships between them (ADR-017). **There
is no Club.** It is a word people use for a Team or for a Venue, and it resolves to one of them every
time; THRØ's own copy says *team* and *venue*.

**Player** — one persistent sporting identity (the THRØ ID). May exist before any account claims it.
Holds no personal data; a name lives in the identity module, reached through a **claim** that is
appended and revocable, never a column updated in place.

**Team** — the competitive organisation, whatever it calls itself: darts team, darts club, pub team,
side. Its venue is a **tenure**, so a Team that moves keeps its identity, history, roster, results,
honours and followers. Distinct from the match-time `Competitor.Team`, which is the **lineup** a
Team fields in one match.

**Venue** — the physical place darts is played. Hosts many Teams and many Events; owns none of them.

**Team venue tenure** — the dated relationship between a Team and a Venue (home, training,
registered). Home tenures never overlap in time.

**Team membership** — a Player's dated relationship with a Team, with a role (player, captain,
vice-captain, admin) and a status. Says nothing about any League.

**League** — the recurring competition authority. **League season** — one occurrence of it, with
dates, divisions, affiliated Teams and registered Players ("Teesside Thursday League — 2026/27").
The design's "Season" is a league season. **Division** — an optional subdivision of a league season.

**Team affiliation** — a Team's dated registration to a League season and optionally a Division.
About the Team, never about a Player.

**Player registration** — a Player's dated eligibility record in a League season, naming the Team it
was made for as it stood at the time. **Not membership**: a member need not be registered, and a
registration outlives the membership it was made under. A transfer is a new registration that
supersedes the old. Eligibility is derived from registration under the season's approved **policy**,
never from membership and never from payment.

**Policy** — a versioned rule body belonging to one authority (League, League season, Event, Series,
Series season) with an effective period, provenance (`manual`, `imported`, `extracted` — an
AI-assisted extraction a human reviewed) and an approval by a named actor. Only an approved policy
may be cited by anything executable; an approved policy is frozen and change is a new version. Two
approved versions of one rule are never in force on the same day.

**Competition** — any structure producing matches: a League season or an Event. Exhaustive.

**Tournament** — the persistent identity of a discrete competition that may recur ("The Riverside
Open"). Not a League.

**Event** — one edition of a Tournament: the discrete competitive occasion players discover, register
for and check in to, with an **entrant kind** (player, pair, team) and an **access** (open,
invitational, qualified, restricted, member-only). Nothing in an Event references a League season.

**Entry** — a typed entrant in an Event: exactly one of a Player, a **Pair** or a Team, and its kind
is its Event's kind. The database refuses anything else.

**Series** — a linked collection of Tournaments. **Series season** — a dated occurrence, linking
specific Events in order at any number of Venues. A Series holds Events and nothing a League has;
series points and standings are projections, never rows beside the competition tables.

**Fixture** — a scheduled meeting between two Teams in a League season (`league_fixture`). Its
schedule has a lifecycle — scheduled, rearranged, postponed — and every change is logged with the
original date. Its venue is copied from the home Team's tenure at scheduling and frozen. Its
**outcome** is a recorded decision (played, awarded, walkover, void) with an actor, a time and the
policy it was taken under; a later decision supersedes an earlier one and the earlier one stays.
**Not a bracket tie**: it has no parent-child dependency, can be awarded with no match played, and
aggregates into a table rather than advancing a competitor.

**Bracket tie** — a pairing in a knockout round of an Event, possibly a bye (`bracket_tie`). Not a
fixture. The Slot states below describe its positions.

**Board** — a physical playing position. States (design): `free`, `called`, `playing`, `awaiting`,
`disputed`, `closed`.

**Called** — the organiser has summoned players to a board. **This outranks everything else in the
product**, including notifications and coaching insight.

**Draw** — the assignment of entrants to bracket slots. Reversible only through a recorded
correction. **Team separation** (the design's "Club protection") — a draw policy keeping entrants of
one Team apart in the first round; a policy row, not a flag.

**Slot** — a bracket position in a tournament, which may hold a competitor, be undetermined, be a
bye, or be vacated by walkover or withdrawal. These are five different facts and must not share a
rendering.

**Awarded** — a fixture outcome decided by the organiser without play. A distinct, auditable outcome
type, never a synthetic scoreline.

## Administration (THRØ Secretary)

**Admin task** — something owed: by a Team, a League season or a Player; with a kind, a source, a
subject, a reason and missing facts materialised at creation, a deadline and the rule it was derived
from, a state (`open`, `waiting_player`, `waiting_opponent`, `waiting_league`, `done`, `cancelled`)
and an appended history of every change of state or deadline. Derived from facts and an approved
policy by reconciliation; a fact produces its task once. Never manufactured.

**Submission** — one thing sent by a Team to a League season's administration or to an opposing
Team: a player registration, a result, a rearrangement proposal. Its state is a projection of its
**transitions**, each of which names who moved it and the evidence — a **delivery** attempt the
transport code wrote, an **artefact** retained from the recipient, or a **human confirmation** with
a name and a note. `draft → ready → submitted → delivered → acknowledged → accepted |
accepted_conditional | rejected | action_required`, with `delivery_failed`, `withdrawn` (only before
delivery) and `superseded`. THRØ may take a submission to `delivered`; every later state is the
recipient's word, recorded with the name of the person who said it.

**Disclosure gate** — the one rule for whether anything about a Player may leave THRØ: a live claim
to an account that is an adult with their own live consent, or that has a guardian's. Unknown is
not adult. Checked by the database when a submission is sent.

**Consent record** — a basis (self or guardian), the actor who gave it, an artefact reference and a
time; revocable, never edited. An account a person created for themselves carries its own; one
somebody else typed in starts with none.

**Rearrangement proposal** — one Team's proposed new date for a Fixture, answered by the opponent's
administration and applied by the League through the same command every rearrangement goes
through. A Team's agreement is never the League's act.

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
