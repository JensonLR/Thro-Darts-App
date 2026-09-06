# THRØ — Gate 0: Foundation Acceptance Report

**Date:** 2026-09-03 · **Revision 2** (after hostile review) · **Status:** Gate 0 complete
**Verdict:** PASS WITH BLOCKERS · **Next gate:** Gate 1 — Architecture

Gate 0 was foundation ingestion, not implementation. No product code was written, and none should be
until the blockers in §11 are answered.

> **Revision note.** Revision 1 was rejected by hostile review for three defects, all of which were
> real and all of which are corrected here: it asserted as *verified* a contrast claim that is false
> (§8); it described artefacts as catalogued and built that existed only in working notes (now
> committed — see §14); and it claimed the design and the integrity constraint "agree completely"
> when a live scoring surface renders fabricated dart progress (§6). Several specialist findings had
> also been lost in synthesis and are restored. The underlying investigation held up under attack:
> the darts arithmetic, the bye arithmetic, and every listed contrast figure were independently
> recomputed by the critic and reproduced exactly.

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
| Reference implementation / prototype code | 7 | **None exists.** |
| Sample data | 8 | Present, embedded in the design export. Treated as fixtures throughout. |

**The repository was empty** — zero branches, zero commits, zero files. There is therefore **no
prototype or reference code to retain or discard**, a question Gate 0 had to answer. Nothing has to
be unpicked and no throwaway architecture has been inherited. That advantage should not be squandered
by treating the export's compiled JSX as a starting point: it is a reference, not a foundation.

The `thr-design-system` folder on the founder's local machine did not reach this environment, and
neither did the founding dossier, the product specifications, or the `handoff/TYPOGRAPHY_TOKENS.md`
that the design's own token file references. **Precedence rank 4 is currently empty**, so the founder
brief is carrying product authority alone.

## 2. Design connection status

**The live Claude Design project could not be reached.** `DesignSync` needs an authorization that can
only be granted by running `/design-login` from an interactive Claude Code session on a local
machine. Remote sessions reuse it once it exists, so this is a one-time action that would unblock
live design access permanently.

The approved system was recovered instead from the founder's **published Claude Design export**,
extracted, verified and committed to `docs/design/`. It is genuine: it carries the Claude Design
`@ds-bundle` manifest, per-file source hashes and the Claude Design branding block.

Recovered and verified by reading it: the **complete token layer** (177 tokens, with light and dark
semantic parity); **61 components** across **10 families**; **33 participant screens** in 9 groups
plus the navigation model; and **9 organiser screens** plus the organiser shell, which were initially
believed missing and were recovered in full.

**This is a compiled export snapshot, not the design master and not a live connection.** It cannot be
diffed against the current Design project, and any design work after 2026-09-03 is not reflected.
Provenance is recorded in `docs/design/DESIGN_SOURCE_PROVENANCE.md`.

## 3. Method, and exactly what was verified

Six specialist reviews ran independently and in parallel — darts domain and scoring engine; system
and backend architecture; mobile and shared-domain architecture; security, privacy and safeguarding;
design system and accessibility; rating science, trust and anti-gaming. Each carried a hostile
persona for its own domain. A seventh review then attacked the resulting report.

**Recomputed from first principles rather than accepted:** the impossible dart counts in §6
(exhaustive search over the real dartboard segment set); the bye arithmetic in §6; and **every
semantic colour pair in both themes**, which is now a generated artefact at
`docs/design/CONTRAST_MATRIX.md`.

**Generated mechanically rather than transcribed:** the component, screen and icon inventories
(`docs/design/DESIGN_INVENTORY.md`) and the dead-token and bypass lists
(`docs/design/TOKEN_HEALTH.md`).

Revision 1 claimed more verification than it had performed: it recomputed the failures it listed but
not the passes it asserted, which is how the error in §8 survived. The contrast matrix now exists so
that the question is settled by regeneration rather than by claim.

## 4. Convergent findings — where independent reviewers agreed

Six conclusions were reached separately by three or more reviewers. Treat these as settled.

1. **Rating must be a recomputable projection, never a stored mutable number.** The evidence is in
   the design itself: the organiser dispute screen states *"Ratings are recalculated from the
   corrected result."* An incrementally-mutated rating cannot honour that, because reversing one
   match must ripple to every opponent downstream. Rating is `f(event log)`, versioned and replayable.
2. **Confirmation attaches to the leg, not the match** — *"Legs 1–8 are confirmed by both players and
   give 4–4. The dispute concerns leg 9 only."* Match-level confirmation makes that screen unbuildable
   and forces disputes to be all-or-nothing. Not recoverable retrospectively.
3. **Some statistics on the approved surfaces cannot be honestly computed.** Blocker B1.
4. **`quarantined` is missing** from the eight verification states — and must be an *orthogonal
   eligibility axis*, not a ninth enum value. Overloading the enum destroys the provenance beneath it.
