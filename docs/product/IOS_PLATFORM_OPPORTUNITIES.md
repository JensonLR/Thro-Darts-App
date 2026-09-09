# The iOS and Apple ecosystem opportunity for THRØ

**Status: recommendations awaiting the founder's decisions. Nothing in section 1–7 has been built.**
Researched 2026-09-07 against Apple's own documentation, the current darts software and hardware
market, and this repository as it stands at `aa27531`.

---

## 0. Corrections first — what the brief assumes that is not true

The brief is a good brief. Six of its premises are out of date or do not hold here, and every one of
them changes an answer. They are stated first because several priority areas are downstream of them.

### 0.1 More than half the brief is blocked on decisions you have not made, not on Apple work

The board call, *"you're up next"*, *"next opponent"*, *"round ready"*, the organiser update, the
ranking-movement notification, the ELO widget, the ELO share card, the tournament pass and the
Apple Watch corroborating device all require at least one of three things this repository does not
have, and two of them are your open decisions rather than engineering gaps:

| Missing thing | Status | Evidence |
|---|---|---|
| **Any network code at all** | Absent **by construction** | `packages/client-ios/Package.swift:8-11` — *"There is no network target in this package for anything to depend on."* Zero hits for `URLSession`/`URLRequest`/`NWConnection`/`WebSocket` in the whole client. `tools/check_absence_claims.py` now holds this. |
| **Accounts and identity** | **B4, a founder blocker** | `FOUNDATION_ACCEPTANCE.md:580` — *"Until this exists, the flagship slice is not buildable as specified."* Settings says *"Account and profile · Not built"*. |
| **A rating** | **OD-001, open** | A case-insensitive search for `elo` across the entire repository returns **zero hits** other than inside the words "belongs" and "below". `PlayerRef.rating` exists and is *"never supplied by this app"*; the result screen shows `Tag("Not rated")`. |

**There is no ELO in THRØ and, under OD-001, deliberately so.** PD-018's recent-form figure is a
three-dart average over the last ten completed legs and the decision says in terms that it *"is not a
claim about strength relative to other players, it is never labelled a rating, and nothing seeds a
rating from it."* So a "ranking movement" push, an ELO widget and an ELO share card are not iOS work
that is waiting on effort. They are OD-001 work that is waiting on you.

Everything in section 1 is chosen to be buildable **without** a server, without accounts and without a
rating — or is explicitly marked as depending on one.

### 0.2 "Do not create a payment feature just because Apple supports it" — agreed, and there is none

There are no payments in this repository and none planned: no StoreKit, no PassKit, no merchant id,
and OD-009 (payments, platform rules, fee structure) is **open** with the note *"must not be decided
by: guessing store policy"*. Apple Pay and Tap to Pay are therefore in **DO NOT BUILD**, investigated
only far enough to record what they would cost if OD-009 ever closes.

One rule is worth writing down now, because getting it backwards is the classic rejection:
guideline **3.1.3(e)** — *"If your app enables people to purchase physical goods or services that
will be consumed outside of the app, you must use purchase methods other than in-app purchase."*
A league entry fee or a tournament buy-in is a real-world service, so it is **not** IAP. Unlocking an
in-app statistics module **is** IAP at 30/15%.

### 0.3 The Apple SDK facts the brief gets wrong

Verified against `developer.apple.com` on 2026-09-07:

- **"Live Activities need a server" is false.** A Live Activity can be started and updated entirely
  from the foreground app with no server, no APNs and no network code. The documented budget and
  throttling apply to ActivityKit **push** notifications, not to app-side `update(_:)`. This is the
  single most important correction in this document, and it is why recommendation 1 exists.
- **`UIScreen.screens` is deprecated** (iOS 16.0). External display is now a scene role,
  `windowExternalDisplayNonInteractive` — which is *exactly* iOS 16.0, so club TV mode is available at
  your current floor today.
- **`AVRoutePickerView` is a media route picker, not a screen-mirroring API.** There is no API to
  initiate mirroring; only the user can, from Control Center. Shipping a route picker labelled
  "TV mode" produces a day-one bug report.
- **There is no sports, scoring, game or competition domain in Apple Intelligence's App Intent
  schemas.** The list is fixed — Audio, Calendar, Camera, Clock, Files, Mail, Maps, Messages, Notes,
  Phone, Photos, Reminders, system/in-app search, plus Japan-only Assistant and Visual Intelligence.
  A darts app has nothing to conform to. Any advice to "adopt Apple Intelligence schemas" is wrong.
- **Critical Alerts require an approved entitlement request to Apple** and are reserved for health,
  safety and public safety. **A darts app will not be granted them.** Time Sensitive is the ceiling,
  needs only an Xcode capability, and is the right level for *"you're up next"*.
- **In SwiftUI a universal link arrives at `onOpenURL` as a `URL`**, not as an `NSUserActivity`.
  Writing `.onContinueUserActivity(NSUserActivityTypeBrowsingWeb)` in SwiftUI silently never fires.
- **App Clips invoked by a physical code are capped at 15 MB, not 100 MB.** The 100 MB tier is
  explicitly digital-invocation only and excludes App Clip Codes, QR codes and NFC tags.
- **`apple-app-site-association` is fetched by an Apple CDN, not by the device from your server.**
  Apple picks up a change within 24 hours; installed apps re-check about **once a week**. Universal
  links are not something you iterate on in an afternoon.

### 0.4 The deadline nobody has told you about

Since **28 April 2026** every upload to App Store Connect must be **built with the iOS 26 SDK or
later**. That is an SDK requirement, not a deployment-target one, so `IPHONEOS_DEPLOYMENT_TARGET =
16.0` stays legal. But building against the iOS 26 SDK means the app adopts **Liquid Glass**
automatically, and Apple's own documentation says the escape hatch expires: `UIDesignRequiresCompatibility`
*"is ignored when you build for iOS 27 or later"*. **iOS 27 ships on 14 September 2026 — one week
from now.**

The good news, which I verified in this codebase rather than assumed: **THRØ is unusually insulated.**
Because every screen hand-rolls its navigation, there is not one `NavigationStack`, `TabView`,
`.sheet`, `.toolbar`, `List` or `Form` in the entire client. The whole Liquid Glass surface area is:
21 `TextField`s, 9 `Picker`s, 3 `Toggle`s, 2 `ColorPicker`s, three dialogs, three system sheets, and
the new scroll edge effect on 30 `ScrollView`s.

**The risk worth naming** is not the look. It is that the contrast gate — 60 pairs, absolute
thresholds, dated exceptions — measures **tokens**, not rendered pixels. Liquid Glass re-composites a
translucent material behind certified text, so a pair certified at 4.5:1 against a token background
may render against a different effective background and **nothing in this repository would notice.**
That is the same shape as the defect that produced Home's 1.08:1 masthead: a check that measures the
declaration rather than the result.

### 0.5 Your competition moved last week

**Nodor/Winmau acquired Autodarts in September 2025, and the whole ecosystem relaunched at IFA Berlin
this month.** "Autodarts LENS" turns a phone camera into an auto-scorer; there is a native iOS app,
iOS 18+ recommended, leaning on the Neural Engine; 200,000+ players are reported; and the published
2026–27 roadmap **explicitly includes leagues**. A dartboard manufacturer with retail distribution now
ships a free phone-camera scorer and is coming for the league layer.

### 0.6 And the incumbent cannot follow you

**DartConnect — official scoring app of the PDC, official partner of the WDF — is not in the App Store
at all.** It is a browser page you save to your Home Screen. From their own support documentation:
the app *"shows a spinner that spins for a long time… often between legs while the system is trying to
re-sync"*, matches can be *"not fully saved"* when a device loses connection, and it breaks in Private
Browsing. It can never have a Live Activity, a widget, a Watch app or an external display mode.

