# THRØ — Scoring Conformance Corpus

The scoring engine must produce identical results on iOS, Android and server validation. This
corpus — not any shared code — is the contract that guarantees it.

It is built **before the first engine line**, for two reasons. Retrofitting is technically possible,
but every match recorded beforehand has unknown provenance, and in an evidence product
unknown-provenance history is poison. And the corpus is a prerequisite of *every* shared-domain
strategy, so building it is never wasted regardless of which is chosen later.

## Why this domain can be tested to near-proof

The X01 transition table is closed and small: remaining (0–501) × visit total (0–180) is roughly 91
thousand cases. It is exhaustively enumerable. That is unusual and it changes the strategy — the
core arithmetic can be proven by enumeration, leaving only *sequence-level* rules to be covered by
hand-written cases.

Those sequence-level rules are exactly where implementations diverge: throw order after a set
boundary, undo-after-checkout, correcting a visit three legs back, deciding-leg rules. In a product
whose premise is trustworthy evidence, two devices disagreeing about throw order is a **player-facing
integrity failure**, not merely a bug.

## Layout

```
conformance/
  spec/x01-rules.md             normative prose, semver'd
  spec/rule-tables.json         generated into Swift / Kotlin / server source
  vectors/v1/manifest.json      specVersion, generator commit, SHA-256 per file
  vectors/v1/core-transitions.jsonl    exhaustive, generated
  vectors/v1/bust-rules.jsonl
  vectors/v1/leg-rotation.jsonl
  vectors/v1/sets-and-legs.jsonl
  vectors/v1/undo-and-correction.jsonl
  vectors/v1/idempotency.jsonl
  vectors/v1/adversarial.jsonl         hand-written, append-only
```

JSONL rather than one array, so a failing line number maps directly to a case and diffs stay
reviewable. JSON rather than YAML, to avoid float and boolean-coercion ambiguity.

## Case shape

```json
{
  "id": "bust.doubleout.remainder-one",
  "specVersion": "1.0.0",
  "description": "Double-out: leaving 1 busts and restores the pre-visit score.",
  "setup": {
    "format": { "game": "X01", "startingScore": 501, "inRule": "straight",
                "outRule": "double", "structure": {"kind":"legs","firstTo":5},
                "throwFirst": "A", "alternateStart": "perLeg" },
    "players": [{"id":"A"},{"id":"B"}]
  },
  "commands": [
    {"seq":1,"id":"01J8…","type":"RecordVisit","player":"A","visitTotal":100,"dartsUsed":3},
    {"seq":2,"id":"01J8…","type":"RecordVisit","player":"A","visitTotal":400,"dartsUsed":3}
  ],
  "expect": {
    "outcomes": [
      {"seq":1,"result":"accepted","effect":"scored"},
      {"seq":2,"result":"accepted","effect":"bust","reason":"REMAINDER_ONE"}
    ],
    "state": { "matchState":"in_progress","currentLeg":1,"throwerId":"B",
               "remaining":{"A":401,"B":501},"legsWon":{"A":0,"B":0},"winnerId":null }
  }
}
```

Load-bearing decisions in that shape:

- **Per-command outcomes are asserted, not just final state.** Rejections are part of the contract —
  the approved UI renders them ("Bust. Score restored to 186. Wilson to throw.").
- **`reason` is a closed, versioned vocabulary** shared by engine, API and UI copy:
  `REMAINDER_ONE`, `BELOW_ZERO`, `NOT_CHECKOUT_POSSIBLE`, `IMPOSSIBLE_VISIT_TOTAL`, `NOT_YOUR_TURN`,
  `MATCH_COMPLETE`, `DUPLICATE_COMMAND`, `DARTS_USED_INVALID`.
- **Every command carries a client-generated ULID**, so idempotency is a first-class testable
  property: replaying a command id is a no-op returning the identical outcome.
- **No floating point anywhere.** Averages and percentages are not engine output; they belong to a
  separately tested statistics layer.
- **Comparison is on canonical serialisation** — sorted keys, integers only, string-compared. This
  catches type-width and coercion differences that a structural comparison hides.

## Rules the corpus must cover

These are the rules naive implementations get wrong. All values below were computed exhaustively
over the real dartboard segment set, not recalled.

**Impossible visit totals** — achievable totals are 0–180 *except* 163, 166, 169, 172, 173, 175,
176, 178, 179. Validating `0 ≤ v ≤ 180` is wrong.

**Checkout limits** — double-out maximum is 170, with 159, 162, 163, 165, 166, 168 and 169 not
finishable at or below it. **Master-out maximum is 180, not 170** — naive code copies the double-out
constant.

**Bust, in order:** remaining − visit < 0; or remaining − visit = 1 under double-out; or
remaining − visit = 0 where remaining is not finishable. The third is the one that gets dropped;
under double-out the exact set where an exact score busts is {159, 162, 165, 168, 171, 174, 177, 180}.

**The revert rule** — remaining returns to the pre-visit total, and the busted visit is **recorded**
with a zero contribution, not discarded. It consumed three darts, so it correctly enters the average
denominator. Implementations that drop bust visits inflate averages.

**Structural invariants worth asserting:** remaining = 1 is unreachable at the start of a visit under
double-out; bust is impossible at remaining ≥ 182; minimum darts to finish are 6 / 9 / 12 for
301 / 501 / 701; there are exactly 21 one-dart finishes ({2, 4 … 40} ∪ {50}).

**Double-in** — darts before the opening double score nothing, but the opening double *and every
later dart in that visit* do score. The naive bug voids the whole visit. This is not derivable from a
bare visit total and needs one extra bit (an `opened` flag), so treat it as a format capability gate.

**Throw order** — first throw of the match is an *input event*, never generated inside the engine.
Alternation per leg means the leg-1 starter also starts the decider in a best-of-9; many competitions
bull-up for the decider instead. Set-boundary behaviour must be explicit.

## Governance

- `specVersion` is semver; the vectors directory is versioned.
- **Generated files are never hand-edited.** `adversarial.jsonl` is the only hand-written file and is
  append-only.
- A rule change is **one pull request** containing the spec edit, the rule-table edit, the version
  bump, the regeneration, and all implementations. It cannot be split.
- **CI runs the corpus against every platform as a required check.** The manifest hash prevents a
  platform silently pinning a stale corpus.
- **Every bug that reaches a build becomes an adversarial vector before its fix merges.** No
  exceptions — this is what stops "make the vector pass" degrading into "edit the vector".

## Production drift detection

Every sync command carries the client's computed outcome and engine version. The server recomputes
and compares. A mismatch means the server outcome wins, the event is still appended, and an
engine-divergence alert fires with both outcomes and both versions. This turns the residual
determinism risk from an unbounded unknown into a monitored metric, and it costs almost nothing.
