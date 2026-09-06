# Running the iOS client

> **Verification status, 2026-09-06.** Every package compiles and every test passes on macOS CI — 55
> tests: 16 design, 15 journal, 24 scoring session — and the Xcode app builds for the iOS simulator on
> CI with Xcode 26.6, on every push that touches them. **The app has run on a phone**: the founder's,
> the evening of 2026-09-05, a full best-of-3 from setup to result, in dark mode, on an iPhone 14 Pro Max
> (MQ9P3ZD/A) running iOS 26.6.1. Nine screenshots came back; what they showed is under "First run on
> a phone" below, with the defects they exposed and what was done about each.

## What exists

| Where | What | Verified by |
|---|---|---|
| `packages/design-tokens` | the generated tokens as a Swift package, `ThroTokens` | `build.py --check`; consumed by every build below |
| `packages/engine-swift` | the scoring engine | conformance corpus on Linux, every push |
| `packages/statistics-swift` | the statistics layer, honest about its basis | twenty tests on Linux, every push |
| `packages/client-ios` → `ThroDesign` | the approved components as SwiftUI | tests on macOS, every push |
| `packages/client-ios` → `ThroJournal` | the on-device journal (ADR-006), with retractions (PD-004) | fifteen tests on macOS, every push |
| `packages/client-ios` → `ThroPlay` | setup, ready, scoring, result, undo | twenty-four session tests on macOS, every push |
| `packages/client-ios` → `ThroApp` | Home, tabs, You, Settings, the root view | compiles for macOS and the iOS simulator on every push; drawn, not tested |
| `apps/ios/ThroDarts.xcodeproj` | the app target: thirteen lines that mount `ThroApp` | `xcodebuild` for the iOS simulator, every push |

## Running it on the phone, step by step

Written for someone who has never used Xcode. The phone has already run the durability probe, so the
Mac, the cable, the Apple ID and the phone's Developer Mode are all known to work; nothing below asks
for anything new.

### 1. Get the latest code

1. Open **Terminal** (press ⌘ Space, type `Terminal`, press Return).
2. Find the checkout. `~/Thro Darts App` holds the ThroProbe Xcode project and is **not** the git
   clone — `git status` there says *not a git repository*. Look for the clone:
   ```bash
   ls -d ~/Thro-Darts-App ~/Documents/Thro-Darts-App 2>/dev/null
   ```
3. If a path printed, use it and bring it up to date:
   ```bash
   cd ~/Documents/Thro-Darts-App        # or whichever path printed
   git checkout claude/thro-production-build-je2mkf
   git pull
   ```
   If nothing printed, clone afresh — the repository is public, so no login is needed:
   ```bash
   cd ~
   git clone -b claude/thro-production-build-je2mkf https://github.com/JensonLR/Thro-Darts-App.git
   cd Thro-Darts-App
   ```
4. `git status` should now say `On branch claude/thro-production-build-je2mkf`.
5. Open the app project — **this one, not ThroProbe**:
   ```bash
   open apps/ios/ThroDarts.xcodeproj
   ```
   Xcode opens. The window title reads **ThroDarts**. If it reads ThroProbe, close that window and
   run the command again.

### 2. Tell Xcode who signs it (first time only)

6. Wait for the small status area at the top of the window to finish *Resolving Package Graph*; a
   few seconds. Xcode is reading the four local packages.
7. In the left-hand column, click the very top item — the blue project icon labelled **ThroDarts**.
8. In the middle of the window, under the heading **TARGETS**, click **ThroDarts** (the row with the
   app icon). Not the row under PROJECT.
9. Click the **Signing & Capabilities** tab along the top of that panel.
10. **Automatically manage signing** should be ticked. In the **Team** menu choose your own name —
    the *Personal Team* you used for ThroProbe.
11. If red text appears saying the bundle identifier is not available, click into **Bundle
    Identifier**, replace `app.thro.darts` with `com.thro.ThroDarts` (your ThroProbe identifier used
    `com.thro`, so this will be free), and press Return. The red text goes away.

### 3. Run it

12. Unlock the phone and plug it in. If the phone asks whether to trust this computer, tap **Trust**.
13. At the top centre of the Xcode window is the run destination: it reads **ThroDarts ▸ something**.
    Click the *something* and choose your iPhone by name from the list. Not a simulator.
14. Press **⌘R** (or the ▶ button at the top left). The first build compiles four packages and takes
    a minute or two. The status area shows *Building…* then *Running ThroDarts on <your phone>*.
15. If Xcode says Developer Mode is disabled: on the phone, Settings → Privacy & Security →
    Developer Mode → on, then let the phone restart, and press ⌘R again.
16. If the phone shows *Untrusted Developer* when the app tries to open: Settings → General → VPN &
    Device Management → tap your Apple ID → **Trust**, then open the app from the home screen. This
    is the same certificate ThroProbe used, so it is probably already trusted.
