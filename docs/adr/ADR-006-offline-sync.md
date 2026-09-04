# ADR-006 — Offline sync protocol and scoring authority

**Status:** Accepted · **Date:** 2026-09-03

The highest-risk subsystem. Venues have poor signal; that is the premise, not an edge case.

## Client model

Local SQLite with two tables: an **append-only command journal** and a **rebuildable projection**.
The UI renders the projection; the projection is a fold of the journal through the same pure engine
the server runs. Recovery from process death is a journal replay, which is only viable because the
engine is pure (ADR-002).

**Durability rule, non-negotiable: the command is flushed to the journal *before* it is applied and
acknowledged.** Paint optimistically first; acknowledge only once durable. Rendering first and
persisting second loses a dart on any crash between, and the player will not notice until the scores
disagree with the board.

**Durability must be configured explicitly, and the defaults differ by platform** — a distinction
worth naming, because it points at different knobs. Room uses write-ahead logging with a relaxed sync
that survives process death but **not power loss**. Stock SQLite on iOS defaults differently again,
and — critically — **`fsync` on Apple platforms does not flush the drive's write cache**; that
requires `PRAGMA fullfsync` and `checkpoint_fullfsync`, which default to off. Raising one sync
setting is not sufficient on iOS.

**This must be measured before the client architecture is fixed.** A true storage barrier per visit
on low-end hardware can exceed the 20 ms budget in `LATENCY_BUDGETS.md`, and the stated fallback — a
raw append-only journal with the database demoted to a projection — is a second storage engine on
both clients, not a tweak. Measure durability latency on both reference devices in week one; if the
budget and the durability rule conflict, **the durability rule wins** and the budget is restated. Losing an acknowledged competitive visit has no repair path, so the
setting is raised and validated with real kill tests and power-cut tests on device — not assumed.

### Measurement status — measured on a phone; the SE-class and Android runs are still outstanding

`packages/durability-probe` implements the measurement: it writes synthetic visits, one durable
transaction each, under every candidate configuration and reports the distribution. It runs in CI on
macOS on every push, which is what stops it rotting; it is **not** the measurement this ADR asks for.

Three machines have been measured, 200 visits per configuration, milliseconds. The two Macs are
indicative only. The phone is the first figure here that bears on the decision.

**GitHub `macos-latest`, arm64, virtualised:**

| configuration | P50 | P95 | P99 | worst |
|---|---|---|---|---|
| relaxed — survives process death, **not** power loss | 0.01 | 0.05 | 0.08 | 0.19 |
| `synchronous=FULL`, no Apple barrier | 0.30 | 0.41 | 0.52 | 0.63 |
| `synchronous=FULL` + `fullfsync`, WAL | 1.01 | 2.01 | 5.45 | 19.78 |
| `synchronous=FULL` + `fullfsync`, rollback journal | 3.77 | 7.20 | 16.33 | 20.60 |

**MacBook Air, Apple Silicon, local NVMe** — `Mac17,3`, macOS 26.6.2 (build 25G83), two
consecutive runs, showing the spread:

| configuration | P50 | P95 | P99 | worst |
|---|---|---|---|---|
| relaxed | 0.01 / 0.01 | 0.01 / 0.02 | 0.03 / 0.04 | 0.04 / 0.04 |
| `synchronous=FULL`, no Apple barrier | 0.06 / 0.06 | 0.07 / 0.08 | 0.09 / 0.10 | 0.11 / 0.15 |
| `synchronous=FULL` + `fullfsync`, WAL | 0.42 / 0.43 | 0.73 / 0.55 | 0.97 / 0.63 | 1.07 / 0.68 |
| `synchronous=FULL` + `fullfsync`, rollback journal | 1.35 / 1.36 | 1.56 / 1.72 | 2.31 / 2.33 | 4.61 / 2.68 |

Reproducible to within a few hundredths across runs, so the probe is not measuring noise.

**iPhone 14 Pro Max — `iPhone15,3`, iOS 26.1**, on-device, two consecutive runs, phone idle and
face-down:

