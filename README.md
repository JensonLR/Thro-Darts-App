# THRØ

**The digital home of competitive darts.**
From the pub board to the world stage.

THRØ doesn't decide how good you are. It gives you the evidence to understand where you
are, the tools to improve, and the competition to prove it.

---

## What this repository is

THRØ is a competitive infrastructure platform for darts — not a scorer, not a tournament
app, not a statistics app. It connects players, matches, visits, legs, sets, teams,
leagues, seasons, tournaments, venues, boards, ratings, trust and evidence into a single
competitive graph.

The product exists to help a player answer four questions:

> **Where am I? Why am I here? What can I do next? Where could I go?**

## Current state — read this first

The build follows a gated process in which foundations are established and **attacked** before
features are written. Gate 0's and Gate 1's first drafts were both rejected by hostile review and
corrected rather than defended — in Gate 1's case after the defect was reproduced against a live
database.

| Gate | | |
|---|---|---|
| 0 | Foundation ingestion | Closed — design authority recovered and inspected |
| 1 | Architecture | Closed — 15 decision records, hostile-reviewed and corrected |
| 2 | Repository foundation | Event schema and the command path, proved against a real Postgres |
| 3 | Design ingestion | Token pipeline generating Swift, Kotlin and CSS from one source |
| 4 | Competitive core | Scoring engine passing 258,516 exhaustive transitions, across all three out-rules |
| 5 | Offline match lifecycle | Domain core closed — grants, per-device streams, reconciliation. On-device journal built on iOS under the measured configuration (`ThroJournal`); Android not started |
| 6 | Vertical slice | An iOS slice exists for a match between two people on one phone — setup, scoring, result, journaled. **The slice with identity is still blocked** on the authentication *surface* (B4); ADR-008's mechanism is built |
| 7 | Trust and provenance | Closed — attestation, disputes, adjudication, quarantine, eligibility |
| 8 | Rating | Architecture closed — a replayable projection. **The model is OD-001 and stays open** |
| 9 | Organiser | Correction and adjudication closed, both under the conflict-of-interest rule |
| 10+ | Live, notifications, payments | Not started — each waits on a product decision |

**What is verified, and how:**

