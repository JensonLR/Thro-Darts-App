#!/usr/bin/env python3
"""`color*` flips with the appearance. `thro*` does not. That is a fact, not a convention.

Two whole mechanisms in this repository rest on that sentence and neither of them checks it.

`check_tokens_exist.py` refuses a raw `thro*` pigment painted as a surface on a screen, on the
grounds that a pigment is right in one appearance and wrong in the other. That rule is only worth
anything if the `color*` token the author is sent to instead actually differs between the two. It
was written after Home's masthead drew `throChalkSunken` under `throChalk` text — a light neutral
under near-white, **1.08:1**, the wordmark on the first screen of the app, invisible, and nothing
failed because no pair covered it.

The contrast gate measures each pair in light and in dark. If a token stopped flipping, the gate
would go on printing two rows and checking one fact twice, and its count would not move.

So: **every `--color-*` token must declare a dark value, and it must differ from the light one.**
Today that holds for all of them with no exemption at all, which is the strongest state this check
can be in and the reason to write it now rather than after something breaks it.

An exemption is a dated line with a reason and it is not free: an exempt token is one the contrast
gate is measuring twice under two names, and this says so out loud.

SLATE's board tokens are the case worth stating. `colorBoardLit` is `#174F3C` in light and
`#123A2C` in dark — **both dark green**, because a board is a board in either appearance and what
changes between traits is which dark green. They flip. A "board" token that did not flip would be
a pigment wearing a semantic name, and this is what stops one being added.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "packages/design-tokens"))

# Dated, with a reason, and with the name of whoever decided it. Empty is the correct state.
EXEMPT: dict[str, str] = {}


def main() -> int:
    from build import lift, flat  # noqa: E402 — the generator is the single source of the values

    doc = lift()
    light, dark = flat(doc, "light"), flat(doc, "dark")
    semantic = [n for n in sorted(doc["tokens"])
                if re.match(r"^--color-", n) and doc["tokens"][n]["$type"] == "color"]
    if not semantic:
        print("no --color-* tokens found at all — this check is looking at the wrong file",
              file=sys.stderr)
        return 1

    problems: list[str] = []
    flipping = 0
    for name in semantic:
        declared = "dark" in doc["tokens"][name]["$value"]
        lit, drk = (light.get(name) or "").lower(), (dark.get(name) or "").lower()
        if not declared:
            reason = EXEMPT.get(name)
            if reason:
                continue
            problems.append(f"{name} declares no dark value, so it is the light value in both "
                            f"appearances — a pigment wearing a semantic name.")
            continue
        if lit == drk:
            reason = EXEMPT.get(name)
            if reason:
                continue
            problems.append(f"{name} is {lit} in both appearances. Either give it a dark value or "
                            f"record it in EXEMPT with a date and a reason — the contrast gate is "
                            f"measuring it twice and learning one thing.")
            continue
        flipping += 1

    for name in EXEMPT:
        if name not in semantic:
            problems.append(f"{name} is exempt from flipping and is not a --color-* token any "
                            f"more. Delete the exemption.")
        elif light.get(name, "").lower() != dark.get(name, "").lower():
            problems.append(f"{name} is exempt from flipping and now flips. Delete the exemption — "
                            f"a stale exemption hides the next token that stops.")

    if problems:
        print("Semantic tokens that do not flip:", file=sys.stderr)
        for problem in problems:
            print(f"  {problem}", file=sys.stderr)
        return 1
    print(f"ok: {flipping} of {len(semantic)} semantic colour tokens flip between light and dark, "
          f"{len(EXEMPT)} exempt")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