| configuration | P50 | P95 | P99 | worst |
|---|---|---|---|---|
| relaxed — survives process death, **not** power loss | 0.02 / 0.03 | 0.04 / 0.05 | 0.06 / 0.07 | 0.08 / 0.12 |
| `synchronous=FULL`, no Apple barrier | 0.09 / 0.09 | 0.12 / 0.13 | 0.22 / 0.19 | 0.28 / 0.25 |
| `synchronous=FULL` + `fullfsync`, WAL | 0.70 / 0.65 | 1.64 / 1.60 | 1.98 / 1.87 | 2.08 / 2.18 |
| `synchronous=FULL` + `fullfsync`, rollback journal | 3.33 / 3.26 | 5.14 / 5.37 | 5.55 / 6.08 | 5.76 / 6.84 |

The deciding row reproduces to within 0.04 ms at P95 across the two runs. These figures were
captured from the device console rather than transcribed from the screen, so they are the numbers
the phone actually produced.

The hardware identifier is recorded raw rather than as a marketing name, because `Mac17,3` and
`iPhone15,3` are what `sysctl -n hw.model` and `devicectl` return, and are the thing a later reader
can compare against unambiguously.

The probe asserts that forcing the barrier is slower than not forcing it — CI measured 0.01 ms
against 1.17 ms, the MacBook Air 0.01 ms against 0.38 and 0.45 ms, the iPhone 0.02 and 0.03 ms
against 0.70 and 0.65 ms. Without that check a run where the pragmas were silently ignored would
report excellent numbers and mean nothing.

**CI is roughly 3x slower than the real machine** (P95 2.01 ms against 0.55–0.73 ms), which is the
useful direction: the CI job is a conservative proxy for a Mac rather than an optimistic one, so a
regression that pushes the barrier cost up will show there first.

Two things this does support:

- **The barrier is real and its cost is measurable**, roughly two orders of magnitude over the
  relaxed setting on CI and forty times on local hardware. Row 2 is the one this ADR was written to catch: `synchronous=FULL` on its own
  costs 0.30 ms and looks durable. It is not, on Apple platforms, and the gap between rows 2 and 3
  is the entire cost of being right.
- **WAL over rollback journal**, by about 3.5× at P95 under the same barrier.

### The decision this ADR was waiting for

The row that decides it is `synchronous=FULL` + `fullfsync` on WAL, and on the phone it measures
**P95 1.64 and 1.60 ms against a budget of 20 ms** — inside it by roughly twelve times. Every
configuration measured on the phone meets the budget, including the rollback journal.

**SQLite stays the journal.** The fallback this ADR describes — a raw append-only write-ahead file
with the database demoted to a projection, a second storage engine on both clients — is not
required. The client architecture is unblocked to the extent that one device can unblock it.

Two properties of the phone's numbers are worth keeping:

- **The phone sits between the two Macs**: slower than the MacBook Air (P95 0.55–0.73 ms), faster
  than virtualised CI (2.01 ms). The pessimism in the CI figure was in the useful direction, as
  assumed above.
- **Its tail is far tighter than CI's.** The worst single write on the phone was 2.18 ms; on CI it
  was 19.78 ms, a whisker under the budget. Whatever produces CI's long tail is a property of the
  hypervisor and not of iOS, which is worth knowing before anyone treats a CI regression in the
  worst column as a device problem.

What this does **not** close:

- **This is a flagship.** `LATENCY_BUDGETS.md` names the reference devices as an iPhone SE-class
  device and a ~£150 A-series Android, and says in terms that benchmarking on a Pro model is
  self-deception. An iPhone 14 Pro Max is precisely the phone that warning is about. The result is
  real and it is strong, but the SE-class figure is the one with authority and it does not exist
  yet. Twelve times of headroom makes it unlikely that the SE-class run overturns this — and
  "unlikely" is a prediction, not a measurement, which is the distinction this ADR exists to
  enforce.
- **The Android reference device has not been measured at all.**

One limit of the probe itself, worth stating so the numbers are not over-read: **it measures
latency, not durability.** The guard test proves the pragmas changed the system's behaviour; it does
not prove the write reached NAND. Apple SSDs with power-loss-protected caches can acknowledge a
flush quickly and honestly, and a drive that lied about it would look identical here. Only the
power-cut test distinguishes those two, which is why this ADR asks for one and why neither the probe
nor the kill test below can close the requirement.

### Kill test — passing on the flagship

