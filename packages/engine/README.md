# THRØ scoring engine

The deterministic core. One pure function — `(state, command) -> outcome` — that must return the
same result on iOS, Android and server validation, because that is what allows a client to score
with no network and the server to revalidate the claim afterwards.

```bash
gradle check          # conformance corpus + property tests + determinism guard
```

## What it is not allowed to do

The build fails if the main sources reach for a **clock**, **randomness**, **floating point** or
**I/O**. Those are the four ways two platforms could disagree about a match. Anything
non-deterministic — who threw first, what time it is — arrives as an input.

There is **no dependency beyond the Kotlin standard library**, and no statistic is computed here:
averages and checkout rates belong to a separate layer, which is why no floating point is needed.

## How it is verified

| | |
|---|---|
| **Conformance** | 58 cases, 353 commands from `packages/domain-spec/vectors` |
| **Exhaustive properties** | 71,261 scored and 14,577 bust transitions, every reachable remaining against every achievable visit total |
| **Determinism guard** | build-time check on the main sources |

The two independent implementations — the Python generator that derives the corpus from the
dartboard, and this engine — agree on those counts exactly. That agreement is the point: a single
implementation generating its own expected values proves nothing.

The exhaustive tests exist because the bust condition implementations most often drop — a visit
reaching exactly zero on a number the out-rule cannot finish — accounts for **eight cases in
eighty-six thousand**. A hand-written test would never stumble on it. This one asserts the exact
set: 159, 162, 165, 168, 171, 174, 177, 180.

## Rule data is generated, never hand-written

`RuleTables.kt` is emitted by `packages/domain-spec/generate.py` from the dartboard segment set, and
CI fails if the committed copy is stale. Only the ~200-line state machine is written by hand per
platform, which is what keeps the shared-code decision in
[ADR-002](../../docs/adr/ADR-002-shared-scoring-domain.md) genuinely open.
