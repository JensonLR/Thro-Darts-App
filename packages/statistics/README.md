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
| Finish rate from a checkable position | **Exact** — a *visit-level* measure, and not checkout percentage |
| Checkout % | **Exact** where attempts were recorded; **bounded** where some were not |
| Doubles hit rate | The same quantity under its other name |
| Doubles thrown at | **Exact** when every checkable visit recorded; otherwise **bounded** |

Both figures that count double attempts take the checkout set as an argument. Without it they can
only answer "how many were *recorded*", and a partial count reported as a match total is the same
dishonesty in smaller print: knowing which visits stood on a finish is what separates "did not
attempt" from "did not say".

## Why checkout percentage is computable after all

An earlier version of this layer reported it as permanently unavailable. That was wrong, and the
reason is worth keeping: the capture rule was too narrow, not the maths.

Darts thrown at a double are recorded on **every visit that began on a finish** — not only on one
that ended in a checkout. A player on 40 who throws a single 20 and misses has attempted a double.
Asking only on a successful checkout does not merely lose that attempt; it **biases the figure
upward**, because every recorded attempt succeeded and every miss is invisible. A partial
denominator is worse than an absent one, because it looks like a real number.

The trigger is verified rather than assumed: enumeration over the whole range shows that "a double
could have been thrown at during this visit" is exactly equivalent to "the remaining at the start of
the visit is a checkout number".

## Two things the tests are really checking

**That an approximation never presents itself as a fact.** When the leg-winning visit's dart count
is unknown, the 3-dart average returns an interval with `value` explicitly null — so a client
cannot render it as a single number by accident. The tests assert the exact figure falls inside
that interval.

**That assuming three darts is not harmless.** A 501 leg won in 13 darts, scored as though it took
15, understates the average by more than 20%. That is the whole argument for capturing the dart
count on a checkout.

**That the narrow capture rule inflates checkout percentage.** One test takes a match, removes the
attempts from the visits that did not finish, and asserts the resulting figure can no longer be
reported as a point value at all — and that its upper bound exceeds the truth by exactly the
overstatement the old rule would have published.

A bust visit consumed three darts and scored nothing, so it stays in the denominator and correctly
drags the average down. Implementations that discard busts inflate every average they produce.
