#!/usr/bin/env python3
"""Mechanical health check over the approved THRØ design components.

Every defect found in these components so far was found by reading them — the fabricated dart
progress in `TurnIndicator`, the four scoring components that paint no background. Nothing re-checks
them, so a re-export of the design system could regress any of it silently and the first sign would
be a player seeing chalk on chalk.

**This audit never edits the export.** The design system is source-precedence rank 3 and it is the
founder's to change; findings become design commissions, not patches. The script reports, and a
committed baseline turns it into a ratchet: known violations are recorded against the commission
that will fix them, and anything NEW fails.

The rules are THRØ's own, not generic React lint. A component is judged against the decisions this
repository has already taken — the integrity constraint on dart-level evidence, the Dynamic Type
contract, the contrast floor — because a generic linter would report import order and miss a
scoring surface inventing evidence.
"""

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
COMPONENTS = ROOT / "extracted" / "components"
BASELINE = ROOT / "COMPONENT_AUDIT_BASELINE.json"

# Interactive components are the only ones a touch target applies to; a 2px underline is not a
# target and flagging it would be noise that trains people to ignore the report.
INTERACTIVE = re.compile(r"\bon(Click|Press|Select|Change|Submit|Tap)\b")


def rule_focus_suppressed(text):
    """`outline: none` with nothing put back.

    Worse than omitting a focus state: it removes the one the platform supplied. A keyboard or
    switch-control user loses all focus visibility, and on a text field that is where it matters
    most. B3 records focus appearance as absent across the set; this is the subset that is
    actively suppressed.
    """
    if "outline: 'none'" not in text and 'outline: "none"' not in text:
        return None
    replacement = re.search(r"boxShadow|onFocus|focusVisible|:focus", text)
    if replacement:
        return None
    return "outline:none with no replacement focus indicator"


def rule_dart_level_evidence(text):
    """A component that renders per-dart state.

    THRØ captures visit totals; it must never invent dart-level evidence. A surface that draws
    "two of three darts thrown" is drawing something the app cannot know mid-visit, and on the live
    scoring screen that is evidence a dispute could be built on.
    """
    if re.search(r"\b(dartsThrown|dartIndex|perDart|dartsSoFar)\b", text):
        return "renders per-dart state the app cannot know mid-visit"
    return None


def rule_numeric_font_size(text):
    """A hardcoded font size does not scale.

    B3 names the Dynamic Type contract as the most expensive item to retrofit. Every size that is
    a number rather than a token is one more place that retrofit has to reach.
    """
    hits = re.findall(r"fontSize:\s*(\d+)", text)
    if hits:
        return f"hardcoded fontSize ({', '.join(hits)}) — does not scale with Dynamic Type"
    return None


def rule_hardcoded_colour(text):
    """A colour outside the token layer.

    The token pipeline is the single source for colour across Swift, Kotlin and CSS, and the
    contrast matrix is computed from it. A literal bypasses both.
    """
    hits = re.findall(r"#[0-9a-fA-F]{6}\b|rgba?\([\d.,\s]+\)", text)
    literal = [h for h in hits if "var(" not in h]
    if literal:
        return f"colour literal outside the token layer: {literal[0]}"
    return None


def rule_dark_default_without_background(text):
    """Defaults to the dark theme and paints no background.

    These render light text and rely on a dark ancestor supplying the ground. Dropped onto the
    default chalk surface they are chalk on chalk — a 1.00:1 contrast ratio, invisible. It works in
    the design kit only by CSS cascade, which does not exist on either native platform.
    """
    if "theme = 'dark'" not in text and 'theme = "dark"' not in text:
        return None
    if "background" in text:
        return None
    return "defaults theme='dark' but paints no background — chalk on chalk at 1.00:1 off-cascade"


def rule_small_touch_target(text):
    """An interactive component below the 44px minimum."""
    if not INTERACTIVE.search(text):
        return None
    for match in re.finditer(r"minHeight:\s*(\d+)", text):
        value = int(match.group(1))
        if value < 44:
            return f"interactive component with minHeight {value} — below the 44px minimum"
    return None


RULES = [
    ("focus-suppressed", rule_focus_suppressed),
    ("dart-level-evidence", rule_dart_level_evidence),
    ("numeric-font-size", rule_numeric_font_size),
    ("colour-literal", rule_hardcoded_colour),
    ("dark-default-no-background", rule_dark_default_without_background),
    ("small-touch-target", rule_small_touch_target),
]


def audit():
    if not COMPONENTS.is_dir():
        print(f"components not found at {COMPONENTS}", file=sys.stderr)
        return None
    findings = []
    files = sorted(COMPONENTS.rglob("*.jsx"))
    for path in files:
        text = path.read_text()
        rel = str(path.relative_to(COMPONENTS))
        for name, rule in RULES:
            detail = rule(text)
            if detail:
                findings.append({"component": rel, "rule": name, "detail": detail})
    return findings, len(files)


def main():
    result = audit()
    if result is None:
        return 2
    findings, count = result
    check = "--check" in sys.argv
    update = "--update-baseline" in sys.argv

    by_rule = {}
    for f in findings:
        by_rule.setdefault(f["rule"], []).append(f)

    print(f"design component audit: {count} components, {len(findings)} findings")
    print()
    for name, _ in RULES:
        hits = by_rule.get(name, [])
        print(f"  {name:<28} {len(hits)}")
        for h in hits:
            print(f"      {h['component']}")
            print(f"        {h['detail']}")
    print()

    if update:
        BASELINE.write_text(json.dumps(
            {"componentCount": count, "findings": sorted(
                findings, key=lambda f: (f["rule"], f["component"]))},
            indent=2) + "\n")
        print(f"baseline written: {BASELINE.name}")
        return 0

    if not check:
        return 0

    if not BASELINE.exists():
        print("no baseline — run with --update-baseline first", file=sys.stderr)
        return 2

    known = json.loads(BASELINE.read_text())
    known_keys = {(f["rule"], f["component"]) for f in known["findings"]}
    current_keys = {(f["rule"], f["component"]) for f in findings}

    new = sorted(current_keys - known_keys)
    fixed = sorted(known_keys - current_keys)

    for rule, component in fixed:
        print(f"  FIXED     {component}  ({rule})")
    if fixed:
        print()
        print("  A baseline entry no longer applies. Re-run with --update-baseline so the ratchet")
        print("  tightens rather than silently permitting the finding to come back.")
        print()

    for rule, component in new:
        print(f"  NEW       {component}  ({rule})")

    if new:
        print()
        print("  These are NEW findings against the approved design export. The export is not edited")
        print("  here — it is source-precedence rank 3 and the founder's to change. Raise them as")
        print("  design commissions, or update the baseline if they are accepted.")
        return 1

    print("  no new findings against the baseline")
    return 0


if __name__ == "__main__":
    sys.exit(main())
