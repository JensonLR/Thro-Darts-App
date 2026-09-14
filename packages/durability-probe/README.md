# Durability probe

The measurement ADR-006 requires **before the client architecture is fixed**.

## What it answers

ADR-006's durability rule is non-negotiable: the command is flushed to the journal *before* it is
applied and acknowledged. Rendering first and persisting second loses a dart on any crash between,
and the player will not notice until the scores disagree with the board.

Honouring that rule costs a real number on real hardware. `LATENCY_BUDGETS.md` budgets **P95 ≤ 20 ms,
P99 ≤ 50 ms** for the flush and marks it *must be measured, not assumed*. This probe measures it.

If the strongest configuration exceeds the budget, ADR-006 says which side gives way: **the
durability rule wins and the budget is restated.** The fallback is a raw append-only write-ahead
file with the database demoted to a projection — a second storage engine on both clients, not a
tweak. That is why the decision needs evidence rather than a preference.

## Why macOS is not the answer

**`fsync` on Apple platforms does not flush the drive's write cache.** That needs `PRAGMA fullfsync`
and `checkpoint_fullfsync`, both of which default to off, so raising `synchronous` alone is not
sufficient on iOS. A macOS run is reassuring and irrelevant; ADR-006 asks for **both reference
devices**.

On the Mac the test run labels itself indicative only. On the phone the view warns in orange if it
is running in the Simulator, and the printed report carries a `THRO-PROBE-GUARD` line that fails
loudly if the real-barrier configuration was not slower than the relaxed one — the check the
package's tests apply on a Mac, which a phone with no test bundle would otherwise never run.

## The four configurations

| | Survives |
|---|---|
| WAL + `synchronous=NORMAL` | process death, **not power loss** |
| WAL + `synchronous=FULL` | more, but without the Apple barrier |
| WAL + `FULL` + `fullfsync` + `checkpoint_fullfsync` | the real barrier on Apple |
| rollback journal + `FULL` + `fullfsync` | the conservative comparison |

The first is included precisely because it is the one that looks fine and is not — it is Room's
relaxed default, and it is the failure with no repair path.

One transaction per visit, deliberately. That is what the durability rule costs; batching would
produce a much prettier number describing a system that loses darts.

## Running it

The measurement, on a phone — the only run that counts:

```bash
./scripts/run-probe-on-device.sh
```

That builds, signs, installs and launches a one-button app that wraps `ProbeView`; tap the button
and read the four rows off the console. `docs/runbooks/DURABILITY_MEASUREMENT.md` is the procedure,
written for someone who has never opened Xcode, including how to create the wrapper app.

The kill test ADR-011 requires on every release candidate, and the force-restart procedure:

```bash
./scripts/run-kill-test-on-device.sh
./scripts/run-power-cut-test.sh 0     # then 2
```

Both pull the journal off the device and adjudicate it on the Mac through one pass rule,
`KillProbe.verdict`, via the `adjudicate` executable in this package. See
`docs/runbooks/DURABILITY_KILL_TEST.md` — including why a force-restart on an iPhone turned out not
to substitute for a power cut.

A quick indicative run on the Mac itself:

```bash
swift test --package-path packages/durability-probe
```

**Apple platforms only.** The probe links SQLite3 directly, which SwiftPM does not vend on Linux,
and `fullfsync` is Apple-specific regardless — a Linux number would not be a weaker version of this
answer, it would be an answer to a different question. The *measurement* can only come from a
reference device — but a macOS CI job builds the package and runs the probe on every push, because
the alternative turned out badly: with no compile check anywhere, a type named `Measurement`
collided with `Foundation.Measurement` and reached a person's machine before anything caught it. A
package nothing builds is a package that is broken and does not know it. CI numbers are a runner's
disk and answer nothing; CI compiling is the point.

## What the tests assert, and what they do not

They **report**; they do not gate CI on a budget, because a CI runner's disk says nothing about a
five-year-old phone in a pub and asserting there would manufacture confidence from the wrong
machine.

Two things are asserted, because they hold everywhere:

- **The barrier is actually happening.** If forcing a real flush is not slower than not forcing one,
  the pragmas did not take effect and every number the probe reports is meaningless.
- **A reported percentile is a latency something really took** — nearest-rank, never an
  interpolation between two samples that did not occur.
- **Every pragma is read back after it is set.** `PRAGMA journal_mode = WAL` reports rather than
  fails when it cannot switch, and `sqlite3_exec` with no callback discards the report; the
  configuration is verified to be in force before a single visit is timed.

The captured block also carries a `THRO-PROBE-ENV` attribution line, a `ckpt` column with the cost
of an explicit WAL checkpoint under each configuration's own pragmas (two hundred visits never
trigger one on their own, so `checkpoint_fullfsync` was otherwise never exercised), a
`THRO-PROBE-GUARD` line, and a `THRO-PROBE-INCOMPLETE` line if any configuration threw.

## Recording the result

The measured numbers belong in ADR-006 alongside the decision they inform, with the device and OS
version they came from. A number without the hardware it was measured on is not evidence.
