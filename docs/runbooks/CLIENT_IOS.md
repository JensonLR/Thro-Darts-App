# Running the iOS client

> **Verification status, 2026-09-05 (commit `e797458`).** Every package compiles and every test passes
> on macOS CI — 40 tests: 13 design, 11 journal, 16 scoring session — and the Xcode app builds for the
> iOS simulator on CI with Xcode 26.6, on every push that touches them. **Nobody has yet run this app
> on a phone.** The first run is the founder's, on the Mac with the phone plugged in; the local session
> records what it saw (screenshots go in `docs/runbooks/screenshots/`) and corrects this document where
> the phone disagrees with it. Until then, everything below "What you will see" is what the code does
> and what its tests hold, not what anyone has watched it do.

## What exists

| Where | What | Verified by |
|---|---|---|
| `packages/design-tokens` | the generated tokens as a Swift package, `ThroTokens` | `build.py --check`; consumed by every build below |
| `packages/engine-swift` | the scoring engine | conformance corpus on Linux, every push |
| `packages/statistics-swift` | the statistics layer, honest about its basis | twenty tests on Linux, every push |
| `packages/client-ios` → `ThroDesign` | the approved components as SwiftUI | tests on macOS, every push |
| `packages/client-ios` → `ThroJournal` | the on-device journal (ADR-006) | eleven tests on macOS, every push |
| `packages/client-ios` → `ThroPlay` | setup, ready, scoring, result | sixteen session tests on macOS, every push |
| `packages/client-ios` → `ThroApp` | Home, tabs, the root view | compiles for macOS and the iOS simulator on every push; drawn, not tested |
| `apps/ios/ThroDarts.xcodeproj` | the app target: thirteen lines that mount `ThroApp` | `xcodebuild` for the iOS simulator, every push |

## Running it on the phone

```bash
cd ~/Thro\ Darts\ App          # or wherever the checkout is
git pull
open apps/ios/ThroDarts.xcodeproj
```

1. In Xcode, select the `ThroDarts` target → **Signing & Capabilities**. Choose your **Team** (the
   personal team is fine). If Xcode says the bundle identifier `app.thro.darts` is taken, change it
   to anything under your own identifier; nothing depends on it.
2. Plug the phone in and unlock it. Choose it in the run destination menu at the top of the window.
   If Xcode says *"Your team has no devices from which to generate a provisioning profile"*, the
   phone is not connected or not trusted — that message is not about signing.
3. **Run** (⌘R). The first time, the phone will refuse to open the app until you trust the developer:
   Settings → General → VPN & Device Management → your Apple ID → Trust.

Or, without a phone: choose any iPhone simulator as the destination and Run. That is exactly what CI
does (`xcodebuild -scheme ThroDarts -destination 'generic/platform=iOS Simulator'`).

## What you will see

- **Home.** A warning that the fonts are not embedded (see below), then *No matches yet* with one
  action: **Start match**. Once matches exist, they are listed under *On this device* with the legs,
  the format, when they started, and *Self-reported* or *In progress*. Tapping one resumes it or
  opens its result. The tab bar's *Live*, *Discover* and *You* say plainly that they are not in this
  build.
- **Match setup** (dark). Two names, then 301 / 501 / 701, Bo3 / Bo5 / Bo7 / Bo9, and who throws
  first. Double out is the only out-rule offered. Empty names become *Home* and *Away*.
- **Match ready.** The two players, the format as tags, **Start scoring**.
- **Scoring** (dark). Header with the players and the format; legs and the other player's remaining;
  the thrower's remaining in the 96-point score face; a *Checkout available* card when the thrower is
  on a finish; the turn indicator; the keypad. Quick totals commit at once. Typed totals commit on
  **Enter**, which stays disabled until something is typed. The undo key clears the entry.
- **The two questions (PD-001).** When the visit **began on a checkout number**, the keypad is
  replaced by *Darts thrown at a double?* — 0 / 1 / 2 / 3, preset 0 — whether or not the visit
  finished. When the visit **wins the leg**, *Darts used to check out?* — 1 / 2 / 3, preset 3 — comes
  first, then darts at a double limited to the darts used. **Not sure** records unknown, never zero.
  **Cancel** submits nothing and keeps the entry.
- **Refusals** appear in the snackbar with the harness's wording — *179 cannot be scored with three
  darts.* — and change nothing. **Busts** show the restored score in red, name the reason when the
  engine gives one, and rotate the turn. A **won leg** announces itself and who throws next.
