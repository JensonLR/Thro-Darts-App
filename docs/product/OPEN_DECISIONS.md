# THRØ — Open Decisions Register

Decisions recorded here are **not yet made**. The purpose of this register is to stop them
being made accidentally, by implementation convenience, in a screen or a migration.

If you are implementing and you find yourself needing one of these answered, do not pick a
value and move on. Either keep the decision out of the domain (make it configurable,
optional, or deferred), or escalate it.

**Status key:** `OPEN` — no decision. `ASSUMED` — a working assumption is in use and is
recorded here so it can be revisited. `DECIDED` — resolved; move to the decision register
or an ADR.

---

## OD-001 — Final THRØ Rating model
**Status:** OPEN · **Impact:** product, competitive integrity, credibility

The rating model is not decided and is explicitly not automatically Elo, and never the
3-dart average. Candidates must be evaluated in a research harness against predictive
accuracy, calibration, cold start, uncertainty quality, gaming resistance and small-sample
behaviour. Match outcome remains the primary competitive anchor unless empirical evidence
justifies otherwise.

**Must not be decided by:** shipping a placeholder rating to fill the UI.
**Blocked until:** the Rating Research Laboratory produces evidence (Gate 8).
**Interim position:** any rating produced before that gate is internal and non-public.

## OD-002 — Competitive band taxonomy
**Status:** OPEN · **Impact:** product, brand, player dignity

The design supports an optional band label (`RatingHero` has an optional `band` prop). The
sample data uses "Elite Amateur", which is fixture content at the lowest source precedence
and is **not** an approved taxonomy.

**Resolved for now by:** the band prop being optional — implementation can proceed without
naming bands. Do not introduce a band enum into the domain model until the taxonomy is
approved.

## OD-003 — Final Form representation
**Status:** OPEN · **Impact:** product, domain

The design shows Form as a separate number alongside Rating (`form` prop on `RatingHero`)
and as a recent results sequence (`FormIndicator` with W/L results). Whether Form is
ultimately a rating-like scalar, a windowed performance measure, or both, is undecided.

**Must not be decided by:** hardwiring a formula into a core aggregate. Keep Form computed
in a dedicated module with its own contract.

## OD-004 — Rating establishment threshold
**Status:** OPEN · **Impact:** product, rating credibility

`Confidence` defaults to `required = 10` matches. This is a **component default, not an
approved threshold**. The provisional → established transition, and how uncertainty decays
with inactivity, are part of OD-001.

## OD-005 — Dart-level evidence capture requirements
**Status:** DECIDED — see PD-001 · **Impact:** competitive integrity, statistics honesty, product

**Resolved by the founder.** The capture rule is: ask for darts at a double on every visit that
*began* on a checkout number, whether or not it ended in one, and additionally for darts used on a
visit that wins a leg. An earlier reading asked only on a successful checkout, which would have
recorded every hit and no miss — biasing checkout percentage upward rather than merely leaving it
uncomputable. The original text of this decision is kept below for the record.

The approved scoring flow captures **visit totals only**. This is correct and deliberate:
THRØ must never invent dart-level evidence. The open question is which *additional
optional* capture, if any, is required for a match to support the statistics the product
displays — in particular darts-used-to-finish and doubles-attempted.

This is the sharpest open decision in the foundation because it determines which
statistics THRØ can honestly show. See the Gate 0 acceptance report.

**Must not be decided by:** inferring darts from visit totals. That is forbidden.

## OD-006 — Quarantine as a user-visible state
**Status:** OPEN · **Impact:** trust, design fidelity

The trust model requires a `quarantined` state for suspicious evidence. The approved
`VerificationState` component implements eight states and does **not** include it. The
domain needs quarantine regardless; whether and how it is surfaced to players (as opposed
to organisers and reviewers) is a design decision that the approved system has not yet made.

**Must not be decided by:** silently adding a ninth visual state. Follow the design
deviation process: identify the rule, state the problem, propose the smallest compliant
change, document it.

## OD-007 — Bronze semantic scope
**Status:** OPEN · **Impact:** brand

Bronze (`#A8753B`) is rare and reserved for enduring achievements. The precise set of
achievements that earn it is not enumerated.

**Must not be decided by:** using bronze for general emphasis or for any recurring state.

## OD-008 — Shadow commercial gating
**Status:** OPEN · **Impact:** monetisation, product

Whether Shadow is a premium capability, and at what boundary, is undecided. Shadow is fully
designed (4 screens) but sits behind the evidence requirement — it may only be built from
sufficient legitimate player evidence.

## OD-009 — Payments, platform rules and fee structure
**Status:** OPEN · **Impact:** legal, economics, store compliance

Entry fee, platform fee, refunds, organiser payouts and tax treatment are undecided, and
Apple/Google payment policy for real-world event entry must be researched against current
policy at implementation time rather than assumed.

