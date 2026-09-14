#!/usr/bin/env python3
"""Club TV mode is two keys in a property list, and both fail silently.

**The failure this exists for happened.** iOS hands an app an external display as a *scene*, and it
creates that scene only when the app's `UIApplicationSceneManifest` both declares the
`UIWindowSceneSessionRoleExternalDisplayNonInteractive` role **and** says the app can hold two
scenes at once. This build declared the role and said `UIApplicationSupportsMultipleScenes` NO —
reasoning about what the player sees ("the phone still has one window") rather than about what the
key means, which is whether two scenes may be CONNECTED AT ONCE. A board on a wall while the keypad
is in somebody's hand is exactly two.

Nothing would have said so. `application(_:configurationForConnecting:)` is simply never called, the
cable mirrors the phone, and the wall shows a large copy of the scoring screen. No error, no log, no
failing test — the Swift is correct and unreachable.

So the manifest is held here on every push:

  1. the external-display role is declared, with at least one configuration;
  2. `UIApplicationSupportsMultipleScenes` is true, because without it the role is decoration;
  3. the delegate class it names exists in the app target, under the module-name substitution the
     plist writes it with — a typo there is the same silent failure by a different route.

What it does not prove: that the delegate attaches a window, or that a display was ever connected.
The first is Swift the compiler checks; the second needs a cable and a room, and the readiness
screen reads all three of these facts again on the running phone so the founder is never left
guessing which of them is missing.
"""
import pathlib
import plistlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
PLIST = ROOT / "apps/ios/Support/Info.plist"
APP_SOURCES = ROOT / "apps/ios/ThroDarts"
ROLE = "UIWindowSceneSessionRoleExternalDisplayNonInteractive"


def main() -> int:
    if not PLIST.is_file():
        sys.exit(f"check_scene_manifest: {PLIST} is not there")

    plist = plistlib.loads(PLIST.read_bytes())
    problems = []

    manifest = plist.get("UIApplicationSceneManifest")
    if not isinstance(manifest, dict):
        sys.exit("check_scene_manifest: there is no scene manifest at all, so club TV mode cannot "
                 "work and this check is looking at the wrong file")

    if manifest.get("UIApplicationSupportsMultipleScenes") is not True:
        problems.append(
            "UIApplicationSupportsMultipleScenes is not true. The external-display role below is "
            "then decoration: iOS will not connect a second scene, the cable mirrors the phone, "
            "and nothing reports it."
        )

    configurations = manifest.get("UISceneConfigurations")
    if not isinstance(configurations, dict):
        problems.append("UISceneConfigurations is missing, so no role is declared at all.")
        configurations = {}

    external = configurations.get(ROLE)
    if not isinstance(external, list) or not external:
        problems.append(
            f"{ROLE} declares no configuration. Without it the system has nowhere to put a board "
            f"and mirrors the phone instead."
        )
        external = []

    # The delegate the plist names has to be a class in the app target. The plist writes it with the
    # module-name build setting in front, which is what the runtime resolves — a name that is right
    # in the plist and absent from the source fails at scene connection, in silence, on a wall.
    sources = "\n".join(path.read_text() for path in APP_SOURCES.rglob("*.swift"))
    for configuration in external:
        named = configuration.get("UISceneDelegateClassName")
        if not named:
            problems.append(
                f'the {ROLE} configuration "{configuration.get("UISceneConfigurationName")}" names '
                f"no delegate class, so the scene connects with nothing to fill it."
            )
            continue
        klass = named.rsplit(".", 1)[-1]
        if not re.search(rf"\bclass\s+{re.escape(klass)}\b", sources):
            problems.append(
                f"the manifest names {named} and no class {klass} exists in "
                f"{APP_SOURCES.relative_to(ROOT)}. The scene would connect and stay empty."
            )

    if problems:
        print("Club TV mode cannot work with this scene manifest:")
        for problem in problems:
            print(f"  - {problem}")
        return 1

    print(f"check_scene_manifest: the external-display role is declared, multiple scenes are "
          f"supported, and {len(external)} delegate class(es) exist")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
