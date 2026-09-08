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
  4. **Every icon-only `Button` is named.** A control whose label draws a glyph and nothing else is
     silent to VoiceOver: a chevron is not a word, and a screen reader announces "button" and
     stops.

Rules 2 and 3 are skipped for buttons inside a `.confirmationDialog`/`.alert` block, which are the
system's to draw and must not be restyled.

**`ShareLink` is held to the same three rules**, and it was not: the export's share control was a
bare `Text` with no style and no tap target, so a finger landing beside the words landed on nothing
— the exact complaint that produced this file, on a control it did not look at. A `ShareLink` is a
button the player taps; that it comes from SwiftUI does not make it the system's to draw when we
have given it our own label.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
SOURCES = ROOT / "packages/client-ios/Sources"

BUTTON = re.compile(r"(?:^|[^A-Za-z])(?:Button|ShareLink)\s*(?:\(|\{)")
SHARE = re.compile(r"(?:^|[^A-Za-z])ShareLink\s*\(")
# A button the system draws. `Button("Title") { action }` — the title-and-action initialiser, with
# no label view — is reserved in this codebase for the buttons inside a `.confirmationDialog` or
# `.alert`, which iOS lays out and styles itself and which would look like nothing else on the phone
# if we restyled them. Everything the app draws itself passes a label view, or is a `ThroButton` or
# `ThroTextButton`. The convention is enforced below: a file may only use this form if it actually
# presents a dialog.
SYSTEM = re.compile(r"Button\(\s*\"")
DIALOG = (".confirmationDialog(", ".alert(")
TARGET = ("throTapTarget", "throRowTapTarget", "contentShape", "touchTarget", "ThroButtonFace",
          "ChalkKeyStyle")

# Two of those are names of components rather than modifiers, and they are in the list because each
# one *is* a tap target: it gives the control the size the design says and closes with a
# `contentShape`. Trusting a name is exactly the narrowing this file's docstring warns about, so the
# names are not trusted — `vocabulary_is_honest()` reads each component and holds it to that, and a
# vocabulary entry fails with the component behind it.
#
#   `ThroButtonFace` builds the face inside the label.
#   `ChalkKeyStyle` (SLATE B.3) does it from the `ButtonStyle` instead, because a chalk key's face,
#   its boundary and its pressed state are one drawing and `isPressed` is only readable there.
#
# The declaration each is found by is spelled out, because "the name appears in the file" would be
# satisfied by a comment mentioning it.
PROVIDERS = {
    "ThroButtonFace": ("packages/client-ios/Sources/ThroDesign/Components.swift",
                       "public struct ThroButtonFace"),
    "ChalkKeyStyle": ("packages/client-ios/Sources/ThroDesign/Chalk.swift",
                      "public struct ChalkKeyStyle"),
}

# Rule 4: an icon-only control is named. These are the views that draw nothing a screen reader can
# read, so a label built only from them says nothing at all; any OTHER capitalised view is presumed
# to draw something with words in it, which is why `PlayerIdentity` in a row makes it not icon-only.
MUTE = {"Button", "Icon", "HStack", "VStack", "ZStack", "Group", "Spacer", "Circle", "Rectangle",
        "RoundedRectangle", "Capsule", "Color", "Image", "Divider", "ThroDivider", "Badge"}
VIEW = re.compile(r"\b([A-Z]\w*)\s*\(")


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


def label(block: str) -> str:
    """Just the label — the part that draws — without the modifiers applied to the Button.

    The distinction matters for rule 4: `.buttonStyle(ThroPressStyle(...))` is a capitalised name
    followed by a bracket and draws nothing, so counting it as "this label draws something" made the
    rule pass on a button with no label at all. Found by removing a real `accessibilityLabel` and
    watching the check stay green.
    """
    lines = block.splitlines()
    if not lines:
        return block
    indent = len(lines[0]) - len(lines[0].lstrip())
    out = [lines[0]]
    for line in lines[1:]:
        if line.strip() and len(line) - len(line.lstrip()) == indent and line.lstrip().startswith("."):
            break
        out.append(line)
    return "\n".join(out)


def vocabulary_is_honest() -> list[str]:
    """Every component `TARGET` accepts by name must still be the thing it says it is.

    A word in a list of accepted targets is worth exactly as much as the component behind it. If
    somebody removes the `contentShape` or the minimum height from one of them, every control built
    on it silently stops having a hit area larger than its ink — and this file would go on passing
    them all, which is worse than never having accepted the name.
    """
    problems: list[str] = []
    for name, (where, declaration) in PROVIDERS.items():
        if name not in TARGET:
            problems.append(f"{name} is held to the tap-target contract but TARGET no longer "
                            f"accepts it, so the proof guards nothing.")
            continue
        path = ROOT / where
        if not path.exists():
            problems.append(f"{where} is missing, and TARGET accepts {name} as a tap target")
            continue
        text = path.read_text(encoding="utf-8")
        start = text.find(declaration)
        if start < 0:
            problems.append(f"{name} is accepted as a tap target and no longer exists. Either "
                            f"restore it or take it out of TARGET.")
            continue
        # Bounded at the next top-level declaration, not read to the end of the file. Unbounded, the
        # `.contentShape(` of some later component satisfied this and the check passed with the
        # face's own removed — the exact false comfort it exists to prevent, found by removing it
        # and watching this stay green.
        rest = text[start:]
        end = rest.find("\npublic ", 1)
        body = rest if end < 0 else rest[:end]
        missing = [need for need in (".contentShape(", "minHeight:") if need not in body]
        if missing:
            problems.append(f"{name} is accepted as a tap target but no longer carries "
                            f"{' and '.join(missing)} — every control built on it lost its hit area.")
    return problems


def main() -> int:
    problems: list[str] = []
    buttons = 0
    problems.extend(vocabulary_is_honest())
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
            if SYSTEM.search(code) and not SHARE.search(code):
                if not any(d in text for d in DIALOG):
                    problems.append(
                        f"{rel}:{i + 1}: Button(\"…\") {{ … }} is the system's dialog button, and "
                        f"this file presents no dialog. Use ThroButton or ThroTextButton."
                    )
                continue
            buttons += 1
            kind = "ShareLink" if SHARE.search(code) else "Button"
            block = statement(lines, i)
            if ".buttonStyle(" not in block:
                problems.append(f"{rel}:{i + 1}: a {kind} with no .buttonStyle — it will not react.")
            if not any(t in block for t in TARGET):
                problems.append(
                    f"{rel}:{i + 1}: a {kind} whose label reaches no tap target — a finger landing "
                    f"beside the ink lands on nothing. Add throTapTarget() or throRowTapTarget()."
                )
            # A control whose label draws only a glyph is silent to VoiceOver. A glyph is not a name.
            drawn = label(block)
            if "Icon(" in drawn and ".accessibilityLabel" not in block and not (set(VIEW.findall(drawn)) - MUTE):
                problems.append(
                    f"{rel}:{i + 1}: an icon-only {kind} with no .accessibilityLabel — it says "
                    f"nothing at all to a screen reader."
                )
    if problems:
        print("Controls that do not react:", file=sys.stderr)
        for problem in problems:
            print(f"  {problem}", file=sys.stderr)
        return 1
    print(f"ok: {buttons} controls, every one styled, every one with a tap target, "
          f"and every icon-only one named")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
