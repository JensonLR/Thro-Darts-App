# THRØ — Rating Research Laboratory

The Gate 0 and Gate 1 deliverable is **the laboratory, not the algorithm**: a deterministic offline
evaluation service that consumes a stable evidence projection, runs candidate models, and emits a
comparable metric report.

It must be buildable and runnable **before any rating is published**. A laboratory promised for later
is a laboratory that never gets built, and by the time anyone wants it the schema is already wrong.

## Interface every candidate implements

```
fit(evidence_stream)            -> state
predict(a, b, context)          -> P(a wins leg), P(a wins match | format)
project(state)                  -> display_integer
uncertainty(state)              -> dispersion
```

The `project` step matters: the approved design renders a single unitless integer, while candidate
models carry rating+deviation+volatility, or mean and sigma, or a full posterior. **Build the display
projection layer at foundation** — it is what makes the model choice reversible.

## Candidates

1. **Naive baselines — mandatory.** Always-0.5; global base rate; win percentage; most-recent-result;
   and a **3-dart-average logistic**. Implement precisely the thing that is forbidden *as the rating*,
   so it can be proven inferior — or so we discover it is not. A candidate that cannot beat these on
   held-out log-loss is not a candidate.
2. **Elo family** — fixed K, rating-dependent K, margin-aware, per-competition K.
3. **Glicko and Glicko-2** — the natural fit for the inactivity semantics the design requires.
4. **TrueSkill-style factor graph** — needed if pairs or team fixtures ever contribute.
5. **Bayesian Bradley-Terry with player random effects**, fitted in batch. Not deployable online, but
   the best available estimate of "true" strength against which the online models are judged.
6. **Time-aware** — state-space skill with explicit process noise; time-weighted Bradley-Terry;
   whole-history rating.
7. **Darts-specific hybrids** — leg-level Bradley-Terry composed to a match probability under the
   format. This is the format-invariant formulation and the strongest structural candidate.

## Prediction targets

- **T1 — P(match win)** given format. The primary competitive anchor.
- **T2 — P(leg win)**. The format-invariant unit, and the strongest test of whether a model
  understands darts rather than match length.
- **T3 — leg differential distribution**, for margin-aware models.
- **T4 — visit-total distribution**, only for models claiming performance sensitivity.

## Metrics

**Discrimination:** out-of-sample log-loss (primary); Brier score and Brier skill score against the
base rate; AUC; Kendall's tau and Spearman's rho against the batch reference.

**Calibration** — the family that decides fitness for seeding and projections: reliability diagrams
with both equal-width and equal-frequency bins, plotted rather than merely scored; expected and
maximum calibration error with bootstrap intervals; calibration slope and intercept from a logistic
recalibration; and **sharpness reported alongside** — a perfectly calibrated but unsharp model is
useless for seeding.

**Calibration must be reported stratified** by format, competition tier, rating decile, confidence
level, provenance level and region. Aggregate calibration hides exactly the failures that matter.

**Uncertainty quality:** PIT histograms and coverage tests; CRPS on leg differential; and the
**uncertainty–error correlation** — if higher claimed confidence does not mean lower realised error,
the Confidence surface is decoration and must not ship.

## Behavioural gates — pass/fail, not scores

- **Cold start** — matches-versus-error curve; where does the provisional/established boundary fall?
- **Small sample** — any model publishing a confident number at two matches **fails**.
- **Upset handling** — no single result may move a rating beyond a stated cap; the loss-that-raises-
  rating case (which the design actually shows) must be principled, not an artefact.
- **Format sensitivity** — same skill pair, best-of-5 versus best-of-11: does the prediction move in
  the right direction and magnitude?
- **Cross-pool** — measure **connectivity of the comparison graph**: is it one component, what are
  the bridge edges, what is its algebraic connectivity? Simulate two weakly-connected regions with a
  true skill offset and measure how many bridge matches recover it. **Any model that silently assigns
  comparable numbers across disconnected components is disqualified** — that is the failure that makes
  a national rank meaningless.
- **Non-stationarity** — injected step change and gradual drift; measure lag and overshoot.
- **Stability** — how much does a published integer move on a day with no matches? State a churn budget.
- **Gaming resistance** — the adversarial suite, scored as rating gain per unit of adversarial effort.

## Data interfaces

- **`RatingEvidenceView`** — a stable, versioned, model-agnostic projection over the evidence log,
  and the *only* thing a candidate may read. One row per eligible result carrying full competitive
  context, provenance summary, outcome type, both participants, ordered leg records, and visit-level
  data with **explicit nullability**.
- **Historical ingest adapter** — real league and tournament archives mapped into the same view with
  provenance `imported`, without touching the live domain. Without this the harness has nothing to eat.
- **Deterministic replay CLI** — byte-identical output for a given model, version, range and seed.
- **Frozen evaluation datasets** with **temporally forward splits only**. Random k-fold leaks future
  information through repeated opponents and is invalid here.

## Why synthetic simulation can never approve a model

It can falsify — a model that fails in an easy, well-specified world is dead — and it can stress-test
the adversarial suite. It cannot approve, for five reasons:

1. **Circularity.** The simulator encodes assumptions about how strength converts to outcomes; a model
   from the same family validates itself. That tests implementation, not truth.
2. **The selection graph is the hardest real phenomenon and the least simulable.** Who plays whom is
   profoundly non-random — geography, league membership, seeding, entry cost, travel, and
   self-selection into fields "matched to your level", *which THRØ itself will influence*. This is
   precisely the mechanism that breaks cross-pool comparability.
3. **Reporting bias is endogenous** — which results get submitted, confirmed and disputed depends on
   the result.
4. **Real effects nobody models correctly a priori** — throw order, board and venue effects,
   deciding-leg shifts, fatigue across a tournament day, league versus knockout psychology.
5. **Non-independence** — league players meet the same opponent repeatedly; outcomes within an event
   correlate through fatigue and momentum.

**Approval requires**, in order: held-out real historical data from at least two structurally
different pools; a **prospective shadow period** in which candidates run live against real results
while nothing is published; and documented calibration within stated tolerances on that prospective
data, stratified as above. Anything less and the claim "rating validated" is prohibited.

## Explanations

Explanations are generated **at rating time and stored**, never reconstructed on read — ratings drift,
and a regenerated explanation would quote a past opponent at their present rating. Persist alongside
each computed value: the causing evidence, **both participants' published ratings and confidence at
that instant**, competition, round, format, outcome, predicted probability, realised outcome, the
eligibility decision, the delta, and the model version.

Generate from recorded facts and a **bounded phrase vocabulary** — never free generation, never model
internals. The target register, taken from the approved design: *"Defeated Alex Wilson, rated 1,903."*
/ *"Above-baseline competitive result against a stronger opponent."* Forbidden: K-factors, residuals,
sigma, deviation, volatility, logits, priors, weights, "the algorithm".

Coverage must include the awkward cases: a **loss that raised** the rating; a win that barely moved
it; movement with **no match** (recomputation, correction, decay, eligibility change); and **no
movement at all** because the result is not yet eligible.

**Ledger invariant:** the per-match ledger must reconcile exactly to the net change over the same
period. Any non-match adjustment appears as its own visible ledger line and is never silently absorbed.
