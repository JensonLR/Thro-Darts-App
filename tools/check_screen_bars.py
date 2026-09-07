#!/usr/bin/env python3
"""A screen's top bar is a component, and negative insets belong to the design system.

**This exists because four screens hand-rolled the same bar and all four were wrong the same way.**
The founder, on a screenshot from their phone: *"no back button on view screen for clubs etc. still
ugly cropped view as seen in ss top right."* The back chevron sat off the left edge of the phone and
"Announce" was cut in half by the right one.

The cause was mine, twice. The first version put a −12 inset on the whole row, which shifted every
trailing item toward the right edge. The correction moved that inset onto the chevron — the right
principle — and missed that **the row had no gutter to inset from at all**, so the chevron went to
x = −12 and the last action sat flush against the screen edge.

`TopBar` and `MatchHeader` never had the bug, and the reason is the whole rule: they are design-system
components that apply `spaceScreenGutter` themselves, so their negative inset has something to be
negative *of*. Two checks follow from that, and both are exact rather than heuristic:

  1. **`BackChevron` is constructed only by `PageBar`.** A screen that builds its own back button is
     a screen that has to get the gutter right on its own, which is the thing that failed.
  2. **No negative horizontal padding outside `ThroDesign`.** In the design system a component owns
     the gutter it is insetting from; in a screen it is arithmetic against a margin that may not be
     there. Every one that exists today is in `ThroDesign` and is correct.

What this does not prove: that any of it looks right. Nothing here renders a pixel. It proves that the
one shape which produced the defect three times cannot be written again without failing a build.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCES = ROOT / "packages/client-ios/Sources"

# The one file allowed to build a back chevron: the bar every page uses.
BAR = "PageBar"
CHEVRON = re.compile(r"\bBackChevron\s*\(")
NEGATIVE = re.compile(r"\.padding\(\s*\.(?:leading|trailing|horizontal)\s*,\s*-")


def main() -> int:
    if not SOURCES.is_dir():
        sys.exit(f"check_screen_bars: {SOURCES} is not a directory")

    problems = []
    chevrons = 0
    insets = 0
    for path in sorted(SOURCES.rglob("*.swift")):
        text = path.read_text()
        where = path.relative_to(ROOT)
        module = path.relative_to(SOURCES).parts[0]

        for match in CHEVRON.finditer(text):
            chevrons += 1
            # Which type is it inside? The nearest **file-scope** `struct X` above it — matched
            # without leading whitespace on purpose, so a nested type (`PageBar.Action`) does not
            # get mistaken for the owner, which is what this reported on its first run.
            before = text[: match.start()]
            owner = None
            for declaration in re.finditer(r"^(?:public\s+)?struct\s+(\w+)", before, re.M):
                owner = declaration.group(1)
            if owner != BAR:
                problems.append(
                    f"{where}: {owner or 'top level'} builds its own BackChevron. Use {BAR}, which "
                    f"owns the screen gutter — a hand-rolled bar has to get that right on its own, "
                    f"and four of them did not."
                )

        for match in NEGATIVE.finditer(text):
            insets += 1
            if module != "ThroDesign":
                line = text[: match.start()].count("\n") + 1
                problems.append(
                    f"{where}:{line}: a negative horizontal inset outside ThroDesign. In a component "
                    f"it is measured against a gutter the component applies; in a screen it is "
                    f"measured against a margin that may not exist."
                )

    if chevrons == 0:
        sys.exit("check_screen_bars: found no BackChevron at all, so the pattern is wrong")

    if problems:
        print("Top bars that will crop or vanish on a phone:\n", file=sys.stderr)
        for problem in problems:
            print(f"  - {problem}", file=sys.stderr)
        return 1

    print(f"check_screen_bars: {chevrons} back chevron(s), all in {BAR}; "
          f"{insets} negative horizontal inset(s), all in ThroDesign.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