17. The app opens on **Home**: a light screen, a yellow *Fonts not embedded* notice, *No matches yet*
    and a **Start match** button, with a tab bar along the bottom.

### 4. The first-run test plan

Everything below is what the tests assert; the phone is the first place anyone watches it happen.

- **Start match** → *Match setup* (dark). Type two names, keep **501**, choose **Bo3**, pick who
  throws first, **Continue**. *Match ready* shows both players and the format; **Start scoring**.
- **A refusal.** Tap **1 7 9** then **Enter 179**. A red bar says *179 cannot be scored with three
  darts.* and nothing else changes. The undo key clears the entry.
- **A normal visit.** Tap the **180** quick key. The remaining drops, the turn indicator names the
  other player. Give them a **60**.
- **A finish position.** Give the first player another **180** (321 → 141). A *Checkout available*
  card appears and the remaining turns brand-green. Give the second player **60**.
- **The first question.** For the first player tap **1 0 0**, **Enter**. Instead of the keypad:
  *Darts thrown at a double?* with 0 / 1 / 2 / 3 — because 141 was a finish, even though this visit
  did not take it. Tap **0**. Remaining 41.
- **A bust.** Second player: any total. First player: tap **6 0**, **Enter**. It asks the double
  question first (41 is a finish); answer, and the score shows in red as *Bust — score restored*
  with *Bust. Score restored to 41. <name> to throw.* The keypad's next tap clears the red.
- **The finish.** Second player again; then first player **4 1**, **Enter**. *Darts used to check
  out?* → tap **2**. *Darts thrown at a double?* now offers only 1 / 2 → tap **1**. The bar says
  *Leg 1 to <name>. <other> to throw.* and the legs read 1–0.
- **Kill it mid-leg.** Swipe up from the bottom and pause, swipe the app away, open it again. Home
  lists the match as *In progress*; tap it → *Match ready* → **Continue scoring** → the same score
  and the same player to throw. That is the journal doing its job.
- **Finish the match** (first to two legs in Bo3) → *Result*: *<name> wins*, the legs, six figures
  per player, **Not rated**, **Self-reported** with its explanation, and the line saying the result
  has not left the phone. **Done** returns Home, where the match is listed with its legs.
- The back chevron leaves scoring at any point; nothing is lost.

### 5. What to send back

Screenshots of Home, setup, scoring in its normal state, the checkout card, a question card, the
bust, and the result — into `docs/runbooks/screenshots/` — plus the phone's exact model and iOS
version (Settings → General → About → *Model Name* and *iOS Version*). Where the phone disagrees
with this document, the phone is right.

### If something goes wrong

| Xcode says | Do |
|---|---|
| *Could not resolve package dependencies* | File → Packages → **Reset Package Caches**, then ⌘R |
| *No such module 'ThroApp'* | Product → **Clean Build Folder** (⇧⌘K), then ⌘R |
| *Signing for "ThroDarts" requires a development team* | Step 10 was skipped |
| *Your team has no devices from which to generate a provisioning profile* | The phone is not connected or not trusted; it is not a signing problem |
| *Unable to install… device is locked* | Unlock the phone, ⌘R again |
| Any other red error | Copy the red text in full and send it; do not guess at it |

Without a phone: choose any iPhone simulator as the destination at step 13 and press ⌘R. That is
exactly what CI does (`xcodebuild -scheme ThroDarts -destination 'generic/platform=iOS Simulator'`).

## What you will see

- **Home.** A warning that the fonts are not embedded (see below), then *No matches yet* with one
  action: **Start match**. Once matches exist, they are listed under *On this device* with the legs,
  the format, when they started, and *Self-reported* or *In progress*. Tapping one resumes it or
  opens its result. The tab bar's *Live* and *Discover* say plainly that they are not in this build;
  *You* says the profile is not built and carries the export's settings action in its header.
- **Settings** (from the gear on You). **Appearance: System / Light / Dark** — every screen follows
  it, scoring included (PD-003); **Scoring → Keep screen awake**, on by default as the export's
  Settings lists it; and a *This build* group stating what is true: matches stay on the device,
  sending to THRØ is not built, which face the fonts are, no account.
- **Match setup** (dark). Two names, then 301 / 501 / 701, Bo3 / Bo5 / Bo7 / Bo9, and who throws
  first. Double out is the only out-rule offered. Empty names become *Home* and *Away*.
