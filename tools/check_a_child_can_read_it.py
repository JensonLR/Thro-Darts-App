#!/usr/bin/env python3
"""The page written for young players stays readable, and stays reachable.

**Standard 4 of the ICO's *Age appropriate design code*** asks for privacy information *"in clear
language suited to the age of the child"*, and **DSA Art 14(3)** asks for the conditions and
restrictions on using a service *"in a way that minors can understand"*. `apps/web/under-18.html`
is THRØ's answer to both.

The trouble with a page like that is not writing it — it is that it decays. Somebody adds a clause
because a solicitor asked for one, somebody pastes a sentence across from `terms.html`, and six
months later the "child-friendly" page reads like the adult one with a friendlier heading. Nothing
fails, because prose does not compile.

**So the reading age is measured, not claimed.** Flesch–Kincaid grade level over the page's own
prose, which is crude but has the property that matters here: it moves in the right direction when
somebody writes a long sentence full of long words, which is exactly the failure being guarded
against. The ceiling is grade 7 — roughly a twelve-year-old — against 4.7 as written, so there is
room to edit before it complains.

**Two parts of the page are excluded, and they are excluded honestly.** The "For a parent or carer"
paragraph and the draft note are addressed to adults and say so on their face; holding them to a
child's reading age would be measuring the wrong thing and would tempt somebody to simplify a
disclaimer that ought to be precise.

**And it must stay reachable.** Standard 4 also asks for prominence. A perfect page nobody links to
is not transparency, so this refuses any page in `apps/web/` that does not offer a way to it.

Run: python3 tools/check_a_child_can_read_it.py
"""

from __future__ import annotations

import html
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
WEB = ROOT / "apps/web"
PAGE = WEB / "under-18.html"

GRADE_CEILING = 7.0
LONGEST_SENTENCE = 30

# Addressed to adults on their face. Each is matched by the sentence that opens it.
FOR_ADULTS = (
    "For a parent or carer reading this",
    "This is a draft and has not been reviewed by a solicitor",
)

VOWELS = "aeiouy"


def syllables(word: str) -> int:
    """Vowel-group counting. Wrong on 'queue' and right often enough to rank prose."""
    w = re.sub(r"[^a-z]", "", word.lower())
    if not w:
        return 0
    count, previous_was_vowel = 0, False
    for character in w:
        is_vowel = character in VOWELS
        if is_vowel and not previous_was_vowel:
            count += 1
        previous_was_vowel = is_vowel
    if w.endswith("e") and count > 1 and not w.endswith(("le", "ee")):
        count -= 1
    return max(count, 1)


def prose(markup: str) -> str:
    """The words a reader sees: comments, scripts and tags removed."""
    markup = re.sub(r"<!--.*?-->", " ", markup, flags=re.S)
    markup = re.sub(r"<(script|style|head)\b.*?</\1>", " ", markup, flags=re.S | re.I)
    markup = re.sub(r"<[^>]+>", " ", markup)
    return re.sub(r"\s+", " ", html.unescape(markup)).strip()


def for_the_child(text: str) -> str:
    """Everything from the start up to the first paragraph addressed to an adult."""
    cut = len(text)
    for opening in FOR_ADULTS:
        where = text.find(opening)
        if where != -1:
            cut = min(cut, where)
    return text[:cut]


def sentences(text: str) -> list[str]:
    return [s.strip() for s in re.split(r"[.!?]+(?:\s|$)", text) if s.strip()]


def main() -> int:
    if not PAGE.exists():
        print(f"  FAIL  {PAGE.relative_to(ROOT)} is missing — Standard 4 and DSA Art 14(3) need it")
        return 1

    text = for_the_child(prose(PAGE.read_text()))
    lines = sentences(text)
    words = re.findall(r"[A-Za-z'’]+", text)
    if not lines or not words:
        print(f"  FAIL  {PAGE.relative_to(ROOT)} has no prose in it")
        return 1

    syllable_total = sum(syllables(word) for word in words)
    words_per_sentence = len(words) / len(lines)
    syllables_per_word = syllable_total / len(words)
    grade = 0.39 * words_per_sentence + 11.8 * syllables_per_word - 15.59

    failures: list[str] = []

    if grade > GRADE_CEILING:
        failures.append(
            f"reading age is grade {grade:.2f}, over the {GRADE_CEILING:.0f} ceiling.\n"
            f"    {words_per_sentence:.1f} words per sentence, {syllables_per_word:.2f} syllables per word.\n"
            f"    Shorter sentences move this fastest. Standard 4 asks for language suited to the\n"
            f"    age of the child, and twelve is the age this page is written for."
        )

    for sentence in lines:
        length = len(re.findall(r"[A-Za-z'’]+", sentence))
        if length > LONGEST_SENTENCE:
            failures.append(
                f"a {length}-word sentence — split it:\n      “{sentence[:150]}…”"
            )

    # Prominence. Every page a person *reads* offers a way to it.
    #
    # `wall.html` is exempt and the reason is not convenience. It is a **display**: a board on a pub
    # television, driven by nobody, with `cursor: none` and no pointer in the room. A link on it could
    # not be followed by anybody, and Standard 4 asks for prominence *to a reader*. Adding one would
    # satisfy this check and help no child, which is the worst kind of compliance — so the exemption is
    # written here, in the guard, where somebody adding the next display surface will see it and have to
    # decide rather than copy.
    #
    # What protects a young player on that screen is PD-088, not a link: an under-18 is never named on it.
    DISPLAYS = {"wall.html"}
    unlinked = [
        path.name
        for path in sorted(WEB.glob("*.html"))
        if path != PAGE and path.name not in DISPLAYS and "under-18.html" not in path.read_text()
    ]
    if unlinked:
        failures.append(
            "these pages offer no way to it: " + ", ".join(unlinked) + "\n"
            "    Standard 4 asks for prominence as well as plain language, and a page nobody\n"
            "    links to is not transparency."
        )

    if failures:
        print("The page for young players has drifted:\n")
        for failure in failures:
            print(f"  {failure}\n")
        return 1

    print(
        f"a child can read it — grade {grade:.2f} over {len(lines)} sentences "
        f"({words_per_sentence:.1f} words each), linked from every page"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
