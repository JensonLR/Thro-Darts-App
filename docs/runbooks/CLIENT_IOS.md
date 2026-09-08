# Running the iOS client

> **Verification status, 2026-09-07.** Every package compiles and every test passes on macOS CI —
> 410 tests in all: 55 design, 90 journal, 61 scoring session and share card, 179 opening, app and clubs, 25 Lock Screen, wall and widgets — and the
> Xcode app builds for the iOS simulator on
> CI with Xcode 26.6, on every push that touches them. **The app has run on a phone**: the founder's,
> the evening of 2026-09-05, a full best-of-3 from setup to result, in dark mode, on an iPhone 14 Pro Max
> (MQ9P3ZD/A) running iOS 26.6.1. Nine screenshots came back; what they showed is under "First run on
> a phone" below, with the defects they exposed and what was done about each.

## What exists

| Where | What | Verified by |
|---|---|---|
| `packages/design-tokens` | the generated tokens as a Swift package, `ThroTokens` | `build.py --check`; consumed by every build below |
| `packages/engine-swift` | the scoring engine | conformance corpus on Linux, every push |
| `packages/statistics-swift` | the statistics layer, honest about its basis | 25 statistics tests on Linux, every push |
| `packages/client-ios` → `ThroDesign` | the approved components as SwiftUI | 55 design tests on macOS, every push |
| `packages/client-ios` → `ThroJournal` | the on-device journal (ADR-006), with retractions (PD-004), and its own device identity; and the **club book**, the separate database a captain's roster and fixture list live in | 90 journal tests on macOS, every push — 43 on the journal itself, 14 on the device's book of clubs and people, 14 on the export and what it refuses to read back, 8 on images, and 11 on the league book — teams, results, units and what the database refuses to write |
| `packages/client-ios` → `ThroPlay` | setup, ready, scoring, result, undo, the bust and leg announcements, double-in (PD-008), the checkout route (PD-013), confirming the result (PD-011) and the share card | 61 session tests on macOS, every push |
| `packages/client-ios` → `ThroApp` | Home, tabs, Settings, the root view, the opening (PD-007), and the club, league, tournament and profile screens under Discover (PD-009, PD-010) | 179 app tests on macOS, every push: 13 on the opening (timeline, the tagline's read time, cues, easings, geometry, the throw, the chalk stroke, the wall's dust, the dart), 15 on Home's reading of the journal, the device identity, the shelf and what a delete refuses to do (PD-026), 5 on the club rules the screens obey, 14 on the mapping between the club book and those screens, 7 on who may have a picture, who is told why not, and what a page's top bar offers, 16 on a club, a league and a tournament being three different things, 10 on the knockout draw — the seeding identities for every bracket to 256, the byes, a whole tournament played through, and a knockout match that cannot end level — 10 on double elimination, including a whole one played out and every entrant but the champion checked to have lost exactly twice, and 11 on groups then knockout, including that nobody is drawn against their own group in the first round across all fifteen setups, and that the note shown to a tournament with no shape yet says something different to each of its three readers — the table's arithmetic and its total ordering, where each result came from, and what each tournament shape counts. 26 on **what this build can show you on the phone it is running on** — five states told apart, an unasked permission never reported as a refusal nor answered with a trip to iPhone Settings, every row carrying a sentence you could find something by, the four rows with nowhere to send anybody never growing a button, and every complete match counted as shareable including an abandoned one, which the first version of that count got wrong. The layouts themselves are drawn, not tested — and until 2026-09-07 nothing checked that a screen could be reached at all, which is how the club editor sat unroutable |
| `apps/ios/ThroDarts.xcodeproj` | the app target: thirteen lines that mount `ThroApp`, the ten embedded faces with their licences, the icon and the launch screen (PD-006) | `xcodebuild` for the iOS simulator, every push; `check_fonts.py` on Linux, every push |

## Running it on the phone, step by step

Written for someone who has never used Xcode. The phone has already run the durability probe, so the
Mac, the cable, the Apple ID and the phone's Developer Mode are all known to work; nothing below asks
for anything new.

### 1. Get the latest code

1. Open **Terminal** (press ⌘ Space, type `Terminal`, press Return).
2. The clone is **`~/Thro-Darts-App`** (hyphens). `~/Thro Darts App` (spaces) holds the ThroProbe
   Xcode project and is not a git clone; `~/Documents/Thro-Darts-App` is an older second clone — leave
   it alone. Paste these lines one at a time, without anything after them on the line:
   ```bash
   cd ~/Thro-Darts-App
   git status --short
   ```
