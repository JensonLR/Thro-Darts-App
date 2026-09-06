# thro-engine (Swift)

ADR-002's spike, and nothing more than the spike.

## What this is

ADR-002 **defers** the choice between three native scoring implementations and one shared Kotlin
Multiplatform core, and defines the experiment that settles it:

> **Scope.** Port the pure engine module to a second platform behind the conformance corpus, and run
> the corpus on both. Nothing else — no UI, no persistence, no networking.
> **Exit condition.** The corpus passes identically on both platforms.

So this package contains the engine and a corpus runner. It deliberately contains no UI, no
storage and no networking, because the spike that tests extra things tests nothing precisely.

**It is explicitly not a measurement of build times or debugger ergonomics.** Those were the grounds
on which the mobile review already rejected a shared core, so measuring them again decides nothing.

## The rule tables are generated, not ported

`RuleTables.swift` is emitted by `packages/domain-spec/generate.py` from the same enumeration over
the dartboard that produces the Kotlin tables, and CI fails if the committed copy is stale. A
hand-copied checkout set is a divergence waiting to happen, and it would be one nobody notices until
a player is told they cannot finish a number they can.

Only the state machine is written per language — which is the whole bet ADR-002 is testing.

## Why the two engines look the same on purpose

`Engine.swift` is a line-for-line counterpart of `Engine.kt`, including the order of its checks.
That order is not stylistic: it decides the answer. Moving a bust check above the impossible-total
check would report the wrong reason, and a corpus that only compared accept-versus-reject would
still pass. Keeping the files readable side by side is the practical defence against exactly the
drift ADR-002 is worried about.

## Running it

```bash
swift test --package-path packages/engine-swift
```

Runs on macOS with Xcode and on Linux with the Swift toolchain — CI uses Linux, because a scoring
core verifiable only on a Mac is one that gets verified once rather than on every push.

The exhaustive family needs generating first:

```bash
python3 packages/domain-spec/generate.py --full
```
