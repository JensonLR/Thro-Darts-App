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
| Status | **Automated and passing** | **Outstanding** — force-restart tried, does not discriminate |

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

## Part 2 — The power-cut test (still outstanding, and force-restart will not substitute)

This is the test that decides whether `fullfsync` does what it claims. It cannot be automated: the
device has to actually lose power, and nothing running on that device can be alive afterwards to
report what happened.

### Force-restart was tried and does not work. Do not repeat it.

An iPhone's battery cannot be pulled, so the obvious approximation is a force-restart (Volume Up,
Volume Down, hold Side). It was attempted four times on `iPhone15,3`. The fourth was methodologically
clean — the writer was demonstrably still committing when the device went down, the connection
dropping mid-stream with no termination message — and it was run under **`relaxed`** as a control,
the configuration whose own label reads *survives process death, **not** power loss*:

| device | date | configuration | acknowledged | survived | integrity | lost |
|---|---|---|---|---|---|---|
| `iPhone15,3`, iOS 26.6.1 (23G83) | 2026-09-04 | WAL, `synchronous=NORMAL` (relaxed) | 9446 | 9446 | ok | **0** |

**The control failed to fail.** The weakest configuration lost nothing, so a force-restart on this
hardware does not reach the layer this question is about. It cannot discriminate between `relaxed`
and `fullfsync`, and therefore no force-restart result — including a green one under `fullfsync` —
is evidence about the durability barrier. Running the strong configuration afterwards would produce
a reassuring tick that means nothing, which is worse than no result.

Why it does not work is worth stating so nobody re-derives it: a force-restart is a controlled reset,
not a power cut. The storage controller stays powered across it and in-flight writes complete, and
the ten seconds the button gesture takes is already longer than the kernel's dirty-page flush
interval. There is no window to catch.

### What an actual answer requires

Hardware whose power can be genuinely interrupted mid-write:

1. **An Android reference device with a removable battery**, or one that can be run from a bench
   supply that is switched off. This is also the `~£150 A-series Android` the budget document already
   requires for latency, so one acquisition closes two outstanding items.
2. **A dev board** (Raspberry Pi or similar) running the same SQLite pragmas against comparable flash.
   Not either reference device, so a weaker attribution — but it answers the pragma question, which
   is the part that generalises.

Procedure once such hardware exists: write continuously with the throttled writer so unflushed
commits always exist, cut power mid-write, restore power, then compare the journal against the last
acknowledgement that reached the host. `KillProbe` already does all of this; only the interruption
method changes.

**If it fails**, that is the most valuable result this project can produce: it means `fullfsync` is
not reaching NAND on that hardware, and ADR-006 is explicit that the durability rule wins and the
budget is restated. Record it exactly as measured.

## Device inventory

ADR-011 requires a **named device inventory** — an unowned test is a test that runs once, and
"a phone" is not an owner.

| role | device | OS | status |
|---|---|---|---|
| iOS, flagship | `iPhone15,3` — iPhone 14 Pro Max | iOS 26.1 (23B85), updated mid-session to 26.6.1 (23G83) | the only device available; kill test passing |
| iOS, SE-class reference | *not yet named* | | **needed** — `LATENCY_BUDGETS.md` names an iPhone SE-class device as the reference, and says benchmarking on a Pro model is self-deception |
| Android, ~£150 A-series reference | *not yet named* | | **needed, and now the priority** — unmeasured, no Android toolchain on the build Mac, and it is the only realistic route to a genuine power-cut test as well as the Android latency figure |

The two unnamed rows are why this document is not finished. Neither the latency measurement nor the
power-cut test is closed until they exist.
