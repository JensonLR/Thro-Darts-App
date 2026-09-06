# THRØ brand assets

What the founder supplied on 2026-09-06, as images: the wordmark **THRØ** in black and in the brand
green, and the mark alone — the Ø, a ring with a dart through it — in black, and in green with a dart
flight at the tail. The export's Splash screen references these as `assets/mark-chalk.svg` and
`assets/logo-chalk.svg`, which the design snapshot did not contain.

## What is here

- `render_mark.py` — the mark as geometry, measured against the supplied 1250 px image: ring outer
  radius 0.364 of the frame, inner 0.250 (stroke 0.114); dart half-width 0.040 inside the ring, held
  to the ring's outer edge and tapered to a point 0.643 from the centre; the axis at 45°, lower-left to
  upper-right. `python3 docs/design/brand/render_mark.py <repo root>` regenerates the app icon
  (`apps/ios/ThroDarts/Assets.xcassets/AppIcon.appiconset/AppIcon.png`, 1024 px, chalk on green) and
  the two mark SVGs. Pure Python; no dependencies.
- `ttf_outlines.py` — a small TrueType reader: glyph outlines, flattening, PDF paths, a nonzero
  rasteriser, PNG output. No kerning, no shaping; enough for four letters.
- `render_wordmark.py` — the wordmark: THR from `Archivo-ExtraBold.ttf`'s own outlines, 0.10 of the cap
  height between letters, and the Ø from the mark's geometry at the proportions the supplied wordmark
  gives it (ring outer 0.53 and inner 0.30 of the cap height, dart half-width 0.067, tips 0.95 from the
  centre). `python3 docs/design/brand/render_wordmark.py <repo root>` writes `candidates/` — the
  wordmark as PNG and SVG and a phone-sized preview of the Splash composition. The app draws the same
  geometry live in its opening (`LaunchSequence.swift`, `WordmarkGeometry`); nothing here ships.
- `thro-mark-green.svg`, `thro-mark-chalk.svg` — the mark reconstruction, for reference and review.
- `candidates/` — the wordmark reconstruction and the launch-screen preview, for the founder to check.

## The judgement to confirm

The wordmark's face is read from the supplied image as Archivo ExtraBold — the brand's own UI family at
its heavy weight. The forms match (square terminals, the R's straight leg, the H's proportions); the
letters in the supplied image run a few percent narrower than the static face. The founder confirms or
corrects this on the phone (runbook, next-run checklist item 8). If the face is wrong, the opening's
letters change face in one place.

## The opening

PD-007. The static launch screen is the green field alone; the app's first frames draw the throw that
is the mark, then settle into the Splash composition. Storyboard, timings and two alternative
directions are on the design canvas "THRØ Launch Sequence"; the timings and easings in
`LaunchSequence.swift` are the spec board's and the token layer's.

## What is not here, and what to do when it is

The master vector files. When they are added — `mark.svg` and `wordmark.svg` are the expected names —
the icon and the launch image should be regenerated from the masters rather than from the geometry and
the face, and PD-006's cost paragraph updated. The dart-flight variant is recorded but unused: the
wordmark's Ø has plain points, and the icon follows the wordmark. If the founder prefers the flight for
the icon, that is a small change to the geometry.
