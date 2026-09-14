# THRØ Design System — Inventory

Generated from the committed design export under `extracted/`. This is the
authoritative list of what the approved system contains, and the basis for the
component mapping (Claude Design → iOS → Android → web) once platforms are chosen.

## Components — 61 across 10 families

| Family | Count | Components |
|---|---:|---|
| `core` | 6 | Button, Divider, Icon, IconButton, SectionHeader, Tag |
| `data` | 4 | ComparisonChart, Insight, Stat, TrendChart |
| `development` | 6 | Bracket, PathwayStep, ShadowSelector, TournamentProgress, TrainingDrill, TrainingSession |
| `forms` | 6 | FilterChip, NumericInput, SearchField, SegmentedControl, Tabs, TextField |
| `identity` | 7 | EventHero, EventRow, PlayerComparison, PlayerIdentity, PlayerRow, TeamRow, VenueRow |
| `navigation` | 2 | BottomBar, TopBar |
| `organiser` | 3 | BoardStatus, CallControl, DataTable |
| `rating` | 6 | Confidence, FormIndicator, Rank, RatingCompact, RatingHero, RatingMovement |
| `scoring` | 9 | Checkout, LegState, MatchHeader, MatchSummary, RemainingScore, ScoreHero, ScoreKeypad, SetState, TurnIndicator |
| `state` | 12 | Dialog, EmptyState, ErrorState, LiveIndicator, LoadingState, Notification, OfflineState, Progress, Sheet, Snackbar, SyncState, VerificationState |

## Drawn by engineering, not exported — 1

PD-010 commissioned the club, league, tournament and profile screens from engineering, to be built
**from** the approved system rather than from scratch. Where the system genuinely lacked something,
the rule was to draw it in the system's own idiom and record it here rather than slip it in. Exactly
one element needed that.

| Component | Where | Why it is not exported, and what it borrows |
|---|---|---|
| `Badge` | `ThroDesign/Club.swift` | A club, league or tournament's mark. The export draws a mark for a **person** — `PlayerIdentity`'s grey circle with the initials in the condensed face — and that is untouched and still used for people. A club needed one too, and it is a **rounded square in the club's own colour**, so that a club and a person never read as the same kind of thing in a list. Same face, same proportion (0.38 of the mark), same border weight as the exported mark; only the shape and the fill differ, and both differences carry meaning. The initials on a club's colour are chalk or ink — whichever reads better against it, chosen rather than configured, which is the same guarantee `packages/organisation` makes for the accent. |

Two further composites in the same file — `OrganisationRow` and `OrganisationHeader` — are assembly
rather than invention: a row is `Badge` plus two type roles, and a header is a band of the club's
accent with `Badge`, `Tag` and `Icon.circleCheck` on it. Nothing in either introduces a value.

**Four glyphs were ported, not invented.** `lock`, `shield`, `calendar` and `search` were already in
the export's own icon set (`extracted/components/core/icons.js`) and had simply not been carried into
`ThroDesign` yet. Their path data is verbatim, as every other glyph's is.

**The club editor and its picker (PD-014).** `EditClubScreen` is `TopBar`, `PicturePicker`,
`ThroTextField`, `AccentPicker` and `ThroButton`. The picker wraps the platform's own `PhotosPicker`
— the same standing as the `DatePicker` on a fixture and the `Toggle` in Settings: it is the
operating system's control, not a component the export was expected to draw. **Until 2026-09-07 no
route reached this screen**, so none of it was on a phone; that is recorded in the change record and
is now checked mechanically by `tools/check_screens_reachable.py`. `Badge` gained one parameter, an optional image that fills the same
rounded square the initials would, so a list of clubs stays a list of one shape whether or not
anybody has uploaded anything. No new component, and no new value.

**Picking a colour, and the guarantee that was only kept on one side (PD-014, PD-010).** Three
elements here are engineering-drawn and are recorded rather than slipped in:

| Component | Where | Why it is not exported, and what it borrows |
|---|---|---|
| `AccentPicker` | `ThroDesign/Accent.swift` | Thirteen swatches and the platform's own `ColorPicker`. **Each swatch is drawn as the badge itself will be drawn** — the club's real initials, in whichever neutral THRØ picks for that colour — so the choice is made by looking at the outcome rather than imagining it. No new value: every swatch is a club's content and the well is the operating system's control, the same standing as the `DatePicker` on a fixture. |
| `AccentBranding` | `ThroDesign/Accent.swift` | Not a component — the arithmetic that decides which neutral goes on an accent. It exists because `Branding.kt` had stated that rule since clubs shipped, `BrandingTest` swept the cube to prove it, the pull request claimed it — and `Badge` set its initials in `colorTextInverse` unconditionally, which is chalk on a club's yellow at about 1.4:1. **A guarantee asserted on one side of a port is not a guarantee.** The two neutrals are fixed sRGB rather than the semantic tokens, because those swap with the appearance and a badge is a fixed-colour surface. |
| `PersonMark` | `ThroDesign/Forms.swift` | The circle `PlayerIdentity` has always drawn, **extracted** so a person can be marked at any size and carry a picture. Not a new element: same face, same 0.38 proportion, same fill and border. Drawing a second person-mark beside the first would have left two things that must be kept looking alike, which is the mistake `Badge` was careful not to make in the other direction. |

**The page bar is one component now, not four hand-rolled rows.** A club, a league, a tournament and
a profile all have a full-bleed header of their own, so none of them uses `TopBar` — and each grew its
own row of back-chevron-plus-actions. All four were wrong the same way: the row carried no screen
gutter, so the chevron's negative inset put it **off the left edge of the phone** and the last action
sat flush against the right one and was cropped. The founder found it on a screenshot.

`PageBar` (`ThroApp/ClubScreens.swift`) is that row, once: `BackChevron`, a `Spacer`, and worded
actions, with `spaceScreenGutter` on the row itself. It is assembly, not a new element — and the rule
it encodes is the one `TopBar` and `MatchHeader` already followed and these four did not: **a negative
horizontal inset belongs to a component that applies the gutter it is insetting from.**
`tools/check_screen_bars.py` now fails a build on a `BackChevron` built anywhere but here, and on any
negative horizontal inset outside `ThroDesign`.

**The picture picker is one control now, not one per screen (PD-014).** `PicturePicker`
(`ThroApp/PicturePicker.swift`) is `Badge` or `PersonMark` beside the platform's `PhotosPicker`, and
it is used by both the club editor and a member's picture. It **refuses before it offers**: where
PD-014 says no picture — anybody not established as an adult — there is no picker at all, only the
reason. A disabled control whose only outcome is a refusal would be worse than none, and here it
would be worse than cosmetic.

**The confirm-result screen is composition too (PD-011).** `ConfirmResultScreen` is `TopBar`,
`MatchSummary`, `PlayerIdentity`, `ThroButton` and `VerificationState` as they already exist. The one
thing it adds is words: the label alone would flatter what happened, so the screen says in plain text
that two people at one phone is two people agreeing rather than two devices, and that the names are
the ones typed at the start.

**Three entry screens are composition, not new components.** Starting a club, adding a member and
adding a fixture (`ThroApp/ClubFlow.swift`) are built from `ThroTextField`, `SegmentedControl`,
`ThroButton`, `Badge` and `TopBar` as they already exist. Two things in them are worth stating
because they are the kind of thing that gets slipped in:

- **The accent was a hex field. It is now a palette and a colour well, and that is a change of
  position worth stating rather than quietly editing.** The original reasoning was that a palette
  would mean engineering choosing a set of colours, and PD-010's first condition is that no value
  enters that the token layer does not have. The founder's answer: *"Can we use a better option than
  hex codes for colour select, not very user friendly."* They were right, and the original reasoning
  confused two things. A club's colour is **content**, like its name — it belongs to the club, not to
  THRØ — so offering thirteen suggestions is no more a design token than offering a placeholder name
  is. `AccentSwatch.palette` is recorded here as engineering-chosen content, not as tokens, and
  nothing in it is used anywhere but as a club's own accent.

  What made the change safe is unchanged and is the whole reason it is allowed: `packages/organisation`
  proves by sweeping the colour cube that **no** colour a club can pick makes the app unreadable, so
  the free colour well beside the swatches needs no curation. Since 2026-09-07 the Swift proves it
  too — see `AccentBranding` below, which is a defect this recorded guarantee did not prevent.
- **The date is picked with the platform's own `DatePicker`.** It is the operating system's control,
  not a component the export was expected to draw — the same standing as the `Toggle` already in
  Settings and the keyboard already under every text field. It is styled with the brand tint and
  nothing else.

## Participant app — screens

| Group | Screens |
|---|---|
| **Start** | Splash / launch (`splash`); Onboarding (`onboarding`) |
| **Home** | Home — active player (`home`); Home — match called (`home-called`); Home — new player (`home-new`) |
| **Play** | Match ready (`ready`); Scoring — standard (`scoring`); Scoring — checkout (`scoring-checkout`); Scoring — bust (`scoring-bust`); Scoring — offline (`scoring-offline`); Match result (`result`) |
| **Live** | Live directory (`live`); Live match centre (`live-match`); Stream view (`stream`); Followed players live (`following`) |
| **Tournament** | Check-in (`checkin`); Draw released (`draw`); Bracket — zoomed (`bracket`); Tournament complete (`complete`) |
| **Shadow** | Shadow overview (`shadow`); Shadow match setup (`shadow-setup`); Shadow — playing (`shadow-play`); Practice result (`shadow-result`) |
| **Discover** | Discover (`discover`); Event detail (`event`) |
| **You** | You — profile (`you`); Rating detail (`rating`); Coach insight (`coach`); THRØ Passport (`passport`) |
| **Account** | Notifications (`notifications`); Search (`search`); Settings (`settings`); Privacy (`privacy`) |

**33 participant screens** across 9 groups.

**Dark-theme screens:** `scoring`, `scoring-checkout`, `scoring-bust`, `scoring-offline`, `live-match`, `stream`, `shadow`, `shadow-setup`, `shadow-play`, `splash`  
The ink theme is reserved for focused competitive contexts, not used decoratively.

**Screens without bottom navigation:** `scoring`, `scoring-checkout`, `scoring-bust`, `scoring-offline`, `shadow-play`, `splash`, `onboarding`  
Navigation is removed during active scoring and immersive states.

## Organiser web kit — screens

| Screen id | Component | Icon |
|---|---|---|
| `control` | Control | `target` |
| `boards` | Boards | `grid-2x2` |
| `queue` | Queue | `list-ordered` |
| `entries` | Entries | `clipboard-check` |
| `draw` | DrawManagement | `git-fork` |
| `disputes` | Disputes | `triangle-alert` |
| `verification` | Verification | `circle-check` |
| `league` | League | `shield` |
| `venue` | Venue | `map-pin` |

**9 organiser screens.** A separate large-screen shell with a sidebar and an
organisation/role footer. Organiser workflows are not forced into participant mobile UI.

## Icon set — 70 icons

Generated from Lucide (MIT licence), delivered as inner SVG markup only; `Icon.jsx`
supplies the 24×24 viewBox, 2px stroke and round caps. Licence is permissive and poses
no packaging obstacle for iOS, Android or web.