**Must not be decided by:** guessing store policy. Separate entry fee, platform fee,
refund state, payout state, payment state and registration state in the model regardless.

## OD-010 — Safeguarding obligations
**Status:** OPEN · **Impact:** legal, safety, architecture

Darts includes minors. The specific jurisdictional obligations (age assurance, visibility
of minors, adult–minor contact, broadcast of minors, parental consent, data rules) must be
researched against primary sources before launch. The architecture must support age-aware
behaviour from the start.

**Must not be decided by:** inventing a legal conclusion.

## OD-011 — Font licensing and packaging
**Status:** RESOLVED for iOS by PD-006 (2026-09-06); the founder's legal sign-off is the one open thread · **Impact:** legal, design fidelity, performance

**Resolved by:** both families are published under the SIL Open Font License, Version 1.1 — Archivo
by Omnibus-Type, IBM Plex by IBM — and the founder directed that the fonts be used. The iOS app embeds
ten unmodified static faces with each family's licence text beside them (`apps/ios/ThroDarts/Fonts`),
which is what the licence's conditions ask; PD-006 quotes them. Android has no client yet. This
register records the licence's text, not a legal conclusion; a final read by whoever signs for THRØ's
legal position is the founder's to arrange.

*As first recorded:*

Archivo and IBM Plex Sans Condensed are the approved families. The design kit loads them
from a CDN-derived bundle; the design system itself states production must embed the
binaries locally. Licence terms for embedding in shipped iOS and Android binaries must be
confirmed, and the referenced handoff document `handoff/TYPOGRAPHY_TOKENS.md` was not
available in this environment.

## OD-012 — Product naming and future rename risk
**Status:** ASSUMED · **Impact:** brand

The working product name remains THRØ and must not be changed during implementation. A
future rename has been discussed. Working assumption: keep the name centralised (branding
and copy constants) and out of business logic, so a rename stays manageable.

## OD-013 — Whether a retirement may inform a rating
**Status:** OPEN · **Impact:** rating credibility, player fairness

PD-002 settles the eligibility floor as `participant-confirmed` and says `outcome_type` must be
`played`. It does not name **`retired`**, which is the one genuinely arguable outcome: darts were
thrown and a real performance exists, but the match did not finish, so the sample is truncated in a
way that correlates with the very thing a rating measures — a player retiring while losing is not
the same event as one retiring while winning.

**Resolved for now by:** excluding it. `EligibilityPolicy.informing` defaults to `played` alone, so
the conservative reading is what ships. Admitting retirements is a policy value plus a rating
recomputation, which the architecture supports because rating is a replayable projection.

**Must not be decided by:** an implementation quietly adding `RETIRED` to the default policy because
it felt reasonable. That is how this register gets bypassed.

## OD-014 — Whether capture channel and attestation stay collapsed in the design enum
**Status:** ASSUMED · **Impact:** design fidelity, trust semantics

The approved `VerificationState` has eight labels, and two of them answer different questions:
`thro-recorded` describes **how the result was captured**, while `participant-confirmed` describes
**who attested to it**. A match scored live in THRØ by one player and never confirmed by the other
is `thro-recorded` under a naive reading, yet nobody has corroborated it.

**Working assumption:** the domain models the two axes separately (`CaptureChannel` and
`Attestation`) and *derives* the design's single label from them, so the approved surface is
unchanged while eligibility is decided on the axis that actually bears on it. Rating eligibility
reads attestation, never the label.

**Escalate if:** the design intends `thro-recorded` to imply corroboration, which would make it a
higher trust claim than the domain can support.

## OD-015 — What a client records on a visit that has not opened, under double-in
**Status: CLOSED, 2026-09-07 — decided by the founder as PD-008.**

The founder asked for double-in ("theres leagues & tournaments that are double in"), which forced
the capture rule this entry was waiting on. It is recorded in full as **PD-008** in
[`DECISIONS.md`](DECISIONS.md); in one line: *what a visit records while the player has not opened is
the score from the opening dart onward, and zero means they did not open.*

The reasoning that kept it open is worth keeping, because it is why the decision had to be the
founder's. The engine's unit is a visit, not a dart. Under double-in only the darts from the opening
one onward count, so a player who throws treble twenty, treble twenty, double ten while unopened
scores twenty, not one hundred and forty — and nothing in a visit total says which dart opened. The
answer had to come from how a scorer actually calls it, not from what an engine could infer.

What it cost is in PD-008 and stated there rather than here: a scorer who enters the whole visit
instead of what counted will be believed, because at visit granularity nothing can tell the
difference. All three in-rules are now scored; the engine refuses none of them.

