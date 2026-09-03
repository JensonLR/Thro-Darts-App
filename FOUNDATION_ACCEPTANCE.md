# THRØ — Gate 0: Foundation Acceptance Report

**Date:** 2026-09-03 · **Status:** Gate 0 complete · **Verdict:** PASS WITH BLOCKERS
**Next gate:** Gate 1 — Architecture

Gate 0 was foundation ingestion, not implementation. No product code was written, and none
should be until the blockers in §11 are answered.

---

## 1. Source inventory — what actually reached this environment

| Source | Precedence | Status |
|---|---|---|
| Founder brief (the production gauntlet) | 1 — explicit current founder decisions | **Present.** The only product-authority document available. |
| Production decision / authority register | 2 | **Absent.** Does not exist yet. |
| Approved THRØ Claude Design System | 3 | **Recovered** — see §2. |
| Current product / domain specifications | 4 | **Absent.** |
| Founding dossier | 5 | **Absent.** |
| Approved architectural decisions | 6 | **Absent.** None have been made. |
| Reference implementation / prototype code | 7 | **None exists.** See below. |
| Sample data | 8 | Present, embedded in the design export. Treated as fixtures throughout. |

**The repository was empty.** `JensonLR/Thro-Darts-App` had zero branches, zero commits and zero
files at session start. This is a genuinely greenfield build.

There is therefore **no prototype or reference code to retain or discard** — a question Gate 0 was
required to answer, and the answer is simply "none exists". Nothing has to be unpicked, and no
throwaway architecture has been inherited. That is a real advantage and it should not be squandered
by treating the design export's compiled JSX as a starting point for implementation: it is a
reference, not a foundation.

**The `thr-design-system` folder on the founder's local machine did not reach this environment**,
and neither did the founding dossier, the product specifications, or the
`handoff/TYPOGRAPHY_TOKENS.md` document that the design system's own token file references. The
design export was recovered by another route (§2). Precedence rank 4 — current product
specifications — is currently **empty**, which means the founder brief is carrying product authority
alone.

## 2. Design connection status

**The live Claude Design project could not be reached.** `DesignSync` requires a design-system
authorization that can only be granted by running `/design-login` from an interactive Claude Code
session on a local machine; it cannot be granted in a remote session. Remote sessions reuse that
authorization once it exists, so this is a one-time action that would unblock live design access for
all future sessions.

**The approved design system was recovered instead from the founder's published Claude Design
export** and has been extracted, verified and committed to `docs/design/`. It is genuine: it carries
the Claude Design `@ds-bundle` manifest (format 4, namespace `THRDesignSystem_ac73b5`), per-file
source hashes, and the Claude Design branding block.

What was recovered, verified by reading it:

- **The complete token layer** — 177 tokens: brand and semantic colour with **complete light/dark
  parity** (44 aliases each, no gaps, no orphans), the full typography scale, spacing, radius,
  borders, elevation, and the SET → THROW → IMPACT → RESOLVE motion grammar with reduced-motion
  overrides.
- **61 components** across 10 families — exactly the count the brief specified.
- **33 participant screens** in 9 groups, plus the navigation model.
- **9 organiser screens** plus the organiser shell. These were initially believed missing; they had
  been compiled into the component bundle and were recovered in full.

**Limitations, stated plainly.** This is a *compiled export snapshot*, not the design master and not
a live connection. The `.jsx` files are Babel output, faithful to behaviour and token usage but
derivative. It cannot be diffed against the current state of the Design project, and any design work
done after 2026-09-03 is not reflected. Full provenance is recorded in
`docs/design/DESIGN_SOURCE_PROVENANCE.md`.

## 3. Method

Six specialist reviews were run independently and in parallel — darts domain and scoring engine;
system and backend architecture; mobile and shared-domain architecture; security, privacy and
safeguarding; design system and accessibility; rating science, trust and anti-gaming. Each carried a
hostile persona for its own domain and was instructed to attack its own recommendations. Each was
required to separate what it verified by reading the design source from what it reasoned.

