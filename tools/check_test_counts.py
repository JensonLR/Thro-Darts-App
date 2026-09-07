#!/usr/bin/env python3
"""Hold every stated test count to the tests that actually exist.

These counts have drifted five times in this repository, and each time it was found by hand
afterwards rather than by anything. A count in prose is a claim like any other, and a claim nobody
checks is a claim that stops being true — so this counts the `func test` declarations per test
target and compares them with every number claimed about them.

Two kinds of claim are checked:

  - **README rows**, identified by a fixed label; the first integer after the label is the claim.
  - **Anchored counts anywhere else** — the runbook's header and table, whose numbers were left
    behind by a hundred tests before this covered them. Each is a regex with one group, so the
    document keeps its own wording and only the number is held.

Also checked: **the parts sum to the whole.** A row claiming 41 tests made of parts adding to 33 was
shipped in a pull request body once, and nothing noticed.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent

# README row label -> the test directories it covers.
ROWS = {
    "| On-device journal |": ["packages/client-ios/Tests/ThroJournalTests"],
    "| Scoring session |": ["packages/client-ios/Tests/ThroPlayTests"],
    "| Design layer |": ["packages/client-ios/Tests/ThroDesignTests"],
    "| The opening, the app shell and the club screens |": ["packages/client-ios/Tests/ThroAppTests"],
    "| Statistics honesty |": ["packages/statistics/src/test"],
    "| Statistics honesty, Swift |": ["packages/statistics-swift/Tests"],
    "| On-device journal, Android |": ["packages/journal/src/test"],
}

IOS = "packages/client-ios/Tests"

# Counts claimed outside the README. Each is (file, pattern with one integer group, what it counts).
# A pattern that matches nothing is a failure too: it means the sentence was reworded and the check
# silently stopped checking, which is worse than a wrong number because it looks like a pass.
ANCHORED = [
    ("docs/runbooks/CLIENT_IOS.md", r"(\d+) tests in all",
     [f"{IOS}/ThroDesignTests", f"{IOS}/ThroJournalTests", f"{IOS}/ThroPlayTests", f"{IOS}/ThroAppTests"]),
    ("docs/runbooks/CLIENT_IOS.md", r"(\d+) design,", [f"{IOS}/ThroDesignTests"]),
    ("docs/runbooks/CLIENT_IOS.md", r"(\d+) journal,", [f"{IOS}/ThroJournalTests"]),
    ("docs/runbooks/CLIENT_IOS.md", r"(\d+) scoring session,", [f"{IOS}/ThroPlayTests"]),
    ("docs/runbooks/CLIENT_IOS.md", r"(\d+) opening, app and clubs", [f"{IOS}/ThroAppTests"]),
    ("docs/runbooks/CLIENT_IOS.md", r"(\d+) design tests", [f"{IOS}/ThroDesignTests"]),
    ("docs/runbooks/CLIENT_IOS.md", r"(\d+) journal tests", [f"{IOS}/ThroJournalTests"]),
    ("docs/runbooks/CLIENT_IOS.md", r"(\d+) session tests", [f"{IOS}/ThroPlayTests"]),
    ("docs/runbooks/CLIENT_IOS.md", r"(\d+) app tests", [f"{IOS}/ThroAppTests"]),
    ("docs/runbooks/CLIENT_IOS.md", r"(\d+) statistics tests", ["packages/statistics-swift/Tests"]),
    # The runbook's breakdowns, file by file. These are what "the parts must sum" means here: each
    # part is a real file, and the whole above is the directory that holds them.
    ("docs/runbooks/CLIENT_IOS.md", r"(\d+) on the journal itself",
     [f"{IOS}/ThroJournalTests/JournalTests.swift"]),
    ("docs/runbooks/CLIENT_IOS.md", r"(\d+) on the device's book of clubs and people",
     [f"{IOS}/ThroJournalTests/ClubBookTests.swift"]),
    ("docs/runbooks/CLIENT_IOS.md", r"(\d+) on the export and what it refuses to read back",
     [f"{IOS}/ThroJournalTests/ExportTests.swift"]),
    ("docs/runbooks/CLIENT_IOS.md", r"(\d+) on images", [f"{IOS}/ThroJournalTests/ImageTests.swift"]),
    ("docs/runbooks/CLIENT_IOS.md", r"(\d+) on the opening \(timeline",
     [f"{IOS}/ThroAppTests/LaunchSequenceTests.swift"]),
    ("docs/runbooks/CLIENT_IOS.md", r"(\d+) on Home's reading of the journal",
     [f"{IOS}/ThroAppTests/AppStoreTests.swift"]),
    ("docs/runbooks/CLIENT_IOS.md", r"(\d+) on the club rules the screens obey",
     [f"{IOS}/ThroAppTests/ClubStateTests.swift"]),
    ("docs/runbooks/CLIENT_IOS.md", r"(\d+) on the mapping between the club book",
     [f"{IOS}/ThroAppTests/ClubStoreTests.swift"]),
    ("docs/runbooks/CLIENT_IOS.md", r"(\d+) on who may have a picture, who is told",
     [f"{IOS}/ThroAppTests/PictureTests.swift"]),
    ("docs/runbooks/CLIENT_IOS.md", r"(\d+) on a club, a league and a tournament being three",
     [f"{IOS}/ThroAppTests/LeagueTests.swift"]),
    ("docs/runbooks/CLIENT_IOS.md", r"(\d+) on the league book",
     [f"{IOS}/ThroJournalTests/LeagueBookTests.swift"]),
]

# Kotlin declares a test with an annotation on the line before the function, so both are counted the
# way each language actually writes one. A Kotlin `fun` with no @Test does not run — which is a
# mistake made in this repository once already — so counting the annotations is also the check for it.
COUNTERS = {".swift": re.compile(r"^\s+func test", re.M),
            ".kt": re.compile(r"^\s+@Test\b", re.M)}


def count(where: str) -> int:
    """Tests under a directory, or in one file. A path that is neither is a mistake, not a zero."""
    base = ROOT / where
    if base.is_file():
        pattern = COUNTERS.get(base.suffix)
        if not pattern:
            sys.exit(f"check_test_counts: {where} is not a language this counts")
        return len(pattern.findall(base.read_text()))
    if not base.is_dir():
        sys.exit(f"check_test_counts: {where} is neither a directory nor a file")
    total = 0
    for path in sorted(base.rglob("*")):
        pattern = COUNTERS.get(path.suffix)
        if pattern:
            total += len(pattern.findall(path.read_text()))
    return total


def main() -> int:
    readme = (ROOT / "README.md").read_text().splitlines()
    problems = []
    for label, directories in ROWS.items():
        line = next((l for l in readme if l.startswith(label)), None)
        if line is None:
            problems.append(f"README has no row starting {label!r}")
            continue
        claimed = re.search(r"(\d[\d,]*)\s+tests?\b", line[len(label):])
        if not claimed:
            problems.append(f"{label!r} does not state a test count")
            continue
        stated = int(claimed.group(1).replace(",", ""))
        actual = sum(count(d) for d in directories)
        mark = "ok " if stated == actual else "BAD"
        print(f"{mark} {label.strip('| ')}: README says {stated}, sources have {actual}")
        if stated != actual:
            problems.append(f"{label.strip('| ')}: README says {stated}, sources have {actual}")

    for document, pattern, where in ANCHORED:
        text = (ROOT / document).read_text()
        found = re.search(pattern, text)
        if not found:
            problems.append(f"{document}: nothing matches {pattern!r} any more, so that count "
                            f"stopped being checked. Reword the pattern or the document.")
            continue
        stated, actual = int(found.group(1)), sum(count(w) for w in where)
        mark = "ok " if stated == actual else "BAD"
        print(f"{mark} {document} {pattern!r}: says {stated}, sources have {actual}")
        if stated != actual:
            problems.append(f"{document} {pattern!r}: says {stated}, sources have {actual}")

    if problems:
        print("\nStated counts do not match the tests:", file=sys.stderr)
        for p in problems:
            print(f"  - {p}", file=sys.stderr)
        return 1
    print("\nEvery counted row matches.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