The process is `SIGKILL`ed mid-transaction while writing visits under `synchronous=FULL` +
`fullfsync`, then the journal is reopened and compared against the acknowledgements the console
recorded before the kill.

| device | date | acknowledged | integrity | holes | verdict |
|---|---|---|---|---|---|
| `iPhone15,3`, iOS 26.1 (23B85) | 2026-09-04 | 1523 | ok | none | **PASS — nothing acknowledged was lost** |

`SIGKILL` rather than `exit()`, because `exit()` runs atexit handlers and flushes buffers — exactly
what a crash does not do, so a kill test built on it tests the happy path and passes when it should
not. The run is automated end to end (`scripts/run-kill-test-on-device.sh`), because ADR-011 asks for
it on every release candidate and a test needing someone to tap a phone in the right order at the
right moment is a test that gets skipped under deadline.

**This is the weaker of the two tests ADR-006 asks for, and it does not stand in for the other.**
Process death leaves the kernel, the filesystem and the drive running, so anything SQLite handed to
the kernel still lands. This test would pass on `synchronous=NORMAL` — the configuration this ADR
exists to reject. It says the journal is not corrupted by a crash and that no acknowledged visit
vanished. It says nothing about whether `fullfsync` reaches NAND, which is the entire question.
Reporting a green kill test as durability would be the same error as reporting the CI latency
figure as the budget answer.

### Force-restart does not substitute for a power cut — measured, not assumed

The obvious way to approximate a power cut on an iPhone is a force-restart, since the battery cannot
be pulled. It was run as a control under **`relaxed`** — WAL with `synchronous=NORMAL`, the
configuration whose own label reads *survives process death, **not** power loss* — with the writer
still committing at the moment the device went down:

| device | configuration | acknowledged | survived | integrity | lost |
|---|---|---|---|---|---|
| `iPhone15,3`, iOS 26.6.1 (23G83) | WAL, `synchronous=NORMAL` | 9446 | 9446 | ok | **0** |

**The control failed to fail**, and that is the finding. If the weakest configuration survives a
force-restart intact, the method cannot distinguish it from the strongest, so no force-restart
result is evidence about the barrier — a green run under `fullfsync` would be a reassuring number
that means nothing. A force-restart is a controlled reset: the storage controller stays powered,
in-flight writes complete, and the ten seconds the gesture takes already exceeds the kernel's
dirty-page flush interval. There is no window to catch.

This narrows what the outstanding requirement actually needs. It is not "try harder on the iPhone";
it is hardware whose power can genuinely be interrupted — the `~£150 A-series Android` this ADR
already requires, run from a removable battery or a switched bench supply. One acquisition closes
both the Android latency run and the power-cut test, which is an argument for getting that device
early rather than last.

Note also that the device was updated from iOS 26.1 (23B85) to 26.6.1 (23G83) partway through this
session. The latency figures and the kill test above were taken on 26.1 and are attributed to it;
the force-restart control was taken on 26.6.1. Neither is invalidated, but they are not the same
system and a later comparison must not treat them as one.

**Still outstanding: the SE-class iPhone run, the Android reference device, and the power-cut
test — which now has a known method requirement rather than an open question.**
`docs/runbooks/DURABILITY_MEASUREMENT.md` is the procedure; `ProbeView` is a one-tap front end so the
run does not require setting up a test target. Record device model and OS version with the numbers —
without those the figures are unattributable and cannot be compared to a later run.

The half-typed entry buffer is **UI draft state in a separate non-evidence table**. It must never be
foldable into the journal.

## Scoring authority — three mechanisms

A single writer is not sufficient on its own, because the approved dispute screen shows a per-leg
`Confirmed` column authored by the participant who scored nothing.