3. If `git status --short` printed `M apps/ios/ThroDarts.xcodeproj/project.pbxproj`, that is the
   change Xcode made when you chose your signing team, and **it is what stops `git pull`** ("Your
   local changes to the following files would be overwritten by merge"). Set it aside, then pull:
   ```bash
   git checkout -- apps/ios/ThroDarts.xcodeproj/project.pbxproj
   git checkout claude/thro-production-build-je2mkf
   git pull origin claude/thro-production-build-je2mkf
   git log -1 --oneline
   ```
   The last command prints the commit you are about to build. Compare it with the newest commit at the
   top of the PR's *Commits* tab (https://github.com/JensonLR/Thro-Darts-App/pull/1/commits). If they
   differ, paste the whole Terminal output back rather than building. (Once your Team ID is committed
   to the project — see step 2 of the signing section — Xcode has nothing to change and this step
   becomes a plain pull.)
   If nothing printed, clone afresh — the repository is public, so no login is needed:
   ```bash
   cd ~
   git clone -b claude/thro-production-build-je2mkf https://github.com/JensonLR/Thro-Darts-App.git
   cd Thro-Darts-App
   ```
4. `git status` should now say `On branch claude/thro-production-build-je2mkf`.
   **Which build is on the phone right now?** In the app, You → gear → *This build* → **Build** shows
   the commit the running app was made from (a `+` after it means the checkout had uncommitted
   changes when it was built). If that row is missing, the phone is running a build older than
   2026-09-06 and needs the steps above.
5. Open the app project — **this one, not ThroProbe**:
   ```bash
   open apps/ios/ThroDarts.xcodeproj
   ```
   Xcode opens. The window title reads **ThroDarts**. If it reads ThroProbe, close that window and
   run the command again.

### 2. Signing is already set

The founder's Team ID (`2XM324WPD5`, a public identifier that appears in every provisioning profile,
not a secret) is committed in `project.pbxproj` with automatic signing, since 2026-09-06. Xcode finds
the team already chosen and changes nothing, so `git pull` stays a plain pull. Before that, choosing
the team in Xcode wrote the ID into the tracked project file, and every later pull refused to run over
that local change — which is how the phone stayed on the 5 September build for a day. If Xcode ever
shows a signing error on a different Mac, the Apple ID that owns that team must be signed in under
Xcode → Settings → Accounts; nothing in the project needs to change.

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

#### The App Group, if Xcode asks

The Home Screen and Lock Screen widgets read a small file the app writes into a container both share,
called `group.app.thro.darts`. Both targets already carry the entitlement — the two `.entitlements`
files are committed and `tools/check_app_group.py` holds them in agreement on every push — so on a
team that has automatic signing this normally needs nothing.

If Xcode shows a red line about the App Group on either target: on that target's **Signing &
Capabilities** tab, press **+ Capability**, choose **App Groups**, and tick or add
`group.app.thro.darts`. Xcode registers it with your account as it does so. Do that on **ThroDarts**
and on **ThroLive**; they must be the same group or the widgets read an empty container.

**Nothing else breaks if this is not done.** `containerURL` returns nil for a group the process is
not in, the app quietly writes nothing, and the widgets show their empty state. The app, the Lock
Screen scoreboard and everything else work exactly as before — only the Home Screen widget is blank.
There is no crash and no error to chase.

### 3. Run it

If the app on the phone looks unchanged after a pull, first check Settings → *This build* → **Build**
against `git log -1 --oneline`. If they differ, go back to step 1. If they match and something still
looks stale, Product → Clean Build Folder (⇧⌘K), then Run again.

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
17. The icon on the home screen is the mark — the ring and dart — in chalk on the brand green, and the
    launch screen is the same mark on green. The app opens on **Home**: a light screen set in Archivo,
    *No matches yet* and a **Start match** button, with a tab bar along the bottom. A yellow *Fonts not
    embedded* notice would mean the faces failed to register; it should not appear.

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

### 5. Everything else this build added, in the order to try it

**If anything on the readiness screen says *Blocked* — or if a row says *Working* and you cannot
find the thing — tap Send this at the bottom of that screen.** It turns all thirteen rows into
plain text with the build stamp and the phone's model, ready to send. It carries no match, no name
and no score.

Ten surfaces went in over the last few days, and **most of them are invisible until something else
is true**: a match in progress, a screen plugged in, a fixture with a date on it. That is why a
build can carry all nine and feel like it carries none.

**Start here: Settings → What you can see on this phone.** It is the first thing in Settings. The
screen reads this phone — not a script, not a demonstration — and puts each surface in one of five
states with a sentence saying where to look or what is stopping it. Whatever it says is what your
phone will actually do, so if a row below disagrees with the screen, the screen is right.

Nothing on that screen is a sample: there is no example match and no mock scoreboard, because an
app whose whole argument is that it does not invent results cannot invent one to demonstrate a
feature.

Then, in this order, because each one needs the one before it:

| # | What | How to see it | What has to be true first |
|---|---|---|---|
| 1 | **Score a match** | Start match → two names → **Start scoring** → throw one visit | Nothing |
| 2 | **Lock Screen and Dynamic Island** | **Stay on the scoring screen** and lock the phone. Both remainders are on the Lock Screen; swipe up to the Home Screen and they are in the Dynamic Island | Live Activities on for THRØ, and the scoring screen still open — the scoreboard lasts exactly as long as that screen, so backing out of a match takes it down on purpose |
| 3 | **Apple Watch** | With the same match running, raise your wrist and swipe to the Smart Stack | An Apple Watch paired. There is no watch app — this is the Live Activity reaching the watch by itself |
| 4 | **Club TV mode** | Plug in an HDMI adapter, or Control Centre → **Screen Mirroring** → an Apple TV. The board fills the screen at room size while the phone keeps the keypad | A cable or an AirPlay receiver. **No app can turn this on for you.** If the readiness screen says *Blocked* here, the build cannot be given a screen at all and mirroring is all you will get |
| 5 | **Share card** | Finish the match → on the result screen, **Share the result**. Opening a finished match from Home lands on the same screen | A finished match — won, retired **or** abandoned. An abandoned one gets a card too: no scoreline, and a line saying nothing is claimed about who won |
| 6 | **Home Screen widget** | Long-press the Home Screen → **+** → THRØ → the small or the medium | The App Group (below). Add it once; it redraws itself |
| 7 | **Lock Screen widget** | Lock the phone → long-press → **Customise** → the Lock Screen → tap under the clock → THRØ | The same App Group |
| 8 | **Fixture reminder** | Discover → a club → **Fixtures** → **+** → give it a date more than two hours away → under it, **Remind me** | A club with a dated fixture. The phone asks for notifications the first time |
| 9 | **Add to calendar** | Beside **Remind me** on the same fixture | The same fixture. THRØ asks only to *add* — it cannot read your calendar |
| 10 | **Find the venue** | Beside those two, on a fixture with a venue typed into it | Maps. THRØ never asks where you are |
| 11 | **Find a match in iPhone search** | Swipe down on the Home Screen, type a player's or club's name | Settings → Search left on |
| 12 | **Performance reports** | Settings → **How the app performs** → turn it on, then come back tomorrow | Nothing, but iOS delivers these **at most once a day** — there will be nothing to see today |
| 13 | **Siri, Shortcuts and the Action Button** | Say *"Start a match in THRØ"* to Siri, or *"Continue my match in THRØ"*. Both are in the Shortcuts app under THRØ, and either can go on the Action Button: iPhone Settings → Action Button → Shortcut → THRØ | Nothing. Two phrases rather than ten, because Siri matches them literally |
| 14 | **VoiceOver on the scoring screen** | Settings → Accessibility → VoiceOver on, then score a visit | Nothing. The remaining says *"on a finish"*, a bust says *"Bust — score restored"*, and a figure says its range rather than a bare number |

Two things are honestly not there, and the readiness screen says so rather than failing quietly:

- **Links that open the app.** There is no `thro.app` domain yet. The file a domain would serve is
  written and checked on every push; claiming the domain before it exists would make iOS fetch a
  file that is not there and then silently stop handling links altogether.
- **A watch-face complication.** That needs a watch app, which needs the phone-to-watch transport
  that was deliberately deferred. The Smart Stack (row 3) arrives without either.

Eight of the thirteen rows also carry a button to the place they name — *Start a match*, *Open a
club*, *Open Home*, or THRØ's own page in iPhone Settings, which is the only page iOS lets any app
open. The other five carry none on purpose: no app may attach a display or start Screen Mirroring, the
App Group is fixed in Xcode or in signing, a domain is bought rather than tapped, and the Action
Button lives in a Settings pane no app may open — so a button there would only apologise.

The directions on that screen are held mechanically, because they are the one kind of copy a change
somewhere else can falsify silently: `tools/check_readiness_directions.py` fails a build if a
control the screen names — **Share the result**, **Remind me**, **Add to calendar**, **Find the
venue**, and the two Settings groups — is not drawn under that name in the file that draws it.
Two more guards cover the property-list keys these surfaces are made of:
`tools/check_scene_manifest.py` for the external-display scene, and `tools/check_bundle_faces.py`
for `NSSupportsLiveActivities`, the calendar usage description, and the ten type faces — which it
reads out of the `.ttf` files themselves, because it is the PostScript name inside the file and not
the filename that `UIFont` matches. And `tools/check_launch_colour.py` holds the colour iOS paints
before the app has run to the brand token the opening paints after it — two copies of one hex in two
files, and a flash of the wrong green if they part.

#### If the widgets show nothing

That is the one row that can be blocked by the build rather than by a setting, and the readiness
screen will say **Blocked** with the reason. Fix it once, in Xcode: see *The App Group, if Xcode
asks* under step 2. Nothing else in the app is affected by it — scoring, the Lock Screen, the share
card and the fixtures all work without it.