- **Match ready.** The two players, the format as tags, **Start scoring**.
- **Scoring**. A back chevron and the header with the players and the format; legs and the other
  player's remaining; the thrower's remaining in the 96-point score face, green when they are on a
  finish, with a *Checkout available* card beneath; the turn indicator; the keypad. Nothing scrolls
  and nothing is cut off: everything above the keypad shares the height the keypad leaves, and on a
  short phone the numeral shrinks first. The phone stays awake while this screen is up (Settings →
  Scoring). Quick totals commit at once. Typed totals commit on
  **Enter**, which stays disabled until something is typed. The undo key clears the entry; with
  nothing typed it offers to **undo the last visit** (PD-004): *Strike Man's 100?* with **Undo** and
  **Keep**. Undoing appends a retraction — the struck visit stays in the record, replay skips it, the
  statistics never see it — and the score goes back. Undo again to walk further back.
- **The two questions (PD-001).** When the visit **began on a checkout number**, the keypad is
  replaced by *Darts thrown at a double?* — 0 / 1 / 2 / 3, preset 0 — whether or not the visit
  finished. When the visit **wins the leg**, *Darts used to check out?* — 1 / 2 / 3, preset 3 — comes
  first, then darts at a double limited to the darts used. **Not sure** records unknown, never zero.
  **Cancel** submits nothing and keeps the entry.
- **Refusals** float over the top of the scoring area with the harness's wording — *179 cannot be
  scored with three darts.* — change nothing, and clear on the next key. **Busts** and **won legs**
  put a card over the screen for both players (PD-005): the bust card leads with the score the player
  is left on, in red, with the reason when the engine gives one and who throws now; the leg card
  leads with the legs as they stand and who throws first next. **Continue** (or a tap on the scrim)
  resumes scoring; the keypad waits until then. Under the card the restored score stays red on the
  hero until the next key.
- **Result.** *{Winner} wins*, the legs, each player's six figures (3-dart average, first 9,
  checkout %, 180s, highest checkout, 140+) — exact as a number, bounded as a range that says so,
  unavailable as a dash with its reason — then *Not rated*, *Self-reported* with its explanation, and
  a line saying the result has not left the phone. **Done**, **Play again**, or **Undo last visit** for
  the mis-key that ended the match, which reopens it.

## First run on a phone

2026-09-05, the founder, dark mode, iPhone 14 Pro Max (MQ9P3ZD/A), iOS 26.6.1. Setup → ready → scoring → result, a full
best-of-3 ("Man v Woman", 0–2), then Home listing it as *Self-reported*. Screenshots: Play, Home with
the match *In progress*, scoring with the thrower on 141, the *Darts thrown at a double?* card after a
100 from 141, a bust from 41 with *Bust. Score restored to 41. Man to throw.*, the result (two screens),
Home after, and Match setup.

What worked as the tests say: the PD-001 question appearing only when the visit began on a finish;
the bust restoring the score and rotating the turn; the result's honest figures — a player who never
reached a finish shows a dash under *Checkout %* with its reason, the other shows 100 % from one
attempt; *Not rated*; *Self-reported* with its explanation; the match surviving the trip back to Home
and reopening at the same score.

What the phone disagreed with, and what changed:

| Seen | Cause | Change |
|---|---|---|
| Home, Play, ready and result rendered **dark** | the phone was in dark mode and those screens followed the system appearance | those screens now set light on both the window and their own environment; the export draws them light and has no dark variant |
| on the scoring screen the **checkout card was cut off** and the turn indicator pushed below the keypad | a TopBar above the MatchHeader added 64 points the screen does not have | the TopBar is gone; a 44-point back chevron sits at the header's leading edge; the vertical paddings are the export's own |
| the loser's *Highest checkout* said *No leg has been won yet, so there is nothing to report* — false on a result where the other player won two | the statistics note was written for one player's log and read as if about the match | both implementations now say *This player has not won a leg, so there is no checkout to report* (and the same for best leg); no test asserted the old words, and the six-word floor still holds |

**Second run, the same night, on commit `690e36d`.** Five screenshots: Home light with the finished
match listed as *Self-reported*; the result light, *Woman wins* in brand green, the loser's highest
checkout reading *This player has not won a leg, so there is no checkout to report*; Match setup dark;
scoring dark with the back chevron in the header and the remaining, turn indicator and keypad all on
screen at once; Match ready light with both players, the three format tags and *Start scoring*. All
three fixes above are confirmed on the device. The status bar text follows each screen's scheme.

Still to add: the screenshots themselves into `docs/runbooks/screenshots/`.

**Then the founder decided** (PD-003): the player chooses the appearance. The You tab now carries
System / Light / Dark; setup and scoring stay dark as drawn.

**Third run, 2026-09-06, on commit `e9382ad`.** The founder confirmed the retraction, the appearance
choice on every screen and the Settings screen, and found one thing wrong: with the thrower on a
finish the scoring screen scrolled and the checkout card was cropped. Two founder decisions followed
and are built in the commits after it: the scoring screen no longer scrolls (everything above the
keypad fits, the checkout card names the fact and not the number, the numeral shrinks before it clips),
and a bust or a won leg is announced on a card both players see (PD-005).

