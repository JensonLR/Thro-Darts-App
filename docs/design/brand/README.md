# THRØ brand assets

What the founder supplied on 2026-09-06, as images: the wordmark **THRØ** in black and in the brand
green, and the mark alone — the Ø, a ring with a dart through it — in black, and in green with a dart
flight at the tail. The export's Splash screen references these as `assets/mark-chalk.svg` and
`assets/logo-chalk.svg`, which the design snapshot did not contain.

## What is here

- `render_mark.py` — the mark as geometry, measured against the supplied 1250 px image: ring outer
  radius 0.364 of the frame, inner 0.250 (stroke 0.114); dart half-width 0.040 inside the ring, held
  to the ring's outer edge and tapered to a point 0.643 from the centre; the axis at 45°, lower-left to
  upper-right. Run `python3 docs/design/brand/render_mark.py <repo root>` to regenerate the app icon
  (`apps/ios/ThroDarts/Assets.xcassets/AppIcon.appiconset/AppIcon.png`, 1024 px, chalk on green), the
  launch mark (`LaunchMark.imageset/LaunchMark.pdf`, a 104-point box as the Splash draws it) and the two
  SVGs below. Pure Python; no dependencies.
- `thro-mark-green.svg`, `thro-mark-chalk.svg` — the reconstruction, for reference and review.

## What is not here, and what to do when it is

The master vector files. When they are added — `mark.svg` and `wordmark.svg` are the expected names —
the icon and the launch mark should be regenerated from the master rather than from the geometry, and
the launch screen can carry the wordmark under the mark as the Splash draws it (mark 104 wide, wordmark
150 wide, 28 points apart, on `--thro-green`). Until then the reconstruction stands in, and PD-006
records that it is a reconstruction.

The dart-flight variant is recorded but unused: the wordmark's Ø has plain points, and the icon follows
the wordmark. If the founder prefers the flight for the icon, that is a one-line change to the geometry.