5. **The verification label must be derived from a composite provenance record, not stored in its
   place.** The design proves the labels are compositions: `thro-verified` is defined as *"Recorded in
   THRØ **and** confirmed by the organiser."* Storing only the enum means trust can never be
   re-derived under a changed policy, never audited, and two results reaching the same label by
   different routes become indistinguishable. A team that builds `provenance ENUM(8)` loses this
   permanently.
6. **`Undo` has two incompatible meanings.** The component's `aria-label` says "Undo last score";
   the screen wires it to clear the digit buffer. One emits no event; the other must append an
   auditable correction. Collapsing them leads directly to mutating the local journal.

## 5. Divergent findings — adjudicated

### Shared domain strategy

The mobile review recommends three native implementations governed by a conformance corpus, with rule
*data* generated into all three languages, rejecting Kotlin Multiplatform on toolchain burden and iOS
debuggability. The backend review recommends a KMP module, arguing it collapses the drift surface
from three implementations to one.

**Adjudication: defer, but honestly.** Both agree on what must happen now, and both are prerequisites
of either path: a **pure, dependency-free, value-typed engine module** (no floating point, no clock,
no randomness, no I/O), and a **versioned conformance corpus**, now specified at
`docs/architecture/CONFORMANCE_CORPUS.md`.

Two honest qualifications that revision 1 omitted. First, the corpus is genuinely a common prefix and
is never wasted; the *rule-table generator* is **not** — it is only needed on the three-implementation
path, so it is a real cost of deferring. Second, the kill criterion must be **correctness, not IDE
ergonomics**: build times and debuggability are the arguments used to reject KMP a priori, so testing
those merely re-litigates a settled dispute. The trigger to record is the mobile review's own:
**if two or more genuine cross-platform divergences reach a human-tested build, or the rule surface
grows past X01 plus sets, migrate to a single shared core** — proven correct by the same corpus.

### Scoring authority — three mechanisms, not two

Revision 1 claimed a single-writer lease and per-device evidence streams "compose" to produce the
design's dispute screen. That was wrong on two counts, and the corrected model needs a third mechanism.

The dispute screen carries a per-leg **`Confirmed`** column reading `Both` / `Blake only`. Shaw's
evidence card says *"Entered after the match from memory"* — so Shaw authored no live stream at all,
yet Shaw is recorded as confirming legs 1–8. That column is a **third object**: a per-leg attestation
authored by the *non-scoring* participant. Two mechanisms cannot produce it.

And a lease, as stated, contradicts §7's rule that scoring must be network-independent: a
server-granted lease is unavailable in exactly the venues whose bad signal is the premise.

**The corrected model:**

1. **A scoped offline scoring grant**, issued by the server at match-open — the moment the design
   already draws (*"Both players must confirm before scoring opens"*). It is authored by the server,
   held on the device, and **valid without a network at scoring time**. This is the lease, and it is
   compatible with network-independent scoring.
2. **Per-device evidence streams**, gapless per `(aggregate, device)`, never discarded and never
   cross-device deduplicated. Two streams for one match is *corroboration*; divergence is a dispute.
3. **Per-leg participant attestation** as a first-class event, authored by the non-scoring
   participant. This is what the `Confirmed` column reads from.

**The offline two-device case, stated explicitly**, because it was unaddressed: both players score
the whole match offline on separate devices. Neither holds an exclusive claim; both produce complete
conflicting streams; there are no attestations. Reconcile at **outcome level** — winner and per-player
leg scores — *not* by digest equality, because a digest over a leg's events makes a single mis-keyed
and corrected visit mismatch on a leg both players agree about, yielding "9 of 9 legs disputed" for a
match nobody disputes. Use a visit-level diff only to *explain* a mismatch. This produces a
**whole-match-contested** state that the design does not currently draw (added to B3).

Two further consequences to record now: offline matches remain **self-reported until sync** — an
explicit product decision, not a defect, and one that feeds directly into B2 — and **peer-to-peer
sync must not be built in the first slice** (iOS and Android share only Bluetooth LE, which adds a
permission and a privacy declaration for no first-release benefit).

## 6. Domain risks

**The approved *input* model is visit totals, and this is correct.** `ScoreKeypad` offers quick keys
180/140/100/60/45/26, digit entry, Miss and Undo, and commits one number per visit. There is no
segment input anywhere in the 61 components. The `Checkout` route (T20/T11/D14) is *advice*, confirmed
by a user setting "Checkout suggestions · On", and is never captured as evidence.

**But two display surfaces render granularity the input cannot supply.** Revision 1 wrongly concluded
the design and the integrity constraint "agree completely". They agree on input; they diverge on
display:

- **`TurnIndicator` on the live scoring screen** is passed `dartsThrown: bust ? 0 : 2` and renders
  three pips labelled *"2 of 3 darts thrown"*. A visit-total keypad cannot know that two darts have
  been thrown mid-visit. This is fabricated dart progress on the most-used screen in the product.
  Fix: the component must take a turn state (open/closed), with the three-pip form reserved for a
  future dart-level capture mode.
