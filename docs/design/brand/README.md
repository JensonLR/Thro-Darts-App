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
  height between letters, and the Ø at the wordmark's own proportions — ring outer 0.524 and inner 0.255
  of the cap height, dart half-width 0.065, tips 0.95 from the centre — **read from
  `MarkGeometry.Ratios.wordmark`**, so the reference rendering, the app's opening and `apps/web/wordmark.svg`
  are one drawing (PD-091). `python3 docs/design/brand/render_wordmark.py <repo root>` writes `candidates/` — the
  wordmark as PNG and SVG and a phone-sized preview of the Splash composition. The app draws the same
  geometry live in its opening (`LaunchSequence.swift`, `WordmarkGeometry`); nothing here ships.
- `thro-mark-green.svg`, `thro-mark-chalk.svg` — the mark reconstruction, for reference and review.
- `candidates/` — the wordmark reconstruction and the launch-screen preview, for the founder to check.

## The two judgements, and how they were settled (PD-091)

**The face is Archivo ExtraBold** — the brand's own UI family at its heavy weight, read from the supplied
image: square terminals, the R's straight leg, the H's proportions. The letters in that image run a few
percent narrower than the static face. It has been on the founder's phone in the opening since 6 September,
and when the founder compared the web against the app on 13 September the objection was to the **Ø**, not to
the letters.

**The Ø has the letters' weight, not the raster's.** There were two measurements. The supplied image gave a
ring of 0.53 / 0.30 of the cap (stroke 0.23); Archivo ExtraBold's own glyphs give an O of 0.524 with a 0.269
side stroke and an H stem of 0.261. The outer radii agree to within 1%; the strokes do not, and the reason is
in the paragraph above — the raster's letters are lighter than the static face, so its ring is too. Every
rendering THRØ actually ships sets THR in the static face at full weight, so a ring measured off the raster
would be visibly lighter than the stems beside it. **0.524 / 0.255 / 0.065 is the wordmark**, and
`render_wordmark.py` now reads it from the Swift rather than holding its own.

If the master vectors below arrive, they supersede both measurements and every generator should be pointed
at them.

## The opening

PD-007, second version. The static launch screen is the green field alone; the app's first frames are
a real dart's throw — flight, strike, quiver — then the ring blooming as its echo, then the settle into
the Splash composition. Storyboard, timings and two alternative directions are on the design canvas
"THRØ Launch Sequence"; the timings and easings in `LaunchSequence.swift` are the spec board's and
the token layer's; the dart's anatomy is `DartAnatomy` there.

- `render_sounds.py` — the opening's three sounds, synthesised in pure Python:
  `apps/ios/ThroDarts/Sounds/thro-whoosh.wav` (the flight, 0.85 s), `thro-thud.wav` (the dart in the
  board, 0.75 s), `thro-chalk.wav` (the ring drawing itself, 0.8 s); mono, 16-bit, 44.1 kHz. They are
  physically shaped and mixed for the sequence, and they are placeholders in the honest sense: drop
  recorded foley under the same filenames and nothing else changes. `apps/ios/check_fonts.py` checks
  the three are present and well-formed on every push.

## What is not here, and what to do when it is

The master vector files. When they are added — `mark.svg` and `wordmark.svg` are the expected names —
the icon and the launch image should be regenerated from the masters rather than from the geometry and
the face, and PD-006's cost paragraph updated. The dart-flight variant is recorded but unused: the
wordmark's Ø has plain points, and the icon follows the wordmark. If the founder prefers the flight for
the icon, that is a small change to the geometry.
