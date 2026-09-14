# Running the durability probe

For someone who has never opened Xcode. Roughly 15 minutes, most of it waiting for a clone.

**Why bother:** ADR-006 will not let the client architecture be fixed until this number exists, and
it decides between SQLite-as-journal and a second storage engine on both clients. It cannot be
answered by reasoning, only by measuring, and only on a real phone.

---

## Part 1 — Get the code (Terminal, 3 minutes)

Open **Terminal** (⌘-Space, type `terminal`, Enter) and paste these one at a time:

```bash
cd ~/Documents
git clone https://github.com/JensonLR/Thro-Darts-App.git
cd Thro-Darts-App
git checkout claude/thro-production-build-je2mkf
```

> **The last line is not optional.** `main` is an empty starting commit with only docs on it. Every
> line of code lives on that branch, and Xcode's own "Clone Git Repository…" button would put you on
> `main` and show you almost nothing.

## Part 2 — A first number, without Xcode at all (1 minute)

Still in Terminal:

```bash
swift test --package-path packages/durability-probe
```

This runs on the Mac. It is **indicative only** — a Mac SSD is not a phone, and Apple's flush
behaviour differs by device class — but if it errors, we find that out in one minute instead of
after twenty minutes of Xcode setup.

You should see a table of four configurations with P50/P95/P99 columns, and the package's tests
all passing.
Roughly this shape — your numbers will differ, the ordering should not:

```
  configuration                                            P50    P95    P99  worst   budget
  relaxed (survives process death, NOT power loss)        0.01   0.05   0.08   0.19   meets
  synchronous=FULL, no Apple barrier                      0.30   0.41   0.52   0.63   meets
  synchronous=FULL + fullfsync (the real barrier)         1.01   2.01   5.45  19.78   meets
  rollback journal + FULL + fullfsync                     3.77   7.20  16.33  20.60   meets
```

Rows must get slower going down. One of the four tests exists to check exactly that: if forcing the
barrier is not slower than not forcing it, the pragmas were silently ignored and every number in the
table is meaningless. It fails loudly rather than printing a reassuring table.

This same command runs in CI on macOS on every push, so if it fails here and passes there, the
difference is your machine and worth saying so.

## Part 3 — The number that counts (on a real phone)

The app project already exists at `~/Thro Darts App/ThroProbe`, already links the probe, and already
signs against the right team. It is built and installed by one script, not by the Xcode GUI: every
failure then prints in full rather than appearing as a red badge next to a dropdown, and the second
reference device gets measured exactly the same way as the first.

### 3a. Prepare the phone

This is the only part nobody can do for you, and it is what everything else waits on.

1. Plug the iPhone into the Mac with a cable.
2. Unlock it. If it asks **Trust This Computer?**, tap **Trust** and enter the passcode.
3. On the iPhone: **Settings → Privacy & Security → Developer Mode → on**, then restart when it
   asks. Developer Mode only appears once a Mac running Xcode has been connected, so if you cannot
   find it, do step 1 first and look again.

To confirm the Mac can see it:

```bash
xcrun devicectl list devices
```

Your iPhone should be listed. If it says `No devices found.`, the steps above are not finished —
nothing later will work, and the error you will get is Apple's misleading
`Your team has no devices from which to generate a provisioning profile`, which reads like a signing
problem and is not one.

### 3b. Build, install, launch

```bash
cd ~/Documents/Thro-Darts-App
./scripts/run-probe-on-device.sh
```

That registers the phone, mints a development provisioning profile, builds, installs and launches.
A free Apple ID is enough to run on your own device.

Two failures are worth knowing in advance, because both have opaque errors:

| What you see | What it means |
|---|---|
| Apple reports the bundle identifier is already taken | Identifiers are globally unique across every Apple developer account. Re-run with `PROBE_BUNDLE_ID=com.yourname.throprobe ./scripts/run-probe-on-device.sh`. The app never ships, so any unique value is fine. |
| Installs, then refuses to open | One-time trust step. On the iPhone: **Settings → General → VPN & Device Management → tap your Apple ID → Trust**. Then tap the app icon directly. |

### 3c. Take the measurement

1. The app opens with one button. Put the phone down — do not keep the screen busy. The probe is
   timing storage barriers, and scrolling during the run measures something else.
2. Tap **Run the probe**. It takes maybe 30 seconds.
3. The console capture from `run-probe-on-device.sh` is the evidence. The app also appends the same
   block, verbatim, to `Documents/thro-probe-report.txt` in its container, so a run taken with no
   cable attached is not lost — pull it when there is one:

   ```bash
   xcrun devicectl device copy from --device <id> --domain-type appDataContainer \
     --domain-identifier com.thro.ThroProbe --source Documents/thro-probe-report.txt \
     --destination ./thro-probe-report.txt
   ```

   Numbers read off the screen are a lower grade of evidence than captured ones — sixteen figures
   copied by hand — and go into ADR-006 labelled as screen-read until the pulled block replaces
   them. The screen shows the same attribution line and checkpoint figure the block carries, and
   red `GUARD FAILED` text if the pragmas did not take effect, in which case nothing on it counts.