Findings that decide the foundation were then **re-verified independently** rather than accepted:
the impossible dart counts in §6, the bye arithmetic in §6, and every contrast ratio in §8 were
recomputed from first principles. All checked out, with one correction noted in §6.

## 4. Convergent findings — where independent reviewers agreed

Five conclusions were reached separately by three or more reviewers. Convergence of this kind is the
strongest evidence Gate 0 produced, and these should be treated as settled.

1. **Rating must be a recomputable projection, never a stored mutable number.** Reached
   independently by the security, rating, darts-domain and backend reviews. The evidence is in the
   approved design itself: the organiser dispute screen states *"Ratings are recalculated from the
   corrected result."* An incrementally-mutated rating cannot honour that sentence, because
   reversing one match must ripple to every opponent downstream of it. Rating is `f(event log)`,
   versioned and replayable.
2. **Confirmation attaches to the leg, not the match.** Reached by five reviewers from the same
   evidence: *"Legs 1–8 are confirmed by both players and give 4–4. The dispute concerns leg 9
   only."* Match-level confirmation makes that screen unbuildable and forces disputes to be
   all-or-nothing. This granularity cannot be recovered retrospectively.
3. **Some statistics on the approved surfaces cannot be honestly computed.** Reached by every
   reviewer that looked at scoring. This is blocker B1 (§11).
4. **`quarantined` is missing** from the design's eight verification states — and it must be an
   *orthogonal eligibility axis*, not a ninth value of the provenance enum. Overloading the enum
   destroys the pre-quarantine provenance.
5. **`Undo` has two incompatible meanings.** The component's own `aria-label` says "Undo last
   score" (revoke a committed visit); the screen wires it to clear the digit buffer. These are
   categorically different — one emits no event, the other must append an auditable correction.
   Collapsing them leads directly to mutating the local journal.

## 5. Divergent findings — adjudicated

**Shared domain strategy — genuine disagreement.** The mobile review recommends three native
implementations governed by a conformance corpus, with rule *data* generated into all three
languages; it rejects Kotlin Multiplatform on toolchain burden, iOS debuggability and agent
productivity. The backend review recommends a KMP module, arguing it collapses the drift surface
from three implementations to one.

**Adjudication: do not decide this at Gate 0 — and it is not necessary to.** Both reviews agree on
the two things that matter now, and both are prerequisites of either path:

- The engine must be a **pure, dependency-free, value-typed module** with no floating point, no
  clock access, no randomness and no I/O.
- A **versioned conformance corpus is mandatory** and is what makes the decision reversible: it
  proves any replacement implementation correct.

Build the common prefix, then run a time-boxed KMP-on-iOS spike in Gate 1 with explicit kill
criteria (Xcode build-time delta, debuggability through the bridge). The corpus is never wasted work
under either outcome.

**Scoring authority — apparent disagreement, actually complementary.** The backend review specifies
a single-writer scoring lease; the mobile and security reviews specify per-device evidence streams
reconciled by leg digest. These compose rather than conflict: the lease governs *live scoring
authority*, while a non-holder's evidence still exists as its own stream and becomes contested
evidence for adjudication. Together they produce exactly the dispute screen the design draws.
**Adopt both.**

## 6. Domain risks

**The approved input model is visit totals, and this is correct.** `ScoreKeypad` offers quick keys
180/140/100/60/45/26, digit entry, Miss and Undo, and commits one number per visit. There is no
segment input anywhere in the 61 components. The `Checkout` component's route (T20/T11/D14) is
*advice shown to the player*, confirmed by a user setting "Checkout suggestions · On" — it is never
captured as evidence. The design and the integrity constraint agree completely.

**Fabricated dart-level evidence appears in the highest-stakes screen in the product.** The
organiser dispute evidence table, captioned *"Evidence · THRØ-recorded legs"*, carries a per-leg
`Darts` column. Two of its nine rows are **arithmetically impossible**, which I verified by
exhaustive computation over the real dartboard segment set:

- Leg 6 — 19 darts implies a one-dart finish of 48. One-dart double-out finishes are
  {2, 4, … 40} ∪ {50}. **48 is impossible.**
