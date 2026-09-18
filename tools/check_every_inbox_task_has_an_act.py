#!/usr/bin/env python3
"""Every task the server can put in somebody's inbox has something to do about it.

**This exists because two of the four kinds had nothing.** `consent_required` and
`result_submission_due` drew a card under *Action required* with a reason, a due date and no control at
all. A player was told a league was waiting on them and left to work out where to go. The two that did
have controls — `registration_required` and `rearrangement_answer_due` — hid the gap, because the inbox
looked as though it worked.

The shape is the one `check_screens_reachable.py` catches for screens: something exists, something else
is supposed to handle it, and nothing holds the two lists against each other. A test could not have
caught it — no test in this repository builds a view — so it is checked here instead.

  * The kinds the server can create: every `kind = "…"` passed to `insertTask` in `Secretary.kt`.
  * The kinds the inbox draws an act for: every `item.kind == "…"` in `AccountScreens.swift`.

A kind that is deliberately read-only says so with `// no-act:` and a reason on the same line as its
`kind =`, and is printed, so a deliberate exemption stays visible rather than silently becoming the norm.

What it does not prove: that the act is the right one, or that it works. Only that a card a person is
shown is not a dead end.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SECRETARY = ROOT / "services/api/src/main/kotlin/thro/api/Secretary.kt"
INBOX = ROOT / "packages/client-ios/Sources/ThroApp/AccountScreens.swift"
MAKES = re.compile(r'kind\s*=\s*"([a-z_]+)"')
DRAWS = re.compile(r'item\.kind\s*==\s*"([a-z_]+)"')
EXEMPT = "no-act:"


def main() -> int:
    for path in (SECRETARY, INBOX):
        if not path.is_file():
            sys.exit(f"check_every_inbox_task_has_an_act: {path.relative_to(ROOT)} is not there — "
                     "the tree moved and this check stopped checking")

    source = SECRETARY.read_text()
    made, exempt = {}, {}
    for line_no, line in enumerate(source.splitlines(), 1):
        for kind in MAKES.findall(line):
            (exempt if EXEMPT in line else made)[kind] = line_no
    drawn = set(DRAWS.findall(INBOX.read_text()))

    if not made and not exempt:
        sys.exit("check_every_inbox_task_has_an_act: no task kinds found in Secretary.kt — "
                 "the code moved and this check stopped checking")

    for kind, line_no in sorted(exempt.items()):
        print(f"  read-only by decision: {kind} (Secretary.kt:{line_no})")

    missing = {k: n for k, n in made.items() if k not in drawn}
    if missing:
        print("check_every_inbox_task_has_an_act: a card is drawn with nothing to do about it.\n")
        for kind, line_no in sorted(missing.items()):
            print(f"  {kind} — made at Secretary.kt:{line_no}, and no branch in AccountScreens.swift")
        print("\nGive it an act, or the way to the place the act lives. A card that says something is owed")
        print("and offers no way to settle it is the shape PD-126 removed, in the one screen for tasks.")
        return 1

    stale = sorted(drawn - set(made) - set(exempt))
    if stale:
        print("check_every_inbox_task_has_an_act: the inbox draws an act for a kind the server never makes.\n")
        for kind in stale:
            print(f"  {kind} — a branch in AccountScreens.swift, and no insertTask for it")
        print("\nEither the server stopped making it, or the name drifted. Both are worth knowing.")
        return 1

    print(f"check_every_inbox_task_has_an_act: {len(made)} task kinds, every one with something to do"
          + (f" ({len(exempt)} read-only by decision)" if exempt else ""))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
