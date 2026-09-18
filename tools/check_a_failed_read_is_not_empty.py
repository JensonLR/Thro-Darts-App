#!/usr/bin/env python3
"""A read that failed is never drawn as a read that found nothing.

**This exists because of a defect found seven times in one sweep.** A captain with a friendly waiting
for their answer was told "No friendlies yet" whenever the connection dropped. Somebody opening the
blocked list on a dropped connection was told "Nobody is blocked" — on the screen about safety. And a
person who runs three teams was told "You run no team on THRØ yet".

Every one was the same line of code: a `catch` that wrote an empty collection, or a `try?` whose
failure fell into `?? []`. The read failed; the screen then made a positive statement about the
world, and the statement was false. An empty state is a claim. A failed read has nothing to claim.

What is checked, in `packages/client-ios/Sources`:

  1. **A catch that assigns an empty collection.** `catch { list = [] }`, `catch { x = [:] }`.
  2. **`try?` swallowed into an empty default.** `(try? await api.myTeams()) ?? []`.

Both are matched only where the value is a *collection*, because `catch { count = 0 }` is arithmetic,
not a claim about a list — and only where the read went to **the server** (`api.` in the expression),
because that is the shape that was defective. A phone's own book failing to read is a different thing
with a different likelihood and a different right answer, and is recorded as an open question rather
than swept in here to make one check look thorough.

What it does not prove: that the screen draws the failure well, only that the model no longer lies to
it. And it cannot see a read whose failure is swallowed some other way — the three shapes above are
the ones that were actually there.

A `catch` that clears a stale list **and says why** is not this defect and is not reported: the fault
is a failure that makes a false statement, not one that empties a list. A search box that clears its
last results and puts "Venues could not be searched just now." beside the field is right. So a catch is
allowed when it also assigns something that carries the sentence — a name holding `said`, `note`,
`message`, `error`, `failed` or `refus`.

An occurrence that is genuinely right for some other reason carries `// not-a-read:` and a reason on
the same line or the line before, and is counted and printed so the exemptions stay visible rather
than becoming invisible.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCES = ROOT / "packages/client-ios/Sources"
EMPTY = r"(?:\[\s*\]|\[\s*:\s*\])"
# `api.` in the same statement is what makes it a read of the server rather than of this phone.
CATCH_EMPTY = re.compile(r"\bapi\.[^\n]*\n(?:[^\n]*\n){0,6}?[^\n]*catch\s*\{(?P<body>[^}]*?\b\w+\s*=\s*" + EMPTY + r"[^}]*)", re.S)
# The catch said something as well as clearing: not a false statement, so not this defect.
SAYS_WHY = re.compile(r"\b\w*(?:said|note|message|error|failed|refus)\w*\s*=", re.I)
TRY_DEFAULT = re.compile(r"try\?[^\n]*\bapi\.[^\n]*?\?\?\s*" + EMPTY)
ALLOWED = "not-a-read:"


def lines_of(text):
    return text.splitlines()


def main() -> int:
    if not SOURCES.is_dir():
        sys.exit(f"check_a_failed_read_is_not_empty: {SOURCES} is not a directory")
    files = sorted(SOURCES.rglob("*.swift"))
    if not files:
        sys.exit("check_a_failed_read_is_not_empty: no Swift under Sources — the tree moved and this check stopped checking")

    bad, allowed = [], []
    for path in files:
        text = path.read_text()
        lines = lines_of(text)
        for pattern, what in ((CATCH_EMPTY, "a catch that writes an empty collection"),
                              (TRY_DEFAULT, "a try? whose failure becomes an empty collection")):
            for m in pattern.finditer(text):
                if pattern is CATCH_EMPTY and SAYS_WHY.search(m.group("body") or ""):
                    continue
                line_no = text[: m.start()].count("\n") + 1
                here = lines[line_no - 1] if line_no <= len(lines) else ""
                before = lines[line_no - 2] if line_no >= 2 else ""
                where = (path.relative_to(ROOT), line_no, what, m.group(0).replace("\n", " ")[:100].strip())
                (allowed if (ALLOWED in here or ALLOWED in before) else bad).append(where)

    for path, line, what, snippet in allowed:
        print(f"  allowed: {path}:{line} — {snippet}")
    if bad:
        print("check_a_failed_read_is_not_empty: a failed read is written as a read that found nothing.\n")
        for path, line, what, snippet in bad:
            print(f"  {path}:{line} — {what}")
            print(f"    {snippet}")
        print("\nLeave the value unread instead, and draw the failure. An empty state is a claim; a failed read")
        print("has nothing to claim. If this one is genuinely not a read, say `// not-a-read: <why>` above it.")
        return 1
    print(f"check_a_failed_read_is_not_empty: {len(files)} Swift files — no failed read is drawn as an empty one"
          + (f" ({len(allowed)} said why they are not reads)" if allowed else ""))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