- Leg 9 — 16 darts implies a one-dart finish of 64. **Also impossible** — and leg 9 is *the disputed
  leg*, the row the entire ruling turns on.

The other seven rows are feasible. This is sample data, not a shipped defect — but it is on the
screen where a human official decides a competitive result and where the same screen states that
ratings are recalculated from that decision. The `Darts` column must be removed, replaced with
`Visits` (always exact), or shown only where dart counts were genuinely captured. Never inferred.

**Bye arithmetic in the approved design is wrong.** The organiser setup screen reads *"74 entries ·
Round of 64 with 10 byes"*. A bye advances a player without playing; it does not remove one. Verified
correct figures for 74 entrants: bracket 128, **54 byes**, 20 players in preliminaries, **10
preliminary matches** — 10 winners plus 54 byes gives 64. The design's "10" is the number of
preliminary matches, mislabelled as byes. *(The reviewing agent's own restatement said "20
first-round matches", conflating players with matches; the figures above are mine and are the
correct ones.)* The domain must compute bracket size, byes and preliminary matches — the UI must
never carry them.

**Other material domain risks.** Master-out maximum is 180, not 170 — naive code copies the
double-out constant. The nine impossible visit totals (163, 166, 169, 172, 173, 175, 176, 178, 179)
must be rejected; `NumericInput`'s `max=180` is a bound, not a legality check. Bust condition three —
*score reaches exactly zero on a non-checkout number* — is the one implementations drop; under
double-out the exact set is {159, 162, 165, 168, 171, 174, 177, 180}. A bust visit must be recorded,
not discarded: it consumed three darts and contributed zero, so it correctly drags the average down.

**Throw order is the largest unmodelled area.** Nothing in the 42 screens establishes who throws
first — no bull-up, no starter indicator, no alternation display. Under strict alternation in a
best-of-9 the leg-1 starter also starts the decider; many competitions bull-up for it instead. Throw
advantage is asymmetric and material, so a rating engine that ignores it is measuring the wrong
thing.

**Sets are in scope and must be built now.** `LegState` and `SetState` both carry set structure.
Retrofitting a set layer into a leg-flat aggregate is a rewrite. Per-round format override is also
required — real tournaments escalate from Bo9 to Bo11 for finals, and the design uses one format
throughout.

**Terminal states the brief's state machine omits but the organiser screens require:** walkover,
void, abandoned, leg-replayed and disputed. Each has different rating and statistics eligibility.

## 7. Architecture assumptions

These are Gate 1 inputs, not decisions. They are recorded so Gate 1 argues against something
concrete.

- **Modular monolith**, not microservices — a service split solves an organisational problem this
  team does not have, and would destroy the single transaction that event append + projection +
  idempotency-key release depends on. Enforce hard module walls for match, trust and rating from the
  first commit; let the rest graduate.
- **One managed Postgres** holding the event log, competitive graph, read models, search and job
  queue. One transactional boundary is worth more to a one-operator team than any throughput
  advantage.
- **Append-only is a database grant, not a convention** — revoke UPDATE and DELETE on the evidence
  schema and assert it in CI.
- **Command receipts must be written in the same transaction as the event append.** A crash between
  two transactions either double-applies a visit or loses one; both corrupt a match.
- **A naive `global_seq` tail will silently skip events**, because identity values are assigned at
  insert time and not commit time. Consume to a watermark derived from the oldest in-flight
  transaction. This is the classic silent-corruption bug in exactly this architecture.
- **Ordering never depends on wall clock.** Order by `(deviceId, sequence)`; device time is
  evidence, server time is authority. A wrong clock is not a cheating signal and must never reject
  an event.
- **Durability must be explicit.** SQLite and Room default to a mode that survives process death but
  **not power loss**. Losing an acknowledged competitive visit has no repair path.
- **Rejected or unsyncable events are never discarded client-side.** A conventional "retry N times
  then drop" queue destroys competitive evidence.
- **The scoring module must be network-independent by construction**, enforced by the module
  dependency graph in CI. Discipline alone will fail.
