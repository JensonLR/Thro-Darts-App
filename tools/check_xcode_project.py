#!/usr/bin/env python3
"""The hand-maintained Xcode project refers only to things it defines.

`apps/ios/ThroDarts.xcodeproj/project.pbxproj` is written by hand in this repository — there is no
project generator, and the file is tracked. It is also the one file here that nothing checks: a
mistyped object id costs a macOS runner several minutes to discover, and macOS runners bill ten
times what a Linux one does, which is why the rest of the iOS checks live on Linux and run in a
second.

Three things are held:

  1. **Every object id referenced is defined.** A `buildPhases` entry, a `productReference`, a
     `buildConfigurationList`, a `targetProxy` — all of them are 24-character ids, and a wrong one
     is a project Xcode either refuses or silently builds without.
  2. **Every object defined is referenced**, except the root. An orphan is usually the other half of
     a mistyped reference: the object was written and then pointed at by nothing.
  3. **Braces and parentheses balance**, because a truncated write leaves a file that looks almost
     right and parses as nothing.

It deliberately does not try to be a plist parser. The failure this exists for is a dangling
reference, and finding those needs only the ids.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
PROJECT = ROOT / "apps/ios/ThroDarts.xcodeproj/project.pbxproj"

# An object is defined by `<id> /* comment */ = {` or `<id> = {` at the start of a line.
DEFINED = re.compile(r"^\t\t([0-9A-F]{24})\b[^=]*= \{", re.M)
# Any 24-hex-digit token anywhere is a reference to one.
TOKEN = re.compile(r"\b([0-9A-F]{24})\b")


def main() -> int:
    if not PROJECT.exists():
        print(f"check_xcode_project: {PROJECT} is missing", file=sys.stderr)
        return 1
    text = PROJECT.read_text(encoding="utf-8")

    problems: list[str] = []

    # 3. Balance first: everything else is meaningless in a truncated file.
    for opener, closer in (("{", "}"), ("(", ")")):
        # Count only outside quoted strings, which is where the shell script phase lives.
        depth, in_quote, escaped = 0, False, False
        for ch in text:
            if escaped:
                escaped = False
                continue
            if ch == "\\":
                escaped = True
                continue
            if ch == '"':
                in_quote = not in_quote
                continue
            if in_quote:
                continue
            if ch == opener:
                depth += 1
            elif ch == closer:
                depth -= 1
                if depth < 0:
                    problems.append(f"a stray {closer!r} closes something that was never opened")
                    break
        if depth > 0:
            problems.append(f"{depth} unclosed {opener!r}")

    defined = set(DEFINED.findall(text))
    if not defined:
        print("check_xcode_project: no objects found — the format must have changed", file=sys.stderr)
        return 1

    root = re.search(r"rootObject = ([0-9A-F]{24})", text)
    if not root:
        problems.append("no rootObject")
    referenced: set[str] = set()
    for line in text.splitlines():
        ids = TOKEN.findall(line)
        if not ids:
            continue
        stripped = line.lstrip()
        # A definition line names itself first; that occurrence is not a reference to it.
        own = DEFINED.match(line if line.startswith("\t\t") else "\t\t" + stripped)
        for found in ids:
            if own and found == own.group(1) and ids.index(found) == 0:
                continue
            referenced.add(found)

    for missing in sorted(referenced - defined):
        where = next((f"line {i + 1}" for i, l in enumerate(text.splitlines()) if missing in l), "?")
        problems.append(f"{missing} is referenced ({where}) and never defined")
    for orphan in sorted(defined - referenced - ({root.group(1)} if root else set())):
        problems.append(f"{orphan} is defined and referenced by nothing — a mistyped reference?")

    # A target without its own product, phases or configuration list is the other common slip.
    for target in re.finditer(r"([0-9A-F]{24}) /\* (\w+) \*/ = \{\n\t\t\tisa = PBXNativeTarget;(.*?)\n\t\t\};",
                              text, re.S):
        body, name = target.group(3), target.group(2)
        for required in ("buildConfigurationList", "productReference", "productType"):
            if required not in body:
                problems.append(f"target {name} has no {required}")

    if problems:
        print("The Xcode project does not hold together:", file=sys.stderr)
        for problem in problems:
            print(f"  - {problem}", file=sys.stderr)
        return 1
    targets = re.findall(r"isa = PBXNativeTarget;", text)
    print(f"check_xcode_project: {len(defined)} objects, {len(targets)} targets, "
          f"every reference defined and every object reachable.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
