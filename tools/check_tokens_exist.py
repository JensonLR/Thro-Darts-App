#!/usr/bin/env python3
"""Every design token the client names is a token that exists.

The generated tokens are four flat namespaces — `ThroColor`, `ThroSpacing`, `ThroType`,
`ThroMotion` — and the names in them do not respect that split. `motionScaleImpact` is in
`ThroMotion`; `motionTravelMedium`, which reads exactly like a sibling, is in `ThroSpacing`,
because it is a distance. Writing `ThroMotion.motionTravelMedium` is the obvious mistake and it is
the one this repository made.

Swift catches it — in CI, on a macOS runner, several minutes into a build, after everything else has
already run. This catches it in under a second on any machine, which is the difference between a
typo and a wasted cycle.

It checks the generated file rather than a list kept here, so a token that is added, renamed or
removed upstream is reflected the moment the file is regenerated.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
GENERATED = ROOT / "packages/design-tokens/generated/ThroTokens.swift"
SOURCES = [ROOT / "packages/client-ios/Sources", ROOT / "packages/client-ios/Tests"]
NAMESPACES = ("ThroColor", "ThroSpacing", "ThroType", "ThroMotion")


def declared() -> dict[str, set[str]]:
    out: dict[str, set[str]] = {}
    current = None
    for line in GENERATED.read_text(encoding="utf-8").splitlines():
        opened = re.match(r"public enum (\w+)", line)
        if opened:
            current = opened.group(1)
            out[current] = set()
            continue
        member = re.match(r"\s+public static let (\w+)", line)
        if member and current:
            out[current].add(member.group(1))
    return out


def main() -> int:
    tokens = declared()
    missing = [n for n in NAMESPACES if n not in tokens]
    if missing:
        print(f"{GENERATED.relative_to(ROOT)} declares no {', '.join(missing)}", file=sys.stderr)
        return 1

    problems: list[str] = []
    used = 0
    for root in SOURCES:
        for path in sorted(root.rglob("*.swift")):
            rel = path.relative_to(ROOT)
            for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
                code = line.split("//")[0]
                for namespace, name in re.findall(r"\b(%s)\.(\w+)" % "|".join(NAMESPACES), code):
                    used += 1
                    if name in tokens[namespace]:
                        continue
                    elsewhere = [n for n in NAMESPACES if name in tokens[n]]
                    where = f" — it is {elsewhere[0]}.{name}" if elsewhere else ""
                    problems.append(f"{rel}:{number}: no {namespace}.{name}{where}")
    if problems:
        print("Tokens that do not exist:", file=sys.stderr)
        for problem in sorted(set(problems)):
            print(f"  {problem}", file=sys.stderr)
        return 1
    print(f"ok: {used} token references, every one declared")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