> **Do not use the Simulator for this.** Simulator storage is your Mac's SSD. The app will warn you
> in orange if it detects one. A simulator number is not a weaker version of the answer — it is an
> answer to a different question.
## What we are looking for

Four configurations, weakest to strongest. The one that decides this is
**`synchronous=FULL + fullfsync`**, because on Apple platforms plain `fsync` does not flush the
drive's write cache — `synchronous=FULL` on its own looks like a durability barrier and is not one.

| If that row is | Then |
|---|---|
| **P95 ≤ 20 ms** | SQLite stays the journal. The client architecture is settled and UI work can start. |
| **P95 > 20 ms** | ADR-006 is explicit: the durability rule wins and the budget is restated. The fallback is a raw append-only write-ahead file with the database demoted to a projection — a second storage engine on both clients, not a tweak. |

Either answer is useful. The bad outcome is guessing.

## Recording it

The numbers go into ADR-006 **with the device and iOS version they came from**. A latency without
its hardware is not evidence, and the next person to read that record needs to know whether it was
measured on a current phone or a five-year-old one — because the five-year-old one is the case that
matters in a pub.

## Appendix — recreating the Xcode project from scratch

Only needed if `~/Thro Darts App/ThroProbe` is lost, or when standing the probe up on a second
Mac. The existing project is already correct; do not redo this to fix a failure.

Xcode → **Create New Project…** → **iOS** → **App**, then:

1. Open **Xcode**.
2. **Create New Project…**
3. Choose **iOS** along the top, then **App**. Click **Next**.
4. Product Name: `ThroProbe`
5. Organisation Identifier: a domain you control, reversed and lowercase — `com.thro`. (Bundle
   identifiers are conventionally all lowercase. This app never leaves the device, so the value only
   has to be unique to you.)
6. Interface: **SwiftUI**. Language: **Swift**.
7. **Storage: `None`.** Not SwiftData, not Core Data. Both stand up their own SQLite stack inside
   the app process, and this app exists to measure SQLite write latency — a second SQLite client in
   the process being measured is a confounding variable for no benefit. They also generate
   boilerplate in `ContentView.swift` that the replacement below removes.
8. **Testing System: `None`.** The alternatives generate test targets inside `ThroProbe` that this
   procedure never runs — the probe package's tests live in the package and run from Terminal
   (Part 2), not from this app.
9. Leave **Host in CloudKit** unticked. Click **Next**.
10. Save it in `~/Thro Darts App` — outside the repository. That is where all three scripts look
    for it (`~/Thro Darts App/ThroProbe/ThroProbe.xcodeproj`); put it anywhere else and set
    `PROBE_PROJECT=/path/to/ThroProbe.xcodeproj` when running them. The scripts build into
    `~/Library/Developer/Xcode/DerivedData`, not beside the project, because `~/Documents` is an
    iCloud Drive folder on this Mac and `codesign` refuses a bundle carrying iCloud's Finder
    metadata. Click **Create**.

Then **File → Add Package Dependencies… → Add Local…**, choose
`Documents/Thro-Darts-App/packages/durability-probe`, and add it to the **ThroProbe** target.
Replace the whole of `ContentView.swift` with:

```swift
import SwiftUI
import DurabilityProbe

struct ContentView: View {
    var body: some View { ProbeView() }
}
```

Then open `ThroProbeApp.swift` — the file with `@main` on it — and add the `init`:

```swift
import SwiftUI
import DurabilityProbe

@main
struct ThroProbeApp: App {
    init() {
        // Before any UI, and it returns promptly on purpose.
        //
        // The kill test (docs/runbooks/DURABILITY_KILL_TEST.md) is driven by launch arguments.
        // Its write phase starts a background writer and returns so that SwiftUI can present a
        // scene: iOS allows an app roughly twenty seconds to finish launching, and an earlier
        // version that looped here never let the launch complete, so the watchdog SIGKILLed the
        // writer at about eighteen seconds every time — which looked exactly like the device
        // restarting and was nothing of the sort.
        //
        // Without this call the script launches the app, the app comes up showing the ordinary
        // probe screen, and the script waits for acknowledgements that are never coming.
        KillProbe.runFromLaunchArgumentsIfRequested()
    }

    var body: some Scene {
        WindowGroup { ContentView() }
    }
}
```

These two files are the entire app. They live outside this repository, in the Xcode project, which
is why they are written out here in full: without them the repository describes a test it cannot
actually run.

Finally set the deployment target to **iOS 16.0**. Xcode defaults it to the current SDK (26.5 at
the time of writing), which would make the app installable only on a recent flagship — and
`LATENCY_BUDGETS.md` names an iPhone SE-class device as a reference device precisely because
benchmarking on a Pro model is self-deception. `DurabilityProbe` declares `.iOS(.v16)`, so 16.0
is the package's own floor.
