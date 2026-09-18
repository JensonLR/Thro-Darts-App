#!/usr/bin/env python3
"""VoiceOver coverage is a ratchet: it may rise, and it may not quietly fall (PD-171).

Accessibility does not break in one commit. It erodes — a component is replaced by a hand-rolled one, a
label is dropped in a refactor, a new screen ships without any, and nobody notices because nothing fails.
`IOS_PLATFORM_OPPORTUNITIES.md` item 14 recorded "21 labels ... zero accessibilityValue" and by the time
anybody counted again it was 67 and 6 — the number moved twice and the record moved neither time.

So this counts, and holds a floor per package. Raising a floor is a commit that says why; lowering one is
refused. It is deliberately crude: it cannot tell a good label from a bad one, and it does not try. What it
can do is make a silent loss loud, which is the failure this repository actually had.

**What it does not check**, so nobody reads a green tick as more than it is: whether a label is accurate,
whether the order a screen reads in makes sense, whether a control is reachable by swipe, or anything at
all about running VoiceOver. Those need a person with the Accessibility Inspector, and that is still owed.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCES = ROOT / "packages" / "client-ios" / "Sources"

# The floor each package is held to, measured 18 September 2026. Raise with the commit that earns it.
# ThroVenueKit is a television nobody holds, and ThroPlay composes ThroDesign's controls rather than
# rolling its own, so both are honestly zero and are recorded as such rather than left out.
FLOORS = {
    "ThroDesign":   {"accessibilityLabel": 26, "accessibilityValue": 4, "accessibilityElement": 23},
    "ThroApp":      {"accessibilityLabel": 36, "accessibilityValue": 1, "accessibilityElement": 22},
    "ThroPlay":     {"accessibilityLabel": 0,  "accessibilityValue": 0, "accessibilityElement": 3},
    "ThroLiveKit":  {"accessibilityLabel": 2,  "accessibilityValue": 1, "accessibilityElement": 2},
    "ThroWatchKit": {"accessibilityLabel": 3,  "accessibilityValue": 0, "accessibilityElement": 1},
}


def count(folder: pathlib.Path, needle: str) -> int:
    total = 0
    for swift in folder.rglob("*.swift"):
        total += len(re.findall(re.escape(needle), swift.read_text(encoding="utf-8")))
    return total


def main() -> int:
    bad = []
    lines = []
    for package, floors in sorted(FLOORS.items()):
        folder = SOURCES / package
        if not folder.is_dir():
            bad.append(f"{package}: no such package — the floor names something that is not there")
            continue
        got = {needle: count(folder, needle) for needle in floors}
        for needle, floor in floors.items():
            if got[needle] < floor:
                bad.append(f"{package}.{needle}: {got[needle]}, and the floor is {floor} — "
                           f"say why in the ledger and lower the floor deliberately, or put it back")
        lines.append(f"  {package:<13} " + "  ".join(f"{n.replace('accessibility',''):<8}{got[n]}" for n in floors))

    for line in lines:
        print(line)
    if bad:
        for b in bad:
            print(f"BAD {b}")
        return 1
    print("check_voiceover_does_not_regress: every package is at or above its floor "
          "(labels are counted, not judged; running VoiceOver is still owed)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