1. **A scoped offline scoring grant**, issued by the server, held on the device, and **valid without
   a network at scoring time**. This is what makes authority compatible with offline scoring rather
   than contradicting it.

   **Issued at check-in, not at match-open.** Match-open is the moment the design draws ("Both
   players must confirm before scoring opens") — but nothing guarantees a network at that moment, and
   a player arriving at a dead-signal venue must still be able to score. Check-in is inherently
   online (it is how the organiser knows who is present), so grants for a player's whole event are
   pre-issued there. Match-open then confirms participation locally.

   **Lifetime: the competition session plus 24 hours**, renewed opportunistically whenever the device
   has signal. A tournament day is ten hours or more, so anything shorter fails the case this exists
   for. **Grants are revocable**, and an organiser reassigning a scorer revokes the old one.

   **This is a deliberate, bounded exception to ADR-008's rule that permissions are never carried on
   the client**, and the exposure is stated rather than hidden: a revoked scorer retains the ability
   to *record* evidence on that device until the grant expires or the device reaches the network.
   The mitigation is that recording is not the same as being believed — evidence recorded under a
   revoked grant is accepted into the log, flagged, and routed to organiser review rather than
   silently trusted. Evidence is never destroyed for an authorization reason.
2. **Per-device evidence streams**, gapless per `(aggregate, device)`, never discarded and never
   deduplicated across devices. Two streams for one match is *corroboration*; divergence is a dispute.
3. **Per-leg participant attestation** as a first-class event, authored by the non-scoring
   participant. This is what the `Confirmed` column reads from.

**The offline two-device case:** both players score the whole match offline. Reconcile at **outcome
level** — winner and per-player leg scores — not by digest equality, because a digest over a leg's
events makes a single mis-keyed-then-corrected visit mismatch on a leg both players agree about. Use
a visit-level diff only to *explain* a mismatch. This yields a whole-match-contested state that the
design does not currently draw (raised as a design commission).

**Offline matches remain self-reported until sync.** That is a recorded product consequence, not a
defect, and it feeds directly into founder decision B2.

**Peer-to-peer sync is not built in the first slice** — iOS and Android share only Bluetooth LE,
which costs a permission and a privacy declaration for no first-release benefit.

## Server algorithm — order matters, each step prevents a named failure

1. **Receipt lookup** on `(device, command_id)`. Hit returns the stored response verbatim, including
   a stored rejection.
2. **Authorise** — does this actor hold a current grant for this match?
3. **Gap check** on the per-device sequence. A gap is rejected with the expected value, never applied
   past.
4. **Rehydrate** and check the expected stream sequence.
5. **Revalidate against the rules engine.** Reject with a stable code: total not achievable, checkout
   not permitted for the out-rule, negative remaining, bust mishandled, wrong thrower, leg already won,
   match finalised.
6. **Compare the client's computed outcome.** A mismatch appends the server's outcome and raises an
   engine-divergence alert carrying both outcomes and both engine versions.
7. **Append**, relying on the `(match_id, device_id, device_seq)` uniqueness; **take a savepoint
   first**, because a unique violation aborts the enclosing transaction and the retry must not lose
   the receipt lookup. Roll back to the savepoint, re-read, revalidate, retry, bounded.
8. **Write the receipt in the same transaction.** If the *receipt* key itself conflicts, that is a
   concurrent duplicate of the same command: re-read it and return the stored response, never an
   error.

**Never accept an asserted result.** A client cannot say "I won 5–3"; the server derives the outcome
from the visit stream. And the honest limit must be stated in the API contract: the server validates
that a claim is **rule-consistent**, never that it is what happened.

## Failure modes and their prevention

| Failure | How it corrupts a match | Prevention |
|---|---|---|
| Retried command applied twice | Phantom visit, wrong remaining | Receipt unique per device, written in the append transaction |
| Commands arrive out of order | Bust evaluated against the wrong total | Gapless sequence; server rejects gaps rather than applying past them |
| Process killed mid-visit | Lost visit; app disagrees with the board | Journal flush precedes acknowledgement |
| Client engine drifts from server | Player told they won a leg the server rejects | Conformance corpus in CI, plus per-command divergence detection |
| Device clock wrong or manipulated | Fraudulent backdating | Ordering by sequence; device time is evidence only |
| Stale journal replayed weeks later | Old commands applied to a finalised match | Grant expiry and a finalised-match rejection |
| Token expires offline | — | **Scoring is unaffected; auth is not on the scoring path.** On reconnect a 401 must not drop the queue, sign the user out, or clear local data |
| Rejected batch | Evidence destroyed | **Never discarded client-side.** Persist durably with the server's reason until resolved |

## Revisit trigger

Any evidence loss observed in the field; or divergence alerts firing more than negligibly, which
would trigger ADR-002's kill criteria.
