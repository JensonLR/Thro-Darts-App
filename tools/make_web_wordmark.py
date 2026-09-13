#!/usr/bin/env python3
"""The wordmark the web serves, drawn from the geometry the app draws.

**The defect this fixes.** Every page in `apps/web` printed the *text* `THRØ` in the sport face and called
it the wordmark. It is not the wordmark. THRØ's Ø is **a dart through a ring** at measured proportions —
`MarkGeometry.Ratios.wordmark`, which the app draws live in `LaunchSequence.swift` — and a typeface's Ø is a
letter with a stroke across it. On a phone at arm's length the difference is a detail; on a pub television
it is somebody else's logo on the brand's green, and the founder spotted it on sight.

**Generated, not exported**, for the reason `make_android_icon.py` gives: the ratios are the source, and a
committed bitmap or a hand-drawn path knows nothing about them. Change a ratio, re-run, and every surface
moves together. `--check` fails the build if somebody changed one and did not.

**Which numbers are the wordmark's, and why it is not the ones in `docs/design/brand`.** That directory's
`render_wordmark.py` carries `RING_OUT=0.53, RING_IN=0.30, BAR=0.067` and calls itself a *candidate*,
measured off the founder's 2000 px artwork and never confirmed. The Swift carries
`ringOuter: 0.524, ringInner: 0.255, halfWidth: 0.065` and is **what the app has been drawing on the
founder's own phone since PD-006**. Where two sources disagree the shipped one wins, so this reads the
Swift. The discrepancy is real and is worth somebody's attention — it is recorded in the change record
rather than silently reconciled here.

Run:  python3 tools/make_web_wordmark.py
      python3 tools/make_web_wordmark.py --check
"""

from __future__ import annotations

import math
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "docs/design/brand"))

from ttf_outlines import TTF, quad_segments  # noqa: E402  (path set above)

GEOMETRY = ROOT / "packages/client-ios/Sources/ThroDesign/Geometry.swift"
LAUNCH = ROOT / "packages/client-ios/Sources/ThroApp/LaunchSequence.swift"
FACE = ROOT / "apps/ios/ThroDarts/Fonts/Archivo-ExtraBold.ttf"
TOKENS = ROOT / "apps/web/tokens.css"
OUT = ROOT / "apps/web/wordmark.svg"

# The cap height everything is expressed in. Arbitrary — the SVG scales — but a round number keeps the
# path data readable when somebody opens the file to see what it is.
CAP = 100.0
K = math.sqrt(0.5)


def wordmark_ratios() -> dict[str, float]:
    """`Ratios.wordmark`, from the Swift the app draws with."""
    m = re.search(
        r"static let wordmark = Ratios\(ringOuter:\s*([\d.]+),\s*ringInner:\s*([\d.]+),"
        r"\s*halfWidth:\s*([\d.]+),\s*tip:\s*([\d.]+)\)",
        GEOMETRY.read_text(),
    )
    if not m:
        raise SystemExit(f"could not find Ratios.wordmark in {GEOMETRY.relative_to(ROOT)}")
    outer, inner, half, tip = (float(g) for g in m.groups())
    return {"ringOuter": outer, "ringInner": inner, "halfWidth": half, "tip": tip}


def gap() -> float:
    """The space between the inked edges of the letters, in cap heights."""
    m = re.search(r"static let gap: CGFloat = ([\d.]+)", LAUNCH.read_text())
    if not m:
        raise SystemExit(f"could not find WordmarkGeometry.gap in {LAUNCH.relative_to(ROOT)}")
    return float(m.group(1))


def chalk() -> str:
    m = re.search(r"^\s*--thro-chalk:\s*(#[0-9A-Fa-f]{6});", TOKENS.read_text(), re.M)
    if not m:
        raise SystemExit("no --thro-chalk in the web's tokens")
    return m.group(1).upper()


def build() -> str:
    r = wordmark_ratios()
    g = gap()
    font = TTF(str(FACE))
    scale = CAP / font.cap_height

    # THR, set on the baseline with `gap` between inked edges — the app's own measure, which is why the
    # letters are placed by their ink and not by their advance widths.
    letters, pen = [], 0.0
    for character in "THR":
        contours = font.contours(font.cmap[ord(character)])
        xs = [x for c in contours for x, _, _ in c]
        letters.append((pen - min(xs) * scale, contours))
        pen += (max(xs) - min(xs)) * scale + g * CAP

    outer, inner = r["ringOuter"] * CAP, r["ringInner"] * CAP
    half, tip = r["halfWidth"] * CAP, r["tip"] * CAP
    cx, cy = pen + outer, CAP / 2

    # The dart: six corners, tip and two shoulders at each end, on the 45° axis. `MarkGeometry.barPoints`.
    local = [(tip, 0), (outer, half), (-outer, half), (-tip, 0), (-outer, -half), (outer, -half)]
    dart = [(cx + u * K - v * K, cy + u * K + v * K) for u, v in local]

    top = cy + tip * K
    bottom = cy - tip * K
    width = cx + tip * K
    height = top - bottom

    def y(v: float) -> float:
        """Font space is y-up; SVG is y-down."""
        return top - v

    paths = []
    for x0, contours in letters:
        for contour in contours:
            points = quad_segments(contour, steps=6)
            paths.append("M" + " L".join(f"{x0 + px * scale:.2f},{y(py * scale):.2f}" for px, py in points) + " Z")

    dart_points = " ".join(f"{px:.2f},{y(py):.2f}" for px, py in dart)
    colour = chalk()

    return f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {width:.0f} {height:.0f}"
     width="{width:.0f}" height="{height:.0f}" role="img" aria-label="THRØ">
  <!-- Generated by tools/make_web_wordmark.py from MarkGeometry.Ratios.wordmark. Do not edit.
       The Ø is a dart through a ring at the app's own proportions, not the typeface's Ø. -->
  <title>THRØ</title>
  <path d="{" ".join(paths)}" fill="{colour}" fill-rule="nonzero"/>
  <circle cx="{cx:.2f}" cy="{y(cy):.2f}" r="{(outer + inner) / 2:.2f}"
          fill="none" stroke="{colour}" stroke-width="{outer - inner:.2f}"/>
  <polygon points="{dart_points}" fill="{colour}"/>
</svg>
"""


def main() -> int:
    wanted = build()
    if "--check" in sys.argv:
        if not OUT.exists() or OUT.read_text() != wanted:
            print("apps/web/wordmark.svg is not the wordmark the app draws.\n")
            print("  Re-run: python3 tools/make_web_wordmark.py")
            return 1
        r = wordmark_ratios()
        print(f"the web's wordmark is the app's — ringOuter {r['ringOuter']}, tip {r['tip']}, gap {gap()}")
        return 0
    OUT.write_text(wanted)
    print(f"wrote {OUT.relative_to(ROOT)} from Ratios.wordmark")
    return 0


if __name__ == "__main__":
    sys.exit(main())
