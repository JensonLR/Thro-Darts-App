#!/usr/bin/env python3
"""Hold the share card to colours that are the same in light mode and in dark mode.

A share card is the one thing THRØ makes that leaves the phone. It is a raster: it cannot be
tapped for a basis, it cannot be corrected after the fact, and it outlives the app that drew it. So
it has to be *one picture* — the same picture whoever drew it.

Most of THRØ's colour tokens are semantic and resolve from the asset catalogue by the phone's trait,
which is right for a screen and wrong for a picture that is about to be sent to somebody else. Two
players in the same group chat, one on a phone in dark mode and one in light, would post cards that
did not match, and neither would have any way to tell a theme from a defect.

The brand tokens — `throGreen`, `throChalk`, `throGreenOnink` and the rest — carry one value in both
traits. This holds the card to those, and it reads the values out of the **generated** token file
rather than a list kept here, so a token that becomes trait-dependent in a future generation is
caught by this check rather than by two people comparing screenshots.

It also refuses a card that references no tokens at all, because a check that passes on an empty set
is a check that has stopped working.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
TOKENS = ROOT / "packages/design-tokens/generated/ThroTokens.swift"
# Every file drawn into the shared image. A view reached from the card belongs here too.
CARD = ["packages/client-ios/Sources/ThroPlay/ShareCard.swift"]

# /// light #0F3D2E   dark #0F3D2E
# public static let throGreen = Color("throGreen", bundle: .module)
DECLARED = re.compile(
    r"///\s*light\s+(#[0-9A-Fa-f]{3,8})\s+dark\s+(#[0-9A-Fa-f]{3,8})\s*\n"
    r"\s*public static let (\w+)\s*=")
USED = re.compile(r"ThroColor\.(\w+)")


def main():
    if not TOKENS.exists():
        print(f"{TOKENS} is missing — run packages/design-tokens/build.py", file=sys.stderr)
        return 1

    values = {name: (light, dark) for light, dark, name in DECLARED.findall(TOKENS.read_text())}
    if not values:
        print(f"No token declarations parsed out of {TOKENS.name}. The generator's output shape "
              "changed and this check stopped seeing anything.", file=sys.stderr)
        return 1

    used = {}
    for relative in CARD:
        path = ROOT / relative
        if not path.exists():
            print(f"{relative} is missing. The share card moved and this check did not follow it.",
                  file=sys.stderr)
            return 1
        for name in USED.findall(path.read_text()):
            used.setdefault(name, relative)

    if not used:
        print("The share card references no design tokens at all. Either it stopped using the "
              "design system, or this check stopped seeing it.", file=sys.stderr)
        return 1

    problems = []
    for name in sorted(used):
        where = used[name]
        if name not in values:
            problems.append(f"{name} ({where}) is not a token this build generates")
            continue
        light, dark = values[name]
        if light.lower() != dark.lower():
            problems.append(
                f"{name} ({where}) is {light} in light mode and {dark} in dark — a card drawn on "
                "one phone would not match the same card drawn on another")

    print(f"{len(used)} colour token{'' if len(used) == 1 else 's'} on the share card, "
          f"read against {len(values)} generated tokens.")
    for name in sorted(used):
        light, dark = values.get(name, ("?", "?"))
        mark = "  ok  " if light.lower() == dark.lower() else " FAIL "
        print(f"{mark} ThroColor.{name:<28} {light}")

    if problems:
        print("\nThe share card must look the same whoever draws it:", file=sys.stderr)
        for problem in problems:
            print(f"  - {problem}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