### 6. What to send back

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

- **Home.** The mark on the board's own dark surface, and under it a fact — how many matches this
  phone has watched this week. Then the match you walked away from, if there is one, as the largest
  thing on the screen; then **Last 7 days**, three figures from the audited honesty layer (a new
  phone shows three dashes and says why, because a number without its sample is a claim); then the
  record under *On this device*, with **Edit** revealing an archive and a delete on every row; then
  the shelf, if anything is on it. Tapping a match resumes it or opens its result.
- **Live.** What is actually happening: matches in progress on this phone, fixtures your clubs have
  played and nobody has entered a result for, and fixtures still to play. It says at the bottom that
  watching somebody else's match needs THRØ's servers, which are not in this build.
- **Play.** The match still going, **Start match**, what was played last time — read back from the
  journal rather than remembered separately — and the last three matches.
- **You.** Who plays on this phone and the clubs you keep, with the note that a profile, a passport
  and a rating need THRØ's servers **at the bottom**, where an absence belongs. The export's
  settings action is in the header.
- **Scoring.** When the thrower is on a finish, the route appears under the remaining score —
  *T20 T20 D20* for 160 (PD-013). It is **one** route: most finishes have several and players
  disagree, so THRØ takes a position and `docs/product/DECISIONS.md` states the rule it takes it by.
  What is not a preference is that the route is a legal finish of exactly that number under this
  match's own out-rule, and that is checked for every route in every rule, in three places.
- **The end of a match.** The result screen offers **Confirm the result** (PD-011). Each player is
  asked in turn, by name, so the phone gets handed over. Both agreeing makes it
  *participant-confirmed*; either refusing makes it *disputed* and deletes nothing; and if a visit is
  added or undone afterwards the agreement stops applying and the screen says so. The screen also
  says in words what the label would flatter: two people at one phone is two people agreeing, not
  two devices, under the names typed at the start.
- **Who plays on this phone.** Match setup offers the people it already knows as a row of taps, so
  nobody retypes their opponent every Tuesday (ADR-016). *You* lists them, and tapping one opens
  their page: matches, legs won, 3-dart average, checkout %, 180s and highest checkout, computed from
  their own matches on this device through the same honesty layer a single match's figures use. A
  figure it cannot support is a dash with the reason — a checkout percentage is refused outright for
  somebody who has played under more than one out-rule, because whether a visit began on a finish
  depends on the rule.
- **Badges and pictures (PD-014).** An admin taps **Edit** on their club, league or tournament to
  change its name, its colour, or to pick a badge from the photo library; and **Add a picture** on a
  member's page to give them one. Both use the same control. An image is resized on the phone and
  written out again carrying nothing it came with — including where a photograph was taken. Removing
  it removes the file. Nothing has left the phone: an image is screened when it is published, and
  there is nowhere to publish to yet, which the screen says rather than implying otherwise.

  A member's picture is offered **only** for somebody recorded as an adult. For a minor, or for
  anybody whose age was never given, there is no picker at all — an admin sees the reason instead of
  a control that would refuse them, and the two reasons are different sentences because only one of
  them can ever change. A person on this phone — one of the two names typed at an oche — has no
  recorded age anywhere, so they have no picture either, and their page says so. Whether they should
  be able to is **OD-021**, and it is the founder's to answer.

  **Until 2026-09-07 none of this was reachable.** `EditClubScreen` was written and documented, and
  `ClubRoute` had no case for it: no club on a phone could be renamed, recoloured, badged or deleted,
  and nothing pointed the club page at its own badge. `ClubStore.setAvatar` was public and tested and
  called from nowhere. This runbook described the Edit screen as though you could open it. Every test
  was green, because no test here builds a screen — `tools/check_screens_reachable.py` now fails a
  build on a screen nothing constructs or a route case nothing assigns.
- **Discover — clubs, leagues and tournaments.** *No clubs yet* with one action: **Start a club**.
  What you start is kept on this phone and nowhere else. A club has a name, a kind (club, league or
  tournament) and — for a **league**, what its results are counted in (legs, matches or points),
  which is asked once because a stored 3–1 with no unit on it cannot be reinterpreted later; for a
  **tournament**, its shape, chosen once from four. And — if you want one — its own colour, picked
  from thirteen swatches or from the
  phone's own colour well. **Each swatch is drawn as the badge will be**, with the club's real
  initials on it, and underneath it the screen says what the initials read at — 12.4:1, say. You
  never choose the colour they are set in: THRØ picks whichever of its two colours reads better on
  yours, which is why there is nothing you can pick that makes the badge unreadable. Inside it: a roster you keep, and a fixture list an official keeps.
  Adding somebody asks their **age**, and says on the spot what follows from the answer — a member
  under 18, or one whose age is not given, is listed only to an admin and is reached by no
  announcement, until THRØ has taken safeguarding advice (OD-010). A fixture can be postponed,
  played or cancelled, and once it is played or cancelled it does not move again. The announcement
  composer is reachable and tells you exactly who it would reach and who it would not; **it cannot
  send**, because sending needs a connection this build has not got, and it says so rather than
  pretending.