- **Result.** *{Winner} wins*, the legs, each player's six figures (3-dart average, first 9,
  checkout %, 180s, highest checkout, 140+) — exact as a number, bounded as a range that says so,
  unavailable as a dash with its reason — then *Not rated*, *Self-reported* with its explanation, and
  a line saying the result has not left the phone. **Done** or **Play again**.

## Where the data is

`Application Support/THRO/journal.sqlite` inside the app's container, in WAL mode with
`synchronous=FULL`, `fullfsync` and `checkpoint_fullfsync` — the configuration ADR-006 measured. The
journal refuses to open under any other configuration. Deleting the app deletes the journal; there is
no export yet.

Every visit is committed to that file **before** the screen updates (`MatchSession.submit`). If the
commit fails, the screen says *Not saved, so not scored* and the state does not change.

## Fonts

Archivo and IBM Plex Sans Condensed are **not embedded**: the licence is open item B3. The type roles
name the faces; when the faces are not registered, the system face is used and Home shows *Fonts not
embedded* rather than substituting silently. To embed them once licensed: add the font files to the
`ThroDarts` target, add `UIAppFonts` (*Fonts provided by application*) with their filenames to the
target's Info settings, and the notice disappears on its own — `ThroFont.customFacesRegistered`
asks the system for the faces by family name.

## What the design does not specify, and what this build does about it

Read against `docs/design/DESIGN_UNSPECIFIED.md`. Nothing here decides an item; each keeps the
platform's own behaviour or renders the honest minimum, and says so.

| Item | This build |
|---|---|
| 1 Dynamic Type | Type roles scale through `relativeTo`; spacing and radius do not (ADR-010). **No clamps** — at accessibility sizes the 96/88 score face will clip. |
| 2 Pressed / focus | The platform's own. Nothing removed (the export removed the text field's focus ring; SwiftUI's stays). |
| 5 Safe areas | The platform's: content respects them, only backgrounds paint under them. |
| 7 Attestation | Not in the app. The harness asks the non-throwing player to confirm each leg on the same device; the app does not, because a confirmation with no identity behind it is not the participant-confirmed state PD-002 describes. **Every result is self-reported.** |
| 9 Stat basis | Bounded is a range, unavailable is a dash; the reason is shown in the metadata role beneath. |
| 11 Offline-completed result | *Self-reported*; and because no sync exists, the screen says the result has not left the phone rather than showing a *Queued* that promises one. |
| 15 Disabled | The export's opacity multiplier. |
| 18 Invalid score feedback | The engine's refusal in the snackbar, in the harness's words. |
| 20 Dark mode | Dark is contextual as in the export: setup and scoring are dark, the rest follow the system appearance. |
| 23 Landscape | The Xcode template's orientations are left as they are; the scoring screen has no landscape design. |
| 24 Truncation | Names truncate with an ellipsis in the header, the identity, and the Home rows. |
| 25 Haptics | None. |

Composed from the export's components because the export does not draw them:

- A **two-player local match setup**, after the export's only setup screen (Shadow's).
- The **PD-001 questions**, in the keypad's place, from Eyebrow, heading, Button.
- A **TopBar above the MatchHeader** so a player can leave the scoring screen; the journal makes
  leaving safe.
- **Play again** on the result, from the Shadow result.

Read differently from the JSX, on purpose: Enter disabled on an empty entry (the export scores 0);
the undo key clears the entry (the export labels it *Undo last score* and every screen uses it to
clear; the journal is append-only and corrections are not built); the segmented control's segment
is 44 points, not the export's 40; the checkout card shows the number and no route, because no
route table exists in this repository.

## What is not built

No network, sync or server calls of any kind — the module graph has no network target, which is how
LATENCY_BUDGETS.md's structural requirement is enforced. No attestation, no rating (OD-001), no
identity or sign-in (item 6), no organiser surface, no Live / Discover / You. The app scores a match
between two people on one phone and keeps it. That is all it claims.

## Checking it yourself

```bash
swift test --package-path packages/client-ios          # design, journal, play tests (macOS)
swift test --package-path packages/statistics-swift    # the twenty honesty tests (any platform)
xcodebuild -project apps/ios/ThroDarts.xcodeproj -scheme ThroDarts \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```
