#!/usr/bin/env python3
"""The brand is the mark, on every page, and the colours are the tokens.

**Why this exists.** The founder looked at a new page and said, in effect, *that is not the logo — that is
the text with the slashed O in it.* They were right, and it was true of **every page on the site**: eleven
files set the name in a typeface and called it the wordmark. THRØ's Ø is a **dart through a ring** at
measured proportions (`MarkGeometry.Ratios.wordmark`), which the app has drawn live since PD-006. A
typeface's Ø is a letter with a stroke across it. Those are two different logos, and the site was wearing
the wrong one.

It is the sort of mistake nobody makes on purpose and everybody makes again, because typing `THRØ` is
easier than referencing an asset and it looks nearly right until somebody who knows the brand sees it.

**Three things are held here.**

1. **The mark is the mark.** No page may present the brand name as text in a heading or a brand slot; it
   uses `wordmark.svg`, which `tools/make_web_wordmark.py` generates from the app's own ratios. The name
   in running prose is fine and expected — this is about the logo, not the word.
2. **Every page carries it.** Two pages (`fixtures.html`, `table.html`) had no brand on them at all, and a
   league table with no identity on it is a table somebody screenshots with nothing to say where it came
   from.
3. **Colours come from the tokens.** A hex literal in a stylesheet is a colour that will not follow the
   brand when the brand moves. The exceptions are stated below and each has a reason.

Run: python3 tools/check_brand.py
"""

from __future__ import annotations

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
WEB = ROOT / "apps/web"

BRAND = "THRØ"

# A hex colour may appear in these places for reasons that are not "somebody guessed a green".
COLOUR_EXCEPTIONS = {
    # The generated token file *is* where the hexes live.
    "tokens.css",
}
# Fallbacks after a var(), for a television browser too old to resolve custom properties. The var is the
# source; the literal is what stops the page being unreadable on a 2016 Samsung. Permitted — **and
# checked against the token**, because a fallback written from memory is a second, wrong brand colour
# that only ever appears on the devices nobody tests on. Both of the first two written here were wrong.
FALLBACK = re.compile(r"var\((--[a-z0-9-]+),\s*(#[0-9A-Fa-f]{6})\s*\)")
# Neutral ink used for shadows and hairlines, where a token would be inventing a brand colour for
# something that is not one.
NEUTRAL = re.compile(r"rgba?\(\s*\d+\s*,\s*\d+\s*,\s*\d+\s*(,\s*[\d.]+\s*)?\)")


def pages() -> list[pathlib.Path]:
    return sorted(WEB.glob("*.html"))


def brand_as_text(markup: str) -> list[str]:
    """The name set as type inside a heading or a brand slot — the logo, drawn wrong."""
    found = []
    for match in re.finditer(
        r"<(h1|h2|p)\b[^>]*class=\"[^\"]*(wordmark|brand|eyebrow)[^\"]*\"[^>]*>(.*?)</\1>", markup, re.S
    ):
        if BRAND in re.sub(r"<[^>]+>", "", match.group(3)):
            found.append(match.group(0)[:90].replace("\n", " "))
    return found


SWIFT = ROOT / "packages/client-ios/Sources"
# `ThroWordmark` is the one place the name may be composed from letters, because it is the thing that
# draws the mark. `LaunchSequence` animates the same composition into being.
DRAWS_THE_MARK = {"Slate.swift", "LaunchSequence.swift"}


def brand_as_swift_text() -> list[str]:
    """`Text("THRØ")` — the brand rendered by a font, on a screen, where the mark belongs.

    It was in five files and every one was a **second screen**: the Lock Screen widget, the external
    display board, the Apple TV's two screens and the watch. The phone's own screens all drew the mark
    properly, which is the shape of this defect — the surfaces nobody demos got a quick `Text`.
    """
    found = []
    for path in sorted(SWIFT.rglob("*.swift")):
        if path.name in DRAWS_THE_MARK:
            continue
        for number, line in enumerate(path.read_text().splitlines(), start=1):
            if 'Text("' + BRAND + '")' in line:
                found.append(f"{path.relative_to(ROOT)}:{number} draws the brand with a font.")
    return found


def main() -> int:
    complaints: list[str] = []

    for offender in brand_as_swift_text():
        complaints.append(
            f"{offender}\n"
            f"    Use ThroWordmark(capHeight:color:), which draws the Ø from the mark's own geometry."
        )

    if not (WEB / "wordmark.svg").exists():
        complaints.append("apps/web/wordmark.svg is missing — run tools/make_web_wordmark.py")

    for page in pages():
        markup = page.read_text()
        name = page.name

        for offender in brand_as_text(markup):
            complaints.append(
                f"{name}: the brand is set as text in a heading — {offender}\n"
                f"    THRØ's Ø is a dart through a ring, not the typeface's Ø. Use wordmark.svg."
            )

        if "wordmark.svg" not in markup:
            complaints.append(
                f"{name}: carries no brand mark.\n"
                f"    A page somebody screenshots with nothing on it to say where it came from."
            )

    tokens = dict(re.findall(r"^\s*(--[a-z0-9-]+):\s*(#[0-9A-Fa-f]{6});", (WEB / "tokens.css").read_text(), re.M))

    for sheet in sorted(WEB.glob("*.css")) + sorted(WEB.glob("*.html")):
        if sheet.name in COLOUR_EXCEPTIONS:
            continue
        text = sheet.read_text()
        for token, fallback in FALLBACK.findall(text):
            real = tokens.get(token)
            if real is None:
                complaints.append(f"{sheet.name}: var({token}) is not a token in tokens.css")
            elif real.upper() != fallback.upper():
                complaints.append(
                    f"{sheet.name}: the fallback for {token} is {fallback}, but the token is {real}.\n"
                    f"    An old browser would show the wrong brand colour, on the one device nobody tests."
                )
        text = FALLBACK.sub("", text)
        text = NEUTRAL.sub("", text)
        for hexes in re.finditer(r"(?<![\w&])#[0-9A-Fa-f]{6}\b", text):
            line = text[: hexes.start()].count("\n") + 1
            complaints.append(
                f"{sheet.name}:{line}: the colour {hexes.group(0)} is written out.\n"
                f"    Use a token from tokens.css, or var(--token, {hexes.group(0)}) if an old "
                f"television browser needs the fallback."
            )

    if complaints:
        print("The brand has drifted:\n")
        for complaint in complaints:
            print(f"  {complaint}\n")
        return 1

    print(f"the brand holds — {len(pages())} pages, all wearing the generated mark, no loose colours")
    return 0


if __name__ == "__main__":
    sys.exit(main())