The only darts apps doing native Apple work are one-person projects — Oche (a Watch-only scorer),
Dart Scoreboard Pro (Watch complication + AirPlay), Darts365 (the category's only Apple TV app). None
has a league, a venue or a trust story. **The premium-native lane in darts is not crowded. It is empty.**

---

## 1. TOP RECOMMENDATIONS

Ranked. Every one of the first nine needs **no server, no accounts and no rating** — they are
buildable against the app as it exists today.

### 1 — The Dynamic Island is the scoreboard for the player who isn't holding the phone · **MUST**

**Recommendation.** Start a Live Activity when a leg starts. Lock Screen and Dynamic Island show the
two remaining scores, whose throw it is, and the leg. The phone lies on the table where it always is;
both players read it without picking it up.

**Why it matters.** This is the "why hasn't every darts app done this?" item, and I can say precisely
why they haven't: the category models the phone-holder as the scorer, so a Lock Screen summary looks
pointless. But **darts is the sport where you put the phone down and walk away from it**, and where
the people waiting for a board outnumber the people throwing. Zero evidence of any darts app using
Live Activities was found anywhere in the market research.

**Complexity: low-to-moderate.** A widget extension, an `ActivityAttributes`, and `update(_:)` calls
from `MatchSession` where it already changes state. Days, not weeks.

**Backend: none.** Verified against Apple's documentation: `pushType` is optional, and the budget and
throttling apply to push, not to app-side updates. 8 hours active plus up to 4 lingering on the Lock
Screen — a league night fits. `Text(timerInterval:)` keeps counting with your code not running at all.

**Apple requirements.** `NSSupportsLiveActivities` in the app target's Info.plist; a widget extension.
No entitlement. **The 4 KB cap covers `ActivityAttributes` + `ContentState` combined** — pass ids, not
payloads. The Live Activity runs in its own sandbox with **no network and no location access**.

**The honesty catch, and it is the interesting part.** Your code must be running to call `update`.
When the app backgrounds you get nothing. So set `staleDate` and let the surface say *"score may be
out of date"* rather than showing a number it cannot vouch for. That is this repository's existing
discipline — an uncomputable figure says so — extended onto a new surface.

**Free with it:** an iPhone Live Activity appears automatically in the **Apple Watch Smart Stack**
(iOS 18/watchOS 11) with no watch app written. That answers most of the Watch question on its own.

**Classification: MUST.**

---

### 2 — Club TV mode over HDMI · **MUST**

**Recommendation.** Adopt the external-display scene and draw a venue board: the draw, board
allocations, who is on next, and the live leg. The organiser plugs a £50 Apple Digital AV Adapter into
the pub's TV.

**Why it matters.** You suspected this could be the most valuable organiser-facing enhancement. The
research says you are right, and the bar is on the floor. Current best-practice guides tell organisers
to *"export the schedule as a PDF and post it on the wall, or announce matches over the pub PA
system"*; retailers sell darts whiteboards as current stock; the formal roles are still **Caller** and
**Marker**; and event guides budget **"10–15 minutes for scoreboard updates and regrouping"** between
rounds. Exactly one darts app on the store has an Apple TV app. DartConnect's answer is "open this URL
in a browser on something plugged into the telly."

**Complexity: low, and lower than it looks.** `UISceneSession.Role.windowExternalDisplayNonInteractive`
is **exactly iOS 16.0** — available at your current floor. The system creates the scene automatically
when a display is attached *or when the user turns on AirPlay mirroring*, so **AirPlay to a venue's
Apple TV falls out of the same code for free**. SwiftUI has no native support until iOS 27, so it is
about fifty lines of `UIWindowSceneDelegate` boilerplate hosting a `UIHostingController`; add
`sceneAccessory` behind `if #available(iOS 27, *)` later.

**Backend: none.** HDMI is deterministic — no network, no discovery, no pub Wi-Fi. That last point
matters: pub guest Wi-Fi very commonly has client isolation, which kills AirPlay discovery entirely.
Treat AirPlay as a bonus, never as the plan.

**Classification: MUST.** This is the organiser-facing feature with the best ratio of value to effort
in the entire report.

---

### 3 — One canonical route, and deep links into it · **MUST (foundation)**

**Recommendation.** Replace the two private `@State` route enums with one serialisable route type, put
it behind a router the app scene can reach, and accept a custom URL scheme in `onOpenURL`.

**Why it matters.** Every other recommendation terminates in "…and tapping it opens the right screen."
Today nothing can. There is **no `onOpenURL`, no `NSUserActivity`, no `CFBundleURLTypes` and no
`NavigationStack` anywhere in the client**; navigation is a hand-rolled `@State` + `switch`.
`ClubRoute` is `public` but not `Codable`, and `PlayFlow.Step` is `internal` and carries **live
`MatchSession` objects as associated values**, so it cannot be serialised at all. `ClubsFlow`'s route
is destroyed when you switch tabs. Widgets, Live Activity taps, Spotlight results and App Intents all
need an address, and there is nowhere to send them.

**This is the dependency that gates items 1, 4, 7 and every widget.** Do it first or do the others twice.

**Complexity: moderate.** Four structural edits: a URL parser, a serialisable route spanning tab +
club + play, lifting both `@State`s out of their views, and an entry point on the app scene.

**Backend: none. Apple requirements: none** — a custom scheme needs no domain and no entitlement.
Universal links can come later and need a **domain and static hosting, not a server**: about £10 a
year plus a free Pages host serving a correct AASA. Budget a week of propagation before they work.

**Classification: MUST.**

---

### 4 — Core Spotlight · **SHOULD**, and it is the cheapest thing here

**Recommendation.** Index matches, people, clubs, leagues and tournaments into Spotlight. Typing a
club name into the iPhone's search field finds it and opens it.

**Why it matters.** It is the only place a phone will surface THRØ's content without the user opening
the app, and it costs almost nothing: **no entitlement, no capability, no server, no domain, no
account, and it has worked since iOS 9** — your floor is irrelevant. Two facts to design around: the
index is on-device and **never synced to the user's other devices**, so a new phone is empty until you
rebuild it; and Spotlight will ask you to reindex at times you do not choose.

**Complexity: low** — but it is downstream of item 3, because tapping a result must go somewhere.

**Classification: SHOULD.**

---

### 5 — Make the offline write state machine honest before anything can sync · **MUST**

**Recommendation.** Give every outbound item an explicit state — `pending → inFlight →
acked(serverReceipt) | failed(reason, attempts)` — where **only a server acknowledgement moves
anything to acked**. Surface the states verbatim, with counts and the age of the oldest pending item.

**Why it matters, and this is a defect not an idea.** `ThroDesign/Status.swift` already ships an
`OfflineState` whose message reads *"Changes will sync when connection returns"* and a `SyncState` with
four states including *"Synced — This match is saved to THRØ."* **Neither is constructed anywhere in
the app, and there is no sync.** They are harmless while unreachable — and they are a trap, because
the next person to build sync will reach for `SyncState` and ship copy claiming a server confirmed
something. The words are already wrong for what THRØ should promise: *"saved to THRØ"* asserts a
server receipt, and *"will sync when connection returns"* promises a future that may not arrive.

Two things Apple's documentation forces into the design, both of which suit this repository:
`NWPathMonitor` tells you about interfaces, **not whether a pub's captive portal will pass a packet** —
so never gate a request on reachability, attempt and record the failure; and background `URLSession`
applies **an escalating delay each time the system relaunches you**, so use one session with many
tasks enqueued at once, never one-at-a-time.

**Complexity: moderate. Backend: this is the client half; it is worth building before the server exists,
because it is the part that decides what the app is allowed to claim.**

**Classification: MUST.** The founder's brief calls offline resilience "extremely important". The
honest version of it starts by deleting a promise the app cannot keep.

---

### 6 — One haptic language · **SHOULD**

**Recommendation.** Route every haptic through `ThroHaptics`, extend its vocabulary to the events the
rest of the app has, and give the whole app one preference.

**Why it matters.** There are **two haptic systems today**. `ThroHaptics` has four named, tested events
and **exactly four call sites**, all in the scoring screen. The opening has its own generators on a
*different* preference key. Nothing in `ThroApp` — not Home, not clubs, not leagues, not settings, not
one navigation control — produces a haptic at all. A deliberate haptic language is a good idea; you
already have the beginning of one and it reaches two screens.

**Complexity: low. Backend: none.**
Note `.sensoryFeedback` (iOS 17) is *not* an upgrade here: it is a generic vocabulary, and
`ThroHaptics` names four events the design specified. Keep the named layer; it is the better artefact.

**Classification: SHOULD.**

---

### 7 — App Intents: start a match, and score from the Action Button · **SHOULD**

**Recommendation.** One `AppIntent` ("Start a match") and one `AppShortcut` to begin with. Later, an
`AppEntity` for a match and a person so Spotlight and Shortcuts can address them.

**Why it matters.** It puts THRØ on the Action Button, in Shortcuts, and at the top of Spotlight. The
whole category has invested in voice — Score Darts, Darts Voiceboard, MyDarts, DartVoice, Ochetron and
recent Russ Bray all do in-app speech recognition — and **not one of them exposes it through Siri or
App Intents**, so none of it works from the Lock Screen, a Watch, AirPods or a Shortcut.

**Complexity: about a day for the first intent.** Entities plus queries plus indexing is three to five
days and carries a permanent tax: every change must be reindexed and the query must resolve stale ids.

**Apple requirements.** Every shortcut phrase must contain the `\(.applicationName)` token; maximum ten
App Shortcuts. **Without a schema domain Siri matches your literal phrases only** — it will not parse
"what's my checkout", and as established in §0.3 there is no domain for a darts app to adopt.

**Classification: SHOULD.**

---

### 8 — Share cards, rendered on the device · **SHOULD**

**Recommendation.** `ImageRenderer` (iOS 16) over a SwiftUI view built from the design system, into the
share sheet. Result cards, a leg's checkout, a season's form.

**Why it matters.** The category's share cards are image exports — DartConnect's Player Card,
DartVision's one-click share. **No evidence was found anywhere of a shareable link that opens a live
match**, which is a gap, but that one needs a domain. The image is available today and is where the
craft shows.

**Complexity: low. Backend: none.** Backend rendering would buy consistent output and a link preview —
neither of which you can use yet, and both of which need the server you do not have.

**One rule.** A share card is a claim leaving the phone. It must carry its verification state and its
sample the way every other figure in this app does — a card that shows a three-dart average without
saying it is self-reported over four legs is exactly the laundering PD-020 forbids in a league table.

**Classification: SHOULD.**

---

### 9 — Local notifications for what this device already knows · **SHOULD**

**Recommendation.** Time and calendar triggers for fixture reminders, "league night in 30 minutes", and
"you left a leg open". Notification categories with actions.

**Why it matters.** They need **no server, no APNs and no Push Notifications capability**, and they
support the same categories, actions, sounds, thread grouping, relevance scores and interruption
levels as remote ones — **including Time Sensitive**, which needs only an Xcode capability and no Apple
approval. They **mirror to a paired Apple Watch for free**, and since watchOS 10.1 a Double Tap on a
notification fires its first non-destructive action.

**The limit, stated plainly:** they can never cover a cross-device event. "You're up next" from an
organiser's phone to a player's phone is a server feature. Everything this device already knows is not.

**Classification: SHOULD.**

---

### 10 — A venue on a map, with directions and no location permission · **SHOULD**

**Recommendation.** Show the venue, offer directions by handing off to Maps.

**Why it matters.** It is the whole of the brief's "avoid invasive location tracking" instruction,
satisfied by construction. Verified: rendering a map with a marker, geocoding an address, calculating
travel time between two coordinates you already know, Look Around, and
`MKMapItem.openInMaps(launchOptions:)` **all work with no `NSLocationWhenInUseUsageDescription`, no
CoreLocation link and no prompt.** Maps opens, uses *its own* authorisation, and routes from the user's
position — your app never asks and never learns where they are. Only `UserAnnotation`,
`MapUserLocationButton`, `showsUserLocation` and `CLLocationManager` trigger the prompt.

**MapKit needs no entitlement, capability, key or account.** At an iOS 16 floor you wrap `MKMapView`;
the SwiftUI map, Look Around and in-MapKit geocoding need iOS 17/18/26.

**Classification: SHOULD.**

---

### 11 — Add a fixture to Calendar without asking for anything · **SHOULD**

**Recommendation.** Present `EKEventEditViewController` pre-filled. No permission, no usage string, no
prompt — it runs out of process and the user saves it themselves.

**The honest trade-off, which is why this belongs in THRØ:** you genuinely do not know whether they
saved it, **so the app must not say "added to calendar."** That is the same discipline as the export's
digest, which says what it proves and what it does not.

A subscribable ICS feed is the server-side alternative and is worth knowing the shape of: refresh
cadence belongs to iOS, not you — hours to a day — **and there is no push**. Fine for a season's
fixtures, useless for "your match moved to board 3 in ten minutes."

**Classification: SHOULD.** iOS 17's write-only tier is better; at an iOS 16 floor the editor route is
the only one that does not demand full calendar access.

---

### 12 — MetricKit, written into the journal · **SHOULD**

**Recommendation.** Subscribe to MetricKit and write the payloads into THRØ's own store, with an export
from a diagnostics screen.

**Why it matters.** It needs **no backend at all**. Metrics arrive at most daily; **diagnostics arrive
immediately** and carry call stack trees. You get launch time-to-first-draw, hang rate, hitch ratio,
peak memory and terminations from real phones. And Xcode Organizer — the usual answer — is **frequently
empty at small scale**, so on-device MetricKit is the only signal that works before you have users.

It also fits this repository exactly: measured rather than assumed, local, auditable, and it would have
given you a number for the opening's frame timing instead of a judgement.

**Classification: SHOULD.**

---

### 13 — Raise the deployment floor · **DECISION (see §8)**

Apple's own June 2026 figures: **79% on iOS 26, 14% on iOS 18, 7% on everything older combined.**
iOS 16 is a low-single-digit sliver.

What the floor costs THRØ is **less than it would cost a typical app**, and I checked rather than
assumed: `ContentUnavailableView` would be a *regression*, because `EmptyState` is an approved design
component used in six places; `.sensoryFeedback` would lose the four named events. What it genuinely
costs is symbol effects, scroll transitions, `visualEffect`, mesh gradients, zoom transitions, the
SwiftUI Map API, Look Around, EventKit's write-only tier, `CKSyncEngine`, **interactive widgets, Control
Center controls, and Spotlight-indexed App Intent entities** — and every Liquid Glass API.

There is **not one `#available` or `@available` in the entire client**, so raising the floor is a pure
unlock with no compatibility code to remove.

---

### 14 — Accessibility: close the VoiceOver gaps and fill in the nutrition labels · **SHOULD**

Dynamic Type is the strong part and has a written, tested contract (PD-024: the keypad stays pinned so
a key never moves under a thumb mid-visit). VoiceOver is 21 labels and 21 element groupings with
**zero `accessibilityValue`, zero custom actions and zero identifiers**, and no test renders a screen.
`accessibilityRepresentation` (iOS 15) is the right tool for the keypad and the score display: expose a
`Stepper`'s semantics rather than a pile of buttons.

**Accessibility Nutrition Labels** are real: nine features, declared per platform in App Store Connect,
supported on OS 26+. The bar is strict — you may claim a feature only if **all common tasks** work with
it. **They are voluntary and Apple has published no mandatory date**; do not let anyone tell you there
is a deadline. Most of your competitors will leave them blank.

---

### 15 — Widgets, after one architectural decision · **COULD**

A Home Screen widget is a **poor live scoreboard** — the reload budget is roughly 40–70 refreshes a day
per instance, giving 15–60 minute latency. It is a good *"last night's average, next fixture"* surface.
The live surface is the Live Activity.

**The real cost is not the widget.** The journal and club book live in `Application Support/THRO/`,
inside the app's own container, and **no extension can read that** — not a widget, not a Watch app, not
a Live Activity's own process. Sharing needs an **App Group**, which means new entitlements, new
provisioning profiles, and migrating the one file that is the only copy of what was thrown off the path
ADR-006 measured. See the recommendation in §8, decision 6: **do not move the journal.**

---

## 2. QUICK WINS

Each is days, needs no server, no accounts and no rating, and could start this week.

| # | Win | Effort | Why now |
|---|---|---|---|
| 1 | **Core Spotlight indexing** | 1–2 days | No entitlement, no server, no domain; works at iOS 16. Needs item 3 for the tap target. |
| 2 | **One `AppIntent` + one `AppShortcut`** | ~1 day | Action Button, Shortcuts, Spotlight top hit. |
| 3 | **Custom URL scheme + `onOpenURL`** | 1 day | Unblocks widget, Live Activity and Spotlight taps. No domain needed. |
| 4 | **Route every haptic through `ThroHaptics`** | 1–2 days | Two systems and four call sites today; the whole app outside scoring is silent. |
| 5 | **`ImageRenderer` share card** | 2–3 days | On-device, no backend, carries verification state. |
| 6 | **MetricKit into the journal** | 1–2 days | Real field performance data with no backend; Organizer is empty at this scale. |
| 7 | **Calendar add via `EKEventEditViewController`** | half a day | Zero permissions. Must not claim it saved. |
| 8 | **`MKMapItem.openInMaps` for a venue** | half a day | Directions with no location permission at all. |
| 9 | **Delete or gate `SyncState` / `OfflineState`** | hours | They promise a server that does not exist. Unreachable today; a trap tomorrow. |
| 10 | **Accessibility Nutrition Labels** | half a day, then honest auditing | Voluntary, visible on the product page, and most competitors will leave them blank. |
| 11 | **`CADisableMinimumFrameDurationOnPhone`** | minutes | Defaults to **NO**, meaning 120 Hz is *unavailable* until you set it. For an app whose opening is a 4.86 s animation, this is worth one line. |

---

## 3. BIG BETS

Four. The first is the gate on most of the brief; the second is the one nobody else can copy.

### Bet 1 — The backend, and with it half of this brief

Everything the brief asks for that crosses devices — the board call, "you're up next", the round-ready
push, the organiser update, a spectator's Live Activity, widget push, joining someone else's club,
linking a fixture result to a match scored in THRØ — is one project: **a server, plus identity (B4),
plus the sync ADR-006 already specifies and nothing has built.**

Be clear-eyed about the realtime part, because Apple's own documentation is: a WebSocket or SSE
connection **dies when the app suspends**; background push explicitly *"doesn't guarantee delivery"*
and Apple says *"don't try to send more than two or three per hour"*. **Sub-second background
awareness on iOS does not exist.** The architecture that does work is a foreground WebSocket, a
*visible* push for anything consequential, and a full reconcile-on-foreground that treats every local
state as possibly stale.

**Sequencing that saves you a rewrite:** build the honest write state machine (§1.5) first, on the
client, before the server exists. It decides what the app is allowed to claim, and it is the piece
that makes ADR-006's reconciliation implementable rather than aspirational.

### Bet 2 — The first attested result in steel-tip darts

**Nothing in the category distinguishes "I typed 180" from "a 180 happened."** The written rule for
webcam darts is literally *"be honest and not tarnish the sport by entering false scores."*
DartCounter's own users asked for a live board view to stop cheating and were told it is on the
long-term schedule. The only verified rating in darts is DARTSLIVE's, and it **requires a soft-tip
machine**. MODUS solved integrity by giving up on remote play and **building a studio**.

You already have the primitive. PD-002 sets the floor at `participant-confirmed`; PD-011 makes both
players confirm and says on screen that two people at one phone is not two devices; ADR-016 refuses to
launder a local history into a rated record. What is missing is the second device and the ranking that
counts only corroborated matches — and the incumbents cannot build it in a browser tab.

This is the one that answers *"why hasn't every darts app done this?"* with something other than a
framework.

### Bet 3 — Publish an open darts interchange format

**There is no open standard for darts. None.** IPTC SportsML-G2 is a real open sports interchange
standard and its controlled vocabularies cover about eleven sports — **darts is not one of them, and
nothing in it models legs, sets, 501, checkouts, three-dart averages or 180s.** DartConnect exports
CSV with no published schema. Every platform is an island, and DartCounter's terms actively forbid a
player's history leaving.

You are unusually well placed: you already have a versioned export format, a conformance corpus, and
two independent engine implementations proving the rules are writable down. Publishing a small,
permissively licensed match/fixture/result format costs a spec and a repository, and it gives you a
principled, non-adversarial reason to talk to Scolia, Gran Darts, Lidarts and iDarts.

### Bet 4 — Scolia

The only hardware vendor with a public page that **invites** third parties: *"The Scolia API is the
perfect choice for building your own scorekeeping or analytical solution. Through this API, you will be
able to receive all the events related to, or detected by your Scolia systems."* Per-throw ground truth
from a premium board, without building computer vision, from a partner who — unlike Winmau — is not
launching a rival league platform. Documentation and pricing are behind a business conversation.

**This is the highest-value single email in this report.**

---

## 4. iOS / APPLE OPPORTUNITY MATRIX

| Area | Exists today? | Needs | Verdict |
|---|---|---|---|
| Live Activities / Dynamic Island | No | Widget extension | **MUST** |
| External display (club TV over HDMI) | No | ~50 lines UIKit; iOS 16.0 | **MUST** |
| Canonical route + deep linking | No | Refactor of two `@State` enums | **MUST** |
| Honest offline write states | Chrome only, unreachable | Client work | **MUST** |
| Core Spotlight | No | Nothing | **SHOULD** |
| App Intents / Shortcuts / Action Button | No | Nothing | **SHOULD** |
| One haptic language | Two systems, 4 call sites | Nothing | **SHOULD** |
| Native share cards (`ImageRenderer`) | No | Nothing | **SHOULD** |
| Local notifications | No | Time Sensitive capability | **SHOULD** |
| MapKit venue + directions | No | Nothing | **SHOULD** |
| EventKit calendar add | No | Nothing | **SHOULD** |
| MetricKit | No | Nothing | **SHOULD** |
| Accessibility: VoiceOver values/actions, nutrition labels | Partial | Nothing | **SHOULD** |
| Motion/polish: symbol effects, scroll transitions, zoom transitions | No | **iOS 17/18 floor** | **SHOULD**, after the floor decision |
| Widgets (small/medium/large, Lock Screen) | No | **App Group + a projection** | **COULD** |
| StandBy | Falls out of a Live Activity | — | **COULD** |
| Control Center control / Action Button control | No | **iOS 18** | **COULD** |
| Apple Watch — Smart Stack surface | No | Free with a Live Activity (iOS 18) | **SHOULD** |
| Apple Watch — glance companion | No | Watch target, `WCSession` | **COULD** |
| Apple Watch — full scoring companion | No | 6–10 weeks + permanent tax | **REJECT** |
| Universal links | No | **A domain + static hosting** | **COULD** |
| Push notifications (cross-device) | No | **A server** | **COULD**, gated on Bet 1 |
| Realtime (WebSocket / SSE) | No | **A server** | **COULD**, gated on Bet 1 |
| Local peer sync (Network framework / Multipeer) | No | Local Network permission | **EXPERIMENT** |
| iPad organiser experience | **No — `TARGETED_DEVICE_FAMILY = 1`, iPhone only, portrait only** | Real design work | **COULD** |
| QR entry (scan a fixture / an entrant list) | No | Nothing | **SHOULD** |
| Camera / `DataScannerViewController` | No | A12+ device floor | **COULD** |
| Score-sheet OCR | No | Vision; validated against the engine | **EXPERIMENT** |
| Wallet passes (no remote updates) | No | Pass Type ID + a signing host | **COULD** |
| Wallet passes with remote updates | No | **A server + APNs + 4 endpoints** | **REJECT for now** |
| Sign in with Apple | No | **A server** — and see §6 | **COULD**, gated on B4 |
| Passkeys | No | **A full WebAuthn relying party** | **COULD**, gated on B4 |
| CloudKit / `CKSyncEngine` | No | iCloud, iOS 17 | **EXPERIMENT** |
| SwiftData + CloudKit | No | — | **REJECT** — forbids `@Attribute(.unique)`, forces every property optional, add-only schema evolution. Hostile to an evidence journal. |
| Foundation Models (on-device LLM) | No | iOS 26 | **EXPERIMENT** |
| SpeechAnalyzer (hands-free scoring) | No | iOS 26 | **EXPERIMENT** |
| tvOS app | No | 4–8 weeks **+ a networking layer you don't have** | **REJECT** |
| App Clips + App Clip Codes | No | 15 MB budget, second target | **REJECT** |
| NFC | No | Entitlement | **REJECT** |
| Apple Pay / Tap to Pay | No | Merchant id, PSP, entitlements | **REJECT** (no payments exist or are planned) |
| Critical Alerts | No | An approved entitlement Apple will not grant | **REJECT** |
| Apple Intelligence App Intent schemas | No | **No sports domain exists** | **REJECT** |
| Communication notifications | No | Capability + service extension | **REJECT** — a 4.5.3 / 2.5.16 review risk |
| Live Activity broadcast channels | No | A server; irreversible capability | **COULD**, far future |
| Handoff | No | `NSUserActivity` | **COULD** |
| Vision Pro / visionOS | No | — | **REJECT** — visionOS does not support Live Activities, and there is no darts there |

---

## 5. EXTERNAL INTEGRATION OPPORTUNITIES

Researched against public documentation and terms of service. **Nothing here proposes reverse
engineering or scraping.** Where the only route in would breach a service's terms, it is in "not
possible" and stays there.

### Available now

| Target | What you get | Note |
|---|---|---|
| **OBS / vMix** — a club stream overlay | OBS **Browser Source** is full Chromium; **obs-websocket v5 has been bundled with OBS since v28** (port 4455, documented protocol); vMix **Data Sources** reads JSON from a URL and updates titles automatically | **Free, documented, needs nobody's permission.** DartConnect already proved the demand with DCTV. A hosted scoreboard page plus a small JSON feed is a club streaming product in days. **Best value-to-effort of any integration.** |
| **DartConnect public API** | `public-api.dartconnect.com`. Confirmed endpoints `/tournaments`, `/org-group-members`; staging mirror exists | **Key by request to customer service.** They are Official Scoring App of the PDC and Official Partner of the WDF. Bulk export today is CSV only. **The API's own terms are unverified — read them when you request the key.** Both your best integration and your strongest incumbent. |
| **LeagueRepublic** | A documented public **JSON API** in three tiers, plus embeds — and a **dedicated darts page** that already understands 501/301/Cricket | The most realistic route to real UK grassroots league data that somebody else already maintains. Base URLs and auth unverified (help centre unreachable). |
| **Challonge** | API v2.1 with **OAuth**; single elimination, double elimination, round robin, Swiss | **A paid plan is required above 500 requests a month, with the grace period ending 6 July 2026.** Bracket plumbing, not darts data. |
| **Toornament** | v2 API, viewer/participant/organizer scopes; a **Generic discipline** exists for unlisted sports | Darts as a first-class discipline is unverified. |
| **TheSportsDB** | Has a PDC Darts league; unusually permissive terms | **"You cannot publish apps to an appstore unless you are a paid subscriber" — the $9/mo tier is mandatory for an iPhone app, not optional.** |

### Possible partnership

| Target | Why | Ask |
|---|---|---|
| **Scolia** | A published page inviting third parties to build the scorekeeping layer on their detection. Per-throw ground truth from a premium board. Not launching a rival league platform. | **Send this email first.** |
| **iDarts** (idarts.nl) | The darts statistics database — PDC, WDF and BDO, the only one including pairs and team tournaments, with an API export function, and **now inside the WDF's own rankings pipeline via DartConnect**. | The best darts-native alternative to a betting feed. Pricing not public. |
| **Gran Darts (Granboard)** | The BLE protocol is fully mapped by the community across six-plus independent implementations — service UUID, hit notifications, all 88 segments, LED writes. Talking BLE to a board the *user already owns* involves no account, no terms and no server. | It is also **not sanctioned**: no licence, no support, no promise it survives a firmware update. **Ask before shipping.** |
| **Sportradar** | Official PDC data partner since 2011; darts v1 and v2 APIs documented. | **They distribute official PDC data to the betting industry *exclusively* and to media *non-exclusively*** — the media track is the only door. Reported at $10,000+/month. See the caution below. |
| **Lidarts** | AGPL-3.0, no API; a third party resorted to a scraper. The clean move is to **contribute a read API upstream** and consume it. | **Do not reuse its code in a proprietary backend — AGPL's network clause would oblige you to publish yours.** |
| **Winmau / Autodarts** | Local Board Manager on port 3180 is *de facto* open — Home Assistant, ioBroker and ESP32 clients consume it today. | **De jure undefined: no endpoint reference, no schema, and no API terms at all** — which is worse than restrictive terms, because there is nothing to comply with and nothing to rely on. And you would be asking a direct competitor. |

### Requires investigation

**Tournament Planner / Visual Reality** — a darts product genuinely exists, but I could find no API,
no developer portal and no published export schema. Ask them directly; do not assume.
**Sport:80** — 90+ governing bodies, an integrations page, no public API docs, and no evidence any
darts body uses it. A trigger to re-check, not a project.
**Unicorn Smartboard** — BLE, discoverable, but no published GATT profile and no SDK.
**Goalserve, Stats Perform/Opta** — darts coverage could not be confirmed on any page. Do not assume it.

### Not possible

| Target | Why |
|---|---|
| **DartCounter** | The most restrictive terms found anywhere. Forbids scraping, automated access, **access through a user's own credentials or tokens**, derived statistics, **and operating a "competing, complementary, related or derivative product or service."** Aimed squarely at an app like THRØ. There is no compliant route. |
| **Target Omni** | Target's four-camera auto-scorer, sold *"exclusively for DartCounter"*. A sealed loop that inherits the terms above. |
| **DARTSLIVE / PHOENIXDART** | Closed, card-locked Asian soft-tip machine networks. The account graph is the business. No developer surface at all. |
| **PDC directly** | No feed exists, and pdc.tv's terms forbid reproducing content **including "statistics"** without written permission. |
| **Battlefy** | No official API; community wrappers ride undocumented endpoints. Challonge does the same job legitimately. |
| **api-sports.io** | Does not carry darts. |
| **JDC, the DRA, UKDA county darts, every national federation** | No machine-readable feed anywhere. Hand entry or organiser upload is the only path — **which is a product opportunity, not an integration.** |
| **Spond, TeamSnap, "Superleague"** | No public API found; "Superleague" is a league name, not software. |

### Three corrections to the brief's list

- **"DartConnect Omni" does not exist.** Omni is a **Target Darts** product paired exclusively with
  DartCounter. No evidence DartConnect has any camera-scoring hardware.
- **"Target Nexus" does not exist** — no evidence of any Target product by that name.
- **`dartcounterapp.com` is not DartCounter** (that is `dartcounter.net`). Its "DartCounter API" page
  describes an API for which no independent evidence exists. **Do not build against it.**

### The betting caution, flagged because you asked

Sportradar, Enetpulse, Goalserve, Statorium and SportDevs are built for, priced for and shaped by the
betting industry, and the PDC's exclusive betting carve-out ties the good data to gambling
distribution. Darts has an active integrity regime under the DRA and the JDC has a junior remit. **A
grassroots and junior-facing app visibly running on betting infrastructure invites questions you do not
want**, on top of App Store age-rating scrutiny. iDarts is the exception: darts-native, trusted by the
WDF and by commentators, and not *of* that industry.

---

## 6. THINGS I MISSED — and one you asked about directly

### "What about being able to log in with Apple ID on iOS and similar for Android?"

Answered precisely, because three parts of the usual answer are wrong.

**1. Sign in with Apple is not required just because you have accounts.** Guideline 4.8 triggers only
if you use a **third-party or social** login (Google, Facebook, X, LinkedIn, Amazon, WeChat) for the
primary account. Apple's own exception list includes *"your app exclusively uses your own account setup
and sign-in systems."* If THRØ's identity is its own, Sign in with Apple is a **choice, not an
obligation**.

**2. It does not save you a backend — it needs one.** On Android and the web there is no native SDK;
you use the OIDC web flow, which needs a **Services ID** as the client id (not your App ID), a
registered domain hosting `/.well-known/apple-developer-domain-association.txt` where **a 301 on that
path fails verification**, and a server that exchanges the code — where the client secret is **an ES256
JWT you sign yourself** from a `.p8` key, valid at most six months and **regenerated, not static**. Plus
JWKS validation and `/auth/revoke` on account deletion, which is **required**.

Two traps: **name and email are returned only on the very first authorization** — lose them and they
are gone; and **as of 24 August 2026 Apple is issuing private relay addresses on `private.icloud.com`**
alongside the existing `privaterelay.appleid.com`. Allowlist both.

**3. Passkeys are the better bet if you are building a backend anyway — and they are not serverless.**
This is the most common misconception. A passkey needs a **full WebAuthn relying party**: single-use
challenges, attestation and assertion verification, credential and signature-counter storage,
revocation, recovery — plus a `webcredentials` AASA file, without which the request errors out. What
they buy is one server serving iOS, Android and web with no per-platform SDK, and cross-device sign-in
by QR and BLE proximity.

**My recommendation: neither, yet.** Both are downstream of B4, which is a *design* blocker —
`DESIGN_UNSPECIFIED.md` records that there is no sign-in screen, no enrolment, no recovery and no
session management anywhere in the approved system. Choosing an auth mechanism before the surface is
designed is choosing it by implementation convenience, which is the thing the open-decisions register
exists to prevent. When it is designed: **passkeys as the primary, Sign in with Apple as a
convenience, your own identity as the record.**

### Things not in your brief that I would put on the list

1. **Local peer networking — the structural moat.** Darts is intrinsically multi-device: the marker's
   phone, both players' phones, the venue screen. The whole category solves this by having every device
   open a browser against a cloud server **in pubs, over pub Wi-Fi** — which is exactly why
   DartConnect's own docs describe spinners between legs and matches "not fully saved". Apple's Network
   framework and MultipeerConnectivity include **peer-to-peer Wi-Fi that needs no access point at
   all**. Two phones at the oche can corroborate a result with no server and no Wi-Fi. That is the
   second-device half of PD-002 and Bet 2, available offline. Note it needs
   `NSLocalNetworkUsageDescription` and **denial is near-silent** — discovery just returns no peers, so
   "found nobody" is ambiguous between *nobody is here* and *you said no*, and this app should say so.
2. **`CADisableMinimumFrameDurationOnPhone` defaults to NO** — 120 Hz is *unavailable* to the app until
   you set it. One line, for an app whose opening is a 4.86-second animation.
3. **Foundation Models (iOS 26)** — an on-device LLM with no server, no token cost and no network.
   Structured extraction from a free-text note into schema-validated metadata; natural-language search
   over local history. **The discipline is non-negotiable: model output is a proposal, never evidence,
   and must land in a distinct confirmable state before touching the append-only journal.** Note prompt
   behaviour is **not stable across OS point releases**.
4. **SpeechAnalyzer (iOS 26)** — fully on-device transcription, no network, built for distant audio.
   Hands-free scoring at the oche, which six competitors do with in-app recognition and none exposes
   anywhere useful. Not available on watchOS.
5. **`BGContinuedProcessingTask` (iOS 26)** — the first background primitive that is visible,
   progress-reporting and cancellable, with a system Live Activity. It is honest by construction, which
   is why it suits this app better than `BGProcessingTask` ever did.
6. **The new age-rating questionnaire** — responses were due 31 January 2026, and **a pub and darts
   context will hit the alcohol questions.** Worth answering deliberately rather than discovering.
7. **iPad is not merely un-optimised — it is switched off.** `TARGETED_DEVICE_FAMILY = 1`, iPhone only,
   portrait only. An organiser's iPad experience is not a stretch of the current UI; it is a new
   platform decision and a design commission.
8. **Handoff** — an `NSUserActivity` per match makes a leg pick up on another device the moment there
   is another device.
9. **A darts-native reason to own the venue screen.** Everything above is generic. The specific thing:
   the caller and the marker are still formal roles in the sport. A venue board that shows *who is on
   next and on which board* replaces the shouting, not the scoreboard.

### The one thing I would tell you is missing from the whole plan

There is a **defect class** the brief's Apple list cannot fix. Three rows in the runbook claimed
shipped features were absent — attestation, haptics, and the checkout route — for weeks. I fixed those
and added `tools/check_absence_claims.py`, because **a claim of absence decays in the direction of a
lie**: the code gains a capability and the sentence does not notice. Every surface in this report —
a widget, a Live Activity, a share card, a TV board — is a **new place for a claim to be made**, and
none of them is covered by a test that renders a screen. Before building six new surfaces, it is worth
deciding how you will hold them to the same honesty standard as the ones you have.

---

## 7. DO NOT BUILD

| Thing | Why not |
|---|---|
| **NFC** | Loses to a QR code on every axis. A QR is ink — free on a sheet, a beermat, a shirt; tags cost money each. **Background reading needs iPhone XS+, an unlocked phone, and none of {camera open, Wallet open, reader session active}** — in a pub, "camera open" and "phone in a pocket" are the normal states, **and a tap that does nothing, with no error, is the worst possible failure for an app whose brand is honesty about uncertainty.** Both paths end at the same universal link. A QR can be screenshotted into the league WhatsApp group; a tag cannot. Only case it wins: a venue-owned tag beside the board, which is a partnership product — and even then, print a QR on the same sticker. |
| **A tvOS app** | 4–8 weeks, and the blocker is not the UI: **an Apple TV cannot read the iPhone's local store.** You would need a server, CloudKit or a local peer link — **and pub Wi-Fi breaks all three.** You would invent a networking layer for an app whose premise is that it has none. A £50 HDMI adapter works offline, today, at your current floor. |
| **App Clips + App Clip Codes** | **15 MB when invoked by a physical code**, not 100 MB. A second target, a second review surface, App Store Connect experience configuration, and physical code production — to buy a branded scan affordance and a no-install trial. A plain QR to a universal link costs nothing and works on Android. |
| **Apple Pay / Tap to Pay** | There are no payments and none planned; OD-009 is open. Recorded for when it closes: Apple Pay needs a merchant id, a payment processing certificate that **expires every 25 months**, an entitlement, and **a payment processor — Apple Pay is a card presentation method, not an acquirer.** Tap to Pay additionally needs an organization account, a two-stage entitlement approval and a **Level-3 PCI-certified PSP**. |
| **A full Apple Watch scoring companion** | **In darts you throw with the arm the watch is on.** Wrist input during a leg is ergonomically wrong. 6–10 weeks plus a permanent two-codebase tax on every scoring rule. The option that looks impressive and gets used by nobody. |
| **`WKExtendedRuntimeSession` for a watch scoreboard** | Apple supports exactly four session types: self care, mindfulness, physical therapy, smart alarm. **There is no sports or scoring type.** Claiming "mindfulness" to keep a darts scoreboard alive is an abuse of the API and a review risk. |
| **Apple Intelligence App Intent schemas** | **There is no sports, scoring, game or competition domain.** Nothing to conform to. |
| **Critical Alerts** | Requires an entitlement request Apple grants for health, safety and public safety. A darts app will not get it. Time Sensitive is the ceiling and is the right level anyway. |
| **Communication notifications for score alerts** | Designed for person-to-person communication. Dressing up a score alert as one is a 4.5.3 / 2.5.16 review risk. |
| **Wallet passes with remote updates** | A pass **cannot be updated remotely without a server**: a web service URL, four REST endpoints, an APNs client authenticating with the pass type certificate, and a registration store. And it **cannot be safely generated on-device**, because signing means shipping the Pass Type ID private key inside the app where any user can extract it. A static pass with no updates is a **COULD**; the rest is a server project wearing a pass. |
| **SwiftData or Core Data + CloudKit** | Forbids `@Attribute(.unique)`, forces every property optional-or-defaulted and every relationship optional, bans `.deny` delete rules, and locks you into **add-only schema evolution** where renaming reads as delete-plus-add. Directly hostile to a constrained, append-only evidence journal. |
| **Chromecast / smart-TV browser for club mode** | Chromecast has no native iOS support — a third-party SDK, a registered receiver app, a privacy-manifest disclosure and permanent maintenance. A smart-TV browser needs a hosted web app **and a server**. |
| **`AVRoutePickerView` as "TV mode"** | It is a media route picker for `AVPlayer`. It does not initiate screen mirroring. Shipping it under that label produces a day-one bug report. |
| **Any DartCounter integration** | Their terms forbid automated access, credential-based access, derived statistics, and operating a competing or complementary product. There is no compliant route. |
| **visionOS** | Does not support Live Activities, and there is no darts audience there. |
| **A ranking-movement notification, an ELO widget or an ELO share card** | **There is no rating.** OD-001 is open and names *"shipping a placeholder rating to fill the UI"* as exactly how it would be decided by accident. Building the surface first is how the decision gets made for you. |

---

## 8. DECISIONS I NEED FROM YOU

Nine. Decisions 1–3 unblock work that can start immediately; 4 gates roughly half the brief.

```
DECISION — APPLE WATCH

A — Full companion (score a leg on the wrist)
    Pros  The most impressive demo. Nobody in darts has it.
          Reuses the engine unchanged — engine-swift and statistics-swift declare no platform
          restriction at all, deliberately, so they already compile for watchOS.
    Cons  In darts you throw with the arm the watch is on. Wrist input mid-leg is ergonomically wrong.
          6–10 weeks, then a permanent tax: every scoring rule change lands in two codebases.
          Needs its own screenshots, review and release train.
          OD-020 is blocked on a durability measurement nobody has taken — the probe can be pointed
          at watchOS; nobody has a watch to point it at.

B — Tournament companion (a glance surface plus a haptic when it is your throw)
    Pros  Real value: the non-throwing player checks their wrist instead of reaching across the table.
          One-way phone-to-watch over WatchConnectivity needs no server and no network.
          2–4 weeks.
    Cons  Still a second target, a second release train, and a second design surface.
          A background "you're up" tap must come from a notification — WKInterfaceDevice.play only
          fires while the watch app is active.

C — Notifications and complications only
    Pros  The first tranche is FREE. An iPhone Live Activity appears automatically in the Apple Watch
          Smart Stack (iOS 18 / watchOS 11) with no watch app written, and local notifications from
          the phone mirror to the watch for nothing.
          A watch-face complication is 3–5 days on top, not weeks.
          Near-zero ongoing cost.
    Cons  No wrist input, ever. No watch-native scoring story to market.

Recommended: C, then B only if players ask for it.
The Smart Stack surface arrives as a by-product of recommendation 1, so C costs you nothing to
start and forecloses nothing. A is the option that looks impressive and gets used by nobody.

MY CHOICE: [ ]
```

```
DECISION — CLUB TV MODE

A — External display scene over HDMI
    Pros  Available at your CURRENT iOS 16 floor — the scene role is exactly iOS 16.0.
          Deterministic: no network, no discovery, no pub Wi-Fi involved.
          ~50 lines of UIKit scene-delegate code; iOS 27 adds a SwiftUI-native API later.
          A £50 Apple Digital AV Adapter, carried by the organiser.
    Cons  Someone must carry a cable and an adapter. The display is non-interactive by definition.

B — AirPlay to a venue Apple TV
    Pros  Falls out of A's code for FREE — the system creates the same scene when the user turns on
          mirroring. No extra work.
    Cons  The user must start it from Control Center; there is no API to initiate mirroring.
          Both devices must be on the same network, and pub guest Wi-Fi very commonly has client
          isolation, which kills AirPlay discovery entirely.
          A bonus, never the plan.

C — A browser page on a smart TV
    Pros  Any screen with a browser.
    Cons  Needs a hosted page AND a server to get state from the phone to it — contradicting the
          local-first premise. Pub smart-TV browsers are awful or absent.

D — A tvOS app
    Pros  The best-looking venue product, and only one darts app on the store has one.
    Cons  4–8 weeks. SwiftUI compiles for tvOS but the code does not port — it is a focus-engine
          platform with no taps and no gestures; every control needs a focus state and layouts must
          be 10-foot legible.
          And the real blocker: an Apple TV cannot read the iPhone's local store. You would need a
          server, CloudKit or a local peer link, and pub Wi-Fi breaks all three.

Recommended: A, with B free alongside it.
Revisit D only after Bet 1 exists and a venue has asked for it twice.

MY CHOICE: [ ]
```

```
DECISION — DEPLOYMENT TARGET

A — Stay on iOS 16
    Pros  Nothing to do. Reaches every phone the app reaches today.
    Cons  Apple's June 2026 figures: 79% iOS 26, 14% iOS 18, 7% everything older COMBINED.
          Costs symbol effects, scroll transitions, visualEffect, mesh gradients, zoom navigation
          transitions, the SwiftUI Map API, Look Around, EventKit's write-only tier, CKSyncEngine,
          interactive widgets, Control Center controls and Spotlight-indexed App Intent entities.
          A widget at iOS 16 is a static picture you cannot tap.

B — Raise to iOS 17
    Pros  Unlocks symbol effects, scroll transitions, visualEffect, ContentUnavailableView,
          interactive widgets, AppIntentConfiguration, StandBy, the SwiftUI Map API, Look Around,
          EventKit write-only access and CKSyncEngine.
    Cons  Still no Control Center controls, no Spotlight-indexed entities, no mesh gradients,
          no zoom transitions.

C — Raise to iOS 18
    Pros  Everything in B, plus Control Center controls and the Action Button, Spotlight-indexed
          App Intent entities, mesh gradients, zoom navigation transitions, MapKit place cards,
          and the Live Activity surfaces that make recommendation 1 worth building — Apple Watch
          Smart Stack, tailored StandBy, activity families.
          Reaches roughly 93% of devices on Apple's own figures.
    Cons  Drops the remaining single-digit tail.

Recommended: C.
Two facts make this cheaper than it sounds. There is not one #available in the entire client, so
raising the floor is a pure unlock with no compatibility code to delete. And the floor costs THRØ
less than it would a typical app, because your design system already answers much of what the new
APIs offer — ContentUnavailableView would be a REGRESSION next to the approved EmptyState, and
.sensoryFeedback would lose ThroHaptics' four named events. Keep those; take the rest.

MY CHOICE: [ ]
```

```
DECISION — THE BACKEND, AND WHEN

A — None. Stay local-first indefinitely.
    Pros  Everything in sections 1 and 2 still ships. No hosting, no on-call, no data protection
          surface, no cost. The app keeps its strongest honest claim: nothing leaves the phone.
    Cons  Forecloses the board call, "you're up next", organiser updates, spectators, joining
          someone else's club, linking a fixture result to a scored match, and every cross-device
          notification. Roughly half your brief.

B — A domain and static hosting only (~£10/year plus a free Pages host)
    Pros  Buys universal links, shareable https:// links that open the app, a public club front,
          and an OBS/vMix browser-source scoreboard for club streams.
          No server, no on-call, no personal data.
    Cons  Still no push, no sync, no cross-device anything.
          AASA propagation is up to 24 hours to Apple's CDN and about a week to installed apps.

C — A real server: identity (B4), sync (ADR-006), APNs
    Pros  Unblocks everything above and Bet 2's second device.
          services/api already has the command path, idempotency, per-device sequences, the
          authorization model and the audit log — tested, and not deployed.
    Cons  Identity is B4, a founder blocker, and it is a DESIGN blocker: there is no sign-in screen,
          no enrolment, no recovery and no session management in the approved system.
          Hosting, on-call, secrets, data protection, and an APNs operational tail.
          OD-001 still gates anything that looks like a ranking.

Recommended: B now, C when B4 is designed.
B is cheap, reversible, and unblocks the club-streaming integration that the market research rates
as the single best value-to-effort item available. C should not start before its design does.

MY CHOICE: [ ]
```

```
DECISION — REALTIME ARCHITECTURE (only if C above)

A — WebSocket
    Pros  Sub-second, bidirectional, well understood.
    Cons  Dies when the app suspends. Apple's own guidance is that keeping one alive in the
          background "isn't a way to do this in the general case."

B — Server-sent events
    Pros  Simpler than a WebSocket for one-way updates; plain URLSession.
    Cons  Same suspension death. One-way only.

C — APNs background push as the channel
    Pros  Reaches a suspended app.
    Cons  Apple states plainly: "the system doesn't guarantee their delivery" and "don't try to send
          more than two or three per hour." It is a refresh HINT, never a channel.

D — Polling
    Pros  Trivial.
    Cons  Worst of both: dies on suspension anyway, burns battery and connections.

Recommended: a foreground WebSocket, a VISIBLE push for anything consequential, and a full
reconcile-on-foreground that treats every local state as possibly stale.
Sub-second background awareness on iOS does not exist. Any architecture that claims it is wrong,
and this app should not be the one that claims it.

MY CHOICE: [ ]
```

```
DECISION — HOW EXTENSIONS READ THE APP'S DATA

A — Move the container to an App Group
    Pros  One store, no duplication; widgets, Watch and Live Activities all read the real thing.
    Cons  Migrates journal.sqlite — the only copy of what was thrown — off the path ADR-006
          measured its durability on. New entitlements and provisioning profiles, touching the
          TestFlight signing workflow.

B — Leave the journal where it is; write a small read-only PROJECTION into an App Group container
    Pros  The evidence file never moves. No migration of the only copy of what was thrown.
          The projection is regenerable, so it can be correctly EXCLUDED from backup — which is what
          Apple's guidance actually asks for, and BackupPolicy already exists to make that decision
          explicit rather than default.
          Matches what ADR-006 already says the architecture is: "the UI renders the projection; the
          projection is a fold of the journal." A widget is just another renderer of a projection.
          Keeps a second process out of SQLite entirely — no second writer, no WAL contention, no
          extension holding a lock while somebody is scoring.
    Cons  Two representations to keep in step. Still needs the App Group entitlement.

C — No extensions at all
    Pros  Nothing to decide.
    Cons  Forecloses widgets, a Watch app and any Live Activity that must survive the app closing.

Recommended: B.
Note an App Group requires a paid Apple Developer Program membership, and if a store is ever moved
into a group container, that choice must be made before there are users to migrate.

MY CHOICE: [ ]
```

```
DECISION — LIVE ACTIVITY SCOPE

A — Local only, no server
    Pros  Ships now. No infrastructure. 8 hours active plus 4 lingering covers a league night.
          Timer text keeps counting with your code not running.
    Cons  Nothing updates while the app is backgrounded, and nothing reaches a second phone.
          Must degrade honestly via staleDate rather than showing a number it cannot vouch for.

B — Local, plus APNs updates later
    Pros  Same code; the server becomes an additional updater when it exists.
    Cons  Push-to-start needs iOS 17.2; the 4 KB payload cap covers attributes and state combined;
          push tokens rotate mid-activity and must be invalidated server-side.

C — Broadcast channels for spectators
    Pros  One push reaches every spectator without per-device tokens.
    Cons  iOS 18+. The capability can ONLY be enabled at developer.apple.com, never in Xcode, and
          DISABLING IT PERMANENTLY INVALIDATES EVERY CHANNEL ID — irreversible.

Recommended: A now, B when the server exists, C only if spectating becomes a real product.

MY CHOICE: [ ]
```

```
DECISION — SHARE CARDS

A — Rendered on the device with ImageRenderer
    Pros  Works today at iOS 16. No backend. Uses the real design system and the real tokens.
    Cons  Output varies slightly with device and text size. No link preview, because there is no link.

B — Rendered by a backend
    Pros  Identical output everywhere; a proper link preview when someone pastes the URL.
    Cons  Needs the server you do not have, plus image hosting and a cache.

Recommended: A.
Whichever you choose, one rule: a share card is a claim leaving the phone, so it must carry its
verification state and its sample the way every other figure in this app does. A card showing a
three-dart average without saying it is self-reported over four legs is the same laundering PD-020
forbids in a league table.

MY CHOICE: [ ]
```

```
DECISION — IDENTITY, WHEN B4 IS DESIGNED

A — Sign in with Apple as the primary
    Pros  Familiar; private relay by default.
    Cons  Apple-only as a native experience; Android and web need the OIDC flow with a Services ID,
          a domain association file, and a self-signed ES256 client secret regenerated every six
          months. Name and email are returned ONLY on the first authorization.
          And it is NOT required: guideline 4.8 triggers only if you use a third-party or social
          login, and exempts apps that use their own sign-in exclusively.

B — Passkeys as the primary, Sign in with Apple as a convenience
    Pros  One WebAuthn server serves iOS, Android and web with no per-platform SDK. Cross-device
          sign-in by QR and BLE proximity. No password to leak.
    Cons  A full relying party: challenges, attestation and assertion verification, credential and
          counter storage, revocation, recovery — plus a webcredentials AASA file, without which
          the request simply errors.

C — Your own email or phone identity
    Pros  Total control; no platform dependency.
    Cons  You own recovery, deliverability and every abuse vector. The least interesting work.

Recommended: B, with A as a convenience and your own identity as the record.
But not yet — B4 is a DESIGN blocker, and choosing the mechanism before the surface exists is
choosing it by implementation convenience, which is what the open-decisions register exists to stop.

MY CHOICE: [ ]
```

---

## 9. RECOMMENDED IMPLEMENTATION ORDER

The dependencies are real. Three foundations carry almost everything else.

### Foundation A — routing (blocks the most)

**Nothing can be opened from outside the app until this exists.** Widgets, Live Activity taps,
Spotlight results, App Intents, share links and universal links all terminate in "open the right
screen," and today there is no route that can be named, serialised or reached from the app scene.

→ **Do this first.** One serialisable route, a router the scene can reach, a custom URL scheme,
`onOpenURL`. Then Core Spotlight, App Intents and the Live Activity's tap target all become small.

### Foundation B — honest write states (blocks the server)

Build `pending → inFlight → acked | failed` on the client **before** the server exists. It decides
what the app is allowed to claim, and it is the piece that makes ADR-006's reconciliation
implementable rather than aspirational. Delete or gate the sync chrome that currently promises a
server, so nobody ships its copy by accident.

### Foundation C — the extension boundary (blocks widgets and the Watch)

Decide the App Group and the projection (§8, decision 6) before writing a widget, a Watch target or a
Live Activity that must outlive the app. Getting this wrong means migrating the journal twice.

### Then, in order

1. **Live Activity** — needs A for its tap target; needs nothing else. Delivers the Watch Smart Stack
   surface for free.
2. **External display / club TV** — independent of everything; could run in parallel from day one.
3. **Core Spotlight, App Intents, share cards, local notifications, MapKit, EventKit, MetricKit** —
   all small, all after A.
4. **The haptic language and the accessibility gaps** — independent; do them whenever there is a gap
   between larger pieces.
5. **The deployment-target decision** — before the motion and polish work, because it decides what
   that work can use.
6. **Widgets** — after C.
7. **A domain and static hosting** — unblocks universal links and the OBS/vMix club scoreboard.
8. **The server, identity and sync** — after B4 is designed. Then push, realtime, spectators, and the
   second device that makes Bet 2 real.
9. **Scolia, DartConnect and LeagueRepublic** — the emails can go today; the integrations land after
   the server.

### What NOT to sequence

Do not start the Watch, tvOS, App Clips, Wallet, NFC or payments at all. Sections 4 and 7 say why.
And do not build a ranking surface of any kind before OD-001 closes: the decision names *"shipping a
placeholder rating to fill the UI"* as exactly the way it would be made by accident, and a widget is
a very good place to make that mistake.

---

*Nothing in sections 1–7 has been implemented. The corrections in §0 and the guard described at the
end of §6 were the only code changes made while producing this report.*
