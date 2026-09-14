#!/usr/bin/env python3
"""Unavailable is a place in the light. It is never an opacity.

SLATE's rule, grafted from the OCHE direction: a control a player cannot use is drawn on a darker
ground with its own ink, not faded towards whatever is behind it. The reason is arithmetic. Fading a
control composites its label towards its background, and contrast is a ratio between the two — so
the fade moves both numbers together and the label's legibility collapses faster than its
brightness does.

What that cost, measured on this repository the day this check was written:

  - `ScoreKeypad`'s Enter key, the one control in this app that commits evidence, drew its resting
    state as the whole button at 0.4 opacity. Composited: **2.20:1** in light and 2.92:1 in dark.
    Its replacement sits on `colorBoardSunken` with `colorTextOnBoardSecondary` on it: **7.60:1**,
    and the ready state is the brightest ground on the board rather than the only unfaded one.
  - `ThroButtonFace` still fades at 0.38. Every disabled button in the app measures between
    **1.91:1** and 3.48:1. It is recorded below rather than fixed here, because the paper side of
    the app gets `colorBackgroundRecessed` when SLATE reaches it and changing every button in the
    app is not a thing to smuggle into a change scoped to the keypad.

**This is a design law and not a WCAG gate.** WCAG 2.1 exempts inactive components from 1.4.3
entirely, so nothing here is a conformance failure. That exemption is the reason this check has to
exist: the contrast gate is allowed to look away from exactly the state this rule is about.

What it looks for: an `.opacity(...)` whose argument mentions availability — disabled, empty,
enabled, locked, unavailable, read-only. A decorative opacity (a ring at 0.6, a gradient stop) is
not availability and is not matched. An exception records a known state and the ratio it was at; it
does not licence a worse one, and it names who removes it.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
SOURCES = ROOT / "packages/client-ios/Sources"

# The words that make an opacity an availability statement rather than a decorative one.
AVAILABILITY = re.compile(r"\b(disabled|isEmpty|isDisabled|enabled|unavailable|available|locked|"
                          r"readOnly|readonly|inactive)\b")
OPACITY = re.compile(r"\.opacity\(([^\n]*)")

# Known, dated, measured. `(the worst ratio it is at, why, who removes it)`.
EXCEPTIONS = {
    ("ThroDesign/Components.swift", ".opacity(disabled ? 0.38 : 1)"):
        (1.91, "ThroButtonFace, every variant in both appearances (raised 2026-09-08). The paper "
               "side's answer is colorBackgroundRecessed, which arrives with SLATE E.6.",
         "SLATE E.6"),
}


def main() -> int:
    problems: list[str] = []
    checked = 0
    seen: set[tuple[str, str]] = set()
    for path in sorted(SOURCES.rglob("*.swift")):
        rel = str(path.relative_to(SOURCES))
        for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            code = line.split("//")[0] if not line.lstrip().startswith("//") else ""
            match = OPACITY.search(code)
            if not match:
                continue
            checked += 1
            # Only the argument, not the rest of the line: a row that reads
            # `.opacity(0.6)` next to something about a disabled sibling is not a dimming.
            argument = match.group(1)
            if not AVAILABILITY.search(argument):
                continue
            key = (rel, ".opacity(" + argument.strip().rstrip(")") + ")")
            exact = next((k for k in EXCEPTIONS if k[0] == rel and k[1] in code), None)
            if exact:
                seen.add(exact)
                continue
            problems.append(
                f"{rel}:{number}: {code.strip()} — availability drawn as an opacity. A faded "
                f"control is a control whose label lost its contrast. Put it on "
                f"colorBoardSunken (board) or colorBackgroundRecessed (paper) instead."
            )
            _ = key
    # An exception nothing matches any more is a stale note that hides the next regression.
    for entry in EXCEPTIONS:
        if entry not in seen:
            problems.append(f"{entry[0]}: the recorded exception for `{entry[1]}` matches nothing "
                            f"any more. Delete it — a stale exception is a hole with a date on it.")
    if problems:
        print("Availability drawn as opacity:", file=sys.stderr)
        for problem in problems:
            print(f"  {problem}", file=sys.stderr)
        return 1
    print(f"ok: {checked} opacities, none of them an availability statement, "
          f"{len(EXCEPTIONS)} recorded exception(s) still standing")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