- **The organiser dispute evidence table** carries a per-leg `Darts` column, discussed below.

**Fabricated dart counts appear in the highest-stakes screen in the product.** The organiser dispute
table, captioned *"Evidence · THRØ-recorded legs"*, has two of nine rows that are **arithmetically
impossible**, verified by exhaustive computation and independently reproduced under hostile review:

- Leg 6 — 19 darts implies a one-dart finish of 48. One-dart double-out finishes are {2, 4 … 40} ∪
  {50}. **48 is impossible.**
- Leg 9 — 16 darts implies a one-dart finish of 64. **Also impossible** — and leg 9 is *the disputed
  leg*, the row the ruling turns on.

This is sample data, not shipped code, but it is on the screen where an official decides a competitive
result and where the same screen states that ratings are recalculated from that decision. The `Darts`
column must be removed, replaced with `Visits` (always exact), or shown only where dart counts were
genuinely captured.

**The design contains four arithmetic impossibilities, not one.** Reporting only the dispute table
understated how unreliable rank-8 sample data is:

1. The dispute table rows above.
2. The **bust screen uses remaining = 186** — but bust is mathematically impossible at remaining ≥
   182, and 186 is not a legal visit total. The entry buffer is pre-filled with it.
3. The organiser shows *"Round of 64"* with *"41 of 64"*; a Round of 64 has 32 matches.
4. Rating detail shows a hero delta of +27 while its own chart moves 1821 → 1847 (+26) and its ledger
   rows sum to +37. That yields a genuine invariant: **the per-match ledger must reconcile exactly to
   the net change over the same period, and any non-match adjustment must appear as its own visible
   ledger line rather than being silently absorbed.**

**Bye arithmetic in the approved design is wrong.** The organiser reads *"74 entries · Round of 64
with 10 byes"*. A bye advances a player without playing. Verified for 74 entrants: bracket 128,
**54 byes**, 20 players in preliminaries, **10 preliminary matches** — 10 winners plus 54 byes gives
64. The design's "10" is the preliminary-match count, mislabelled. The domain must compute these; the
UI must never carry them.

**Other material risks.** Master-out maximum is 180, not 170. The nine impossible visit totals must be
rejected — `NumericInput`'s `max=180` is a bound, not a legality check. Bust condition three (exact
zero on a non-finishable number) is the one implementations drop. A bust visit must be recorded, not
discarded. Full rule detail is in `docs/architecture/CONFORMANCE_CORPUS.md`.

**A boundary that must be stated in the API contract:** double-out can be *permitted* from visit
totals but never *verified*. The server can assert "this claim is rule-consistent"; it can never
assert "this is what happened". Without that qualifier, §7's "the server validates competitive
evidence" will be read in six months as "the server can detect false scores". It cannot.

**Throw order is the largest unmodelled area.** Nothing in the 42 screens establishes who throws first
— no bull-up, no starter indicator, no alternation display. Throw advantage is asymmetric and
material, so a rating engine that ignores it measures the wrong thing.

**Sets are in scope and must be built now**; retrofitting a set layer into a leg-flat aggregate is a
rewrite. Per-round format override is required — real tournaments escalate to a longer format for
finals.

**The competitive entity is not a player.** The design contains a full league surface (divisions,
seasons, fixtures with rearrangement and *awarding*, captains, a published table with a `Team rating`
column) and Pairs events. If `Match` is built with home and away *player* ids, introducing
`Competitor = Player | Pair | Team` later is exactly the rewrite this report warns about for sets.
A slot graph generalises brackets; it does **not** generalise a league fixture, which has no
parent/child dependency, has a scheduled window and rearrangement lifecycle, can be awarded with no
match played, and aggregates into a table rather than advancing a competitor. Introduce `Competitor`
at Gate 1 regardless of scope, model `Competition` as tournament-or-league-season with `Fixture`
distinct from `Slot`, and add `awarded` to the terminal states.

**Terminal states the brief's state machine omits but the organiser screens require:** walkover,
void, abandoned, leg-replayed, awarded and disputed. Each has different rating and statistics
eligibility.

## 7. Architecture assumptions

Gate 1 inputs, not decisions — recorded so Gate 1 argues against something concrete.

- **Modular monolith**, not microservices. Hard module walls for match, trust and rating from the
  first commit; the rest graduate.
- **One managed Postgres** holding the event log, competitive graph, read models, search and jobs.
  One transactional boundary is worth more to a one-operator team than any throughput advantage.
- **Append-only is a database grant, not a convention** — revoke UPDATE and DELETE on the evidence
  schema and assert it in CI.
- **Command receipts written in the same transaction as the event append.** A crash between two
  transactions either double-applies a visit or loses one.
- **A naive global-sequence tail will silently skip events**, because identity values are assigned at
  insert and not at commit. Consume to a watermark derived from the oldest in-flight transaction.
