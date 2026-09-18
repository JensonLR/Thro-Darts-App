#!/usr/bin/env python3
"""The web's type is the design system's type, and the faces it asks for are the faces it ships.

A sibling to `check_tokens_exist.py` rather than a clause inside it: that check reads Swift and the
generated `ThroTokens.swift`, and the web reads CSS. Same bargain, different language.

**Every failure here is silent and looks like a design decision** — the same sentence
`check_bundle_faces.py` opens with, because it is the same class of fault one platform over.

  1. A raw `font-size: 14px` renders. It just renders at a size the scale never agreed to, and the
     site drifts one declaration at a time. `apps/web/thro.css` had twenty-five of them and no type
     scale at all; `body` set no size, so every page ran at the browser's 16px while the token layer
     said 17.
  2. A `font-family` naming a face by name renders too, in whatever the reader's machine has.
     `wall.html` named `Inter` — a face THRØ does not own, does not ship and never loaded — so every
     pub television running THRØ drew in its own system font under THRØ's colours.
  3. A `font-weight` with no matching `@font-face` renders *most* convincingly of all: the browser
     smears the nearest weight into a synthetic bold. Nothing is missing, nothing errors, and the
     type is simply wrong.

So this holds three things at once: no raw sizes, no faces named outside the tokens, and a real file
behind every weight anything on the site asks for.

`wall.html` is exempt from the size rule and from nothing else. It is a television read from four
metres and its type scales off the viewport, which a px scale cannot express — so its sizes must be
viewport units, **every one of them**. A `px` there fails, which is what makes the exemption a rule
rather than a hole.
"""
from __future__ import annotations

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
WEB = ROOT / "apps/web"
CSS = WEB / "thro.css"
WALL = WEB / "wall.html"
TOKENS = WEB / "tokens.css"
FONT_DIR = WEB / "fonts"
LICENCE = FONT_DIR / "OFL-Archivo.txt"

COMMENT = re.compile(r"/\*.*?\*/", re.S)
HTML_COMMENT = re.compile(r"<!--.*?-->", re.S)
STYLE_BLOCK = re.compile(r"<style[^>]*>(.*?)</style>", re.S | re.I)
STYLE_ATTR = re.compile(r'style\s*=\s*"([^"]*)"', re.I)
FONT_SIZE = re.compile(r"font-size\s*:\s*([^;}\"]+)")
FONT_FAMILY = re.compile(r"font-family\s*:\s*([^;}\"]+)")
FONT_WEIGHT = re.compile(r"font-weight\s*:\s*([^;}\"]+)")
FACE = re.compile(r"@font-face\s*\{[^}]*\}")
FACE_WEIGHT = re.compile(r"font-weight\s*:\s*(\d+)")
FACE_SRC = re.compile(r'url\(\s*"([^"]+)"')
VIEWPORT = re.compile(r"^[0-9.]+(vw|vh|vmin|vmax)$")


def decomment_css(text: str) -> str:
    return COMMENT.sub(" ", text)


def token_weights() -> dict[str, int]:
    """`--font-weight-bold` is a name; a face needs the number behind it."""
    out = {}
    for name, value in re.findall(r"(--font-weight-[\w-]+)\s*:\s*(\d+)", TOKENS.read_text(encoding="utf-8")):
        out[name] = int(value)
    return out


def faces_in(text: str) -> dict[int, str]:
    """weight -> src url, for every @font-face in this stylesheet."""
    out = {}
    for block in FACE.findall(text):
        weight = FACE_WEIGHT.search(block)
        src = FACE_SRC.search(block)
        if weight and src:
            out[int(weight.group(1))] = src.group(1)
    return out


def asked_weights(text: str, weights: dict[str, int]) -> set[int]:
    """Every weight this stylesheet asks something to be drawn in, resolved to a number."""
    out: set[int] = set()
    for raw in FONT_WEIGHT.findall(text):
        value = raw.strip()
        if value.isdigit():
            out.add(int(value))
            continue
        named = re.search(r"--font-weight-[\w-]+", value)
        if named and named.group(0) in weights:
            out.add(weights[named.group(0)])
    # `<strong>` and `<b>` are bold with nothing in any stylesheet saying so, and there are 78 of
    # them across these pages. A missing 700 would be synthesised in every one.
    out.add(700)
    return out


