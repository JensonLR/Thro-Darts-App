# THRØ — domain spec and conformance corpus

The scoring rules must produce identical results on iOS, Android and server validation. **This
corpus is the contract that guarantees it** — not any shared implementation, which is why
[ADR-002](../../docs/adr/ADR-002-shared-scoring-domain.md) can leave the shared-code question open.

## Everything here is derived, not transcribed

The only input is the dartboard segment set. Achievable totals, checkout sets, bogey numbers, bust
conditions, one-dart finishes and minimum darts to finish all fall out of it by enumeration.

That is deliberate. The approved design's own sample data contains four arithmetic impossibilities —
including two dart counts on the organiser's dispute-resolution screen that no dartboard can produce.
Nothing in this system is copied from a source that could be wrong.

## Files

| | |
|---|---|
| `generate.py` | Derives the rule tables and emits the corpus. `--full` adds the exhaustive transition table (86,000 cases, CI only) |
| `validate.py` | Property tests against **independent** darts facts, plus structural invariants and a replay of every vector |
| `rule-tables.json` | Generated. Feeds Swift, Kotlin and server sources — no platform hand-copies these values |
| `vectors/*.jsonl` | The corpus. One case per line, so a failing line number maps directly to a case |

```
python3 generate.py && python3 validate.py
```

## What the exhaustive run shows

Across all 86,000 `(remaining, visit total)` transitions under double-out:

| Outcome | Cases |
|---|---:|
| scored | 71,261 |
| bust — below zero | 14,398 |
| bust — remainder one | 171 |
| leg won | 162 |
| **bust — score reached zero on an unfinishable number** | **8** |

That last row is the point. It is the bust condition implementations drop, and it accounts for
**0.009%** of the space — which is precisely why hand-written tests miss it and why the table is
enumerated rather than sampled. The eight values are 159, 162, 165, 168, 171, 174, 177 and 180.

## Governance

- **Generated files are never hand-edited.** `adversarial.jsonl` is the only hand-written file and is
  append-only.
- A rule change is **one pull request**: spec, rule tables, version bump, regeneration, and every
  implementation. It cannot be split.
- **Every bug that reaches a build becomes an adversarial vector before its fix merges.** This is what
  stops "make the vector pass" degrading into "edit the vector".
- CI fails if the committed corpus is stale, if any property check fails, or — once engines exist —
  if any platform diverges.

## The dart (1.4.0, OD-023)

A visit may be recorded as the darts that were thrown (`RecordDarts`). A dart is decided by its **ring**, never
its value — a single 20 and a D10 both score 20, and only one finishes a double-out leg — so the per-dart rule is
stated by ring and `validate.py` proves the values those rings produce are exactly the finishing and opening
segments. It then holds the per-dart transition to the visit transition for every hand of up to two darts from
every reachable score, under all three out-rules: they agree everywhere except where a hand reaches zero on a dart
that may not finish, which only darts can see. A match may play `keepScoredDarts`, the local rule where the darts
before the busting one stand; its invariants are checked over the same space.

## Deliberately absent

Averages, checkout percentages and any other statistic. Those belong to a separately tested layer:
the engine deals in state transitions, and **no floating point appears anywhere in this package**.