## OD-016 — What a club, league or tournament may show, and to whom
**Status: CLOSED, 2026-09-07 — decided by the founder as PD-009.** **A public front, a private inside** — a club's name, badge, kind and published fixtures are public; members, results and announcements are members-only, and a member recorded as a minor is never listed to anyone but an admin.

The reasoning below is kept, because it is why the decision had to be theirs.

The founder asked for clubs and leagues to hold their own data and be visible in the app. Every
question below has been answered *provisionally and restrictively* in `packages/organisation`, and
each answer is a placeholder for yours, not a decision.

| Question | What the code does today | What it would mean to change it |
|---|---|---|
| May a non-member see a club's page? | **No.** `Permissions.may(null, …)` is false for every action, including VIEW. | A public club page is a discovery feature and probably what a league wants. It also makes the membership list a privacy decision rather than a members-only one. |
| May a member see the membership list? | **Yes** — `VIEW_MEMBERS` is a member right. | If juniors are listed, this is a safeguarding surface as well as a privacy one. |
| Who admits and removes members? | **Admins only.** An official may announce and manage fixtures, but not change who belongs. | Officials doing it is more convenient and gives more people the power to remove someone. |
| Can a person belong to many clubs? | Nothing prevents it; nothing depends on it. | A "home club" concept would change the profile and probably the rating. |

**Options, if it helps to choose from a shortlist:**

- **A — members only.** Nothing about a club is visible until you are in it. Safest, worst for
  discovery, and probably wrong for a league that wants to advertise a new season.
- **B — a public front, a private inside.** Name, badge, kind and *published* fixtures are public;
  members, results and announcements are not. This is what most sports club apps do.
- **C — the club decides, per field.** The most flexible and the most ways to get it wrong; it also
  means someone at every club has to understand the settings.

Engineering's reading: **B**, with the membership list members-only and juniors never listed to
anyone but an admin. But it is a privacy decision about other people's children and it is not
engineering's to take.

## OD-017 — Whether members may message each other, and what protects that
**Status: CLOSED, 2026-09-07 — decided by the founder as PD-009.** **Announcements only** — broadcast, from an official, with an author on the record. Member-to-member messaging is not built and is not to be built until the founder has taken safeguarding advice. The refusals in `packages/organisation` stay: nobody recorded as a minor, or whose age is not established, is reached until OD-010 is answered.

The reasoning below is kept, because it is why the decision had to be theirs.

The founder asked for the app to "become a hub for them to communicate with member and arrange
things". What is built is **announcements only**: broadcast, from an official or admin, to a
membership, with an author on the record and no private channel anywhere. And a member whose age is
MINOR *or UNKNOWN* receives nothing at all until OD-010 is answered — enforced in
`Announcements.deliver`, not documented and hoped for.

**Member-to-member messaging is not built, not stubbed, and not behind a flag.** It is absent,
because the controls it needs would determine its data model and building the model first would
prejudge them:

- Can an adult start a conversation with a member recorded as a minor? Under what consent?
- Is there moderation, and is it before or after the fact? Who does it — the club, or THRØ?
- How is a message reported, and who sees the report?
- How long is a message kept, and who can delete it — the sender, the club, or nobody?
- Does a club's own official have any privileged view of it? (If yes, say so to members. If no, say
  that too.)

**Must not be decided by:** engineering, and not by looking at what other apps do. Two of these are
legal questions in every jurisdiction THRØ would operate in, and the safeguarding regime for a
sports club with junior members is specific.

**The honest interim:** announcements cover the actual jobs a club secretary has — the fixture is
off, subs are due, the AGM is Tuesday. A club that needs a private word has a phone.

## OD-018 — How a fixture is agreed
**Status: CLOSED, 2026-09-07 — decided by the founder as PD-009.** **The official's list** — an official schedules, moves and cancels; agreeing a fixture happens off the app. Propose-and-accept is deferred, not refused.

The reasoning below is kept, because it is why the decision had to be theirs.

`Fixture` is deliberately thin: a date, two sides, a venue, and a state that says whether it is
still going ahead. It carries no result, because a result belongs to the match aggregate and its
provenance, and a fixture that could assert one would be a second, unverified place a score could
come from.

What is not modelled, because leagues genuinely differ:

- Does an official schedule fixtures, or do captains agree them between themselves?
- Who may postpone, and does the other side have to accept?
- Is there a deadline, and what happens when a fixture is never played — void, or awarded?
- Does a fixture need a marker, and is that a role?

**Options:** **A — the fixture list is the official's**, and everything else happens off the app
(simplest, matches most small leagues). **B — propose and accept**, with both sides on the record
(more work, and the record is worth having when a league is decided by a walkover). **C — a league
constitution**, configured per organisation (the most general and the most to get wrong).

Engineering's reading: **A first**, because it is what the model already supports and it is
reversible; **B** the moment a league asks for it.