`accessibility`, `arrow-down`, `arrow-left`, `arrow-right`, `arrow-up`, `award`, `bell`, `bell-ring`, `calendar`, `chart-no-axes-column`, `check`, `chevron-down`, `chevron-left`, `chevron-right`, `chevron-up`, `circle`, `circle-alert`, `circle-check`, `circle-dot`, `circle-question-mark`, `circle-slash`, `circle-user`, `circle-x`, `clipboard-check`, `clock`, `cloud-check`, `cloud-off`, `compass`, `ellipsis`, `eye`, `eye-off`, `file-pen`, `flag`, `gavel`, `git-fork`, `globe`, `grid-2x2`, `heart`, `house`, `info`, `lightbulb`, `list-ordered`, `loader`, `lock`, `log-out`, `map-pin`, `minus`, `move-right`, `pencil-line`, `play`, `plus`, `radio`, `refresh-cw`, `rotate-ccw`, `search`, `settings`, `share`, `shield`, `shield-check`, `smartphone`, `target`, `trending-up`, `triangle-alert`, `trophy`, `undo-2`, `user`, `users`, `video`, `wifi-off`, `x`

## Totals

- **61** components
- **33** participant screens
- **9** organiser screens
- **70** icons

### Ending a match short (PD-016), engineering-drawn

| Thing | Why it is not exported | What it is made of |
|---|---|---|
| `MatchHeader.onEnd` | The export's scoring screen has no way out at all, and the same header already carries an engineering-drawn `onBack` for that reason. A match that will not be played out has to be endable from the screen the players are looking at when it happens. | A trailing 44-point target on the header row that already exists, Lucide `x` from the approved set, `colorTextSecondary`. Costs nothing vertically, which is the constraint that decides this header's shape. |
| `EndMatchCard` | Nothing in the export offers a way to stop. | The `Eyebrow` / `heading2` / `metadata` / `ThroButton` stack `RetractionCard` already uses, because it is the same kind of moment: a serious recorded thing offered with its consequence stated first. |
| `EndMatchConfirmCard` | As above. | The same stack, plus one `colorStatusError` line saying it cannot be undone — the part that would otherwise be a surprise, since PD-004 makes a mis-keyed visit undoable and a player will reasonably expect the same here. |
| The "No result" row state | The export draws finished and in-progress. It does not draw *finished with no result*, because nothing in the design ends a match early. | `Tag` in `neutral`. Deliberately **not** a `VerificationState`: there is no result, and a self-reported badge would attest to a claim nobody made. |

### The four design commissions (PD-015), engineering-drawn

| Thing | Why it is not exported | What it is made of |
|---|---|---|
| `StatItem.Confidence` and `StatGrid`'s three forms | `DESIGN_UNSPECIFIED` #9: the export's `Stat` takes label/value/delta/unit and has nowhere for a figure that cannot be honestly computed. | The same `Eyebrow` / sport-face value / metadata note the export draws, plus `colorTextSecondary` for a figure that is not a fact and an approved `Tag` reading "Range". No new colour, no new type role. |
| `ThroPressStyle` | `DESIGN_UNSPECIFIED` #2: zero of 61 components implement a pressed state. | `motionScaleImpact` inverted, `motionDurationInstant`, and a fill one step along. Every value is a token; nothing is a number typed here. |
| `ThroFocusRing` | Same item. The export's own focus ring fails contrast on brand and ink surfaces, so a colour alone would not have been an answer. | A 2-point `colorSurfaceBrand` stroke drawn *outside* the control's border, so it never overlaps an error border and the contrast problem does not arise. |
| `ThroHaptics` | `DESIGN_UNSPECIFIED` #25: nothing specified for the keypad, where it matters most. | Not drawn at all — four named events mapped to the platform's own feedback generators, with the mapping asserted by a test because "four different sensations" is the whole claim. |
| The Dynamic Type ceiling | `DESIGN_UNSPECIFIED` #1: the export's type scale is fixed pixels with no clamps. | `dynamicTypeSize(...)` on one screen. The contract, including the limit it accepts and why, is `docs/design/DYNAMIC_TYPE.md`. |

