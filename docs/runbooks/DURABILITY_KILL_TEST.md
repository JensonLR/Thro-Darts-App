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
./scripts/run-kill-test-on-device.sh [configurationIndex] [killAfterMs]
```

Connect and trust the iPhone first; `scripts/run-probe-on-device.sh` documents that setup. The app
must call `KillProbe.runFromLaunchArgumentsIfRequested()` from its `@main` struct's `init` —
`docs/runbooks/DURABILITY_MEASUREMENT.md` gives that file in full. Without it the app ignores the
launch arguments, comes up showing the ordinary probe screen, and this script waits for
acknowledgements that never arrive.

Arguments: the configuration index (0–3 into `Durability.candidates`, default 2 — the real Apple
barrier) and how long to write before the kill, in milliseconds (default 1500). `PROBE_PROJECT`
points at the Xcode project if it is not at `~/Thro Darts App/ThroProbe`; `PROBE_BUNDLE_ID` changes
the bundle identifier, applied at build time so the app that is built is the one that is launched.

**What it does.** Builds the `adjudicate` executable from the probe package, builds and installs
the app, then launches it with `--kill-test-write <index> <ms> --fresh --max-visits 5000000`. The
app writes visits to a journal in its Documents directory, one durable transaction each, printing
and flushing an acknowledgement after every commit; a background thread sends `SIGKILL` to the
process after the delay, which lands wherever the writer happens to be — usually inside a
transaction, which is the case worth testing. The script then pulls the journal off the device —
main file, `-wal`, `-shm` and `-journal` — and adjudicates it on the Mac.

`SIGKILL`, not `exit()`. `exit()` runs atexit handlers and flushes buffers, which is precisely what
a crash does not do; a kill test built on it quietly tests the happy path.

**The app's launch flags**, for anyone driving it by hand:

| flag | default | meaning |
|---|---|---|
| `--kill-test-write <index> <ms>` | required | configuration and kill delay; both must be present and readable |
| `--fresh` | off | delete any existing journal first |
| `--max-visits N` | 20000 | journal size cap. Reaching it makes the writer idle, and an idle writer voids the run (below) — the scripts set it far beyond what their windows can reach |
| `--throttle-us N` | 0 | microseconds between visits. The power-cut script sets 8000; zero is refused there, because an unthrottled writer hits any cap in seconds |
| `--kill-test-inspect [seq]` | — | adjudicate the app's own journal on the device. The scripts do not use this: they pull and adjudicate on the Mac |

An unreadable value is an error, not a default: the app prints `KILLTEST-ARGS-ERROR` and exits 1.
It also echoes `KILLTEST-CONFIG …` with what it is actually running, so a log whose numbers look
wrong can be checked against the configuration that produced them.

**Pass condition** — one rule, `KillProbe.verdict`, applied by the `adjudicate` executable to the
pulled journal:

1. the writer was still committing when the kill landed — a `KILLTEST-CAP-REACHED` or
   `KILLTEST-WRITE-ERROR` marker in the log voids the run, because a writer that had stopped left
   the kernel time to flush and the kill then put nothing at risk;
2. `integrity_check ok`;
3. no holes in the sequence, and the row count equals the highest sequence;
4. the highest sequence in the journal is at least the last acknowledgement seen on the console.

Three outcomes, with distinct exit codes: **PASS** (0), **FAIL** (2) — an acknowledged visit is
missing, a gap, or a corrupt journal — and **VOID** (3), which means the run measured nothing: the
writer was idle, or the journal is absent or empty. Void is not a pass. A journal that is not there
opens as an empty database, and an empty database passes `integrity_check` with zero rows and zero
holes, so without the third outcome "nothing was measured" came out as "nothing was lost".

The fourth comparison is one-directional on purpose. `SIGKILL` discards buffered stdout, so a write
can land without its acknowledgement ever reaching the console — the journal legitimately running
*ahead* of the console record is normal and expected. Running *behind* it means a write that was
reported durable is gone, which is the failure ADR-006 has no repair path for.

> Notes for whoever maintains this, because each of these was a real bug and each produced a
> confident wrong answer.
>
> *CRLF.* `devicectl --console` relays device output with CRLF endings. The sequence number was
> scraped out as `1840\r`, Swift's `Int()` returned nil for it, and the missing acknowledgement
> was silently treated as "none supplied" — a FAIL over an intact journal. The parser now trims
> before parsing and rejects what it cannot read; the scripts strip the CR at the boundary.
>
> *The sidecar.* In WAL mode recent commits live in the `-wal` file and nowhere else. A pull of the
> main database alone reported 269,811 rows for a journal that held 270,779 — "967 acknowledged
> visits lost", none of which had been. The scripts pull all four files and refuse to adjudicate a
> WAL-mode journal without its sidecar; `adjudicate` warns when one is absent, checked *before*
> the file is opened, because SQLite creates an empty sidecar on open and a check made afterwards
> always finds one.
>
> *Two copies of the rule.* The pass rule was implemented in `printReport` and again in the exit
> path, and they disagreed about holes — a journal with a gap printed PASS while exiting 2. Then the
> power-cut script grew a third copy in shell, `LOST=$(( LAST_ACK - MAXSEQ ))`, which checked the
> tail and nothing else. There is now one function, and every script reaches it through
> `adjudicate`. A false failure gets investigated; a false pass gets believed.

### Result on file

| device | date | configuration | acknowledged | max seq | rows | holes | integrity | verdict |
|---|---|---|---|---|---|---|---|---|
| `iPhone15,3` (iPhone 14 Pro Max), iOS 26.1 (23B85) | 2026-09-04 | `synchronous=FULL` + `fullfsync`, WAL | 1523 | 1524 | 1524 | none | ok | **PASS** |
| `iPhone15,3` (iPhone 14 Pro Max), iOS 26.6.1 (23G83) | 2026-09-05 | `synchronous=FULL` + `fullfsync`, WAL | 1107 | 1108 | 1108 | none | ok | **PASS** |

The second run is the pipeline above — pull with sidecar, adjudicate on the Mac — exercised end to
end after the review that removed the shell copy of the pass rule.

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

Procedure once such hardware exists — the same three steps `scripts/run-power-cut-test.sh`
automates for an iPhone, done by hand where `devicectl` does not apply:

1. **Write continuously, throttled, and keep the console.** Launch the app with
   `--kill-test-write <index> 3600000 --fresh --throttle-us 8000 --max-visits 100000` and capture
   its stdout on the host. The acknowledgements are the only ground truth that survives the cut;
   the throttle is what guarantees unflushed commits exist at every instant; the cap must not be
   reached before the cut (a `KILLTEST-CAP-REACHED` or `KILLTEST-WRITE-ERROR` line voids the run).
2. **Cut power mid-write.** Then restore it, and confirm the device came back on the same OS build
   it started on — an update in between voids the run.
3. **Pull the journal and adjudicate it on the host.** All four files: `thro-kill-test.sqlite`,
   `-wal`, `-shm`, `-journal`. Then

   ```bash
   swift run --package-path packages/durability-probe adjudicate <pulled/journal.sqlite> <last KILLTEST-ACK on the console>
   ```

   which applies `KillProbe.verdict` — integrity, row count against highest sequence, holes, and
   the tail against the console — and exits 0 for PASS, 2 for FAIL, 3 for VOID. Do not query the
   pulled file with anything else first: the first thing to open a WAL-mode database checkpoints
   its sidecar into the main file, and a hand query before the adjudicator is how a run gets
   adjudicated twice against different files.

Run configuration 0 first. If the weakest setting survives the cut, the interruption is not
reaching the layer under test and a pass under configuration 2 is not evidence.

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
