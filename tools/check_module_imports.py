#!/usr/bin/env python3
"""Every Swift file that names a type from another local module must import that module.

**A transitive dependency is linkable, not nameable.** `ThroPlay` depends on `ThroJournal`, so a
test target that imports `ThroPlay` links `Seat` — and cannot say `Seat` without importing
`ThroJournal` itself. That has now cost two CI rounds on a macOS runner, four minutes each, for two
different types:

  - `Geometry.swift` moved into `ThroDesign` naming `ThroMotion` with only `import SwiftUI`.
  - `DartVisitTests.swift` named `Seat` with `import ThroEngine` and `@testable import ThroPlay`.

`check_tokens_exist.py` learned this lesson for the token layer and only for the token layer. This
generalises it: it reads every module's own public top-level declarations, then reads every Swift
file and asks whether the modules it names are modules it can see.

**What it deliberately does not do.** It is not a compiler and does not resolve scope. It matches a
public type name as a whole word in code with comments and string literals stripped, and it only
considers names declared by exactly one local module — a name two of our modules both declare is
ambiguous to this check and is skipped rather than guessed at. So it can miss a defect (a shadowed
name, a name only ever written inside a string) but it cannot invent one, which is the direction a
guard should fail in.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent

# Where a local Swift module's sources live. A module is a directory of .swift files whose name is
# the module name — the layout SwiftPM's default target discovery already requires.
SOURCE_ROOTS = [
    "packages/client-ios/Sources",
    "packages/engine-swift/Sources",
    "packages/statistics-swift/Sources",
]

# ThroTokens is generated into one file rather than a Sources directory.
EXTRA_MODULES = {"ThroTokens": ["packages/design-tokens/generated/ThroTokens.swift"]}

# Every Swift file that is compiled into something, and which module (if any) it belongs to.
SEARCH_ROOTS = ["packages", "apps"]

# **Top level only, and that is the whole difference between a guard and a nuisance.** A nested
# type cannot be named unqualified from another module — `ClubExport.Member` is `Member` to nobody
# — so a rule that read indented declarations flagged eight files that compile: SwiftUI's `Group`
# against `Groups.Group`, the standard library's `Result` and `Failure` against nested ones of ours,
# and a `private struct Notice` against `MatchSession.Notice`. Anchoring at column zero removes all
# eight without an exception list, because it is the same rule the compiler is applying.
DECLARATION = re.compile(
    r"^public\s+(?:final\s+)?(?:enum|struct|class|actor|protocol|typealias)\s+([A-Z]\w*)",
    re.MULTILINE,
)
IMPORT = re.compile(r"^\s*(?:@testable\s+)?import\s+(\w+)", re.MULTILINE)

# Any type declared anywhere in a file, at any nesting and any access level. This is how a target
# says "that name is mine": `FixtureActions` declares its own nested `Outcome`, and it is not
# ThroEngine's however similar they look.
ANY_DECLARATION = re.compile(
    r"\b(?:enum|struct|class|actor|protocol|typealias)\s+([A-Z]\w*)")

BLOCK_COMMENT = re.compile(r"/\*.*?\*/", re.DOTALL)
LINE_COMMENT = re.compile(r"//[^\n]*")
STRING = re.compile(r'"""(?:.|\n)*?"""|"(?:\\.|[^"\\\n])*"')


def code_only(text: str) -> str:
    """The file with its comments and string literals blanked out.

    A type named in prose is not a reference to it, and this check exists because a *reference*
    without an import does not compile. Newlines are preserved so line numbers survive.
    """
    def blank(m):
        return re.sub(r"[^\n]", " ", m.group(0))
    text = BLOCK_COMMENT.sub(blank, text)
    text = STRING.sub(blank, text)
    return LINE_COMMENT.sub(blank, text)


def modules() -> dict:
    """module name -> its .swift files."""
    found = {}
    for root in SOURCE_ROOTS:
        base = ROOT / root
        if not base.is_dir():
            continue
        for d in sorted(base.iterdir()):
            if d.is_dir():
                found[d.name] = sorted(d.rglob("*.swift"))
    for name, paths in EXTRA_MODULES.items():
        found[name] = [ROOT / p for p in paths]
    return found


def main() -> int:
    mods = modules()
    if len(mods) < 3:
        print(f"check_module_imports: only found {len(mods)} modules — the layout moved", file=sys.stderr)
        return 1

    # public name -> the module that declares it, or None where two modules both declare it.
    owner = {}
    for name, files in mods.items():
        for f in files:
            for decl in DECLARATION.findall(code_only(f.read_text(encoding="utf-8"))):
                owner[decl] = None if decl in owner and owner[decl] != name else name
    ambiguous = sorted(n for n, m in owner.items() if m is None)
    declared = {n: m for n, m in owner.items() if m is not None}
    if not declared:
        print("check_module_imports: no public declarations found at all", file=sys.stderr)
        return 1

    # A file's **compilation unit**: the module directory it sits in, or the test target's. Every
    # name that unit declares anywhere is its own — nesting and access level included — because
    # that is what the compiler resolves to before it ever looks at another module.
    def unit_of(f: pathlib.Path) -> pathlib.Path:
        parts = f.resolve().parts
        for marker in ("Sources", "Tests"):
            if marker in parts:
                i = len(parts) - 1 - parts[::-1].index(marker)
                if i + 1 < len(parts):
                    return pathlib.Path(*parts[: i + 2])
        return f.resolve().parent

    home = {}
    for name, files in mods.items():
        for f in files:
            home[f.resolve()] = name

    owns: dict = {}

    every = []
    for root in SEARCH_ROOTS:
        every += sorted((ROOT / root).rglob("*.swift"))

    # Not preceded by a dot: `AccessibilityNotification.Announcement` is SwiftUI's member and not
    # ThroApp's top-level type, and a member reference never needs the declaring module imported.
    names = re.compile(r"(?<![.\w])(" + "|".join(sorted(map(re.escape, declared))) + r")\b")
    problems = []
    checked = 0
    for f in every:
        if "/.build/" in str(f) or "/build/" in str(f):
            continue
        text = f.read_text(encoding="utf-8")
        code = code_only(text)
        seen = set(IMPORT.findall(text))
        mine = home.get(f.resolve())
        unit = unit_of(f)
        if unit not in owns:
            local = set()
            for sibling in sorted(unit.rglob("*.swift")):
                local |= set(ANY_DECLARATION.findall(code_only(sibling.read_text(encoding="utf-8"))))
            owns[unit] = local
        checked += 1
        wanted = {}
        for m in names.finditer(code):
            module = declared[m.group(1)]
            if module == mine or module in seen or m.group(1) in owns[unit]:
                continue
            line = code[: m.start()].count("\n") + 1
            wanted.setdefault(module, []).append((line, m.group(1)))
        for module, hits in sorted(wanted.items()):
            where = ", ".join(f"{name} (line {line})" for line, name in hits[:4])
            problems.append(
                f"  {f.relative_to(ROOT)} names {where} but does not `import {module}`."
            )

    if problems:
        print("Swift files naming a module they cannot see:", file=sys.stderr)
        for p in problems:
            print(p, file=sys.stderr)
        print("\nA transitive dependency is linkable, not nameable. Importing ThroPlay links "
              "ThroJournal but does not let the file write `Seat`; add the import.", file=sys.stderr)
        return 1

    note = f", {len(ambiguous)} name(s) skipped as ambiguous" if ambiguous else ""
    print(f"ok: {checked} Swift files, {len(declared)} public types across {len(mods)} modules, "
          f"every named module imported{note}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
