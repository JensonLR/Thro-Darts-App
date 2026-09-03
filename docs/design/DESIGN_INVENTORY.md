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

## Icon set — 0 icons



## Totals

- **61** components
- **33** participant screens
- **9** organiser screens
- **0** icons