- **The bundle identifier and Android applicationId must not contain the product name.** The brief
  anticipates a rename; changing an Android `applicationId` means a new Play listing with no
  migration path — installs, reviews and ratings all lost. Keep all identifiers ASCII: `Ø` is not.

## 8. Design assumptions and risks

**The token layer is genuinely strong** and should be preserved: complete light/dark parity, and
every one of the nine status/surface pairs passes AA in **both** themes. `ErrorState`'s
what/safe/todo contract, the shared trust vocabulary, and the organiser information architecture are
all high quality. `screens-integrity.jsx` is the most product-correct artefact in the export.

**But the components are a demo, not a contract.** Across all 61: **zero** implement focus, hover or
pressed; four implement disabled; one implements loading. For a keypad used one-handed at speed, the
absence of a pressed state is a functional defect, not a polish gap — the player gets no
confirmation that a score registered.

**Three design-side P0s:**

1. **Theme scope is an undocumented cascade side effect.** Scoring is dark only because of a
   hardcoded screen-ID allowlist in the throwaway prototype harness. Five scoring components default
   to `theme='dark'` and paint no background — on the default light background their text is
   **chalk on chalk, 1.00:1, verified**. The 96px remaining score is literally invisible; it works
   today only because an ancestor happens to be ink. SwiftUI and Compose have no cascading custom
   properties, so this does not port at all.
2. **The type scale is fixed pixels with no Dynamic Type or fontScale contract**, against a mandate
   for first-class native iOS and Android. Several hero styles already have negative leading, so
   implementing the scale in scalable units would clip every hero. Retrofitting changes every
   layout, not every colour.
3. **There is no machine-readable token source.** `tokens.css` is a compiled artefact — the stripped
   `@font-face` rules left orphaned subset comments behind. Three platforms would hand-copy 177
   tokens and drift is certain.

**Verified accessibility failures** (all recomputed independently):

| Pair | Ratio | Consequence |
|---|---:|---|
| Focus ring on brand green | **1.29:1** | Focus invisible on every primary button |
| Focus ring on ink | **1.99:1** | Focus invisible on all ink surfaces |
| `border-strong` on chalk | **1.70:1** | Fails 1.4.11 — and it is the *only* boundary of secondary buttons |
| `border-default` on chalk | **1.27:1** | Fails 1.4.11 |
| Chalk on chalk (the invisible default) | **1.00:1** | See P0 above |

The token file's own guidance that pewter (`#717875`, 4.18:1) is safe at "18px+" is **wrong**: WCAG
large text is 24px regular or 18.66px bold. At 18px regular it fails AA, and the comment authorises
a failing usage. Separately, `--touch-target-minimum: 44px` is defined and **never used anywhere**;
three interactive components sit below it.

**The real organiser gap is layout, not screens.** The organiser CSS classes have no definitions in
the export: no sidebar width, no content max-width, no column ratios, no grid gutters, **no
breakpoints**, no minimum supported width. The screens are readable as composition but not
reproducible as layout. No brand mark of any kind was exported — `logo-chalk.svg` is referenced and
absent.

**Fonts.** The `@font-face` rules were stripped entirely; the export contains no font-loading
mechanism and no binaries, so it silently substitutes today — which its own comment forbids. Both
families are believed to be OFL 1.1, but this must be confirmed rather than assumed, with particular
attention to any Reserved Font Name clause, because subsetting is exactly what production will want.
Icons are Lucide under MIT, which poses no obstacle.

## 9. Security, privacy and safeguarding risks

**The honest anchor for the whole architecture:** THRØ cannot prove a dart landed. It can only prove
*who asserted what, when, from which device, and who corroborated it*. The goal is not to prevent
false scores but to make every score attributable, corroborated, and reversible without collateral
damage. The design's verification vocabulary already implements exactly this.

**The adversary is not primarily an external attacker.** It is the opponent, the colluding pair, and
the conflicted organiser — and the design makes the incentive concrete: rating gates bye allocation
(*"Byes go to the highest-rated checked-in players"*), seeding, event fit and public rank, with entry
fees of £18–£40 and prize funds of £1,400 attached.