- **Ordering never depends on wall clock.** Order by `(device, sequence)`; device time is evidence,
  server time is authority. A wrong clock is not a cheating signal and must never reject an event.
- **Durability must be explicit.** SQLite and Room default to a mode surviving process death but
  **not power loss**. Losing an acknowledged visit has no repair path.
- **Rejected or unsyncable events are never discarded client-side.**
- **The scoring module must be network-independent by construction**, enforced by the module
  dependency graph in CI.
- **The bundle identifier and Android applicationId must not contain the product name.** A rename is
  anticipated; changing an Android applicationId means a new Play listing with no migration — installs,
  reviews and ratings lost. Keep all identifiers ASCII: `Ø` is not.
- **Fix the public URL shapes now** (`/e/{eventId}`, `/m/{matchId}`, `/p/{playerHandle}`) — universal
  and app links make them permanent.

Performance budgets are at `docs/architecture/LATENCY_BUDGETS.md`.

## 8. Design assumptions and risks

**The semantic colour layer is strong** — full light/dark parity across 44 aliases. `ErrorState`'s
what/safe/todo contract, the shared trust vocabulary, and the organiser information architecture are
genuinely good, and `screens-integrity.jsx` is the most product-correct artefact in the export.

**The rest of the token layer is 27% aspirational.** Generated evidence in
`docs/design/TOKEN_HEALTH.md`: **48 of 177 tokens are never referenced**, including
`--touch-target-minimum` (the accessibility floor), nine of twelve motion tokens (so the SET → THROW →
IMPACT → RESOLVE grammar exists only as token names — three components animate at all), all four
border composites, `--color-scrim`, and every semantic spacing alias — meaning
`--space-gutter-android` is dead and **every screen is laid out on the iOS 20px gutter**. There are
**16 raw colour values and 10 off-scale font sizes** bypassing the token layer entirely.

**The components are a demo, not a contract.** Across all 61: **zero** implement focus, hover or
pressed; four implement disabled; one implements loading. For a keypad used one-handed at speed, the
absence of a pressed state is a functional defect.

**Three design-side P0s:**

1. **Theme scope is an undocumented cascade side effect.** Scoring is dark only because of a hardcoded
   screen-ID allowlist in the throwaway prototype harness. **Four components — `LegState`,
   `RemainingScore`, `ScoreHero` and `SetState` — default to `theme='dark'` and paint no background
   at all.** On the default light background their text is chalk on chalk, **1.00:1**: the 96px
   remaining score is literally invisible. It works today only because an ancestor happens to be ink.
   SwiftUI and Compose have no cascading custom properties, so this does not port.
   *(Revision 1 wrongly named `MatchSummary` in this list; it defaults to light.)*
2. **The type scale is fixed pixels with no Dynamic Type or fontScale contract**, against a mandate
   for first-class native iOS and Android. Several heroes already have negative leading, so scaling
   them naively clips. Retrofitting changes every layout.
3. **There is no machine-readable token source.** `tokens.css` is a compiled artefact — the stripped
   `@font-face` rules left orphaned subset comments behind. Three platforms would hand-copy 177 tokens.

**Accessibility failures — 21 semantic pairs fail, generated at `docs/design/CONTRAST_MATRIX.md`.**
Revision 1 claimed all nine status/surface pairs passed AA in both themes. **That was false**, and the
contradicting figure had already been computed. Seventeen of eighteen pass; the exception matters:

| Pair | Ratio | Consequence |
|---|---:|---|
| **`live` on `live-surface` (light)** | **4.38:1** | **Fails AA.** The most-used status in a live-scoring product — Live directory, match centre, stream overlay, every "playing now" row |
| Bronze as text on chalk | 3.68:1 | Fails AA; large text only |
| `text-tertiary` on `bg-secondary` (both themes) | 4.21 / 4.30:1 | Fails AA on sunken surfaces, including notification timestamps |
| `text-inverse` on brand green (dark) | 1.99:1 | Ink on deep green — nobody flagged this; the generated matrix found it |
| Focus ring on brand green | 1.29:1 | Focus invisible on every primary button |
| Focus ring on ink | 1.99:1 | Focus invisible on all ink surfaces |
| `border-strong` on chalk | 1.70:1 | Fails 1.4.11 — and it is the *only* boundary of secondary buttons |
| Chalk on chalk (the invisible default) | 1.00:1 | See P0-1 above |

The token file's guidance that pewter (4.18:1) is safe at "18px+" is **wrong** — WCAG large text is
24px regular or 18.66px bold — and the comment therefore authorises a failing usage.
`--touch-target-minimum: 44px` is defined and **used nowhere**; three components sit below it, and the
keypad's six-across quick-score row falls to 40px wide below a 344px viewport.

**`ScoreKeypad` — the highest-stakes component — has three defects.** `disabled` is opacity plus
`pointer-events: none` with **no disabled attribute on any button**, and pointer-events does not block
keyboard or switch control, so an assistive-technology user can commit a visit while the keypad is
meant to be locked. **Empty submit commits a zero** — a stray tap appends a 0-score visit
indistinguishable from a genuine Miss, and Undo clears the buffer rather than revoking it, so there is
no recovery path. The digit buffer passes 0–999 to the command layer unvalidated.

