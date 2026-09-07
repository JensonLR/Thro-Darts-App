#!/usr/bin/env python3
"""Every control reacts, and every control is big enough to hit.

The founder, from a build on their phone: *"Buttons need to be more reactive, sometimes when I
press close to them they don't react and have to be exactly direct on them."*

Both halves of that were one habit. `.buttonStyle(.plain)` is SwiftUI for **do nothing**: no
pressed appearance, and a hit area the size of the ink the label happens to draw. It was on 32
controls, including `ThroButton` — the primary button of the whole application. `ThroPressStyle`,
built for PD-015, was on three.

Nothing in this repository was going to catch that. No test constructs a screen, and a hit area is
not a thing a unit test can see. So it is checked here, mechanically, on the source:

  1. **No `.buttonStyle(.plain)` in the app's own source.** A control either uses `ThroPressStyle`
     or it is a system control (a `.confirmationDialog` or `.alert` button) that Apple styles.
  2. **Every `Button` outside a dialog carries a `.buttonStyle`.** Not being `.plain` is not enough
     if the style is missing altogether.
  3. **Every `Button` label reaches a tap target.** One of `throTapTarget`, `throRowTapTarget`,
     `contentShape`, or a `touchTargetMinimum` frame must appear inside the label.

Rules 2 and 3 are skipped for buttons inside a `.confirmationDialog`/`.alert` block, which are the
system's to draw and must not be restyled.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
SOURCES = ROOT / "packages/client-ios/Sources"

BUTTON = re.compile(r"(?:^|[^A-Za-z])Button\s*(?:\(|\{)")
# A button the system draws. `Button("Title") { action }` — the title-and-action initialiser, with
# no label view — is reserved in this codebase for the buttons inside a `.confirmationDialog` or
# `.alert`, which iOS lays out and styles itself and which would look like nothing else on the phone
# if we restyled them. Everything the app draws itself passes a label view, or is a `ThroButton` or
# `ThroTextButton`. The convention is enforced below: a file may only use this form if it actually
# presents a dialog.
SYSTEM = re.compile(r"Button\(\s*\"")
DIALOG = (".confirmationDialog(", ".alert(")
TARGET = ("throTapTarget", "throRowTapTarget", "contentShape", "touchTarget")


def statement(lines: list[str], start: int) -> str:
    """The `Button` and everything modifying it, however long its label runs.

    A fixed window of lines cannot do this: a row's label is thirty lines and a chevron's is three,
    and guessing a number either misses a real defect or invents one. The chain ends at the first
    line indented no further than the `Button` that is neither its closing brace nor another
    modifier — which is exactly where the compiler ends it too.
    """
    indent = len(lines[start]) - len(lines[start].lstrip())
    out = [lines[start]]
    for line in lines[start + 1 :]:
        # A blank line or a comment between a Button and its modifiers is still inside the chain.
        if not line.strip() or line.lstrip().startswith("//"):
            out.append(line)
            continue
        here = len(line) - len(line.lstrip())
        if here < indent:
            break
        if here == indent and not line.lstrip().startswith((".", "}")):
            break
        out.append(line)
    return "\n".join(out)


def main() -> int:
    problems: list[str] = []
    buttons = 0
    for path in sorted(SOURCES.rglob("*.swift")):
        text = path.read_text(encoding="utf-8")
        lines = text.splitlines()
        rel = path.relative_to(ROOT)
        for i, line in enumerate(lines):
            code = line.split("//")[0] if not line.lstrip().startswith("//") else ""
            if ".buttonStyle(.plain)" in code:
                problems.append(
                    f"{rel}:{i + 1}: .buttonStyle(.plain) — no pressed state and a hit area the "
                    f"size of the ink. Use ThroPressStyle."
                )
            if not BUTTON.search(code):
                continue
            if SYSTEM.search(code):
                if not any(d in text for d in DIALOG):
                    problems.append(
                        f"{rel}:{i + 1}: Button(\"…\") {{ … }} is the system's dialog button, and "
                        f"this file presents no dialog. Use ThroButton or ThroTextButton."
                    )
                continue
            buttons += 1
            block = statement(lines, i)
            if ".buttonStyle(" not in block:
                problems.append(f"{rel}:{i + 1}: a Button with no .buttonStyle — it will not react.")
            if not any(t in block for t in TARGET):
                problems.append(
                    f"{rel}:{i + 1}: a Button whose label reaches no tap target — a finger landing "
                    f"beside the ink lands on nothing. Add throTapTarget() or throRowTapTarget()."
                )
    if problems:
        print("Controls that do not react:", file=sys.stderr)
        for problem in problems:
            print(f"  {problem}", file=sys.stderr)
        return 1
    print(f"ok: {buttons} controls, every one styled and every one with a tap target")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
