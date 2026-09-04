# Kill and power-cut tests

ADR-011: *"Two properties this architecture depends on are not testable by a build server, and an
unowned manual test is a test that runs once."* It requires both of these on **every release
candidate**, and says a release candidate without them is not a release candidate.

They are two different tests answering two different questions, and the easy one does not stand in
for the hard one.

| | Kill test | Power-cut test |
|---|---|---|
| Simulates | The app crashing | The battery being pulled |
| Still running during the event | Kernel, filesystem, drive | Nothing |
| Survives if data reached | The kernel | **The NAND itself** |
| Would pass on `synchronous=NORMAL` | **Yes** | No |
| Automatable | Yes | No — needs hands |
| Status | **Automated and passing** | **Outstanding** |

The row that matters is the fourth. A green kill test says almost nothing about the pragma this
whole exercise is about, because `fullfsync` exists to push data past the drive's write cache and
process death never threatens that cache. Do not let a passing kill test be reported as durability.

---

## Part 1 — The kill test (automated)

```bash
cd ~/Documents/Thro-Darts-App
./scripts/run-kill-test-on-device.sh
```

Connect and trust the iPhone first; `scripts/run-probe-on-device.sh` documents that setup. The
app must call `KillProbe.runFromLaunchArgumentsIfRequested()` from its `@main` struct's `init` —
`docs/runbooks/DURABILITY_MEASUREMENT.md` gives that file in full. Without it the app ignores the
launch arguments, comes up showing the ordinary probe screen, and this script waits for
acknowledgements that never arrive. Optional
arguments are the configuration index (0–3 into `Durability.candidates`, default 2 — the real Apple
barrier) and how long to write before the kill in milliseconds (default 1500).

**What it does.** Writes visits to a journal in the app's Documents directory, one durable
transaction each, printing and flushing an acknowledgement after every commit. A background thread
then sends `SIGKILL` to the process, which lands wherever the writer happens to be — usually inside
a transaction, which is the case worth testing. The app is relaunched, reopens that same journal and
reports what survived.

`SIGKILL`, not `exit()`. `exit()` runs atexit handlers and flushes buffers, which is precisely what
a crash does not do; a kill test built on it quietly tests the happy path.

**Pass condition.** `integrity_check ok`, no holes in the sequence, and the highest sequence in the
journal at least as high as the last acknowledgement seen on the console.

That last comparison is one-directional on purpose. `SIGKILL` discards buffered stdout, so a write
can land without its acknowledgement ever reaching the console — the journal legitimately running
*ahead* of the console record is normal and expected. Running *behind* it means a write that was
reported durable is gone, which is the failure ADR-006 has no repair path for.

> A note for whoever maintains this. The first version of this script reported FAIL on a run whose
> journal was perfectly intact: `devicectl --console` relays device output with CRLF endings, the
> sequence number was scraped out as `1840\r`, Swift's `Int()` returned nil for it, and the missing
> acknowledgement was silently treated as "none supplied". A false failure on a durability test is
> the worst available outcome — it either causes a panic about data loss that did not happen, or
> trains people to disbelieve the test. The parser now rejects an unreadable argument loudly instead
> of degrading to nil, and the script strips CR at the boundary. Keep both.

### Result on file

| device | date | configuration | acknowledged | integrity | holes | verdict |
|---|---|---|---|---|---|---|
| `iPhone15,3` (iPhone 14 Pro Max), iOS 26.1 (23B85) | 2026-09-04 | `synchronous=FULL` + `fullfsync`, WAL | 1523 | ok | none | **PASS** |

---

## Part 2 — The power-cut test (manual, still outstanding)

This is the one that decides whether `fullfsync` is doing what it claims. It cannot be automated:
the device has to actually lose power, and no software running on that device can arrange to be
alive afterwards to tell you what happened.

An iPhone cannot have its battery pulled. The available approximations, weakest first:

1. **Force-restart** (Volume Up, Volume Down, hold Side until the Apple logo). This is closer to a
   kernel panic than a power cut — the hardware stays powered and the drive can still flush its
   cache. Better than the kill test, still not the real event.
2. **Run the battery to zero** while writing. A genuine power loss, but slow and awkward to arrange
   repeatedly, and iOS shuts down deliberately at its cutoff rather than dying abruptly.
3. **Android reference device with a removable battery, or a dev board.** The only way to get a
   truly abrupt cut. If the answer matters at the level of certainty ADR-006 implies, this is what
   provides it, and it is a reason to test the Android device early rather than last.

### Procedure

1. Plug in and trust the device. Note the model identifier and OS build.
2. Start a long write run, so the kill lands mid-transaction rather than between transactions:
   ```bash
   ./scripts/run-kill-test-on-device.sh 2 600000
   ```
   Leave it writing. Acknowledgements stream to the console; **keep that console output** — it is
   the record of what was acknowledged, and it is the only ground truth you will have afterwards.
3. Cut power by whichever method above you are using, while writes are in flight.
4. Restart the device, then:
   ```bash
   xcrun devicectl device process launch --device <id> --console com.thro.ThroProbe \
     --kill-test-inspect <last acknowledged sequence from step 2>
   ```
5. Record the report verbatim, with the device identifier, the OS build, and which cut method was
   used. A power-cut result without its method is not comparable to any other run.

**If it fails**, that is a real result and the most valuable one this project can produce. It means
`fullfsync` is not reaching NAND on that hardware, and ADR-006 is explicit about what follows: the
durability rule wins and the budget is restated. Record it exactly as measured. Do not re-run until
it passes and report that.

---

## Device inventory

ADR-011 requires a **named device inventory** — an unowned test is a test that runs once, and
"a phone" is not an owner.

| role | device | OS | status |
|---|---|---|---|
| iOS, flagship | `iPhone15,3` — iPhone 14 Pro Max | iOS 26.1 (23B85) | available; kill test passing |
| iOS, SE-class reference | *not yet named* | | **needed** — `LATENCY_BUDGETS.md` names an iPhone SE-class device as the reference, and says benchmarking on a Pro model is self-deception |
| Android, ~£150 A-series reference | *not yet named* | | **needed** — unmeasured; no Android toolchain is installed on the build Mac |

The two unnamed rows are why this document is not finished. Neither the latency measurement nor the
power-cut test is closed until they exist.