def main() -> int:
    problems: list[str] = []

    for required in (CSS, TOKENS, WALL):
        if not required.exists():
            print(f"  FAIL  {required.relative_to(ROOT)} is missing")
            return 1

    weights = token_weights()
    if not weights:
        print("  FAIL  apps/web/tokens.css declares no --font-weight-*; the faces cannot be resolved")
        return 1

    css = decomment_css(CSS.read_text(encoding="utf-8"))
    # The @font-face blocks state their own literal weights; they are not the site's type.
    css_rules = FACE.sub(" ", css)

    # 1. No raw sizes in the site stylesheet.
    sizes = 0
    for value in FONT_SIZE.findall(css_rules):
        sizes += 1
        if not value.strip().startswith("var(--typography-"):
            problems.append(
                f"apps/web/thro.css: font-size: {value.strip()} is a raw size. The scale is in "
                f"tokens.css (--typography-*-size); round to the nearest one rather than adding a number."
            )

    # 2. No face named outside the tokens, anywhere.
    for value in FONT_FAMILY.findall(css_rules):
        if not value.strip().startswith("var(--font"):
            problems.append(
                f"apps/web/thro.css: font-family: {value.strip()} names a face outside the tokens. "
                f"Use var(--font-ui) or var(--font-sport)."
            )

    # 3. A file behind every weight, and the licence beside the files.
    faces = faces_in(css)
    wall_text = HTML_COMMENT.sub(" ", WALL.read_text(encoding="utf-8"))
    wall_css = decomment_css("\n".join(STYLE_BLOCK.findall(wall_text)))
    wall_faces = faces_in(wall_css)

    if faces != wall_faces:
        problems.append(
            "apps/web/wall.html and apps/web/thro.css declare different @font-face sets. The wall "
            "links tokens.css and its own style and nothing else, so it carries its own copy — and a "
            "copy that has drifted is a television drawing in a face the rest of the site replaced."
        )

    for weight, src in sorted(faces.items()):
        path = (WEB / src).resolve()
        if not path.exists():
            problems.append(f"apps/web/thro.css: @font-face weight {weight} points at {src}, which is not there.")

    wanted = asked_weights(css_rules, weights) | asked_weights(wall_css, weights)
    for weight in sorted(wanted):
        if weight not in faces:
            problems.append(
                f"apps/web: font-weight {weight} is asked for with no @font-face behind it. The "
                f"browser will synthesise it and nothing will look broken enough to notice."
            )

    if faces and not LICENCE.exists():
        problems.append(
            f"apps/web/fonts ships {len(faces)} faces and {LICENCE.name} is not beside them. "
            f"A font shipped without its OFL text is a licence problem, not a rendering one."
        )

    # 4. No inline sizes or faces in the pages.
    inline = 0
    for page in sorted(WEB.glob("*.html")):
        text = HTML_COMMENT.sub(" ", page.read_text(encoding="utf-8"))
        for attr in STYLE_ATTR.findall(text):
            for value in FONT_SIZE.findall(attr):
                inline += 1
                problems.append(
                    f"{page.relative_to(ROOT)}: style=\"font-size:{value.strip()}\" is a raw size on "
                    f"an element. A page does not decide its own type; thro.css does."
                )
            for value in FONT_FAMILY.findall(attr):
                problems.append(f"{page.relative_to(ROOT)}: style names a face inline: {value.strip()}")

        block = decomment_css("\n".join(STYLE_BLOCK.findall(text)))
        if not block:
            continue
        for value in FONT_FAMILY.findall(FACE.sub(" ", block)):
            if not value.strip().startswith("var(--font"):
                problems.append(
                    f"{page.relative_to(ROOT)}: font-family: {value.strip()} names a face outside the "
                    f"tokens. THRØ ships its own; use var(--font-ui)."
                )
        for value in FONT_SIZE.findall(FACE.sub(" ", block)):
            value = value.strip()
            if page.name == WALL.name:
                # The wall's exemption, and its price: viewport units or nothing.
                if not VIEWPORT.match(value):
                    problems.append(
                        f"{page.relative_to(ROOT)}: font-size: {value} — the wall's type scales off "
                        f"the viewport so a television of any size reads it. A fixed size here is not "
                        f"the exemption it was given."
                    )
            elif not value.startswith("var(--typography-"):
                problems.append(f"{page.relative_to(ROOT)}: font-size: {value} in a <style> block is a raw size.")

    if problems:
        print("The web's type has come off the design system:", file=sys.stderr)
        for problem in sorted(set(problems)):
            print(f"  {problem}", file=sys.stderr)
        return 1

    kb = sum((WEB / src).stat().st_size for src in faces.values()) // 1024
    print(f"check_web_type: {sizes} font-sizes in thro.css, every one a type token; {inline} inline sizes "
          f"across {len(list(WEB.glob('*.html')))} pages; {len(faces)} faces on disk ({kb} KB total, "
          f"subset, self-hosted) covering every weight asked for")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
