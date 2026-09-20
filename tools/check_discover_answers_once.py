#!/usr/bin/env python3
"""Discover has one cause of trouble, so it gets one answer.

**It had three.** With no connection to THRØ, one screen showed, at one moment:

  * LEAGUES — a red Snackbar with a *Try again* button;
  * TOURNAMENTS — a line of grey prose, and no way to try again;
  * YOUR TEAMS ON THRØ — another line of grey prose, and no way to try again.

Three different answers to one question, and only one of them offering the tap that fixes all three.
A player is left to work out whether the red one is worse than the grey ones. It is not. It is the
same thing, three times, dressed differently.

There is one shape now — `DiscoverTrouble`, the reason and the control that tries again — and this
holds the screen to it. Every `case .failed` in `DiscoverScreen.swift` must be answered by that view
and nothing else, so a fourth section cannot arrive with a fourth presentation, and a red alarm cannot
creep back into one of them while the others stay quiet.

What it does not prove: that the reasons themselves read well, or that the retry reaches the server.
The first is the founder's to judge, and `NearbyTests` holds the second.
"""
import pathlib
import re
import sys

SCREEN = pathlib.Path(__file__).resolve().parent.parent / "packages/client-ios/Sources/ThroApp/DiscoverScreen.swift"
ANSWER = "DiscoverTrouble("


def main():
    lines = SCREEN.read_text(encoding="utf-8").splitlines()
    failures, problems = 0, []
    for number, line in enumerate(lines, start=1):
        if not re.match(r"\s*case \.(failed|idle)\b", line):
            continue
        failures += 1
        # The answer is whatever the branch draws first: the next line with anything on it.
        answer = next((l for l in lines[number:] if l.strip()), "")
        if ANSWER not in answer:
            problems.append(f"line {number}: {line.strip()} is answered by "
                            f"{answer.strip()[:70] or 'nothing'}")
        else:
            print(f"  line {number:4d}  {line.strip()}")
    if failures < 3:
        problems.append(f"only {failures} trouble branches found — has the screen been renamed or "
                        f"the sections moved out of it?")
    for problem in problems:
        print(f"FAIL {problem}", file=sys.stderr)
    if problems:
        raise SystemExit(1)
    print(f"{failures} ways for Discover to be in trouble, all of them answered the same way")


if __name__ == "__main__":
    main()