- **Settings** (from the gear on You). **Appearance: System / Light / Dark** — every screen follows
  it, scoring included (PD-003); **Scoring → Keep screen awake**, on by default as the export's
  Settings lists it; **Opening → Sound** and **Haptic on the strike**, both on by default, with *Play
  the opening again* (PD-007); and a *This build* group stating what is true: the commit the app was
  built from, matches stay on the device, sending to THRØ is not built, which face the fonts are, no
  account.
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

**The screenshot files themselves are not in this repository, and cannot be added from here.** They
arrive in conversation from the founder's phone; nothing in this environment can write them into
`docs/runbooks/screenshots/`. What each one showed is written out above instead — including, for the
sixth, the exact defect it found and the commit that fixed it. Adding the images is the founder's to
do if they want them under version control; the record does not depend on it.

**Sixth look, 2026-09-07 at 13:54, on a build transferred from a Mac.** One screenshot, of a club
called *The Lockdown Inn*, and it found a defect two rounds of tests, a design review and a canvas had
all missed:

| Seen | Cause | Change |
|---|---|---|
| **no back button on the club page** — a sliver of the chevron at the very left edge | the top row carried no screen gutter, so the chevron's own −12 inset put its glyph at x = −12 | one `PageBar` for all four pages that have their own header, with `spaceScreenGutter` on the row and **no negative inset anywhere** — `BackChevron` already draws its glyph at the leading edge of its 44-point target |
| **"Announce" cropped by the right edge** | the same missing gutter: the last action sat flush against the screen edge with nothing to spare | the same fix, plus `fixedSize` on every action so a label can never be squeezed into an ellipsis |

The founder had reported the cropping once before and it had been "fixed" once before — by moving the
inset off the row and onto the chevron, which was the right principle and left the row with no gutter
to inset from. `TopBar` and `MatchHeader` never had the bug, because they apply the gutter themselves.
`tools/check_screen_bars.py` now fails a build on a `BackChevron` built anywhere but `PageBar`, or a
negative horizontal inset outside `ThroDesign`.

What the same screenshot confirmed working: the club's accent colour and badge, *YOU ARE AN ADMIN*,
*Club · No members yet*, **Last played** with the played fixture under it and the *Nothing scheduled —
every fixture here has been played or cancelled* line that tells that state apart from having no
fixtures at all, and the five-tab bar with Discover selected.

**Then the founder decided** (PD-003): the player chooses the appearance. The You tab now carries
System / Light / Dark; setup and scoring stay dark as drawn.

**Fourth look, 2026-09-06 at 10:43, on commit `e9382ad` still.** Three screenshots — Home with the
*Fonts not embedded* notice and the 1–1 match from the night before, Settings without the Scoring
group, the result of the first match — show the phone running the build from the night before: none
of the four pushes since (the non-scrolling scoring screen, the announcement cards, the fonts, the icon
and launch screen) had reached it. The founder's Terminal showed why: every `git pull` since had
aborted on Xcode's signing change to `project.pbxproj` ("Your local changes … would be overwritten by
merge"), and the pasted step-1 lines carried their trailing comments, which zsh read as arguments
(`cd: too many arguments`). Nothing from those pushes is verified on a device yet. Step 1 now checks
`git status` first, sets the signing change aside, carries no inline comments, and ends with
`git log -1 --oneline`; the signing section says how to commit the Team ID so the pull stays clean; and
Settings shows the build's commit so a screenshot can say what it is of.

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
8. The home-screen icon: the mark in chalk on green. Then the opening, **seventh version**: a lit
   spot far off in the dark under a beam from above; a real dart coming in from the lower left,
   crossing a screen and a half at one constant angle, smeared by its own speed, while the wall closes
   and every speck of chalk on it streams outward past you; then the hit — a flash on the frame of the
   thud, the heavy buzz, the frame shaking, the shaft and flights whipping while the barrel stays dead
   still, a shadow under the dart where it stands out of the board, and **chalk blown off the board,
   travelling outward along the dart's own line**; then the ring, which is **struck into being rather
   than drawn**: where that shock crosses the mark's radius the chalk is set at full width, so the
   ring lights up from the dart and races round both ways until it closes — and **closes with a
   flare**; the mark taking its place in THRØ as T, H, R are struck in beside it, a firm tap each; the
   tagline arriving under it; then stillness; Home fading up — **four and nine tenths seconds**.
   Silent switch on: no sound. A tap goes straight to Home. Settings → Opening → *Play the opening
   again* replays it.

   **The two things this version is for.** First: **is there any break in the ring now, at the bottom
   right or anywhere else?** The old version had one, and it was structural — two chalk strokes met
   there and each thinned to a point. Nothing tapers any more, so a break should be impossible; say if
   you see one. Second: **does the ring's arrival feel like something happening?** It should read as
   the strike making the mark, not as a circle being drawn.

   Then, as before: **does the dart feel thrown and flying? Does the wall come at you? Does the hit
   land? Do the sounds fit?** Each of the three sounds can be replaced by a recorded one under the
   same filename. **Is the bottom line still long enough to read at 0.87 s?** — half a second shorter
   than the version you read it on. **Is the wordmark right?** Its letters are Archivo ExtraBold and
   the Ø carries their exact weight, measured off the face; say if the supplied wordmark is not that
   face. With Reduce Motion on, the name and the tagline, still, for a second and a tenth.

   **Double in.** Match setup now has a *Start on* row: *Any* or *Double in*. Start a double-in match
   and check: nothing scores until a double lands; the screen says who is not in and what to enter;
   entering 180 while not in is refused with a reason (three trebles cannot open); entering what
   counted from the double scores it; a new leg closes the door again for both players.