**`Dialog` and `Sheet` claim modality they do not implement** — `aria-modal="true"` with no scrim, no
focus trap, no Escape handler, no initial focus. `Dialog` is what confirms "Publish the draw", "Close
check-in" and "Void the match". Claiming `aria-modal` on a non-modal element is worse than nothing: it
tells assistive technology the rest of the page is inert when it is not.

**`TrendChart` is the rating-evidence surface and is not evidence.** It auto-derives its scale with no
axes and no y-scale, so **a 3-point and a 300-point rating change render as identical slopes**. It
accepts a `tableLabel` prop and never renders a data table, so intermediate points are unreachable
non-visually.

**The organiser gap is layout *and* keyboard operability.** The organiser CSS classes have no
definitions — no sidebar width, content max-width, column ratios, gutters, breakpoints or minimum
width. And `DataTable`, used across disputes, entries, verification, draw and league, renders rows as
a clickable `<tr>` with no tab index, role or key handler: a keyboard failure on the surface where an
official decides competitive results. The participant harness classes are equally undefined, so
**safe-area insets are specified nowhere** — on a full-bleed scoring screen whose bottom element is
the keypad.

**Fonts.** The `@font-face` rules were stripped entirely; the export contains no font-loading
mechanism and no binaries, so it **silently substitutes today**, which its own comment forbids. Every
glyph-width-dependent measurement is provisional. Both families are believed OFL 1.1 but must be
confirmed, with attention to any Reserved Font Name clause, because subsetting is exactly what
production will want. Icons are Lucide under MIT — no obstacle.

The full catalogue of what the design does not specify is at `docs/design/DESIGN_UNSPECIFIED.md`
(24 items).

## 9. Security, privacy and safeguarding risks

**The honest anchor:** THRØ cannot prove a dart landed. It can only prove *who asserted what, when,
from which device, and who corroborated it*. The goal is not to prevent false scores but to make every
score attributable, corroborated, and reversible without collateral damage.

