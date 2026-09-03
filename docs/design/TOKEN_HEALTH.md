# THRØ — Token Health (generated)

Generated from the committed export. Regenerate rather than edit.

**177 tokens defined. 48 are never referenced anywhere** — not by another
token, not by any component, not by any screen. That is 27% of the layer.

A dead token is not harmless: it states an intention the system does not keep. Two of these
matter a great deal — `--touch-target-minimum` is the accessibility floor, and the motion
tokens are the entire SET → THROW → IMPACT → RESOLVE grammar.


### Dead — motion (9)

`--motion-duration-resolve`, `--motion-duration-standard`, `--motion-easing-exit`, `--motion-easing-set`, `--motion-easing-throw`, `--motion-scale-impact`, `--motion-travel-large`, `--motion-travel-medium`, `--motion-travel-small`

### Dead — spacing/layout (11)

`--space-control-pad-x`, `--space-control-pad-y`, `--space-group-gap`, `--space-gutter-android`, `--space-inline-gap`, `--space-row-gap`, `--space-section-gap`, `--spacing-10`, `--spacing-11`, `--spacing-9`, `--touch-target-minimum`

### Dead — border (6)

`--border-brand`, `--border-hairline`, `--border-strong`, `--border-width-focus`, `--color-border-inverse`, `--rule-section`

### Dead — colour (9)

`--color-background-secondary`, `--color-chart-negative`, `--color-chart-positive`, `--color-chart-secondary`, `--color-scrim`, `--color-surface-focus`, `--color-text-inverse-secondary`, `--thro-pewter-light`, `--thro-white`

### Dead — typography (8)

`--typography-body-large-line`, `--typography-family-sport`, `--typography-family-ui`, `--typography-heading-3-line`, `--typography-label-default-line`, `--typography-label-strong-line`, `--typography-metadata-line`, `--typography-numeric-feature`

### Dead — other (5)

`--elevation-0`, `--elevation-1`, `--elevation-nav`, `--radius-circle`, `--radius-none`

---

## Token bypasses — values hardcoded past the token layer

The README states that where a component and a token disagree, the token wins. These are the
known instances where a component or screen does not consult the token layer at all.

### Raw hex and rgba

| File | Line | Value |
|---|---:|---|
| `components/scoring/TurnIndicator.jsx` | 42 | `rgba(247,246,242,0.6)` |
| `ui_kits/thro-app/screens-account.jsx` | 68 | `rgba(247,246,242,.72)` |
| `ui_kits/thro-app/screens-account.jsx` | 97 | `rgba(247,246,242,.4)` |
| `ui_kits/thro-app/screens-home.jsx` | 197 | `#A7ADAA` |
| `ui_kits/thro-app/screens-home.jsx` | 209 | `#A7ADAA` |
| `ui_kits/thro-app/screens-home.jsx` | 219 | `#A7ADAA` |
| `ui_kits/thro-app/screens-stream.jsx` | 33 | `rgba(8,10,9,0.94)` |
| `ui_kits/thro-app/screens-stream.jsx` | 59 | `#A7ADAA` |
| `ui_kits/thro-app/screens-stream.jsx` | 91 | `#A7ADAA` |
| `ui_kits/thro-app/screens-stream.jsx` | 97 | `#2C312E` |
| `ui_kits/thro-app/screens-stream.jsx` | 108 | `#A7ADAA` |
| `ui_kits/thro-app/screens-tournament.jsx` | 243 | `#A7ADAA` |
| `ui_kits/thro-app/screens-tournament.jsx` | 248 | `#A7ADAA` |
| `ui_kits/thro-organiser/app.jsx` | 46 | `#7C8380` |
| `ui_kits/thro-organiser/app.jsx` | 66 | `#2C312E` |
| `ui_kits/thro-organiser/app.jsx` | 77 | `#7C8380` |

**16 raw colour values.**

### Off-scale font sizes

The approved type scale is: 13, 14, 15, 17, 18, 21, 25, 32, 40, 56, 72, 96px.

| File | Line | Size |
|---|---:|---|
| `components/development/Bracket.jsx` | 74 | 11px |
| `components/navigation/BottomBar.jsx` | 79 | 11px |
| `ui_kits/thro-app/screens-stream.jsx` | 58 | 12px |
| `ui_kits/thro-app/screens-stream.jsx` | 65 | 34px |
| `ui_kits/thro-app/screens-stream.jsx` | 90 | 12px |
| `ui_kits/thro-app/screens-stream.jsx` | 105 | 10px |
| `ui_kits/thro-app/screens-stream.jsx` | 113 | 24px |
| `ui_kits/thro-app/screens-stream.jsx` | 272 | 10px |
| `ui_kits/thro-app/screens-you.jsx` | 144 | 12px |
| `ui_kits/thro-organiser/app.jsx` | 43 | 11px |

**10 off-scale font sizes.**

---

## Recommended CI gates

1. Regenerate this file and fail on any *new* dead token or bypass.
2. Reject raw hex/rgba and off-scale font sizes in all platform sources.
3. Fail if any semantic token lacks a dark-theme value.
4. Regenerate `CONTRAST_MATRIX.md` and fail on any regression against its baseline.