## OD-019 — Logos, avatars, and what happens to an image somebody uploads
**Status:** OPEN · **Impact:** safeguarding, moderation, storage cost, legal

`AssetRef` is an opaque handle and this repository stores nothing and fetches nothing. That is
deliberate: the moment an image is accepted, questions follow that are not engineering's.

- Is an uploaded image checked before it is shown, and by what — a person, a service, or nothing?
- A profile picture of a junior member: who may see it? (This is OD-010 again, in a second place.)
- What happens to a club's badge when the club leaves, or to a photo when a person deletes their
  account? Deletion in the app, or deletion from storage, and how quickly?
- Who is responsible for a copyright claim on a club badge — the club, or THRØ?
- Are images resized and re-encoded on the way in? (Engineering's recommendation: yes, always, and
  strip every piece of metadata — a phone photo carries the place it was taken.)

**The one part that is engineering's and is done:** `packages/organisation` already guarantees that
whatever colour a club picks, the app stays readable — the text on an accent is chosen rather than
configured, and a sweep of the colour cube proves no choice falls below the contrast floor. The same
discipline has no equivalent for an image; a photograph cannot be made safe by arithmetic.

## OD-020 — Apple Watch: what it is for, and which of the three shapes THRØ can honestly build
**Status:** OPEN · **Impact:** product surface, durability, and one measurement that has not been taken

The founder asked to see the options. There are three, and **which of them is buildable is decided by
a rule this repository already keeps** rather than by taste:

> Every visit is committed to the journal **before** the screen updates (`MatchSession.submit`). If
> the commit fails, the screen says *Not saved, so not scored* and the state does not change.

That is ADR-006's rule, it is measured (P95 1.6 ms against a 20 ms budget on an iPhone 14 Pro Max),
and it is why the app can be trusted with a match. A watch either keeps it or breaks it, and the
three options are exactly the three ways that goes.

### A — A glance, and nothing more

The watch shows the match the phone is scoring: remaining, whose throw, legs, and the bust or won-leg
announcement PD-005 already defines. No input. A complication, and a view.

- **Keeps the rule trivially**, because nothing is recorded on the wrist.
- **Costs**: a watchOS target, a build in CI, and a `WatchConnectivity` session that is *allowed* to
  be late or lossy because nothing depends on it arriving.
- **Worth**: modest and real. The phone is usually on the shelf and the player is at the oche; a
  glance at the remaining without walking over is worth something. It is not what most people mean
  when they ask for a watch app.

### B — Scoring from the wrist, with the watch's own journal

The watch records visits. To keep the rule it needs **its own durable journal**, not a message to the
phone: `WatchConnectivity` is best-effort by design, so "the watch takes the entry and the phone
stores it" would show a score that is not yet saved — precisely what the rule exists to prevent.

- **The architecture is already most of the way there.** The engine is Swift and dependency-free; the
  journal is SQLite and so is watchOS; and the two-device reconciliation this needs is *already built
  and tested* (`packages/trust`), because a watch and a phone are two devices with their own streams
  — the same problem the offline model already solves.
- **The one thing missing is a measurement.** ADR-006's durability numbers were taken on a phone. A
  watch has a different chip, a different flash controller and a much tighter power budget, and
  `synchronous=FULL` with `fullfsync` may well cost more than 20 ms there. `packages/durability-probe`
  would have to be **run on a watch** before a line of the scoring UI is written, and the answer might
  be no — in which case the honest outcome is A, and knowing that is worth the probe.
- **The interface is the other risk.** A 45 mm screen cannot hold the export's keypad. The plausible
  shape is the Digital Crown for the total plus one large confirm, with the common totals as quick
  keys — and that is a **design commission** (B3), not an engineering choice.

### C — The watch as the second, corroborating device

The trust model's centre is that one player's word never moves a rating (PD-002), and that
corroboration comes from two independent devices. A watch on the opponent's wrist is a natural second
device: they confirm what they saw, from where they are standing, without holding a phone.

- **This is the option that is uniquely THRØ's** rather than a scoring app's. It is also the one that
  makes a rated match possible in a pub without two phones on the oche.
- **Blocked twice over**: it needs identity (**B4**) so the watch's confirmation is *someone's*, and
  it needs the sync path, which does not exist. Neither is close.

### Engineering's reading

**Run the probe first, then decide between A and B.** The measurement is a day, it is the only fact
that separates the two, and taking it before designing anything means the design is not thrown away.
**C waits on B4** and should be recorded as the destination rather than attempted early — the
reconciliation it needs is built, so nothing is lost by waiting.

**Must not be decided by:** an assumption that a watch behaves like a phone under `fullfsync`. That
is the whole question, and it is measurable rather than arguable.

