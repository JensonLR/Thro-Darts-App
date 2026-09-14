#!/usr/bin/env python3
"""The type roles are the same roles on iOS and Android (PD-093).

`ThroTypography` exists twice — in `Typography.swift` and in `Typography.kt` — because the weights, trackings
and families live in the Swift rather than in the token source, so no generator can feed both. Two copies of a
type scale drift the first time somebody tunes one. This reads both and fails on any role whose family, size
token, weight, tracking, case or numerals differ, or that exists on one platform only.

Run: python3 tools/check_type_parity.py
"""
from __future__ import annotations

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SWIFT = ROOT / "packages/client-ios/Sources/ThroDesign/Typography.swift"
KOTLIN = ROOT / "packages/client-android/src/main/kotlin/thro/client/Typography.kt"

WEIGHTS = {"regular": "Normal", "medium": "Medium", "semibold": "SemiBold", "bold": "Bold",
           "heavy": "ExtraBold", "black": "Black"}


def swift_roles() -> dict[str, dict]:
    block = SWIFT.read_text().split("public enum ThroTypography {", 1)[1]
    out = {}
    for m in re.finditer(r"public static let (\w+) = ThroTypeRole\((.*?)\)\n", block, re.S):
        a = m.group(2)
        out[m.group(1)] = {
            "family": re.search(r"family: \.(\w+)", a).group(1).upper(),
            "size": re.search(r"size: ThroType\.(\w+)", a).group(1),
            "weight": WEIGHTS[re.search(r"weight: \.(\w+)", a).group(1)],
            "tracking": float((re.search(r"trackingEm: ([-\d.]+)", a) or [None, "0"])[1]),
            "uppercase": "uppercase: true" in a,
            "tabular": "tabularNumerals: true" in a,
        }
    return out


def kotlin_roles() -> dict[str, dict]:
    block = KOTLIN.read_text().split("public object ThroTypography {", 1)[1]
    out = {}
    for m in re.finditer(r"public val (\w+): ThroTypeRole = ThroTypeRole\((.*?)\n    \)", block, re.S):
        a = m.group(2)
        out[m.group(1)] = {
            "family": re.search(r"Family\.(\w+)", a).group(1),
            "size": re.search(r"size = ThroType\.(\w+)", a).group(1),
            "weight": re.search(r"weight = FontWeight\.(\w+)", a).group(1),
            "tracking": float((re.search(r"trackingEm = ([-\d.]+)f", a) or [None, "0"])[1]),
            "uppercase": "uppercase = true" in a,
            "tabular": "tabularNumerals = true" in a,
        }
    return out


def main() -> int:
    s, k = swift_roles(), kotlin_roles()
    problems = []
    for name in sorted(set(s) | set(k)):
        if name not in k:
            problems.append(f"{name}: on iOS and not on Android")
        elif name not in s:
            problems.append(f"{name}: on Android and not on iOS")
        else:
            for field in s[name]:
                if s[name][field] != k[name][field]:
                    problems.append(f"{name}.{field}: iOS {s[name][field]!r}, Android {k[name][field]!r}")
    if not s:
        problems.append("read no roles from Typography.swift — has its shape changed?")
    if problems:
        print("The two type scales have drifted:\n")
        for p in problems:
            print(f"  {p}")
        return 1
    print(f"the type roles are the same on both platforms — {len(s)} roles")
    return 0


if __name__ == "__main__":
    sys.exit(main())
