# THRØ statistics

Separate from the scoring engine on purpose. The engine deals in state transitions and contains no
floating point at all; averages and rates need division. Keeping them apart is what lets the engine
stay exactly reproducible across three platforms.

```bash
gradle test
```

## The rule this layer exists to enforce

THRØ never invents dart-level evidence. A visit total of 100 does not say which three darts were
thrown — so a statistic that depends on knowing them is reported as **unavailable**, not
approximated.

Every figure therefore carries *how it was arrived at*, not just a number:

| Basis | Meaning |
|---|---|
| `EXACT` | Derived with certainty from the recorded evidence |
| `BOUNDED` | An interval or a lower bound. **Never a point value** |
| `UNAVAILABLE` | Not computable from the evidence held. Never approximated |

## What each statistic actually is

| Statistic | From visit totals |
|---|---|
| 180s, 140+, 100+ | **Exact.** 180 has one decomposition, so it is dart-level proof |
| Highest checkout | **Exact** — the remaining finished from |
| Best leg | **Exact in visits.** In darts it is not computable, so it is not claimed |
| First 9 average | **Exact**, with the excluded legs disclosed |
| 3-dart average | **Exact** when the winning visit recorded its darts; otherwise **bounded** |
| Finish rate from a checkable position | **Exact** — and *not* checkout percentage |
| Checkout % | **Unavailable.** Needs doubles attempted |
| Doubles hit rate | **Unavailable.** Purely dart-level |

## Two things the tests are really checking

**That an approximation never presents itself as a fact.** When the leg-winning visit's dart count
is unknown, the 3-dart average returns an interval with `value` explicitly null — so a client
cannot render it as a single number by accident. The tests assert the exact figure falls inside
that interval.

**That assuming three darts is not harmless.** A 501 leg won in 13 darts, scored as though it took
15, understates the average by more than 20%. That is the whole argument for capturing one extra
field per leg.

A bust visit consumed three darts and scored nothing, so it stays in the denominator and correctly
drags the average down. Implementations that discard busts inflate every average they produce.