What to check on the next run, in this order:

1. Scoring with the thrower on a finish: the *Checkout* card, the turn indicator and the keypad all on
   screen, nothing scrolls.
2. A bust: the card with the score the player stays on, the reason when there is one (*That leaves 1.*
   or *N cannot be finished on a double.*), and who throws; the keypad ignores taps until *Continue*
   or a tap on the dimmed screen.
3. A won leg: the card with the legs as they stand and who throws first in the next leg.
4. A won match: no card; the result screen.
5. Settings → Scoring → *Keep screen awake*: with it on, the phone does not dim during scoring.
6. Match setup: names capitalise as you type; *Next* on the keyboard moves to the away player; *Done*
   puts the keyboard away; so does dragging the form. Please say whether *Next* moved the cursor —
   that is the one behaviour this build could not verify without a device.
7. With VoiceOver on, a bust: focus lands on the card and it reads as one sentence, then *Continue*.

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
| 1 Dynamic Type | Type roles scale through `relativeTo`; spacing and radius do not (ADR-010). **No clamps.** The score numeral alone may shrink (to half) when the screen is too short for it, so it never clips or scrolls; that is a floor, not a design. |
| 2 Pressed / focus | The platform's own. Nothing removed (the export removed the text field's focus ring; SwiftUI's stays). |
| 5 Safe areas | The platform's: content respects them, only backgrounds paint under them. The scoring screen is laid out to the height the keypad leaves, so nothing scrolls. |
| 7 Attestation | Not in the app. The harness asks the non-throwing player to confirm each leg on the same device; the app does not, because a confirmation with no identity behind it is not the participant-confirmed state PD-002 describes. **Every result is self-reported.** |
| 9 Stat basis | Bounded is a range, unavailable is a dash; the reason is shown in the metadata role beneath. |
| 11 Offline-completed result | *Self-reported*; and because no sync exists, the screen says the result has not left the phone rather than showing a *Queued* that promises one. |
| 15 Disabled | The export's opacity multiplier. |
| 16 Modal behaviour | The bust and leg card (PD-005) uses the Dialog surface and the scrim token; it dismisses on its button or a scrim tap, traps nothing, animates nothing. |
| 18 Invalid score feedback | The engine's refusal in the snackbar, in the harness's words. |
| 20 Dark mode | **Decided by the founder (PD-003, amended):** System / Light / Dark in Settings, governing every screen, scoring included. Each screen's undrawn rendering — dark Home, light scoring — is the token layer's, unreviewed by design. |
| 23 Landscape | **Portrait only**, as every screen in the export is drawn. A landscape scoring screen would need a design. |
| 24 Truncation | Names truncate with an ellipsis in the header, the identity, and the Home rows. |
| 25 Haptics | None. |

Composed from the export's components because the export does not draw them:

- A **two-player local match setup**, after the export's only setup screen (Shadow's).
- The **PD-001 questions**, in the keypad's place, from Eyebrow, heading, Button.
- A **back chevron at the MatchHeader's leading edge** so a player can leave the scoring screen; the
  journal makes leaving safe. (A TopBar above the header was tried first and cost 64 points the
  scoring screen does not have — see the first run.)
- **Play again** on the result, from the Shadow result.
- The **undo confirmation** (PD-004), in the keypad's place, from Eyebrow, heading, Button; and
  **Undo last visit** on the result.
- A **Settings** screen after the export's own, with only the rows that are true of this build, the
  appearance control in place of a row that would go nowhere, and the platform's switch for *Keep
  screen awake* (the export draws no toggle).
- The **bust and won-leg card** (PD-005), from the Dialog surface, the sport hero face and Button.

Read differently from the JSX, on purpose: Enter disabled on an empty entry (the export scores 0);
the undo key clears the entry (the export labels it *Undo last score* and every screen uses it to
clear; the journal is append-only and corrections are not built); the segmented control's segment
is 44 points, not the export's 40; the checkout card shows the number and no route, because no
route table exists in this repository.

## What is not built

No network, sync or server calls of any kind — the module graph has no network target, which is how
LATENCY_BUDGETS.md's structural requirement is enforced. No attestation, no rating (OD-001), no
identity or sign-in (item 6), no organiser surface, no Live / Discover / profile. No online matches,
so no opponent-approved retraction (PD-004 point 3). The app scores a match between two people on one
phone, lets them undo a mis-key, and keeps it. That is all it claims.

## Checking it yourself

```bash
swift test --package-path packages/client-ios          # design, journal, play tests (macOS)
swift test --package-path packages/statistics-swift    # the twenty honesty tests (any platform)
xcodebuild -project apps/ios/ThroDarts.xcodeproj -scheme ThroDarts \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```
