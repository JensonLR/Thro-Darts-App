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

# The raw brand palette. These are the pigments — `chalk` is the near-white, `ink` is the dark,
# `green` is the field — and **they do not flip with the appearance**, because they are what the
# appearance-aware tokens are built out of. A screen that paints a surface with one of them is
# therefore right in one mode and wrong in the other.
#
# This is not hypothetical. Home's masthead was written as `throChalkSunken` under `throChalk` text,
# on the reading that "sunken" meant the board's dark surface. It is a light neutral. **1.08:1** — the
# wordmark on the first screen of the app, invisible. The design's contrast gate checks token pairs
# it has been told about and this was a pairing no pair covered, so nothing failed.
#
# The rule: a screen may use a semantic token as a surface (`colorBackground*`, `colorSurface*`,
# `colorStatus*`), never a pigment. `ThroDesign` may — building the semantics out of the pigments is
# its job — and so may the opening, which paints the launch field before any of this applies and
# says so in its own header.
# Two shapes, because SwiftUI has two. `.background(ThroColor.x)` / `.fill(ThroColor.x)` names the
# colour inside a call; `.background { ThroColor.x }` and `ZStack { ThroColor.x; ... }` put it on a
# line of its own, because a `Color` **is** a view. The first version of this check only knew the
# first shape, and re-introducing the exact defect it was written for did not fail it — which is the
# only way to find out that a check does not check.
PAINTED = re.compile(r"(?:background|fill)\(\s*ThroColor\.(thro[A-Z]\w*)"
                     r"|^\s*ThroColor\.(thro[A-Z]\w*)\b")
SCREEN_LAYERS = ("ThroApp/", "ThroPlay/")

# Two files paint pigments deliberately, and each of them has to say why.
#
#  - **The opening** paints the launch field before any appearance applies, and says so in its own
#    header.
#  - **The share card** is not a screen. It is a raster that leaves the phone, and a picture that
#    changed with the *sender's* light-or-dark setting would have two people in one group chat
#    posting cards that did not match, with no way to tell a theme from a defect. It is held to the
#    OPPOSITE rule — every colour on it must be the same in both traits — by
#    `check_share_card_tokens.py`, and the exemption below is granted only for a file that check is
#    actually looking at. An exemption nothing else covers is a hole with a comment on it.
PIGMENT_EXEMPT = ("ThroApp/LaunchSequence.swift", "ThroPlay/ShareCard.swift")
HELD_ELSEWHERE = {"ThroPlay/ShareCard.swift": "check_share_card_tokens"}


def exemptions_are_covered() -> list[str]:
    """Every exemption that claims another check holds the file must be telling the truth."""
    import importlib
    problems = []
    for suffix, module_name in HELD_ELSEWHERE.items():
        try:
            module = importlib.import_module(module_name)
        except ImportError:
            problems.append(f"{suffix} is exempt from the pigment rule because {module_name}.py "
                            f"holds it to the opposite one, and that file is gone.")
            continue
        if not any(covered.endswith(suffix) for covered in getattr(module, "CARD", ())):
            problems.append(f"{suffix} is exempt from the pigment rule because {module_name}.py "
                            f"holds it to the opposite one, and it no longer does.")
    return problems


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
                painted = PAINTED.search(code)
                pigment_name = painted and (painted.group(1) or painted.group(2))
                if (pigment_name
                        and any(layer in str(rel) for layer in SCREEN_LAYERS)
                        and not any(str(rel).endswith(e) for e in PIGMENT_EXEMPT)):
                    problems.append(
                        f"{rel}:{number}: ThroColor.{pigment_name} is a raw pigment painted as a "
                        f"surface. It does not flip with the appearance, so this is right in one mode "
                        f"and wrong in the other. Use a colorBackground*/colorSurface* token."
                    )
                for namespace, name in re.findall(r"\b(%s)\.(\w+)" % "|".join(NAMESPACES), code):
                    used += 1
                    if name in tokens[namespace]:
                        continue
                    elsewhere = [n for n in NAMESPACES if name in tokens[n]]
                    where = f" — it is {elsewhere[0]}.{name}" if elsewhere else ""
                    problems.append(f"{rel}:{number}: no {namespace}.{name}{where}")
    problems.extend(exemptions_are_covered())

    if problems:
        print("Tokens that do not exist, or pigments used as surfaces:", file=sys.stderr)
        for problem in sorted(set(problems)):
            print(f"  {problem}", file=sys.stderr)
        return 1
    print(f"ok: {used} token references, every one declared; no raw pigment painted as a surface "
          f"outside {'/'.join(p.rsplit('/', 1)[-1] for p in PIGMENT_EXEMPT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
