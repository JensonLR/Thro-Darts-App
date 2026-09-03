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
**Status:** OPEN · **Impact:** competitive integrity, statistics honesty, product

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
**Status:** OPEN · **Impact:** legal, design fidelity, performance

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
