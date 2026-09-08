#!/usr/bin/env python3
"""A screen that tells you where to look must be held to the place still being there.

**This exists because of what the readiness screen is.** Every other screen in this app shows you
something; `Readiness.swift` tells you where to *go and find* something — "tap **Share the result**
under the score", "**Remind me** is under an upcoming fixture". That makes it the one file whose
copy can be falsified by a change somewhere else entirely: rename a button in `PlayScreens.swift`
and this screen keeps confidently sending somebody to a control that no longer exists, with nothing
failing anywhere. It is the failure the screen was written to prevent, arriving through the screen
itself — which is not hypothetical: the first version of it told the founder an abandoned match had
no share card, about a match with a share button under it.

Two directions, so it cannot rot from either end:

  1. **Every control this screen names must exist**, as a literal, in the file that draws it. A
     renamed button fails the build.
  2. **Every bolded span in the screen's copy must be accounted for** — either as a control in the
     table below, or as an entry in the emphasis list with a reason. A new direction added to the
     copy fails until somebody says which it is; an emphasis entry whose span has gone from the
     copy fails too, so the list cannot fill up with names nothing says any more.

What it does not prove: that the control is reachable, or that the route sentence around it names
the right screen. `check_screens_reachable.py` holds the first; the second is prose, and prose is
held by reading it. This holds the part that is mechanical, which is the part that changes silently.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SCREEN = ROOT / "packages/client-ios/Sources/ThroApp/Readiness.swift"

# A control the copy names → the file that draws it. The label must appear in both.
CONTROLS = {
    "Share the result": "packages/client-ios/Sources/ThroPlay/PlayScreens.swift",
    "Remind me": "packages/client-ios/Sources/ThroApp/FixtureActions.swift",
    "Add to calendar": "packages/client-ios/Sources/ThroApp/FixtureActions.swift",
    "Find the venue": "packages/client-ios/Sources/ThroApp/FixtureActions.swift",
    "Fixtures": "packages/client-ios/Sources/ThroApp/ClubScreens.swift",
    # The two Siri shortcuts, named where Xcode's metadata extractor finds them. Renaming one there
    # renames it in the Shortcuts app, and the readiness row would go on quoting the old name.
    "Start a match": "apps/ios/ThroDarts/ThroIntents.swift",
    "Continue": "apps/ios/ThroDarts/ThroIntents.swift",
    # Two Settings groups. A group heading is a place rather than a button, and it is exactly as
    # able to be renamed out from under a direction, so it is held the same way.
    "Search": "packages/client-ios/Sources/ThroApp/ThroRootView.swift",
    "How the app performs": "packages/client-ios/Sources/ThroApp/ThroRootView.swift",
}

# Bolded spans that are deliberately not controls of this app, each with the reason it is not one.
# A span here that the copy no longer contains is an error: the list would otherwise grow into a
# record of what the screen used to say.
NOT_CONTROLS = {
    "add": "emphasis — the calendar permission is to add, and never to read",
    "at most once a day": "a limit iOS imposes, not a control",
    "+": "the Home Screen's own plus, and the fixture list's, neither drawn by this app's code",
    "+ Capability": "an Xcode menu item",
    "ThroDarts": "an Xcode target name",
    "ThroLive": "an Xcode target name",
    "From Xcode": "which of the two kinds of build the next sentence is about",
    "From TestFlight": "the other one",
}


def copy_of(path: pathlib.Path) -> str:
    """The screen's player-facing words: string literals only, adjacent ones joined.

    Comments are dropped first — this file argues with itself at length in `///`, and holding a
    doc comment's emphasis to being a button would be checking the wrong thing. Adjacent literals
    are joined because Swift's line-length limit splits sentences mid-word, and a `**span**` broken
    across a `+` is one span to a reader and two to a naive regex.
    """
    text = re.sub(r"//[^\n]*", "", path.read_text())
    out, end = [], 0
    for match in re.finditer(r'"((?:[^"\\]|\\.)*)"', text):
        # Two literals separated by nothing but `+` and whitespace are one sentence the compiler
        # will join, so join them the same way — a `**span**` split mid-word across a `+` is one
        # span to the reader. Anything else between them makes them different sentences, and those
        # are kept apart so two unrelated `**` can never be read as one pair.
        if out and re.fullmatch(r"[\s+]*", text[end:match.start()]):
            out[-1] += match.group(1)
        else:
            out.append(match.group(1))
        end = match.end()
    return "\n".join(out)


def main() -> int:
    if not SCREEN.is_file():
        sys.exit(f"check_readiness_directions: {SCREEN} is not there")

    said = copy_of(SCREEN)
    spans = set(re.findall(r"\*\*(.+?)\*\*", said))
    if not spans:
        sys.exit("check_readiness_directions: the screen names no controls at all, so this check "
                 "is looking at the wrong thing")

    problems = []

    for span in sorted(spans):
        if span in CONTROLS or span in NOT_CONTROLS:
            continue
        problems.append(
            f'the copy says **{span}** and nothing says what that is. If it is a control, add it to '
            f'CONTROLS with the file that draws it; if it is emphasis, add it to NOT_CONTROLS with '
            f'the reason.'
        )

    for label, drawn_in in sorted(CONTROLS.items()):
        if label not in spans:
            problems.append(
                f'CONTROLS lists "{label}" and the screen no longer sends anybody to it. Either the '
                f'direction was dropped — in which case that surface now has no route on the one '
                f'screen that gives routes — or this entry is stale.'
            )
        path = ROOT / drawn_in
        if not path.is_file():
            problems.append(f'CONTROLS points "{label}" at {drawn_in}, which is not there.')
        elif f'"{label}"' not in path.read_text():
            problems.append(
                f'the screen tells somebody to look for "{label}" and {drawn_in} does not draw it. '
                f'A renamed control leaves this screen confidently naming one that is gone.'
            )

    for span, reason in sorted(NOT_CONTROLS.items()):
        if span not in spans:
            problems.append(
                f'NOT_CONTROLS excuses **{span}** ("{reason}") and the copy does not say it any '
                f'more. Remove the entry, so this list stays a description of the screen rather '
                f'than of an older one.'
            )

    if problems:
        print("The readiness screen's directions do not match the app:")
        for problem in problems:
            print(f"  - {problem}")
        return 1

    print(f"check_readiness_directions: {len(CONTROLS)} controls named and drawn, "
          f"{len(NOT_CONTROLS)} spans accounted for as emphasis")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
