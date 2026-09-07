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

**The club editor and its picker (PD-014).** `EditClubScreen` is `TopBar`, `Badge`, `ThroTextField`
and `ThroButton`, plus the platform's own `PhotosPicker` — the same standing as the `DatePicker` on a
fixture and the `Toggle` in Settings: it is the operating system's control, not a component the
export was expected to draw. `Badge` gained one parameter, an optional image that fills the same
rounded square the initials would, so a list of clubs stays a list of one shape whether or not
anybody has uploaded anything. No new component, and no new value.

**The confirm-result screen is composition too (PD-011).** `ConfirmResultScreen` is `TopBar`,
`MatchSummary`, `PlayerIdentity`, `ThroButton` and `VerificationState` as they already exist. The one
thing it adds is words: the label alone would flatter what happened, so the screen says in plain text
that two people at one phone is two people agreeing rather than two devices, and that the names are
the ones typed at the start.

**Three entry screens are composition, not new components.** Starting a club, adding a member and
adding a fixture (`ThroApp/ClubFlow.swift`) are built from `ThroTextField`, `SegmentedControl`,
`ThroButton`, `Badge` and `TopBar` as they already exist. Two things in them are worth stating
because they are the kind of thing that gets slipped in:

- **The accent is a hex field, not a swatch palette.** A palette would mean engineering choosing a
  set of colours, and PD-010's first condition is that no value enters that the token layer does not
  have. A club's own colour belongs to the club, so it is typed, previewed live on `Badge`, and
  refused when it is not a colour. That is only safe because `packages/organisation` proves no colour
  in the cube can make the app unreadable — without that proof, a free colour field would be reckless.
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
