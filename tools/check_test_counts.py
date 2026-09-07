#!/usr/bin/env python3
"""Hold the README's test counts to the tests that actually exist.

These counts have drifted three times in this repository, and each time it was found by hand
afterwards rather than by anything. A count in prose is a claim like any other, and a claim nobody
checks is a claim that stops being true — so this counts the `func test` declarations per test
target and compares them with the number the README states for that target.

It is deliberately dumb about prose: each row is identified by a fixed label, and the first integer
after that label is the claim. Adding a test and not updating the README fails here rather than in
somebody's reading six weeks later.
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
}

# Kotlin declares a test with an annotation on the line before the function, so both are counted the
# way each language actually writes one. A Kotlin `fun` with no @Test does not run — which is a
# mistake made in this repository once already — so counting the annotations is also the check for it.
COUNTERS = {".swift": re.compile(r"^\s+func test", re.M),
            ".kt": re.compile(r"^\s+@Test\b", re.M)}


def count(directory: str) -> int:
    base = ROOT / directory
    if not base.is_dir():
        sys.exit(f"check_test_counts: {directory} is not a directory")
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

    if problems:
        print("\nThe README's counts do not match the tests:", file=sys.stderr)
        for p in problems:
            print(f"  - {p}", file=sys.stderr)
        return 1
    print("\nEvery counted row matches.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
