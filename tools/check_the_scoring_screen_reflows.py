#!/usr/bin/env python3
"""PD-024's reflow is decided in one file and has to be obeyed in another.

**It was not.** `ThroDynamicType.reflows(at:)` has existed since that decision was written, with
tests in `DesignTests` holding exactly where the threshold sits and what the ceiling becomes either
side of it — and it was called from **no view in the app**. The decision reads:

    the scoring screen reflows instead of stopping: the upper region scrolling, the keypad pinned

What the screen actually did at an accessibility size was keep laying the head, the route and the
ledger out in a box that could not hold them, and they were drawn through one another: on an iPhone
17 Pro at accessibility-XXXL, both players' remainders sat on top of two ledger rows with a chalk
line struck through all four. A decision recorded, tested, and never wired to anything.

This holds the wire. `PlayScreens.swift` must ask `ThroDynamicType.reflows`, must put the region that
grows inside a `ScrollView`, and must keep the keypad's own ceiling pinned. It is a grep, and a grep
cannot tell whether the result *looks* right — for that there is a simulator, an accessibility text
size and a pair of eyes, which is how the defect was found in the first place. What it can do is stop
the wire being cut again, which is the failure that actually happened.
"""
import pathlib
import sys

SCREEN = (pathlib.Path(__file__).resolve().parent.parent
          / "packages/client-ios/Sources/ThroPlay/PlayScreens.swift")

WANTED = [
    ("ThroDynamicType.reflows", "the screen never asks whether it should reflow"),
    ("ScrollView", "nothing scrolls, so the region that grows has nowhere to grow"),
    ("throPinnedKeypadTypeCeiling", "the keypad is not pinned, so the keys move under the thumb"),
    ("throScoringTypeCeiling", "the rail is not capped, and its eyebrows wrap a letter per line"),
]


def main():
    source = SCREEN.read_text(encoding="utf-8")
    problems = [f"{needle} is not in {SCREEN.name} — {why}"
                for needle, why in WANTED if needle not in source]
    for needle, _ in WANTED:
        if needle in source:
            print(f"  {needle}")
    for problem in problems:
        print(f"FAIL {problem}", file=sys.stderr)
    if problems:
        raise SystemExit(1)
    print("the scoring screen reflows, scrolls, and pins its keys")


if __name__ == "__main__":
    main()
