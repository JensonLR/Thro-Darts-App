#!/usr/bin/env python3
"""The wordmark the web and Android serve, drawn from the geometry the app draws.

**The defect this fixes.** Every page in `apps/web` printed the *text* `THRØ` in the sport face and called
it the wordmark, and Android's loading screen did the same in 56 sp. It is not the wordmark. THRØ's Ø is
**a dart through a ring** at measured proportions — `MarkGeometry.Ratios.wordmark`, which the app draws live
in `LaunchSequence.swift` — and a typeface's Ø is a letter with a stroke across it. The founder spotted it
on sight.

**Generated, not exported**, for the reason `make_android_icon.py` gives: the ratios are the source, and a
committed bitmap or a hand-drawn path knows nothing about them. Change a ratio, re-run, and every surface
moves together. `--check` fails the build if somebody changed one and did not.

Two outputs from one geometry: `apps/web/wordmark.svg`, and
`packages/client-android/src/main/res/drawable/thro_wordmark.xml`, an Android vector drawable. The Ø's
proportions are the ones PD-091 settled.

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
ANDROID = ROOT / "packages/client-android/src/main/res/drawable/thro_wordmark.xml"

# The cap height everything is expressed in. Arbitrary — both outputs scale — but a round number keeps the
# path data readable when somebody opens a file to see what it is.
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


def geometry() -> dict:
    """The wordmark once, in a y-down frame whose origin is the top-left of its own ink box."""
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

    def y(v: float) -> float:
        """Font space is y-up; both outputs are y-down."""
        return top - v

    paths = []
    for x0, contours in letters:
        for contour in contours:
            points = quad_segments(contour, steps=6)
            paths.append("M" + " L".join(f"{x0 + px * scale:.2f},{y(py * scale):.2f}" for px, py in points) + " Z")

    return {
        "paths": paths, "cx": cx, "cy": y(cy), "outer": outer, "inner": inner,
        "dart": [(px, y(py)) for px, py in dart],
        "width": cx + tip * K, "height": top - bottom,
    }


def svg(g: dict, colour: str) -> str:
    dart_points = " ".join(f"{px:.2f},{py:.2f}" for px, py in g["dart"])
    return f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {g['width']:.0f} {g['height']:.0f}"
     width="{g['width']:.0f}" height="{g['height']:.0f}" role="img" aria-label="THRØ">
  <!-- Generated by tools/make_web_wordmark.py from MarkGeometry.Ratios.wordmark. Do not edit.
       The Ø is a dart through a ring at the app's own proportions, not the typeface's Ø. -->
  <title>THRØ</title>
  <path d="{" ".join(g['paths'])}" fill="{colour}" fill-rule="nonzero"/>
  <circle cx="{g['cx']:.2f}" cy="{g['cy']:.2f}" r="{(g['outer'] + g['inner']) / 2:.2f}"
          fill="none" stroke="{colour}" stroke-width="{g['outer'] - g['inner']:.2f}"/>
  <polygon points="{dart_points}" fill="{colour}"/>
</svg>
"""


def vector(g: dict, colour: str) -> str:
    """The same drawing as an Android vector drawable.

    A vector drawable cannot stroke a circle into a ring the way the SVG does, so the ring is the outer
    circle less the inner one by the even-odd rule — the construction `make_android_icon.py` uses for the
    launcher icon. The drawable is drawn in chalk and tinted at the call site, so it follows the palette.
    """
    def circle(r: float) -> str:
        return (f"M{g['cx'] - r:.2f},{g['cy']:.2f}"
                f"a{r:.2f},{r:.2f} 0 1,0 {2 * r:.2f},0"
                f"a{r:.2f},{r:.2f} 0 1,0 {-2 * r:.2f},0z")
    dart = "M" + "L".join(f"{px:.2f},{py:.2f}" for px, py in g["dart"]) + "z"
    return f"""<!-- Generated by tools/make_web_wordmark.py from MarkGeometry.Ratios.wordmark. Do not edit. -->
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="{g['width'] / 2:.0f}dp"
    android:height="{g['height'] / 2:.0f}dp"
    android:viewportWidth="{g['width']:.2f}"
    android:viewportHeight="{g['height']:.2f}">
    <!-- T, H and R: Archivo ExtraBold's own outlines. -->
    <path android:fillColor="{colour}" android:pathData="{" ".join(g['paths'])}" />
    <!-- The Ø's ring, outer less inner. -->
    <path android:fillColor="{colour}" android:fillType="evenOdd"
        android:pathData="{circle(g['outer'])}{circle(g['inner'])}" />
    <!-- The dart through it. -->
    <path android:fillColor="{colour}" android:pathData="{dart}" />
</vector>
"""


def outputs() -> dict[pathlib.Path, str]:
    g = geometry()
    colour = chalk()
    return {OUT: svg(g, colour), ANDROID: vector(g, colour)}


def main() -> int:
    wanted = outputs()
    if "--check" in sys.argv:
        stale = [p for p, text in wanted.items() if not p.exists() or p.read_text() != text]
        if stale:
            print("The wordmark files are not the wordmark the app draws:\n")
            for p in stale:
                print(f"  {p.relative_to(ROOT)}")
            print("\n  Re-run: python3 tools/make_web_wordmark.py")
            return 1
        r = wordmark_ratios()
        print(f"the web's and Android's wordmark is the app's — ringOuter {r['ringOuter']}, tip {r['tip']}, gap {gap()}")
        return 0
    for p, text in wanted.items():
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(text)
    print("wrote " + ", ".join(str(p.relative_to(ROOT)) for p in wanted) + " from Ratios.wordmark")
    return 0


if __name__ == "__main__":
    sys.exit(main())
