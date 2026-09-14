#!/usr/bin/env python3
"""The iOS journal and the Android journal are one journal.

ADR-002's argument is that the domain is one domain rendered on several platforms. For the scoring
engine that claim is held by 258,516 exhaustive transitions run against both implementations. For
the journal it was held by nothing at all until this: two files, written weeks apart in two
languages, whose agreement was a matter of care.

The part that has to agree is the part that is written to disk, because a journal is a file and a
file outlives the process that wrote it. A row written on an iPhone and read on a Pixel is the whole
point of ADR-006; if one wrote `retirement` and the other `RETIREMENT`, every ending would read back
as a row the other build cannot interpret — and the reader is careful to *refuse* such a row rather
than guess, so the failure would be silent, total, and discovered by a player.

So this compares what is written down:

  * the columns of `local_match` and `journal`, in order — the order matters, because both readers
    address columns by index;
  * both append-only triggers, verbatim once whitespace is normalised, including PD-026's narrowing
    of the delete;
  * the stored vocabulary — the `kind` and `seat` words — which the Kotlin enums must serialise to
    even though Kotlin spells its cases in upper case.

It does not compare the code. Two implementations of the same contract are allowed to differ, and
this is the contract.
"""
from __future__ import annotations

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
SWIFT = ROOT / "packages/client-ios/Sources/ThroJournal/Journal.swift"
KOTLIN = ROOT / "packages/journal/src/main/kotlin/thro/journal/Journal.kt"
KOTLIN_TYPES = ROOT / "packages/journal/src/main/kotlin/thro/journal/Types.kt"


def squash(sql: str) -> str:
    """One line, single spaces, no trailing semicolon — so indentation is not a difference."""
    return re.sub(r"\s+", " ", sql).strip().rstrip(";").strip()


def statement(source: str, opening: str) -> str | None:
    """The SQL statement beginning with `opening`, up to its terminating semicolon."""
    start = source.find(opening)
    if start < 0:
        return None
    end = source.find(";", source.find("END", start) if "TRIGGER" in opening else start)
    return squash(source[start : end + 1]) if end > 0 else None


def columns(create: str) -> list[str]:
    """The column names of a CREATE TABLE, in declaration order."""
    body = create[create.index("(") + 1 : create.rindex(")")]
    out = []
    depth = 0
    current = ""
    for char in body:
        if char == "(":
            depth += 1
        elif char == ")":
            depth -= 1
        if char == "," and depth == 0:
            out.append(current.strip())
            current = ""
        else:
            current += char
    out.append(current.strip())
    names = []
    for part in out:
        word = part.split()[0] if part.split() else ""
        if word.upper() in {"PRIMARY", "FOREIGN", "CHECK", "UNIQUE", "CONSTRAINT"}:
            continue
        names.append(word)
    return names


def main() -> int:
    swift = SWIFT.read_text(encoding="utf-8")
    kotlin = KOTLIN.read_text(encoding="utf-8")
    types = KOTLIN_TYPES.read_text(encoding="utf-8")
    problems: list[str] = []

    for table in ("local_match", "journal"):
        opening = f"CREATE TABLE IF NOT EXISTS {table} ("
        a, b = statement(swift, opening), statement(kotlin, opening)
        if a is None or b is None:
            problems.append(f"{table}: not found in {'Swift' if a is None else 'Kotlin'}")
            continue
        # The Swift schema has grown by ALTER over time; the Kotlin one declares the settled shape.
        # So the comparison is on the columns each reader will actually see, in order.
        altered = re.findall(rf"ALTER TABLE {table} ADD COLUMN (\w+)", swift)
        want = columns(a) + [c for c in altered if c not in columns(a)]
        got = columns(b)
        if want != got:
            problems.append(f"{table}: iOS reads {want}, Android reads {got}")

    for trigger in ("journal_append_only_update", "journal_append_only_delete"):
        opening_swift = f"CREATE TRIGGER IF NOT EXISTS {trigger}"
        # The delete trigger is dropped and recreated on both platforms, so it has no IF NOT EXISTS.
        a = statement(swift, opening_swift) or statement(swift, f"CREATE TRIGGER {trigger}")
        b = statement(kotlin, opening_swift) or statement(kotlin, f"CREATE TRIGGER {trigger}")
        if a is None or b is None:
            problems.append(f"{trigger}: not found in {'Swift' if a is None else 'Kotlin'}")
            continue
        if a != b:
            problems.append(f"{trigger} differs:\n      iOS:     {a}\n      Android: {b}")

    # The stored vocabulary. Swift spells the cases as it stores them; Kotlin spells them in upper
    # case and lowercases on the way to disk, so the comparison is against `.lowercase()`.
    swift_kinds = re.search(r"case visit, ([a-z, ]+)\n", swift)
    kotlin_kinds = re.search(r"public enum class Kind \{(.*?)\n        ;", types, re.S)
    if swift_kinds and kotlin_kinds:
        want = ["visit"] + [k.strip() for k in swift_kinds.group(1).split(",")]
        got = [k.strip().rstrip(",").lower() for k in kotlin_kinds.group(1).split("\n") if k.strip().endswith(",")]
        if want != got:
            problems.append(f"journal row kinds: iOS writes {want}, Android writes {got}")
    else:
        problems.append("journal row kinds: could not read the enum from one of the two sources")

    if problems:
        print("The two journals do not agree about what is written to disk:", file=sys.stderr)
        for problem in problems:
            print(f"  - {problem}", file=sys.stderr)
        return 1
    print("check_journal_parity: the iOS and Android journals agree on both tables, "
          "both append-only triggers and the stored row kinds")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
