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

You should see a table of four configurations with P50/P95/P99 columns, and four passing tests.
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

## Part 3 — The number that counts (Xcode, on a real phone)

### 3a. Make a place for the app to live

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
   boilerplate in `ContentView.swift` that step 3c deletes.
8. **Testing System: `None`.** The alternatives generate test targets inside `ThroProbe` that this
   procedure never runs — the probe package's tests live in the package and run from Terminal
   (Part 2), not from this app.
9. Leave **Host in CloudKit** unticked. Click **Next**.
7. Save it in `~/Documents` (**not** inside the Thro-Darts-App folder). Click **Create**.

### 3b. Point it at the probe

1. Menu bar: **File → Add Package Dependencies…**
2. Bottom-left of that window: **Add Local…**
3. Navigate to `Documents/Thro-Darts-App/packages/durability-probe` and click **Add Package**.
4. When it asks which target to add it to, choose **ThroProbe**. Click **Add Package**.

### 3c. Two lines of code

In the left sidebar click **ContentView.swift**. Select everything (⌘A) and replace it with:

```swift
import SwiftUI
import DurabilityProbe

struct ContentView: View {
    var body: some View { ProbeView() }
}
```

### 3d. Let Xcode sign it

You need an Apple ID; a free one works for running on your own device.

1. **Xcode → Settings… → Accounts →** the **+** button → **Apple ID** → sign in.
2. Close Settings.
3. In the left sidebar click the blue **ThroProbe** at the very top.
4. Click the **Signing & Capabilities** tab.
5. Tick **Automatically manage signing**, and pick your name in the **Team** dropdown.

### 3e. Put it on the phone

1. Plug the iPhone in with a cable. Unlock it. Tap **Trust** if it asks.
2. On the iPhone: **Settings → Privacy & Security → Developer Mode → on**, then restart the phone
   when it asks. (iOS 16 and later. It only appears once a Mac with Xcode has been connected.)
3. Back in Xcode, at the top of the window there is a dropdown that probably says a simulator name.
   Click it and pick **your iPhone** under "Devices".
4. Press the **▶︎ Play** button (or ⌘R).
5. First run only: the phone will refuse to open it. On the iPhone go to
   **Settings → General → VPN & Device Management**, tap your Apple ID, tap **Trust**. Then press
   Play again.

### 3f. Take the measurement

1. The app opens with one button. Put the phone down — do not keep the screen busy.
2. Tap **Run the probe**. It takes maybe 30 seconds.
3. Screenshot the four rows, or read them out.

> **Do not use the Simulator for this.** Simulator storage is your Mac's SSD. The app will warn you
> in orange if it detects one. A simulator number is not a weaker version of the answer — it is an
> answer to a different question.

---

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
