# Handoff to a local Claude Code session on macOS

> **Resolved on 2026-09-04.** The measurement this handoff exists to obtain has been taken:
> `iPhone15,3` (iPhone 14 Pro Max), iOS 26.1, two consecutive runs, recorded in the "Measurement
> status" section of `docs/adr/ADR-006-offline-sync.md`. The deciding row measured P95 1.64 / 1.60 ms
> against the 20 ms budget, so SQLite stays the journal.
>
> The document is kept because the same handoff is still needed for what remains — the SE-class
> iPhone, the Android reference device, and the kill and power-cut tests — and because the setup
> notes below are what made the run possible. Two things it got wrong are worth knowing: the Xcode
> project is at `~/Thro Darts App/ThroProbe`, not `~/Documents`, and the blockage was never signing.
> It was that no phone was plugged in; Apple reports that as "Your team has no devices from which to
> generate a provisioning profile", which reads like a signing error. `scripts/run-probe-on-device.sh`
> now checks for the phone first and drives the whole run from the command line.

The remote session that built this branch runs in a Linux container. It has no Swift toolchain, no
Xcode, and no access to the founder's Mac — it can only see what is pasted into the chat. That is
fine for everything up to here, and useless for the one task that remains: taking the durability
measurement on a physical iPhone.

A local session can read the Xcode project, run `xcodebuild`, and talk to the device. Paste the
prompt below into one.

## Setting it up

```bash
cd ~/Documents/Thro-Darts-App
git pull
claude
```

Then paste the prompt. If `claude` is not installed, see https://code.claude.com/docs — the macOS
native installer is `curl -fsSL https://claude.ai/install.sh | bash`. The Claude desktop app for Mac
works too; point it at the same folder.

---

## The prompt

```
You are continuing work on THRØ, a competitive darts infrastructure platform. This repository is at
~/Documents/Thro-Darts-App on branch claude/thro-production-build-je2mkf, with draft PR #1 open. All
CI is green. Do not rename the product.

## The one task

ADR-006 will not let the client architecture be fixed until the durability latency of a single visit
write has been MEASURED on a physical iOS device. That measurement does not exist yet, and it is the
only thing blocking Gate 5. It cannot be reasoned about, only measured, and not on a Mac.

`packages/durability-probe` is that measurement. It compiles and its four tests pass — verified both
on this Mac and on macOS CI. Part 2 of docs/runbooks/DURABILITY_MEASUREMENT.md (running it on the
Mac) is DONE and its numbers are already recorded in ADR-006 as indicative only.

Part 3 — the on-device run — is where the founder is stuck.

## Current state of the blockage

An Xcode project `ThroProbe` was created in ~/Documents (iOS App, SwiftUI, Storage: None, Testing
System: None, organisation identifier `com.thro`). The founder has signed into Xcode with their
Apple ID. They are stuck at Signing & Capabilities and have never used Xcode before.

The remote session could only guess at what was on screen. You cannot afford to do the same, and you
do not have to:

- Read `ThroProbe.xcodeproj/project.pbxproj` directly.
- `xcodebuild -showBuildSettings` for the real signing configuration.
- `xcrun devicectl list devices` to see whether the iPhone is visible and trusted.
- `security find-identity -v -p codesigning` for the signing identities that actually exist.

Diagnose from the machine, not from a description of it.

Strongly consider skipping the Xcode GUI entirely. `xcodebuild -allowProvisioningUpdates` can build
and install to a connected device from the command line, and doing it that way means the steps are
reproducible and you can see every error in full rather than as a red badge. Creating the project
programmatically is also on the table if the existing one is in a bad state.

Two failures to expect: a bundle identifier collision (identifiers are globally unique across all
Apple developer accounts, and `com.thro.ThroProbe` is generic enough to be taken — any unique
replacement is fine, the app never ships), and Developer Mode not being enabled on the iPhone
(Settings > Privacy & Security > Developer Mode, then a restart).

## What done looks like

The app runs on the physical iPhone, the founder taps "Run the probe", and four rows appear with
P50/P95/P99/worst per SQLite configuration. Record those numbers in the "Measurement status" section
of `docs/adr/ADR-006-offline-sync.md`, alongside the two Mac runs already there, WITH the iPhone
model and iOS version. A latency without its hardware is not evidence. Then commit and push to
claude/thro-production-build-je2mkf.

## Rules that carry over, and are not negotiable

- The measurement is evidence. Record what the device reports, including a result that exceeds the
  budget. If the strongest configuration exceeds P95 20 ms, ADR-006 is explicit that the durability
  rule wins and the budget is restated — that is a real outcome with a real cost (a second storage
  engine on both clients), and it must not be massaged into a pass.
- Never disable a test, weaken an assertion, hardcode a passing result, or silence a warning to make
  something go green.
- Never claim production readiness that has not been demonstrated.
- No secrets in the repository, the bundle, logs, or screenshots.
- Do NOT use the iOS Simulator for the measurement. Simulator storage is the Mac's SSD, so it
  answers a different question. The app shows an orange warning if it detects one.
- The probe measures LATENCY, not durability. It proves the pragmas changed behaviour; it does not
  prove the write reached NAND. Only a power-cut test does that, and it is still outstanding. Do not
  let the numbers be read as more than they are.

## What NOT to do

- Do NOT start building the iOS client application. ADR-006 forbids fixing the client architecture
  until this measurement exists. Getting the measurement is the whole job.
- Do NOT start new feature work. The build is at a deliberate stopping point: everything specified
  in the ADRs that does not need a founder decision or a mobile toolchain is built and green.
- Five decisions are blocked on the founder and must not be invented: B3 (design commissions), B4
  (authentication surface — the mechanism is built, the flows cannot be guessed), OD-001 (the rating
  model), OD-010 (safeguarding thresholds), OD-013 (whether a retirement may rate).

## Read before starting

- docs/runbooks/DURABILITY_MEASUREMENT.md — the procedure, written for someone who has never opened
  Xcode
- docs/adr/ADR-006-offline-sync.md — the "Measurement status" section, for what is already known and
  what the measurement decides
- packages/durability-probe/Sources/DurabilityProbe/ProbeView.swift — the one-tap front end
- packages/durability-probe/Sources/DurabilityProbe/Probe.swift — what is actually being timed

The founder has never used Xcode. Give exact steps, ask what they are actually seeing rather than
assuming menu names (Xcode 26 renamed things), and prefer doing it yourself over talking them
through a GUI.
```
