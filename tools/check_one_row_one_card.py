#!/usr/bin/env python3
"""A row is one height and a card is one padding, and a border sits inside its own shape.

**This exists because the app had three rows and two cards.** `CardRow` stood 56 points tall, `LinkRow`
52, and `SettingsRow` set no height at all and used a bare `12` where every other row used the token.
`DeskCard` padded itself 16 and `ContinueCard` 20 — and both sit on the same screens, four points apart,
with nothing to say why. Four points is not seen and is felt: a player moving between screens meets
different rhythms and reads it as different apps. That was the design research's diagnosis, and the
scale was never the problem — the *vocabulary* was.

Three things are checked:

  1. **`ThroRowMetrics` and `ThroCardMetrics` are used.** A set of numbers nobody reads is worse than no
     set at all, because it looks like the thing is solved. This is the defect `check_screens_reachable.py`
     catches for screens, applied to measurements.
  2. **No rounded shape is `.stroke`d as a border.** `.stroke` centres the line on the edge, so half of it
     falls outside the shape; `.strokeBorder` keeps it inside. One card in the app did the first and was
     the one that looked very slightly soft, which nobody could name.
  3. **A row component does not carry a bare height.** A literal beside a row is how the three heights
     came about.

A place that genuinely needs its own number says `// own-measure:` and a reason on the same line, and is
printed, so an exemption stays visible rather than quietly becoming the rule.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCES = ROOT / "packages/client-ios/Sources"
DESIGN = SOURCES / "ThroDesign/Row.swift"
BORDER = re.compile(r"(?:RoundedRectangle|Capsule|Circle)\([^\n]*\)[^\n]*(?:\n\s*)?\.stroke\(")
ROW_HEIGHT = re.compile(r"(?:minHeight|height)\s*:\s*(\d{2,3})\b")
EXEMPT = "own-measure:"
# Rows stand at ThroRowMetrics.height; anything in this band written as a literal is a row that drifted.
BAND = range(44, 73)


def main() -> int:
    if not DESIGN.is_file():
        sys.exit(f"check_one_row_one_card: {DESIGN.relative_to(ROOT)} is not there — "
                 "the measurements moved and this check stopped checking")
    files = sorted(SOURCES.rglob("*.swift"))
    if not files:
        sys.exit("check_one_row_one_card: no Swift under Sources — the tree moved and this check stopped checking")

    bad, allowed = [], []
    used = {"ThroRowMetrics": 0, "ThroCardMetrics": 0}
    for path in files:
        text = path.read_text()
        lines = text.splitlines()
        if path != DESIGN:
            for name in used:
                used[name] += text.count(name)
        for m in BORDER.finditer(text):
            line_no = text[: m.start()].count("\n") + 1
            bad.append((path.relative_to(ROOT), line_no, "a rounded shape used as a border with .stroke",
                        "use .strokeBorder: .stroke centres the line on the edge, so half of it falls outside"))
        for i, line in enumerate(lines, 1):
            if "Metrics." in line or "touchTarget" in line:
                continue
            for m in ROW_HEIGHT.finditer(line):
                if int(m.group(1)) not in BAND:
                    continue
                where = (path.relative_to(ROOT), i, f"a bare row height of {m.group(1)}",
                         "read ThroRowMetrics.height, or say `// own-measure: <why>` on this line")
                (allowed if EXEMPT in line else bad).append(where)

    for name, n in used.items():
        if n == 0:
            bad.append((DESIGN.relative_to(ROOT), 1, f"{name} is defined and read by nothing",
                        "a set of numbers nobody reads looks like the thing is solved, and is not"))

    for path, line, what, _ in allowed:
        print(f"  own measure: {path}:{line} — {what}")
    if bad:
        print("check_one_row_one_card: the row and card vocabulary has drifted.\n")
        for path, line, what, fix in bad:
            print(f"  {path}:{line} — {what}")
            print(f"    {fix}")
        return 1
    print(f"check_one_row_one_card: {len(files)} Swift files — one row height, one card padding, every border inside"
          + (f" ({len(allowed)} said why they measure their own)" if allowed else ""))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
