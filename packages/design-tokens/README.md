# THRØ design tokens

One source, three platforms, no hand-copying.

```bash
python3 build.py            # generate
python3 build.py --check    # CI: fail on stale output or an unrecorded contrast breach
```

## Why this exists

The approved export's `tokens.css` is a **compiled artefact, not a source** — it carries no types,
no descriptions, and no light/dark pairing a generator could read. Three platforms hand-copying 177
values would drift, and drift in a design system is invisible until someone notices a screen looks
wrong months later.

So the export is lifted into a structured source where **light and dark are two modes of one
token**, never two separate token sets. That makes parity a mechanical check rather than a matter of
discipline.

## What it generates

| Output | Notes |
|---|---|
| `tokens.json` | The canonical source. Typed, with modes for light, dark and reduced motion |
| `ThroTokens.swift` + `Colors.xcassets` | Colours resolve from the asset catalogue so the system trait decides, not the call site |
| `ThroTokens.kt` | Light and dark factories for Compose. **Type roles in `sp`, spacing in `dp`** |
| `tokens.css` | Custom properties plus the dark and reduced-motion blocks |

The `sp` versus `dp` split is encoded in the token type rather than left to the implementer. Getting
it wrong is the most common way a type scale silently ignores Android font scaling.

## The contrast gate

Absolute thresholds — 4.5:1 for text, 3:1 for boundaries and focus — **with a dated, itemised
exception list**. Not a regression gate against the current baseline, which would have *frozen* the
21 known failures rather than caught them, including the `live` status on its own surface at 4.38:1.

Every exception names the pair, the ratio and the design commission that will resolve it. A new
failure with no recorded exception fails the build.

Currently: **50 pairs checked, 21 below threshold, 21 recorded exceptions, 0 unrecorded.**

## Still blocked on design input

The pipeline is built, but three inputs must come from Design before native layout begins and must
not be invented: the **Dynamic Type scaling contract**, **focus/hover/pressed appearance** (the focus
ring currently fails contrast on brand and ink, so a colour alone will not fix it), and the
**theme-scope defect** where four scoring components default to dark and paint no background. See
[`../../docs/design/DESIGN_UNSPECIFIED.md`](../../docs/design/DESIGN_UNSPECIFIED.md).