**Authorization must be relationship-based from the first commit.** One person in the approved design
appears simultaneously as Tournament director, Captain, listed player and Venue scorer. Permissions
sit *below* the event — scorers are assigned to individual boards — and roles are season-bounded. A
global role column or roles embedded in the token forces a rewrite of every endpoint on day one. The
conflict-of-interest rule — an official may correct a match *unless* they or their team are in it —
requires a negation that naive role-based access control cannot express. Permissions must never live
in the token, or a removed organiser keeps power until it expires.

**Identity must be physically separable from the event store.** The design makes a binding promise:
deleting a THRØ ID removes the profile and statistics, while *"results of matches you played remain
on your opponents' records and in competition archives, without your name attached."* If display
names are denormalised into events, projections, published brackets, exports or search indexes, that
promise is unimplementable. Events must carry an opaque player reference only, and **every read
model, cache, public page, search index and export must be regenerable from the pseudonymised
source** — that regenerability clause is the expensive part and must be a build-time invariant.

**There is no age signal anywhere, and this is the sharpest safeguarding risk.** Verified: no date of
birth, no age gate, no guardian relationship in onboarding, settings or privacy. Meanwhile real names
are published by default *"on public THRØ pages and in search engines"*; live presence is broadcast
(*"Harry Nunn is playing now · Durham Masters · Board 4"*) with venue and distance; following is
one-way and needs no consent; and there is **no Report and no Block anywhere in the design**. Darts
is played by minors. Ages cannot be retro-assigned without re-consenting the entire user base, and in
the interim minors' names would have been published on search-indexed pages and their live venue and
board broadcast to strangers.

The single cheapest safeguarding property available is already true and must be protected: **there is
no messaging or chat anywhere in the design.**

**"Near you" can work without storing precise location**, and the design already supplies the inputs:
region, home venue and a travel radius are collected, with no location permission requested anywhere.
Resolve the locality to a coarse area code stored as a string; never put a coordinate on a person.
Displayed distances must be **banded** — precise distances to three publicly-known venues locate
someone to a few hundred metres.

**The draw is currently manipulable and unverifiable after the fact** (*"This draw is a draft"* plus
*"Redraw"*, with rating-driven bye allocation). Commit a server-generated random seed and record every
generation including discarded drafts. Cheap now; impossible to prove retrospectively.

**Unclaimed-profile claiming is a day-one attack path.** Migrating paper leagues guarantees unclaimed
player records, and *"that 1,900-rated record is me"* is extremely attractive. The claim flow must be
organiser-verified and audited from the start, not retrofitted onto a backlog of contested identities.

**Prize money should stay off-platform in v1.** Displaying prize funds and taking entry fees through a
hosted processor is very different from holding or disbursing prize money, which converts THRØ into a
regulated-payments and KYC/AML problem — compounded if minors can win.

**No legal conclusions were invented.** The questions requiring primary-source research before launch
are recorded in `docs/product/OPEN_DECISIONS.md`, and include: UK Online Safety Act applicability;
the ICO Age Appropriate Design Code; lawful basis and the age of digital consent (which varies 13–16
across EU member states); proportionate age assurance; US COPPA and state age-verification statutes;
whether entry fees with prize funds are regulated as gambling or as lawful prize competitions per
jurisdiction, and whether minors change that; app-store age-rating, families and reporting-mechanism
rules; and consent to stream identifiable minors from a venue.

## 10. Rating — what the design already settles, and what it does not

**Already correctly separated.** `RatingHero` carries rating, status (provisional/established),
delta, an *optional* band, country and region rank, and form. `Confidence` is a separate component
with three levels. Rating, Form, Rank and Confidence are already four distinct things in the design.

**Two design contracts worth calling out.** Rating *falls* are rendered in secondary text, never in
red — a dignity commitment repeated identically across all three rating components. And
`status='provisional'` **suppresses the number entirely**, rendering an em dash with a "Rating
establishing" tag.