9. The faces: numerals on the scoring screen in IBM Plex Sans Condensed, everything else in Archivo,
   and no *Fonts not embedded* notice on Home.

## Ending a match that will not finish (PD-016)

Somebody leaves, the pub shuts, a player is injured. Tap the **×** at the top right of the scoring
screen and the keypad is replaced by the choice: *Jenson retires*, *Alex retires*, or *Abandon —
nobody wins*. Choosing one shows what it will do in words, and says outright that it cannot be
undone; **Back** goes to the choice rather than out, so the destructive button is never the only way
forward.

- **A retirement is a result.** The other player wins, the legs stand as they were, and both players
  are still asked to confirm it — a retirement is exactly the kind of result people later disagree
  about.
- **An abandonment is not.** Nobody wins, nobody is given the win, and there is no verification badge
  because there is nothing to attest to.

The darts already thrown are kept either way and count towards both players' figures. On Home the
match reads **Retired** or **No result** rather than "In progress", and it will not offer to resume.

**An ending is final.** No more visits, no undo, no second ending — the journal refuses all three.
That is on purpose and it is different from PD-004, which makes a mis-keyed *visit* undoable: a visit
is a transcription, and an ending is a declaration taken behind a confirmation. If it could be undone
the match could un-end, and the result would be a claim that moves.

## Keeping a copy (PD-017)

Everything is on this phone. **Settings → Your darts** says whether it is in the phone's backup —
read from the file system rather than assumed — and offers **Export everything**: one file with every
match, every visit as written (corrections included), and every club. Nothing is sent anywhere; the
share sheet lets you decide where it goes.

Pictures are not in the file. It names the ones this phone holds instead, so a reader knows what is
missing rather than being quietly given less than they think.

There is no import. Merging an exported journal into a live one is the two-device reconciliation
ADR-006 specifies for sync, and sync is not built; an import that pretended to do it would produce a
journal whose sequence lies about what this device wrote.

## What a profile says now (PD-018)

A person's page shows **Recent form** — their three-dart average over their last ten completed legs,
with the window written beside it and the words *Not a rating*. Below three completed legs it is a
dash and says how many more are needed, because one leg is a performance and not form.

It is **not** a rating and is never called one. OD-001 leaves the rating model open because no model
here has been validated against real matches, and this is a description of what somebody has
actually scored rather than a claim about how good they are. Nothing seeds a rating from it.

## Where the data is

`Application Support/THRO/journal.sqlite` inside the app's container, in WAL mode with
`synchronous=FULL`, `fullfsync` and `checkpoint_fullfsync` — the configuration ADR-006 measured. The
journal refuses to open under any other configuration. Deleting the app deletes the journal; there is
no export yet.

Every visit is committed to that file **before** the screen updates (`MatchSession.submit`). If the
commit fails, the screen says *Not saved, so not scored* and the state does not change.

## Fonts

Archivo and IBM Plex Sans Condensed are **embedded** (PD-006): ten static faces in
`apps/ios/ThroDarts/Fonts`, the weights the type roles use, with each family's SIL Open Font License
text beside them, listed under `UIAppFonts` in `apps/ios/Support/Info.plist`. Each type role resolves
its weight to a named face (`ThroFont.faceName`), and `apps/ios/check_fonts.py` runs on every push and
fails if the Swift table, the plist, the files and the licences disagree. If the faces ever fail to
register, the type layer falls back to the system face and Home shows *Fonts not embedded* rather than
substituting silently. IBM Plex Sans Condensed stops at Bold, so a heavy sport role takes Bold.

## Installing without the Mac

