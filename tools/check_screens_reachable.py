#!/usr/bin/env python3
"""Every screen is built by something, and every route is somewhere you can get to.

**This exists because of a defect found three times.** `EditClubScreen` was written and documented
— and `ClubRoute` had no case for it, so nothing in the running app could construct it. No club on a
phone could be renamed, recoloured, given a badge or deleted. Before that, `Export.read` was tested
and shown nowhere, and `ClubStore.setAvatar` was public, tested, and called from nothing.

Each time the tests were green and honest: no test in this repository constructs a screen, so they
were all true statements about code nothing could open. Reachability is not something the test suite
is shaped to see, so it is checked here instead.

Two checks, both mechanical:

  1. **Every `…Screen` is constructed somewhere** — in the package, or in one of the app targets
     under `apps/ios`, which is where a root screen is mounted and nowhere else. Zero construction
     sites means the screen exists only in its own file and in its tests.
  2. **Every case of a `…Route` enum is assigned somewhere in Sources.** A route case nothing
     assigns is a screen nothing navigates to, which is how the first defect happened.

What it does not prove: that the construction site is itself reachable, or that a human can find the
control. A screen built inside a branch that never runs passes this, and so does a route assigned
only from code nothing calls. That is a weaker claim than "reachable", and it is said here rather
than implied — but it is the exact claim that was false three times, and it now fails on every push.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCES = ROOT / "packages/client-ios/Sources"
# Screens are *declared* in the package and some are *mounted* by an app target — the phone's root
# view, the venue screen an Apple TV opens on. Those targets are a dozen lines each and are the only
# place a root is constructed, so a check that read only the package would call every root
# unreachable. Found when the tvOS app was added: `ThroVenueScreen` is built in `apps/ios/ThroTV`
# and nowhere else, which is correct and was reported as a defect.
APPS = ROOT / "apps/ios"

SCREEN = re.compile(r"^\s*(?:public\s+)?struct\s+(\w*Screen)\s*:\s*View\b", re.M)
# Two spellings, because the two flows in this app chose different words for the same thing:
# `ClubRoute` in the clubs tab and `Step` inside `PlayFlow`. A third spelling would be missed,
# which is why the run prints how many it found — a count that drops is a check that stopped
# checking.
ROUTE = re.compile(r"^\s*(?:public\s+)?enum\s+(\w*Route|\w*Step)\b[^{]*\{(.*?)^(?:\s*)\}",
                   re.M | re.S)
CASE = re.compile(r"^\s*case\s+([\w, ]+)", re.M)
# `route = .edit(id)`, `= .list`, `ClubRoute.member(...)`. Anything that names a case as a value.
ASSIGNED = re.compile(r"(?:=\s*|\w+Route\s*)\.(\w+)")


def swift_files():
    return sorted(SOURCES.rglob("*.swift"))


def main() -> int:
    if not SOURCES.is_dir():
        sys.exit(f"check_screens_reachable: {SOURCES} is not a directory")

    texts = {path: path.read_text() for path in swift_files()}
    mounted = "\n".join(p.read_text() for p in sorted(APPS.rglob("*.swift"))) if APPS.is_dir() else ""
    everything = "\n".join(texts.values()) + "\n" + mounted
    problems = []

    screens = {}
    for path, text in texts.items():
        for name in SCREEN.findall(text):
            screens[name] = path

    if not screens:
        sys.exit("check_screens_reachable: found no screens at all, which means the pattern is wrong")

    for name, declared_in in sorted(screens.items()):
        built = len(re.findall(rf"\b{name}\s*\(", everything))
        if built == 0:
            problems.append(
                f"{name} ({declared_in.relative_to(ROOT)}) is never constructed, in the package or "
                f"in any app target. It compiles and its tests may pass; nobody using the app can "
                f"reach it."
            )

    assigned = set(ASSIGNED.findall(everything))
    routes = 0
    for path, text in texts.items():
        for enum_name, body in ROUTE.findall(text):
            routes += 1
            for line in CASE.findall(body):
                for case in (c.strip() for c in line.split(",")):
                    if not case:
                        continue
                    if case not in assigned:
                        problems.append(
                            f"{enum_name}.{case} ({path.relative_to(ROOT)}) is never assigned in "
                            f"Sources, so nothing navigates to it."
                        )

    if not routes:
        sys.exit("check_screens_reachable: found no route enums, which means the pattern is wrong")

    if problems:
        print("Screens that nothing can reach:\n", file=sys.stderr)
        for problem in problems:
            print(f"  - {problem}", file=sys.stderr)
        print(
            "\nEither route to it, or delete it. A screen kept 'for later' that nobody can open is "
            "not a feature — it is a claim in the pull request that is not true on the phone.",
            file=sys.stderr,
        )
        return 1

    print(f"check_screens_reachable: {len(screens)} screens, {routes} route enums, all reachable.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