That second contract is the answer to "do not ship an arbitrary rating to fill the UI", and it costs
nothing: **THRØ can ship the entire flagship vertical slice with every player provisional**, every
candidate model running in shadow, and the Confidence surface honestly saying the system is still
learning. That is not a placeholder — it is the truthful state of the world at launch, and it is what
the design was drawn for.

**What must be captured now or rating science becomes impossible later:** outcome type as a
first-class field (a walkover stored as 5–0 is indistinguishable from a played 5–0 forever, and
poisons every candidate model); full competitive context on every result, since format sensitivity
and cross-pool calibration are the core empirical questions; the opponent's **published rating at
that instant**, frozen, or last season's explanations silently rewrite themselves; multiple
concurrent model outputs with exactly one published, which is what keeps the algorithm decision
genuinely open; and a scale epoch, because the design uses absolute rating values as fixed semantic
landmarks (pathway thresholds, field averages, division averages) that would silently rot under an
unanchored model.

**Synthetic simulation can falsify a model but can never approve one.** The selection graph — who
plays whom, driven by geography, league membership, seeding, entry cost and self-selection into
fields "matched to your level", which THRØ itself will influence — is the least simulable and most
important real phenomenon, and it is precisely the mechanism that breaks cross-pool comparability.
Approval requires held-out real data from at least two structurally different pools plus a
prospective shadow period.

**The structural anti-gaming insight:** the posture depends far more on *where results come from*
than on cleverness in the mathematics. Because THRØ owns the competition layer — draw publication,
board assignment, check-in, call control — it can make the fixture exist *before* the result. That
single fact defeats fabricated results, selective submission and most opponent-farming. It must be
protected: ad-hoc player-versus-player matches default to unrated.

## 11. Blocking questions — founder decisions only

Everything else has been resolved or is being resolved inside engineering. These three cannot be.

### B1 — Which statistics does THRØ show, and do we capture darts-used?

THRØ captures visit totals. From those, **180s, 140+/100+ counts, highest checkout, leg win rate and
deciding-leg percentage are exact**, and **First 9 is exact** for legs of three visits or more. But:

- **3-dart average is systematically biased low** — it assumes three darts on every visit including
  the leg-winning one. A 501 leg won in 15 darts scored as 17 reads 29.5 instead of 33.4, a 13%
  understatement.
- **Checkout % cannot be computed at all.** It needs doubles attempted, and there is no way to know
  whether a player threw one dart or three at a double from 40.
- **Doubles hit rate cannot be computed at all.**

The approved design displays all three. The engineering recommendation, converged on by every
reviewer that examined it: **capture `dartsUsed ∈ {1,2,3}` on the leg-winning visit only** — one tap
per leg, roughly five per match. That single optional field makes 3-dart average and best-leg
*exact* and gives an honest lower bound on doubles attempted, without ever inventing a dart. It must
exist in event schema v1 even if the first release never prompts for it, or it creates a permanent
"unknown" cohort.

That leaves Checkout % and doubles hit rate. The options are to rename Checkout % to something
honestly computable — *finish rate from a checkable position*, which is exact from visit totals and
genuinely informative but is **not** checkout percentage and must not reuse the label — or to remove
them pending a dart-level capture mode.

**This is a product and integrity decision, not an engineering one, and it must be made before any
schema is frozen.**

### B2 — Does a unilateral self-reported result move rating?

The organiser design states that self-reported results *"still count"*. Counting **for bracket
progression** and counting **for rating** are different claims, and the design does not distinguish
them.

The recommendation is that the minimum attestation for *rating eligibility* is
**participant-confirmed** — meaning one player's unilateral claim never moves either rating, while
self-reported results still progress the bracket and appear in the record. This is described by the
rating review as the single highest-leverage anti-gaming decision available, and it costs nothing
structurally. The design already supplies the intended remedy in its own copy: assigning a venue
scorer raises a whole round to participant-confirmed or better.

**Which sense of "count" you intend is a founder decision about competitive integrity.**

### B3 — Design work that only you can commission

Four items cannot be invented by engineering without silently redesigning the product, and all
require going back into Claude Design:

1. **A Dynamic Type / font-scaling contract** — per type role: does it scale, what are the clamps,
   and what do the hero numerals do at accessibility sizes. This blocks native layout work, because
   retrofitting it changes every screen.
2. **Focus, hover and pressed appearance** — currently absent from all 61 components. These are brand
   decisions.
3. **The `quarantined` verification state** — the trust model needs it; the design has eight states
   and does not include it.
4. **The organiser layout and breakpoint contract** — sidebar width, content max-width, column
   ratios, grid gutters, minimum supported width. The organiser screens are otherwise complete.

Also needed, and much smaller: **the brand mark** (`logo-chalk.svg` is referenced throughout and was
not exported), and confirmation of the **font licence terms**, specifically any Reserved Font Name
clause.

Separately, running **`/design-login` once from an interactive Claude Code session** on your machine
would give every future remote session live access to the Design project, replacing the export
snapshot.

**Two things I am proceeding with rather than asking about**, because the engineering answer is
unambiguous and the cost of waiting is high: an **age band will be modelled as a first-class
authorization attribute from the first account** (the policy question — declared date of birth versus
age band versus verified assurance — remains yours, but the field and the authorization dimension
must exist), and **Report and Block** will be treated as launch requirements rather than later
additions.

## 12. Recommended initial production boundary

Unchanged from the brief, with two clarifications that Gate 0 evidence forces:

The first production vertical slice is **Discover → Event → Register → Check-in → Draw → Board
assignment → Match called → Match ready → Score → Offline/sync → Result → Confirmation →
Tournament progression → Passport**, backed by real persistence, real API contracts, real auth and
real domain logic.

**Clarification 1 — rating ships provisional.** Every player is `status='provisional'`, no rating
integer is published, candidate models run in shadow, and the research harness is built *during* the
slice rather than promised after it. A laboratory deferred is a laboratory never built, and by the
time it is wanted the schema will be wrong.

**Clarification 2 — the organiser slice is not optional.** The participant journey depends on
organiser-side check-in, draw, board assignment and calling. Those screens exist and their
information architecture is sound; only the layout contract is missing (§11 B3.4).

Single elimination only for tournaments, but the competition structure must be modelled as a slot
graph so that groups and double elimination are later *generators* rather than a rewrite.

## 13. Gate 0 checkpoint

**What was built.** The repository foundation: design authority recovered, verified and committed
with full provenance; a generated design inventory (61 components, 33 participant screens, 9
organiser screens, 70 icons); the open decisions register; and the README establishing product
framing, source precedence and engineering non-negotiables. Five commits, pushed.

**What was tested.** Not code — there is none. What was *verified* was the design source itself:
every contrast ratio in §8 recomputed from first principles; the impossible dart counts in §6
confirmed by exhaustive computation over the real dartboard segment set; the bye arithmetic
recomputed; the component, screen and icon inventories generated mechanically from the export rather
than transcribed.

**What failed.** Two initial readings of mine were wrong and were corrected: I first concluded the
organiser screens had not been exported (they had been compiled into the component bundle), and an
early extraction mis-split the component library. Both were fixed, and the reviewer working from the
incorrect briefing was notified mid-flight. One reviewer's restatement of the bye formula conflated
players with matches; §6 carries my verified figures instead.

**What remains open.** The three blockers in §11, the twelve entries in the open decisions register,
and every Gate 1 architecture decision. Twenty-two items where *the approved design system does not
specify behaviour* are catalogued and must not be invented by engineering.

**Evidence supporting acceptance.** The design authority was inspected rather than remembered — the
brief's central requirement. Six independent reviews converged on five conclusions. The foundation's
sharpest risk (statistics honesty) was found independently by every reviewer that looked for it, and
is escalated rather than quietly patched.

**Verdict: Gate 0 PASSES with three founder blockers.** Gate 1 — architecture — may begin
immediately on everything not gated by B1, since the shared-domain and persistence decisions do not
depend on the statistics question. Schema freeze does.

---

*No part of this repository is production ready. No code has been written, no tests have been run
against an implementation, and no claim of security, offline reliability or rating validity is made
anywhere in this document.*
