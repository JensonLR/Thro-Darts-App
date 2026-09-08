#!/usr/bin/env python3
"""An orientation the app offers is an orientation something has laid out.

`TARGETED_DEVICE_FAMILY` and `UISupportedInterfaceOrientations` are two lines in a project file, and
turning them on is free. What they promise is not: an app that accepts landscape draws its portrait
layout into 390 points of height, and an app that accepts iPad draws its phone layout across 1024.
PD-005 locked THRØ to an upright phone precisely because the scoring screen was built to fit one
screen and could not re-examine that at runtime.

So this holds the two together in both directions:

  1. Every orientation and device family the project offers must be one `ThroStage` has been asked
     about — the pure function the scoring screen's shape comes from, and the thing `StageTests`
     walks eleven real devices through, both ways up, at every text size.
  2. The scoring screen must actually **use** it. A stage nothing calls is a layout nobody has,
     however many tests it passes.

Both halves matter. The first alone would let the screen ignore the stage; the second alone would
let the project quietly go back to portrait-only with the stage still there, and every test would
still be green while the app shipped one orientation.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
PROJECT = ROOT / "apps/ios/ThroDarts.xcodeproj/project.pbxproj"
STAGE = ROOT / "packages/client-ios/Sources/ThroDesign/Stage.swift"
STAGE_TESTS = ROOT / "packages/client-ios/Tests/ThroDesignTests/StageTests.swift"
SCREEN = ROOT / "packages/client-ios/Sources/ThroPlay/PlayScreens.swift"

# Which arrangement each orientation needs the stage to have decided.
LANDSCAPE = ("UIInterfaceOrientationLandscapeLeft", "UIInterfaceOrientationLandscapeRight")
PORTRAIT = ("UIInterfaceOrientationPortrait", "UIInterfaceOrientationPortraitUpsideDown")

# What THRØ has decided to offer, per key. Declared, because "whatever the project happens to say is
# supported" is not a check — the first version of this file only asked whether each orientation
# named had a layout, and passed cleanly when landscape was deleted from the iPhone key, since the
# iPad key still carried it. That is precisely the silent regression this exists to catch: the app
# ships one orientation and every test stays green.
#
# Changing what THRØ offers is a deliberate edit to this table, with the layout work to match.
OFFERED = {
    "UISupportedInterfaceOrientations_iPhone": {
        "UIInterfaceOrientationPortrait",
        "UIInterfaceOrientationLandscapeLeft",
        "UIInterfaceOrientationLandscapeRight",
    },
    "UISupportedInterfaceOrientations_iPad": {
        "UIInterfaceOrientationPortrait",
        "UIInterfaceOrientationPortraitUpsideDown",
        "UIInterfaceOrientationLandscapeLeft",
        "UIInterfaceOrientationLandscapeRight",
    },
}
# Upside-down is deliberately NOT offered on the phone: a scoring phone is propped or held, and a
# player who turns it over mid-leg has done so by accident.
FAMILIES = {"1", "2"}


def main() -> int:
    problems: list[str] = []
    for path in (PROJECT, STAGE, STAGE_TESTS, SCREEN):
        if not path.exists():
            print(f"{path.relative_to(ROOT)} is missing", file=sys.stderr)
            return 1

    project = PROJECT.read_text(encoding="utf-8")
    stage = STAGE.read_text(encoding="utf-8")
    tests = STAGE_TESTS.read_text(encoding="utf-8")
    screen = SCREEN.read_text(encoding="utf-8")

    families = set(re.findall(r"TARGETED_DEVICE_FAMILY = \"?([0-9,]+)\"?;", project))
    if not families:
        problems.append("the project names no TARGETED_DEVICE_FAMILY at all")
    offers_ipad = any("2" in f.split(",") for f in families)
    for family in FAMILIES:
        if not any(family in f.split(",") for f in families):
            problems.append(f"TARGETED_DEVICE_FAMILY no longer includes {family} "
                            f"({'iPhone' if family == '1' else 'iPad'}), and this repository has "
                            f"decided to offer it. Change FAMILIES here if that is intended.")

    orientations = set()
    per_key: dict[str, set[str]] = {}
    for key, value in re.findall(r"(UISupportedInterfaceOrientations\w*) = \"?([^\";]+)\"?;", project):
        per_key.setdefault(key, set()).update(value.split())
        orientations.update(value.split())

    # Each key must offer exactly what was decided, not merely something with a layout behind it.
    for key, expected in OFFERED.items():
        found = per_key.get(key)
        if found is None:
            problems.append(f"{key} is not set at all, so iOS decides for us. It must name "
                            f"{sorted(expected)}.")
            continue
        missing = expected - found
        extra = found - expected
        if missing:
            problems.append(f"{key} no longer offers {sorted(missing)}. That is a whole orientation "
                            f"a player loses, and no test would notice.")
        if extra:
            problems.append(f"{key} offers {sorted(extra)}, which is not in OFFERED. Add it there "
                            f"with the layout work, or take it out of the project.")

    offers_landscape = any(o in orientations for o in LANDSCAPE)
    offers_portrait = any(o in orientations for o in PORTRAIT)

    # 1. Anything offered must be something the stage decides and the tests walk.
    if offers_landscape:
        if "case beside" not in stage:
            problems.append("the project offers landscape and ThroStage has no `beside` arrangement "
                            "— the keys would be drawn under a 390 pt screen.")
        if "on its side" not in tests:
            problems.append("the project offers landscape and StageTests never turns a device on "
                            "its side.")
    if offers_ipad:
        if "iPad" not in tests:
            problems.append("the project offers iPad (TARGETED_DEVICE_FAMILY includes 2) and "
                            "StageTests names no iPad — the phone layout would be stretched across "
                            "1024 points with nothing having checked it.")
    if offers_portrait and "case stacked" not in stage:
        problems.append("the project offers portrait and ThroStage has no `stacked` arrangement.")

    # 2. And the screen must actually ask the stage, or none of it reaches a player.
    if "ThroStage.choose(" not in screen:
        problems.append("ScoringScreen never calls ThroStage.choose — the stage is a layout nobody "
                        "has, however many tests it passes.")
    if "GeometryReader" not in screen:
        problems.append("ScoringScreen measures nothing, so whatever it passes to ThroStage.choose "
                        "is not the room it actually has.")

    # 3. And the stage's own claim has to still be checked.
    for needed in ("keysFit(in:", "everyScreen()"):
        if needed not in tests:
            problems.append(f"StageTests no longer uses `{needed}` — the claim that every device "
                            f"fits in both orientations is not being made any more.")

    if problems:
        print("Orientations offered without a layout behind them:", file=sys.stderr)
        for problem in problems:
            print(f"  {problem}", file=sys.stderr)
        return 1
    print(f"ok: families {sorted(families)}, "
          f"{len(OFFERED['UISupportedInterfaceOrientations_iPhone'])} phone and "
          f"{len(OFFERED['UISupportedInterfaceOrientations_iPad'])} iPad orientations, "
          f"each the one decided; ThroStage decides each and ScoringScreen asks it")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