**The adversary is the opponent, the colluding pair, and the conflicted organiser** — not primarily an
external attacker. The design makes the incentive concrete: rating gates bye allocation (*"Byes go to
the highest-rated checked-in players"*), seeding, event fit and public rank, with £18–£40 entry fees
and £1,400 prize funds attached.

**Authorization must be relationship-based from the first commit.** One person in the approved design
is simultaneously Tournament director, Captain, listed player and Venue scorer. Permissions sit *below*
the event — scorers are assigned to individual boards — and roles are season-bounded. The
conflict-of-interest rule (an official may correct a match *unless* they or their team are in it)
requires a negation that naive role-based access control cannot express. **Permissions must never live
in the token**, or a removed organiser keeps power until it expires.

**The single most concrete attack is cross-match evidence injection:** post a leg event carrying a
stranger's match id and you move a stranger's rating. Every event must be validated against the
aggregate's own participant set, loaded from the store — never against ids in the request body. List
endpoints are the other leak: "Export list" yields the full entrant roster with rating, verification
state and payment status.

**Three verification axes exist in the design and only one is in the brief** — and the evidence
vocabulary is already misused as an identity badge. `VerificationState state="organiser-confirmed"` is
rendered against *the organiser* on the paid-registration screen, where that state's own help text
reads "Confirmed by the competition organiser" — nonsense applied to the organiser. Settings carries a
player-level row reading "Verification · THRØ verified", where that state is defined as a property of
a *result*. These must be three separate models: **result provenance** (eight states plus orthogonal
eligibility), **identity verification** (one real person, one account — never quality or prestige),
and **organiser accreditation**. Left undefined, this becomes `Player.verificationState` on day one
and is the "verification = prestige" failure the brief forbids.

**Identity must be physically separable from the event store.** The design promises that deleting a
THRØ ID removes the profile while *"results of matches you played remain on your opponents' records
and in competition archives, without your name attached."* If names are denormalised into events,
projections, brackets, exports or search indexes, that promise is unimplementable. Events carry an
opaque player reference; **every read model, cache, public page, search index and export must be
regenerable from the pseudonymised source** — that regenerability clause is the expensive part and
must be a build-time invariant.

**There is no age signal anywhere.** No date of birth, no age gate, no guardian relationship. Meanwhile
real names are published *"on public THRØ pages and in search engines"*; live presence is broadcast
with venue and board; following is one-way and needs no consent; and there is **no Report and no
Block**. Ages cannot be retro-assigned without re-consenting the entire user base, and in the interim
minors' names would be on search-indexed pages with their live location broadcast.

**A correction to revision 1's framing:** it praised the absence of chat as the cheapest safeguarding
property available. That understates the exposure. The design contains **venue-operated live video**
— *"Venue feed · 1080p"*, per-board feeds, reconnect handling — which is a far larger user-generated
content surface than chat, with no reporting mechanism anywhere. The Online Safety Act question listed
below is triggered principally by *that*, not by messaging.

**"Near you" can work without storing precise location.** Region, home venue and travel radius are
already collected and no location permission is requested anywhere. Resolve the locality to a coarse
area code stored as a string; never put a coordinate on a person; **band displayed distances**, since
precise distances to three known venues locate someone to a few hundred metres.

**The draw is manipulable and unverifiable after the fact** (a draft state plus "Redraw", with
rating-driven byes). Commit a server-generated seed and record every generation including discarded
drafts. Cheap now, impossible retrospectively.

**Unclaimed-profile claiming is a day-one attack path.** Migrating paper leagues guarantees unclaimed
records, and *"that 1,900-rated record is me"* is extremely attractive.

**Prize money should stay off-platform in v1.** Displaying prize funds and taking entry fees through a
hosted processor is very different from holding or disbursing them, which converts THRØ into a
regulated-payments and KYC/AML problem, compounded if minors can win.

**Also required from day one:** a hash-chained append-only decision log as a first-class store; a
two-person rule for void, redraw and award; device and session management (Settings currently offers
only "Sign out"); scoped and logged organiser exports; and self-hosted fonts, since the CDN reference
leaks user IPs on every launch and interacts directly with the data-protection questions below.

**No legal conclusions were invented.** Research questions are recorded in
`docs/product/OPEN_DECISIONS.md`: Online Safety Act applicability (given live video); the ICO Age
Appropriate Design Code; lawful basis and the age of digital consent (13–16 across member states);
proportionate age assurance; COPPA and US state statutes; whether entry fees with prize funds are
regulated as gambling or lawful prize competitions, and whether minors change that; app-store
age-rating, families and reporting-mechanism rules; and consent to stream identifiable minors.

**Note:** the design export contains realistic personal data, including a plausible email address and
the founder's own name, now committed as fixtures. Seeds must be obviously synthetic so real and
sample data can never be confused.

## 10. Rating — what the design settles, and what it does not

**Already correctly separated.** `RatingHero` carries rating, status, delta, an *optional* band,
country and region rank, and form; `Confidence` is a separate component. Rating, Form, Rank and
Confidence are already four distinct things.

**Two design contracts worth naming.** Rating *falls* render in secondary text, never red — a dignity
commitment repeated identically across all three rating components. And `status='provisional'`
**suppresses the number entirely**, rendering an em dash with a "Rating establishing" tag.

That second contract answers "do not ship an arbitrary rating to fill the UI", and it costs nothing:
**THRØ can ship the entire flagship slice with every player provisional**, candidate models running in
shadow, and Confidence honestly saying the system is still learning. That is not a placeholder — it is
the truthful state of the world at launch.

**What must be captured now or rating science becomes impossible later:** outcome type as a
first-class field (a walkover stored as a scoreline is indistinguishable from a played one forever);
full competitive context on every result; **the opponent's published rating frozen at that instant**,
or last season's explanations silently rewrite themselves; multiple concurrent model outputs with
exactly one published; and a scale epoch, since the design uses absolute values as fixed landmarks
(pathway thresholds, field averages, division averages) that would rot under an unanchored model.

**Synthetic simulation can falsify a model but never approve one** — the selection graph is the least
simulable and most important phenomenon, and it is what breaks cross-pool comparability. Full harness
specification at `docs/product/RATING_HARNESS.md`.

**The structural anti-gaming insight:** the posture depends far more on *where results come from* than
on the mathematics. Because THRØ owns the competition layer, it can make the fixture exist *before*
the result — which defeats fabricated results, selective submission and most farming. Protect it:
ad-hoc player-versus-player matches default to unrated.

## 11. Blocking questions — founder decisions only

### B1 — Which statistics does THRØ show, and do we capture darts-used?

From visit totals, **180s, 140+/100+ counts, highest checkout, leg win rate and deciding-leg
percentage are exact**, and **First 9 is exact** for legs of three visits or more (the denominator
must be disclosed, and excluding short legs systematically drops legs against fast opponents). But:

- **3-dart average is systematically biased low** — it assumes three darts on every visit including
  the leg-winning one. A 501 leg won in 15 darts scored as 17 reads 29.5 instead of 33.4, ~13% low.
- **Checkout % cannot be computed at all** — it needs doubles attempted, and there is no way to know
  whether one dart or three were thrown at a double from 40.
- **Doubles hit rate cannot be computed at all.**

**The blast radius is wider than a profile tile.** Checkout % and 3-dart average both appear on the
**stream and broadcast overlay for both players** — a knowingly-uncomputable statistic shown to an
audience and on a venue screen. And doubles hit rate is not a tile: it is one of three rows in the
Coach comparison chart, benchmarked against a peer cohort, feeding a prescribed training session whose
first drill is a doubles ladder. "Remove it" removes the Coach's evidence base and the training plan's
rationale, not a number.

**The engineering recommendation**, converged on by every reviewer who examined it: capture
**`dartsUsed ∈ {1,2,3}` on the leg-winning visit only** — one tap per leg, roughly five per match.
That single optional field makes 3-dart average and best-leg *exact* and gives an honest lower bound
on doubles attempted, without ever inventing a dart. It must exist in event schema v1 even if the
first release never prompts for it, or it creates a permanent unknown cohort.

For Checkout %, **the design has already answered this itself**: the Coach surface shows conversion
bands and its own copy says *"you convert 31% **of visits**"* — the honest framing. The equivalent is
a *finish rate from a checkable position*: exactly computable from visit totals, genuinely
informative, and **not** checkout percentage, so it must carry a different name and a different API
field. Reusing the label would be the same fabrication in a different costume.

Note this also requires a **`Stat` variant for unavailable and bounded values**, which does not exist
— see B3.

**This is a product and integrity decision, and it must be made before any schema is frozen.**

### B2 — Does a unilateral self-reported result move rating?

The organiser design says self-reported results *"still count"*. Counting **for bracket progression**
and counting **for rating** are different claims and the design does not distinguish them.

**This question is larger than it appears.** A match played entirely offline is self-reported until
sync (§5), and Settings promises *"Offline scoring · Always allowed"*. So the answer also decides
**whether offline tournament play is rateable at all** — in a product whose founding constraint is
that venues have no signal.

Two terms make the question answerable. **Eligible** = may inform the model at all. **Qualifying** =
counts toward establishing a rating; strictly narrower — eligible, *and* the opponent is established,
*and* provenance is at least participant-confirmed, *and* the outcome type is `played`.

The recommendation is that the minimum attestation for *rating eligibility* is
**participant-confirmed**: one player's unilateral claim never moves either rating, while
self-reported results still progress the bracket and appear in the record. This is the highest-leverage
anti-gaming decision available and it costs nothing structurally. The design already supplies the
remedy in its own copy — assigning a venue scorer raises a whole round to participant-confirmed.

### B3 — Design work only you can commission

Full catalogue at `docs/design/DESIGN_UNSPECIFIED.md`. The items that block implementation:

1. **A Dynamic Type / font-scaling contract** — the most expensive item to retrofit.
2. **Focus, hover and pressed appearance** — absent from all 61 components, and the focus ring
   currently fails contrast on brand and ink, so this needs a solution rather than a colour.
3. **The organiser layout and breakpoint contract**, and **keyboard operability of `DataTable`**.
4. **Participant safe-area insets.**
5. **The `quarantined` verification state.**
6. **A `Stat` variant for unavailable and bounded values** — without it, B1's honest option has
   nowhere to render.
7. **The three verification axes** — result provenance, identity verification, organiser accreditation
   (§9).
8. **A pending / not-yet-eligible rating state** and an **offline-completed result state** — between
   them the majority case at launch.
9. **A whole-match-contested dispute state** (§5).
10. **`bye` and `walkover` states on `TournamentProgress`.**

Also needed and smaller: the **brand assets** (`logo-chalk.svg` and `mark-chalk.svg` are both
referenced and neither was exported), and confirmation of the **font licence**, specifically any
Reserved Font Name clause.

Running **`/design-login` once from an interactive Claude Code session** would give every future
remote session live Design access, replacing the export snapshot.

### B4 — The authentication, recovery and identity-claim surface

Revision 1 scoped the slice as backed by "real auth" while **no authentication surface exists in the
design**. Across all 42 screens there is a splash "Sign in" button that routes nowhere and one
settings row reading "Sign-in method · Passkey". There is no enrolment flow, no sign-in screen, no
email verification, no recovery, no re-auth path after a token expires, and no device or session
management.

Two of these are the highest-risk flows in the product. **Passkey recovery** is the hardest problem in
this space, and it sits directly on top of the **unclaimed-profile claiming** attack (§9): a recovery
or claim flow invented by engineering is an account-takeover surface on a competitive identity. The
claim flow must be organiser-verified and audited from the start, not retrofitted onto a backlog of
contested identities.

**Until this exists, the flagship slice is not buildable as specified.**

### Proceeding without asking

Two decisions where the engineering answer is unambiguous and waiting is costly: an **age band will be
modelled as a first-class authorization attribute from the first account** (the policy question —
declared date of birth versus band versus verified assurance — remains yours, but the field and the
authorization dimension must exist), and **Report and Block** are treated as launch requirements.

### A likely fifth blocker, flagged not yet raised

**What is the Live surface in v1?** The design contains a real video product — venue feeds, reconnect
handling, per-board streams — and LIVE is one of the five primary worlds. Scores-only Live is a
modest addition; video is a moderation, cost, storage and regulatory commitment. This is not raised as
a blocker because the slice does not require it, but it should be settled before Live is scheduled.

## 12. Recommended initial production boundary

**Stated honestly, this is narrowed in two places and widened in one relative to the brief.**

The slice is: **Discover → Event → Register → Check-in → Draw → Board assignment → Match called →
Match ready → Score → Offline/sync → Result → Confirmation → Tournament progression → Passport**,
backed by real persistence, real API contracts, real authentication (blocked on B4) and real domain
logic.

**Narrowed — payment is removed**, pending OD-009 and the app-store position on real-world entry fees.
This is a genuine reduction, not a clarification, and it has a consequence: **payment state is
load-bearing on the slice**. The design shows "Register · £18", "Entry paid · £18", an `Unpaid` column
and filter on the organiser entries screen, and closing check-in *"withdraws every outstanding
player… three of them have unpaid entries and would be withdrawn regardless"*. Payment state therefore
changes the entrant count, which changes bracket size and bye count at draw time. **If payment is out
of v1, something else must gate check-in** — an organiser-marked paid flag is the minimum — and that
must be decided before check-in and draw are built.

**Narrowed — rating publication is removed.** Every player is provisional, no rating integer is
published, candidate models run in shadow, and the research harness is built *during* the slice.

**Widened — the organiser web kit is in scope.** The participant journey depends on organiser-side
check-in, draw, board assignment and calling. Those screens exist and their information architecture
is sound; the layout contract is missing (B3.3).

Single elimination only, but model competition structure as a slot graph *and* introduce the
`Competitor` abstraction and the `Fixture` type now (§6), because leagues and pairs are fully designed
and would otherwise force the rewrite this report warns about for sets.

## 13. Surfaces nobody owned — Gate 1 must assign these

Six specialists covered darts domain, backend, mobile, security, design and rating. These had no owner
and need one:

- **Competitor abstraction and the league/fixture model** (§6) — the highest-consequence omission.
- **Notifications.** `Notification` defines seven classes; Settings defines four toggles, one reading
  "Match called · Always on". A missed call causes a forfeit, so this is a competitive-integrity
  surface, not a growth one. "Always on" is also a promise the platforms may not permit. Needs a
  class → channel → user setting → OS interruption-level mapping with an explicit fallback when the OS
  suppresses a call.
- **Live and streaming**, including its Online Safety Act consequence (§9) and moderation model.
- **Observability and operational readiness** — not mentioned once in revision 1.
- **Analytics event taxonomy** — likewise.
- **CI/CD and release process** — Play App Signing, environment-suffixed identifiers so two-device
  sync can be tested, the permanent URL shapes.
- **Testing strategy beyond the scoring corpus.**
- **Internationalisation, en-GB enforcement, and the bounded explanation vocabulary** — the natural
  home for the voice rules.
- **Discover ranking and the objectivity/sponsorship separation.** "Matched to your level"
  personalises paid events with no stated ranking function, and "Verified organiser" is currently both
  an evidence claim and a commercial status.
- **Coach, Training and Transfer statistical honesty.** The Transfer copy *"Four more rated matches
  will confirm transfer"* is a statistical claim no estimator at n=4 can support — the same class of
  honesty problem as B1.

## 14. Gate 0 checkpoint

**What was built.** Design authority recovered, verified and committed with provenance; generated
design inventory, contrast matrix and token health; the catalogue of unspecified design behaviours;
the conformance corpus specification; the rating research harness specification; latency budgets; the
open decisions register; the domain glossary; the README; and this report. Eleven commits, pushed.

**What was tested.** Not code — there is none. What was *verified*: every semantic colour pair in both
themes, by generation; the impossible dart counts, by exhaustive computation; the bye arithmetic; and
the component, screen, icon, dead-token and bypass inventories, generated mechanically.

**What failed, and what was fixed.** Three defects in revision 1, all found by hostile review and all
real: a false verified claim about status contrast; artefacts described as catalogued that lived only
in working notes; and an overstated claim that the design and the integrity constraint fully agree.
All three are corrected above, the missing artefacts are committed, and lost specialist findings are
restored. Earlier in the session two extraction errors of mine were also caught and fixed — I first
concluded the organiser screens had not been exported, and an early split mis-assigned the component
library. One reviewer's restatement of the bye formula conflated players with matches; §6 carries the
verified figures.

**What remains open.** The four blockers in §11, the twelve entries in the open decisions register, the
24 unspecified design behaviours, the ten unowned surfaces in §13, and every Gate 1 decision.

**Evidence supporting acceptance.** The design authority was inspected rather than remembered. Six
independent reviews converged on six conclusions. The sharpest risk was found independently by every
reviewer who looked for it and is escalated rather than patched. The report was then attacked, found
defective, and corrected rather than defended.

**Verdict: Gate 0 PASSES with four founder blockers.** Gate 1 may begin on everything not gated by B1
and B4 — the shared-domain, persistence and authorization decisions do not depend on them. Schema
freeze depends on B1; the flagship slice depends on B4.

---

*No part of this repository is production ready. No code has been written, no tests have been run
against an implementation, and no claim of security, offline reliability or rating validity is made
anywhere in this document.*
