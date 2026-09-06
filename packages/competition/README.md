# THRØ competition

Competitors, brackets, byes and standings. Pure domain, no dependencies.

```bash
gradle test
```

## Why the domain owns the bye arithmetic

The approved organiser screen reads *"74 entries · Round of 64 with 10 byes"*. A bye **advances** a
competitor without playing; it does not remove one. For 74 entrants the bracket is 128, so **54
receive byes** and the remaining 20 play **10 preliminary matches** — whose winners join the 54 to
fill a round of 64. The design's "10" is the preliminary-match count, mislabelled.

That is why the UI carries none of these numbers. A screen that carries arithmetic will eventually
carry wrong arithmetic. The identities are asserted exhaustively for every field size from 1 to 1024.

**Bracket size is computed by bit length, never by a power of two over a logarithm.** A
floating-point `log2` returns a value fractionally above the integer for exact powers of two, which
silently doubles the bracket for 64, 128 and 256 — precisely the field sizes most likely to occur.

## Four facts the design renders identically

The approved bracket shows a missing competitor as "TBC" in every case. These are different things
and are modelled separately: **bye** (advanced without playing), **undetermined** (awaiting an
earlier result), **walkover** (opponent did not play), **withdrawn**.

A bye is **not a win** — the design's own best domain decision. It creates no match, produces no
statistics, and is not rating-eligible.

## Standings that can justify themselves

The tie-break chain is declared per competition, and each row records **which step actually
separated it** from the row above. This matters because the approved league table exposes legs for
and against but has no head-to-head column — so an ordering that used head-to-head could not be
explained from the table shown.

An **awarded** fixture is a distinct, auditable outcome carrying a reason, never a synthetic
scoreline. A synthetic scoreline would pollute leg-difference tie-breaks and reward an unplayed
match in any rating model trained on it.

Drawn fixtures are representable even though the current format's odd leg counts make them
impossible — "no draws" must not become an invariant of the aggregate.