TestFlight: CI builds and uploads the app and the TestFlight app on the phone installs it, so a build can
be fetched on the phone from the phone. `TESTFLIGHT.md` has the one-time setup — the paid developer
programme, an app record, an App Store Connect API key kept in three repository secrets — and how to ask
for a build from the phone's browser or, once the branch is merged, with a `/testflight` comment on the
pull request. The workflow has not yet been run against a real key; the first run is the test of it.

## Icon, launch screen and the opening

The app icon is the mark in chalk on the brand green, generated by `docs/design/brand/render_mark.py`
from geometry measured against the founder's artwork. The static launch screen is the green field
alone. The app's first frames are the opening (PD-007, seventh version): one shot. It opens on a
place — a lit spot far off in a dark hall, under a beam from above, with chalk dust on it. A real dart
— a fine point, a tapered barrel with grip rings, a collar, a slim shaft, standard flights carrying
the mark — comes in from the lower left at the mark's 45° and never changes direction. It crosses a
screen and a half as the camera's aim catches it, blurred by exactly its own speed, then closes slowly
while the wall comes on: the wall's apparent size is one over its distance and the distance closes at
a constant rate, so every speck of chalk on it slides outward from the spot being aimed at and draws
into a streak. At the strike, on the frame of the thud: a flash at the point, a heavy haptic, the
frame shaking, the board giving and holding while the shaft and flights whip and the tungsten does
not, a shadow under the dart, and a shock out through the board — seen as chalk blown off it, stretched
along the dart's own line. **The ring is not drawn; it is set.** Where the shock crosses the mark's
radius the chalk is set at full width on that frame, so the ring lights up from the dart's line and
races round both ways until two lit fronts merge, and flares as it closes. Nothing tapers, so there is
no seam that can break — which is what the sixth version's bottom right did. Then the mark takes its
place as the Ø of THRØ — carrying the letters' own weight, measured off Archivo ExtraBold — and T, H,
R are struck in beside it with a firm haptic each; the tagline arrives under it as the last letter
sets, and is then left alone, still, for 0.87 s, which is the reading. Four and nine tenths seconds,
once per cold launch; a tap skips it
in a fifth of a second. Sound plays through the ambient session, so the silent switch silences it;
Settings → Opening has switches for the sound and the haptics and *Play the opening again*. With Reduce
Motion on it shows the name and the tagline and fades, silently, with nothing moving, holding them for
one and a tenth seconds. The
wordmark's letters are Archivo ExtraBold, drawn live, on the reading that the supplied wordmark is
that face, which the founder confirms or corrects on the phone. Storyboard and spec: the design
canvas "THRØ Launch Sequence"; `docs/design/brand/README.md` says how to replace the mark with the
master file, and the synthesised sounds with recorded ones.

## What is new since the last run on a phone

None of these have been on a phone at all. In the order you are most likely to meet them:

1. **The seventh opening.** Watch it once and skip it once.
2. **Setup** offers the people this phone knows as a row of taps.
3. **The keypad answers.** Every key has a pressed state and a light tap; Enter is firmer; a bust and
   a won leg each get their own distinct one. Settings → Scoring → Haptics turns them off.
4. **A checkout shows its route** — one route, the conventional one, under the match's own out-rule.
5. **Under double-in** the screen says who is not in.
6. **The × at the top right** ends a match that will not finish.
7. **The result** asks both players to confirm it, by name, in turn.
8. **A figure that is not a fact looks different.** A range carries a "Range" tag; an unavailable
   figure is a dash in the quieter neutral with its reason under it. Turn VoiceOver on for one screen
   and check it says "not available" rather than reading out a dash.
9. **Settings → Your darts** says whether your matches are in the phone's backup, and exports them.
10. **Clubs.** Start one, add a member, add a fixture, give it a badge from your photo library.
11. **Settings → What you can see on this phone**, first in Settings. Nine surfaces went in over the
    last few days and most of them only appear once something else is true — a match in progress, a
    screen plugged in, a fixture with a date. This reads what *this* phone will allow and says where
    to look for each one, or what is stopping it. Step 5 of the test plan above walks them in order.
    Nothing on it is a demonstration: no sample match, no mock scoreboard.

## What the design does not specify, and what this build does about it

Read against `docs/design/DESIGN_UNSPECIFIED.md`. Nothing here decides an item; each keeps the
platform's own behaviour or renders the honest minimum, and says so.