| | |
|---|---|
| Scoring rules | 2,988 property checks against independent darts facts — including that **every checkout route THRØ shows is a legal finish of exactly that number** under exactly that out-rule: the darts sum to it, the last lands on a legal finishing segment, none finishes early, none exceeds three darts, and a bogey number is offered no route at all (PD-013) |
| Scoring engine | **258,516 exhaustive transitions** + 64 corpus cases, **on two independent implementations** — both of them in CI on every push, and a runner that cannot find the table now fails instead of skipping itself. The table covered double-out alone until 2026-09-07, which is how a straight-out finish from 1 stayed wrong in both engines; it now covers every out-rule from a remaining of 1 |
| Statistics honesty | 25 tests — an uncomputable figure says so; an approximate one is never a point value. Five of them hold **recent form** (PD-018), which is a description of what somebody has scored over their last ten completed legs and is never called a rating: below three legs it is unavailable and says how many more are needed, an unfinished leg does not move it, and where the underlying average is a range so is the form figure |
| Trust and eligibility | 30 tests — a label can never disagree with the provenance under it |
| Authorization | 21 tests — the conflict-of-interest rule, and age as a dimension |
| Rating projection | 14 tests — reproducible from a watermark pair; OD-001 stays open |
| Competition structure | 13 tests — bracket identities exhaustive for every field size to 1024 |
| Clubs, leagues and tournaments | 11 tests — the whole authority table rather than examples of it; that a member recorded as a minor is listed to an admin and to nobody else; that no accent a club can pick makes the app unreadable, proved by sweeping the colour cube; that an announcement reaches nobody whose age is minor **or unknown** until OD-010 is answered; that a fixture may be moved but never asserts a result; and three on images (PD-014) — **nobody under 18, or of unestablished age, has a picture at all**, every gate an image must pass is named when it fails, and deletion stops it being served at once while the bytes go within thirty days |
| Schema and privileges | 71 property assertions against a real PostgreSQL |
| Command path | 9 integration suites, 169 assertions end to end against a real PostgreSQL |
| Design tokens | 60 contrast pairs, and `tools/check_tokens_exist.py` holding every token reference in the client to the generated file **and refusing a raw pigment painted as a surface** on a screen — the pigments do not flip with the appearance, which is how Home's masthead came to be 1.08:1. Absolute thresholds, 0 unrecorded breaches; every recorded exception carries the measured ratio it was raised at and fails if it worsens |
| Design components | 61 components audited mechanically against a baseline ratchet |
| Statistics honesty, Swift | The same 25 tests, ported case for case, on Linux |
| On-device journal | 84 tests — thirty-eight on the journal: configuration read back on open, append-only by trigger, replay throws on a corrupt row, a retraction supersedes and never deletes, an old journal upgrades on open, the device identity a journal was created with survives a caller that has forgotten it, and a double-in match is stored and replayed as one. Six of those thirty-eight hold **the shelf and the one delete** (PD-026): archiving takes a match off Home and out of nothing else — the visits, the whole list and the export still have it — and it survives a close and reopen because it is a column rather than a flag some screen is holding; a delete takes the match and every visit in it and says how many went, and leaves every other match exactly as it was; **every delete that is not that one still aborts**, including a bare `DELETE FROM journal`; a purge unlocks only the match it names, so another match's rows are as protected during one as they were before it; and a journal written before any of this opens with the column, reads every match back as what it was — on Home — and has the old unconditional trigger *replaced* rather than left beside the new one. Six more on **ending a match short** (PD-016): a retirement has a winner and an abandonment has none, an ending is final so a second one and every later visit or retraction are refused, an ending makes an earlier agreement stale, an ended match still replays every dart thrown in it, and the seat an abandonment has to store is proved inert by reading the rows back with the other one. One holds that a person's legs are numbered **oldest first**, which nothing else would have caught, because every pooled figure before the form figure was order-independent. Fourteen more on the **club book**, the separate database a captain's roster and fixture list live in — written under the same measured configuration, refusing a name that is blank, an accent that is not six hex digits and a kind, role or state this build does not know; a fixture that is cancelled or played never moves again; deleting a club takes its roster with it; and **an age band the store cannot read comes back as *unknown*, never as *adult***, because the permissive fallback is the one that lists a child. Four more on **attestation** (PD-011): a confirmation is an append that changes no score, a refusal outranks the other player's agreement, an agreement does not survive a visit or an undo written after it, and **a row kind this build cannot read is refused rather than replayed as a visit** — it used to fall back to *visit*, which would have put a score in the match nobody threw. Three more on **who played** (ADR-016): a match remembers the people its two names referred to, one written before that reads back with nulls rather than a guess, a person's visits pool across their matches with **legs kept apart** so two matches' leg 1 are not merged, and a match of theirs that will not replay is counted and reported rather than dropped. And three on the device's book of people: the same name typed differently is the same player, a rename keeps the id so their matches follow, and a person needs a name. Eight on **images** (PD-014), which perform the intake rather than describing it: a real JPEG is built carrying GPS and EXIF, put through the same path a club badge takes, and the bytes are read back to prove **the place a photograph was taken does not survive**; a photograph is brought down to badge size; something that is not an image is refused rather than stored; the same picture twice is one file; and a picture is refused for a minor **at the write**, and not handed back at all if an age later stops saying adult. And thirteen on **keeping a copy** (PD-017): an export carries every row as written including the struck ones, a retirement and an abandonment are told apart in the file, an edited file is refused rather than read as genuine, one from a later format is refused rather than guessed at, the same device state exports to the same digest, reading a file writes nothing into the journal — there is deliberately no importer while sync does not exist — and the data folder's backup flag is **set and read back**, so a future change that excluded it is noticed rather than discovered on a new phone. Nine more hold a league's book (PD-019, PD-020, PD-021): a team fixture needs **both** sides or it is refused, because everything that reads one needs both; a result carries where it came from and there is no combination of arguments that writes one which cannot say — the table's own CHECK refuses a scored result with no match and an official's word with nobody's name; recording a result plays the fixture, and a cancelled fixture refuses one because nobody threw; removing a team takes its fixtures and their results with it, and the count is sayable before it happens rather than discovered after; a shape belongs to a tournament, is refused on anything else, and one that reaches a row some other way is not shown; points belong to the league and a league written before they were stored reads back as 2 and 1 rather than as nought; a result row that has lost its provenance is **dropped on read**, because a result nobody can attribute is the one thing a table must not contain; and two on **what the numbers are** (PD-022) — a league's unit round-trips and may be changed while nothing depends on it, and **settles the moment there is one result to reinterpret**, with the refusal naming how many are in the way; a unit is refused for a club, refused when this build does not know it, and never invented for a league made before it was asked. Three of those hold **reading a file back**: a good one describes itself in words a player can check, one written by a phone they no longer have is readable and says so rather than being treated as an error, and a bad one is refused as a sentence rather than by throwing |
| Scoring session | 45 tests — every PD-001 branch; engine → journal commit → screen, never another order; undo as a retraction, including of the visit that ended a match; a bust or a won leg holds the keypad until both players have seen it (PD-005); and under double-in the screen says who is not in and refuses a total that cannot open (PD-008); the checkout route shown is the one derived for that number under the match's own out-rule, never a fixed one (PD-013); and a finished match is self-reported until both players have said so on the phone, disputed if either refuses, and back to self-reported if the result changes under an agreement (PD-011). Three on a **person's figures across their matches** (ADR-016), computed through the same honesty layer a single match's are: **checkout percentage is refused across mixed out-rules** rather than pooled into a number that is a checkout percentage of nothing, and somebody with no matches gets dashes with reasons rather than zeroes. Six more on **ending a match short** (PD-016): the offer is two steps and Back returns to the choice rather than out, it is not offered before a dart is thrown or after the match is over, a retirement has a result for both players to confirm and an abandonment has none, an abandoned match reads as *No result* rather than *In progress*, the sentence that ends a match with no winner names nobody, and the darts are kept either way. Three on the **form figure** (PD-018): it is never called a rating, it is unavailable below three legs and says how many more are needed, and the match count names the ones that ended short |
| Design layer | 38 tests — every icon parses inside its own grid, every type role sits on the approved scale, an error state says what happened, what is safe and what to do, and an unknown stored appearance falls back to *System* rather than guessing. Four of them hold the type faces: every role resolves to one of the ten embedded faces, and weights the families lack land on their nearest face. Seven hold **a club's colour**: the contrast arithmetic itself, that the text on an accent is chosen **per colour** rather than always chalk, that **no colour in the whole cube** leaves a badge below the 3:1 floor, that carrying text ON a colour and being usable AS text are different questions, that every offered swatch is one the store will accept, and that the choice does not change with the phone's dark-mode setting. The Kotlin has stated that rule since clubs shipped; the Swift drew chalk on everything, which is about 1.4:1 on a club's yellow. Two hold **PD-024**, which lifts the scoring screen's text cap by reflowing instead: the screen changes shape at **exactly** the size text used to stop growing — so no size loses anything it had, and no size below the threshold gains a scrolling region under a scoring thumb — and a reflowing screen grows all the way to the reading ceiling rather than stopping somewhere short, because reflowing has to buy the player something |
| The opening, the app shell and the club screens | 97 tests — the opening's cuts are contiguous and it is no longer than its own reasons, its cues land on their beats, the tagline is left still long enough to read, Reduce Motion has no motion and no cues, the mark keeps its measured proportions as it becomes the wordmark's Ø, and the ring is set at full width along its whole length so no taper can come back; a match whose rows will not replay stays on the list saying so, rather than vanishing from it; seven hold **Home's second surface** (PD-026, PD-027) — an archived match is off Home and on the shelf and comes back from it, a delete is **refused while a fixture rests on the match** because that result's whole provenance is the citation and the refusal offers archiving instead, a delete nobody is relying on goes through and says what went with it, the warning names the match and what a delete cannot reach rather than saying *this cannot be undone*, the continue card offers the newest match still open and nothing when every one is done, the week counts the last seven days and tells *nothing yet* from *nothing lately*, and **the week's best leg is one player's leg rather than two players' added together** — a defect written and caught before it shipped, which would have reported every 15-visit leg as a 30-visit one on the first screen of the app, and one that a match this week whose rows will not replay is **counted and named** rather than quietly left out of the average — a figure over the readable half of a week is a different number, not a smaller sample; and the three club rules the screens obey (PD-009) — a stranger sees the front and nothing else, a member recorded as a minor or with no age given is listed only to an admin and the list says how many are hidden, and an announcement's reach is counted with its reasons before it is sent. Nine more hold the mapping between the stored book and the screens, which is where a guarantee quietly stops being kept: a club started on this phone is one its keeper is admin of, the member count is what is actually there, a minor is held and counted and reached by nothing, a fixture that is played will not move and the refusal is kept rather than dropped, a blank name is refused and says why, a member's figures are dashes with reasons rather than zeroes, and **a league describes itself by its teams and not by the people who run it** — the line that used to say "2 members" for a league of eight teams, which is the founder's complaint in miniature. One more holds that Home tells the three endings apart (PD-016): an abandoned match is finished AND is not a result, so it neither offers to resume nor wears a verification badge that would attest to a claim nobody made. Five hold who may have a picture (PD-014) and who is told why not: the picker asks `ImagePolicy` rather than keeping its own copy of the rule, so it can never offer what the book refuses; a minor's refusal and an unrecorded age's are different sentences because they are different facts and only one of them can change; and renaming, recolouring, badging or deleting a club is an admin's, held separately from the roster so the two move on purpose rather than by sharing a name. Thirteen hold that a club, a league and a tournament are three different things (PD-019, PD-020, PD-021): a league table is the arithmetic of its results and is derived rather than stored, so it cannot disagree with the fixtures under it; a fixture with no result counts for nothing rather than as a nil-nil, and a played one that nobody has entered is surfaced rather than swallowed; what a win is worth belongs to the league, so the same results under different points give different tables; the ordering is **total**, so two teams level on everything come out the same way twice; every row says how much of it came from a match scored in THRØ rather than from somebody's word, and **both count while neither is disguised as the other**; a result for a team the league does not have is dropped rather than counted into somebody else's row; each shape counts its own matches and a knockout's byes are the gap to the next power of two, proved by the identity that field plus byes is a power of two for every field to 64; only a round robin has a table, because drawing a knockout one would be drawing it a league; the three are counted in their own units — eight teams is not three members; and three more on **what a result's numbers mean** (PD-022, PD-023) — a unit says itself correctly for one as for many, it is open until the first result and settled after it, and the refusal shown to somebody with no recorded age names where a picture does come from rather than leaving it open. Ten hold **the knockout draw** (PD-021), which is the kind of thing that is either right or plausibly wrong: the seed order is a permutation whose round-one pairs all sum to the bracket size — so the top seed meets the bottom one — and the top two seeds are never in the same half, asserted for every bracket to 256; a field is fitted into the **next** power of two and the gap is the byes, which go to the entrants who went in first because THRØ has no rating to seed on; **a bye advances somebody and is not a win**, has no fixture and appears in no result; a whole eight-entrant tournament is played through and the bottom seed comes out of it; an undrawn round holds *winner of round 1 match 2* rather than a blank; a match already drawn is not offered again, so a second tap cannot make a second fixture for one slot; **a knockout match cannot end level** — the result screen takes a draw because a league fixture may be one, so the tournament names it as a problem and advances nobody; only a knockout is a bracket; and the last three rounds are called what people call them. One more holds that a page's top bar is offered only the actions its viewer may take — the bar itself is a layout and is held by `tools/check_screen_bars.py` instead, because four pages hand-rolled the same bar and all four put the back button off the edge of the phone. Ten more hold **double elimination**, whose losers' bracket is the part that looks right and is not: the losers' side has two rounds for every winners' round after the first; the match count is the one the arithmetic demands and is the same number the page puts on the screen, computed two different ways; **a whole tournament is played out and every entrant but the champion is checked to have lost exactly twice**, which is the property the format is defined by; the drop-in is reversed so nobody is put straight back against the player who has just knocked them out; an unplayed winners' match produces a *loser who is coming* rather than a bye, because reading the first as the second would draw a whole losers' round as walkovers; a bye drops nobody; **the losers' side has to win the final twice** and the winners' side once; and two entrants, who have no losers' side to drop into at all, still resolve. Ten more hold **groups then knockout**: entrants are dealt **snake-wise** so one group does not collect all the strength, every entrant is in exactly one group and the groups differ in size by at most one for every field to 16 over one to six groups, a group is a round robin in which everybody meets everybody once, **the knockout is not drawn until every group has finished** because a bracket built from half-played tables shows people through who are not, and — the assertion the seeding exists for — **nobody is drawn against their own group in the first round**, checked over all fifteen setups from two to six groups and one to three through. Two of those fifteen need the repair step: three groups with two through, and five with three, both pair a group winner with their own runner-up without it, and a test names them so removing the repair says which cases break. And nothing is defaulted — a tournament that has not been told how many groups it has says so rather than picking |
| iOS app | Builds for the iOS simulator on every push that touches it. Run on the founder's phone three times (2026-09-05 / 06), setup to result, each run's findings fixed and confirmed on the next; the opening was watched there on six further occasions, once for each of its first six versions (see the runbook, and PD-007's amendments). The seventh opening has not yet been on a phone. Carries the founder's mark as icon and launch screen and embeds the two type families under the SIL Open Font License (PD-006); `apps/ios/check_fonts.py` holds the fonts, licences and assets to the code on every push |

**Nothing here is production ready**, and no claim of security, offline reliability or rating
validity is made anywhere in this repository. There is an iOS client that scores a match between two people on
one phone and keeps it there — built and tested on CI and run on the founder's phone ([`docs/runbooks/CLIENT_IOS.md`](docs/runbooks/CLIENT_IOS.md)); a TestFlight workflow can put a build on the phone from the phone once the founder's App Store Connect key exists as repository secrets, and has not yet been run against one ([`docs/runbooks/TESTFLIGHT.md`](docs/runbooks/TESTFLIGHT.md)).
It talks to nothing: there is no product API and no deployment — the command path is a tested handler, not a running service. The one thing that does speak HTTP is the playtest harness described below, which runs on a laptop, authenticates nobody, and is not the product.
Claims are made only where evidence exists — see [`FOUNDATION_ACCEPTANCE.md`](FOUNDATION_ACCEPTANCE.md), and [`docs/CHANGE_RECORD.md`](docs/CHANGE_RECORD.md) for the full account of what was decided, what was verified, and every defect found on the way — including the ones that were mine.

**Two decisions are recorded as taken on delegated authority** ([`docs/product/DECISIONS.md`](docs/product/DECISIONS.md)),
each with its reversal path. Two remain open and need design work only the founder can commission:
the authentication surface, and participant result confirmation — without which nothing outside an
organised competition can be rated.

## Repository layout

```
packages/
  domain-spec/    Rule tables and the conformance corpus, derived from the dartboard
  engine/         The deterministic scoring engine (Kotlin, zero dependencies)
  engine-swift/   The same engine in Swift — ADR-002's spike, same corpus
  durability-probe/  Measures the cost of ADR-006's durability rule, on device
  statistics/     Figures that say when they cannot be computed honestly
  statistics-swift/  The same figures in Swift, the same twenty tests
  client-ios/     The iOS client as packages: ThroDesign, ThroJournal, ThroPlay, ThroApp
  competition/    Bracket structure — byes, rounds, walkovers
  organisation/   Clubs, leagues and tournaments: membership, branding that cannot break the app,
                  announcements that cannot reach a child before the question is answered
  trust/          Provenance, derived verification, rating eligibility, reconciliation
  authz/          Relationship-based authorization, and age as a dimension
  rating/         Rating as a versioned replayable projection
  design-tokens/  One token source generating Swift, Kotlin and CSS
apps/
  ios/            The Xcode app target — a few lines that mount ThroApp, plus the icon, launch screen and embedded fonts
services/
  api/            Migrations, the command path, and the playtest harness
docs/
  adr/            15 architecture decision records
  architecture/   Conformance corpus spec, latency budgets
  design/         Design authority — provenance, inventory, contrast matrix,
                  token health, what the system does not specify
    extracted/    Token layer, 61 components, 33 participant + 9 organiser screens
  product/        Glossary, decisions taken, decisions open, rating research harness
  runbooks/       Durability measurement and kill test; running the iOS client
FOUNDATION_ACCEPTANCE.md   Gate 0 report
```

## Running the checks

```bash
python3 packages/domain-spec/generate.py --full && python3 packages/domain-spec/validate.py
gradle -p packages/engine check
gradle -p packages/statistics test
gradle -p packages/competition test
gradle -p packages/trust test
swift test --package-path packages/engine-swift   # needs a Swift toolchain
swift test --package-path packages/statistics-swift
swift test --package-path packages/client-ios      # macOS: design, journal and scoring-session tests
xcodebuild -project apps/ios/ThroDarts.xcodeproj -scheme ThroDarts \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
gradle -p packages/authz test
gradle -p packages/rating test
python3 packages/design-tokens/build.py --check
python3 docs/design/audit_components.py --check

# these need a PostgreSQL 16; set PGHOST, and PGPORT/PGUSER/PGDATABASE if not the defaults
export PGHOST=localhost
bash services/api/test/schema_properties.sh
gradle -p services/api test
```

The database-backed checks skip cleanly and say so when `PGHOST` is unset, rather than
passing silently.

## Playing a match

There is a playtest harness — the real engine and the real command path behind a browser,
so the competitive core can be played before the clients exist. It is **not the product**:
online only, no accounts, no rating, and it says so at the top of every screen.

```bash
PGHOST=localhost gradle -p services/api run
```

Then open `http://localhost:8080`. Enter a visit total the way a chalker would; the app asks
for darts at a double whenever the player **began** the visit on a finish, whether or not they
took it, and additionally for darts used on the visit that wins a leg. Leaving a prompt blank
records *unknown*, which is a different fact from zero — **Stats** in the header then shows the
figure as a range instead of a number.

## Design authority

The approved THRØ Design System is the visual and interaction authority for this build.
It is committed under `docs/design/extracted/` with a full provenance record in
[`docs/design/DESIGN_SOURCE_PROVENANCE.md`](docs/design/DESIGN_SOURCE_PROVENANCE.md).

**Read the design source before implementing any significant screen.** Do not implement
from memory, from screenshots, or from design instinct. Where a component and a design
token disagree, the token wins.

## Source precedence

A lower source may never silently override a higher one:

1. Explicit current founder decisions
2. Approved production decision / authority register
3. Approved THRØ Claude Design System
4. Current THRØ product / domain specifications
5. Founding dossier
6. Approved architectural decisions
7. Reference implementations / prototype code
8. Sample data

Sample player names, ratings, band labels and statistics inside the design export are
rank 8. They are fixtures and must never become product truth by implementation
convenience.

## Non-negotiables

These constraints shape the architecture and are not open to convenience:

- **THRØ never invents dart-level evidence.** A visit total of 100 does not tell you which
  three darts were thrown. Visit totals and dart-level evidence are distinct in domain,
  storage, API and UI.
- **Scoring is deterministic and shared.** The scoring engine is independent of UI,
  network and database, and must produce identical results on iOS, Android and server.
- **Offline-first is not a banner.** Venues have poor signal. Scoring continues without a
  network, on a durable local event journal, and survives process death and device restart.
- **The server validates competitive evidence.** A client cannot simply assert a result.
- **Competitive evidence is append-oriented and auditable.** Corrections create history;
  they never overwrite it.
- **Rating, Form, Rank and Confidence are four separate concepts** — in domain, API,
  storage and UI. The rating model is not yet decided and will not be chosen by
  implementation convenience.
- **Money is never floating point. Timestamps always carry timezone context.**

## Voice

THRØ speaks as a competition official: calm, specific, factual, British English. No emoji
in product UI. No hype. A player at any level is told where they are and what would help —
never that they are bad.

## What is enforced, and where

The competitive properties are not conventions. Each one is asserted by something that fails when it
is removed.

| Property | Enforced by |
|---|---|
| A visit total can be achieved with three darts | Engine, against a corpus derived from the dartboard |
| Two devices may both author one match | `UNIQUE (match_id, device_id, device_seq)` |
| Evidence is never edited or deleted | Append-only grants, including on tables added by later migrations |
| Evidence exists only for a real match | Foreign key to the match aggregate |
| Who is playing cannot be rewritten | No application role holds `UPDATE` on `evidence.match` |
| A module appends only to streams it owns | Trigger mapping each event type to its owning role |
| Authority is recorded, never used to destroy evidence | `authority` column; a revoked scorer's visit still writes |
| A revocation cannot be undone | Trigger on `trust.scoring_grant` and `identity.device` |
| An official cannot correct their own match | `Rule.Except` in the one decision point, before any handler |
| Every decision is on the record | Hash chain computed by the database, not the application |
| The audit log cannot be read by its writers | `REVOKE SELECT` from every appending role |
| One player's word never moves a rating | `EligibilityPolicy.minimumAttestation` (PD-002) |
| No unvalidated rating model can be published | `Publication.check`, plus a singleton table |
| A statistic that cannot be computed says so | `Basis.EXACT` / `BOUNDED` / `UNAVAILABLE` |
| Personal data lives in one place | `identity` schema; match, trust and rating cannot read it |
| Age is available at every decision | A parameter of `Authorizer.check`, not a lookup inside it |
| A visit is durable before it is shown | `MatchSession.submit`: engine decides, journal commits, then the state changes |
| The journal runs only under the configuration that was measured | `Journal.verifyInForce` reads every pragma back on open and refuses anything else |
| Scoring has no compile-time path to a network | The client package graph has no network target to depend on |
| A mis-keyed visit is corrected, never edited | A retraction row in the append-only journal supersedes it (PD-004); replay skips what it strikes and the struck row stays |
| Nothing scores until a player opens | `MatchState.opened`, per player and per leg; a non-zero total no opening sequence can make is refused under its own reason (PD-008) |
| A rule table's floor is the rule's own | The checkout set's minimum comes from the spec, not the constant 2 — a single 1 finishes a straight-out leg, and both engines used to bust it |

## What is deliberately not decided here

`docs/product/OPEN_DECISIONS.md` is the register. The two that shape the most code:

- **OD-001 — the rating model.** No model in this repository claims to be validated, and a test
  fails if one ever does. Every player is provisional and nothing is published.
- **OD-010 — safeguarding obligations.** The age *dimension* exists at every decision; no action
  carries an age requirement, because the thresholds are a legal question this repository does not
  answer. It now has a second edge: a club's announcements reach no member recorded as a minor, or
  whose age is not established, until it is answered — enforced, not documented.
- **OD-019 — clubs and leagues.** Three of the four decisions raised here came back the same day as
  **PD-009** (a public front and a private inside; announcements only; the official's fixture list).
  This one did not: what happens to an image somebody uploads, which is what gates logo and avatar
  upload. Until it is answered a club's identity is its name, its kind and its accent, and its badge
  is drawn from initials rather than a file.
- **OD-020 — Apple Watch.** Blocked on a measurement rather than a decision: run
  `packages/durability-probe` on a real watch and the number chooses between a glance-only watch and
  one that scores. The probe can now be pointed at watchOS; nobody has a watch to point it at.
