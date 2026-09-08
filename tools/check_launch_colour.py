#!/usr/bin/env python3
"""The launch screen and the opening are the same green, or the app flashes.

**iOS paints the launch screen; the app paints everything after it.** `UILaunchScreen` names a
colour in the app target's asset catalogue, and `LaunchSequence` opens on `ThroColor.throGreen` from
the generated design tokens — two files, two copies of one hex, and nothing between them. If the
brand green ever moves, the launch screen keeps the old one and the app opens with a flash of the
wrong colour for about a third of a second, at the exact moment the founder has spent seven versions
of the opening getting right.

Nothing else can catch it. It is not a compile error, no test draws a launch screen, and a
screenshot of the running app looks perfect — the flash is over before anything is captured.

Two claims, both mechanical:

  1. `UILaunchScreen` names a colour that exists in the app's asset catalogue;
  2. that colour's components are the light value of the token the opening actually paints.

What it does not prove: that the opening still uses that token. `LaunchSequence` naming a different
one would pass this and is what the eye catches in one launch, which is the division of labour this
repository keeps everywhere — the machine holds what a person cannot see, and the person holds what
a machine cannot.
"""
import json
import pathlib
import plistlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
PLIST = ROOT / "apps/ios/Support/Info.plist"
ASSETS = ROOT / "apps/ios/ThroDarts/Assets.xcassets"
TOKENS = ROOT / "packages/design-tokens/generated/ThroTokens.swift"
OPENING = ROOT / "packages/client-ios/Sources/ThroApp/LaunchSequence.swift"

# The token the opening's first frame is painted in. Named here rather than parsed out of the Swift,
# because what this checks is that the plist agrees with a decision — and the decision has to be
# written down somewhere for the check to mean anything.
TOKEN = "throGreen"


def token_hex(name: str) -> str | None:
    """The light value from the generated tokens' own doc comment."""
    text = TOKENS.read_text()
    match = re.search(rf"///\s*light\s+#([0-9A-Fa-f]{{6}}).*?\n\s*public static let {name}\b", text)
    return match.group(1).upper() if match else None


def colorset_hex(path: pathlib.Path) -> str | None:
    """The universal colour in a `.colorset`, as six hex digits."""
    try:
        contents = json.loads((path / "Contents.json").read_text())
    except (OSError, json.JSONDecodeError):
        return None
    for entry in contents.get("colors", []):
        components = entry.get("color", {}).get("components")
        if not components:
            continue
        try:
            parts = [components[c] for c in ("red", "green", "blue")]
        except KeyError:
            return None
        out = ""
        for part in parts:
            text = str(part).strip()
            # Xcode writes either "0x2E" or a 0–1 float; both are the same colour.
            value = int(text, 16) if text.lower().startswith("0x") else round(float(text) * 255)
            out += f"{value:02X}"
        return out
    return None


def main() -> int:
    for path in (PLIST, ASSETS, TOKENS, OPENING):
        if not path.exists():
            sys.exit(f"check_launch_colour: {path} is not there")

    plist = plistlib.loads(PLIST.read_bytes())
    problems = []

    launch = plist.get("UILaunchScreen")
    if not isinstance(launch, dict):
        sys.exit("check_launch_colour: there is no UILaunchScreen at all. Without it iOS runs the "
                 "app in compatibility mode, letterboxed on every modern phone.")

    named = launch.get("UIColorName")
    if not named:
        problems.append("UILaunchScreen names no colour, so the launch screen is whatever iOS "
                        "picks and the app opens with a flash of it.")
    else:
        colorset = ASSETS / f"{named}.colorset"
        if not colorset.is_dir():
            problems.append(f"UILaunchScreen names \"{named}\" and there is no "
                            f"{named}.colorset in {ASSETS.relative_to(ROOT)}.")
        else:
            painted = colorset_hex(colorset)
            wanted = token_hex(TOKEN)
            if wanted is None:
                sys.exit(f"check_launch_colour: {TOKEN}'s value could not be read from the "
                         f"generated tokens, so this check has nothing to compare against")
            if painted is None:
                problems.append(f"{named}.colorset has no readable universal colour.")
            elif painted != wanted:
                problems.append(
                    f"the launch screen is #{painted} and ThroColor.{TOKEN} is #{wanted}. The app "
                    f"opens with a flash of the wrong green — about a third of a second, at the "
                    f"moment the opening exists to get right, and over before a screenshot."
                )

    # And the opening's FIRST FRAME really is painted in it — the `.background`, not merely a
    # mention. The first version of this looked for the token anywhere in the file and passed with
    # the background changed to something else entirely, because the same green is used three more
    # times inside the dart. A check that cannot fail is a check that has stopped checking.
    if not re.search(rf"\.background\(\s*ThroColor\.{TOKEN}\b", OPENING.read_text()):
        problems.append(f"the opening's background is no longer ThroColor.{TOKEN}, so the colour "
                        f"this check holds the launch screen to is not the one the app opens on.")

    if problems:
        print("The launch screen and the opening do not agree:")
        for problem in problems:
            print(f"  - {problem}")
        return 1

    print(f"check_launch_colour: the launch screen and ThroColor.{TOKEN} are both "
          f"#{token_hex(TOKEN)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