| Item | This build |
|---|---|
| 1 Dynamic Type | Type roles scale through `relativeTo`; spacing and radius do not (ADR-010). **No clamps.** The score numeral alone may shrink (to half) when the screen is too short for it, so it never clips or scrolls; that is a floor, not a design. |
| 2 Pressed / focus | The platform's own. Nothing removed (the export removed the text field's focus ring; SwiftUI's stays). |
| 5 Safe areas | The platform's: content respects them, only backgrounds paint under them. The scoring screen is laid out to the height the keypad leaves, so nothing scrolls. |
| 7 Attestation | **Built (PD-011), and this row said the opposite for three weeks.** Both players are asked by name on the result screen; both agreeing gives *participant-confirmed*, either refusing gives *disputed*, neither answering leaves *self-reported*, and an agreement does not survive a visit or an undo written after it. The screen says in words that two people at one phone is not two devices, and that the names are the ones typed at the start — which is the weakest form of the state PD-002 describes, not the strong one. An abandoned match is never labelled at all. |
| 9 Stat basis | Bounded is a range, unavailable is a dash; the reason is shown in the metadata role beneath. |
| 11 Offline-completed result | *Self-reported*; and because no sync exists, the screen says the result has not left the phone rather than showing a *Queued* that promises one. |
| 15 Disabled | The export's opacity multiplier. |
| 16 Modal behaviour | The bust and leg card (PD-005) uses the Dialog surface and the scrim token; it dismisses on its button or a scrim tap, traps nothing, animates nothing. |
| 18 Invalid score feedback | The engine's refusal in the snackbar, in the harness's words. |
| 20 Dark mode | **Decided by the founder (PD-003, amended):** System / Light / Dark in Settings, governing every screen, scoring included. Each screen's undrawn rendering — dark Home, light scoring — is the token layer's, unreviewed by design. |
| 23 Landscape | **Portrait only**, as every screen in the export is drawn. A landscape scoring screen would need a design. |
| 24 Truncation | Names truncate with an ellipsis in the header, the identity, and the Home rows. |
| 25 Haptics | **Built (PD-015), and this row said *None* after they shipped.** Four sensations, one for each event the design names: a key, a committed visit, a refusal, a won leg. Settings → Scoring → Haptics turns them off. The opening's strike has its own, on its own switch. Nothing outside the scoring screen and the opening produces one. |

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
is 44 points, not the export's 40. The checkout card's route slot — drawn by the export and empty
until PD-013 — now carries the route from the engine's own table, per out-rule, held by the
conformance corpus to be a legal finish of exactly that number under exactly that rule.

## What is not built

**Universal links are ready and not turned on.** ADR-011's path grammar is fixed, the app's parser
has always read `https://` paths as well as `thro://`, and the association file that a domain would
serve is committed at `services/links/.well-known/apple-app-site-association` —
`tools/check_aasa.py` holds it against the parser on every push. What is deliberately **not** there
is the `associated-domains` entitlement: adding `applinks:thro.app` for a domain nobody owns makes
iOS ask Apple's CDN for a file that is not there, and the app then silently never handles a link.
`services/links/README.md` says the three steps once there is a domain. Note also that a link into a
phone's own data opens nothing on anybody else's until there is a server, which is why the share
card carries no link at all.

**Two approved components describe a server THRØ does not have, and no screen constructs either.**
`SyncState` — *"Synced · This match is saved to THRØ"* — and `OfflineState` — *"Changes will sync
when connection returns"* — are in the design system and are drawn nowhere in this build, because
nothing leaves the phone and a screen showing either would tell a player something untrue about
their own darts. They stay because the design system is the founder's and a component is not
deleted for being early. But they are a **trap** rather than merely unused: the obvious thing to do
when sync is built is to reach for `SyncState`, and that ships copy claiming a server confirmed a
result before any server has. `tools/check_absence_claims.py` holds that no screen constructs
either, on every push, so the trap cannot spring by accident.

**All four tournament shapes draw themselves** (PD-021) — a knockout, a groups stage and the
knockout after it, a round robin's table, and double elimination with its losers' bracket and a final
that may be played twice. What is *not* built is a way to set a groups tournament's group sizes from
anywhere but Edit, and any draw at all for a shape THRØ has not been told the setup of: it says so
rather than guessing.

No network, sync or server calls of any kind — the module graph has no network target, which is how
LATENCY_BUDGETS.md's structural requirement is enforced. No attestation, no rating (OD-001), no
identity or sign-in (item 6), no organiser surface, and nothing live from anybody else — the Live tab shows this phone's own matches and its own clubs' unfinished fixtures, and says so. Clubs exist on the device only:
nothing is published, no club can be joined or searched for, and no announcement can be sent — the
composer exists and refuses, with the reason. A player profile is reachable from a club's roster and
shows dashes with reasons where a figure would be, because nothing on this device is attributed to
anybody. No online matches,
so no opponent-approved retraction (PD-004 point 3). The app scores a match between two people on one
phone, lets them undo a mis-key, and keeps it. That is all it claims.

## Checking it yourself

```bash
swift test --package-path packages/client-ios          # design, journal, play tests (macOS)
swift test --package-path packages/statistics-swift    # the twenty honesty tests (any platform)
xcodebuild -project apps/ios/ThroDarts.xcodeproj -scheme ThroDarts \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```
