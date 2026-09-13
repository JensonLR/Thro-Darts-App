#!/usr/bin/env python3
"""The notice file is one the app and the pages can read, and a live notice speaks to everybody it is for (PD-094).

`apps/web/notice.json` is the one file somebody edits, under pressure, on the day THRØ has to tell people that
something went wrong with their information (UK GDPR Art 34). The app and the pages show **nothing** for a file
they cannot read. That is the right failure for a reader and the wrong one for whoever is publishing: a missing
comma would publish silence, and from the outside silence looks exactly like there being nothing to say. So the
file is held here on every push:

1. It parses, says `"format": 1`, and says `"active"` as true or false.
2. A live notice has an id, a published time, and a title, a summary and a body both for adults and for
   under-18s. Without the second, a child is sent to a page with nothing on it.
3. The under-18 words read at the level `under-18.html` is held to, measured the same way.
4. Both pages read the file, and the front page mounts the card.

Run:  python3 tools/check_notice.py                    the committed file
      python3 tools/check_notice.py draft.json         a draft, before it is pushed
"""

from __future__ import annotations

import datetime as dt
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))

import check_a_child_can_read_it as child  # noqa: E402  (path set above)

WEB = ROOT / "apps/web"
MOUNTS = {
    "notice.html": "THRO.mountNotice(document.getElementById('notice'), 'adult')",
    "notice-under-18.html": "THRO.mountNotice(document.getElementById('notice'), 'under18')",
    "index.html": "THRO.mountNoticeBanner(document.getElementById('notice'))",
}


def words(value: object) -> bool:
    return isinstance(value, str) and value.strip() != ""


def paragraphs(value: object) -> bool:
    return isinstance(value, list) and len(value) > 0 and all(words(v) for v in value)


def part(value: object, who: str) -> list[str]:
    """What is missing from one reader's words: a title, a summary and a body of paragraphs."""
    if not isinstance(value, dict):
        return [f"{who}: needs a title, a summary and a body"]
    found = [f"{who}: {key} is missing or empty" for key in ("title", "summary") if not words(value.get(key))]
    if not paragraphs(value.get("body")):
        found.append(f"{who}: body must be a list of paragraphs, none of them empty")
    return found


def young_reader(value: dict) -> list[str]:
    """The under-18 words, measured as `under-18.html` is."""
    text = " ".join([value["title"].rstrip(".") + ".", value["summary"], *value["body"]])
    measured = child.reading(text)
    if measured is None:
        return ["under18: there are no sentences to read"]
    grade, lines, _, _ = measured
    found = []
    if grade > child.GRADE_CEILING:
        found.append(f"under18: the words read at grade {grade:.2f}, over the {child.GRADE_CEILING:.0f} ceiling — "
                     "shorter sentences and shorter words")
    for sentence in lines:
        length = len(re.findall(r"[A-Za-z'’]+", sentence))
        if length > child.LONGEST_SENTENCE:
            found.append(f"under18: a {length}-word sentence — split it: “{sentence[:120]}…”")
    return found


def main() -> int:
    notice_path = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else WEB / "notice.json"
    problems: list[str] = []
    notice: object = None
    try:
        notice = json.loads(notice_path.read_text())
    except FileNotFoundError:
        problems.append(f"{notice_path} is missing. The path must exist, so that publishing is an edit and not a "
                        "new file somebody has to remember the name of.")
    except json.JSONDecodeError as e:
        problems.append(f"{notice_path} does not parse ({e}). The app and the pages would show nothing at all.")

    live = False
    if isinstance(notice, dict):
        if notice.get("format") != 1:
            problems.append('"format" must be 1 — a format this build does not know shows nothing')
        if not isinstance(notice.get("active"), bool):
            problems.append('"active" must be true or false')
        live = notice.get("active") is True
        if live:
            if not words(notice.get("id")):
                problems.append('a live notice needs an "id"; a new id is what brings a put-away notice back')
            published = notice.get("published")
            try:
                # A date AND a time with its zone. Python and a browser would each take a bare date and read it
                # differently, and the app's parser takes neither — so the one form all three agree on is required.
                moment = dt.datetime.fromisoformat(str(published).replace("Z", "+00:00"))
                if "T" not in str(published) or moment.tzinfo is None:
                    raise ValueError
            except ValueError:
                problems.append(f'a live notice needs "published" as a date, a time and a zone, like '
                                f'"2026-10-01T09:00:00Z" — not {published!r}')
            problems += part(notice, "the notice")
            young = notice.get("under18")
            missing = part(young, "under18")
            problems += missing if missing else young_reader(young)
    elif notice is not None:
        problems.append("the notice must be a JSON object")

    for page, mount in MOUNTS.items():
        path = WEB / page
        if not path.exists():
            problems.append(f"apps/web/{page} is missing")
        elif mount not in path.read_text():
            problems.append(f"apps/web/{page} does not read the notice: it should call {mount}")

    if problems:
        print("The notice would not reach the people it is for:\n")
        for problem in problems:
            print(f"  {problem}\n")
        return 1
    state = "a live notice, with words for adults and for under-18s" if live else "no notice live"
    print(f"the notice holds — {state}; both notice pages and the front page read it")
    return 0


if __name__ == "__main__":
    sys.exit(main())
