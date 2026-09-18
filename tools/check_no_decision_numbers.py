#!/usr/bin/env python3
"""No decision number ever reaches a person reading THRØ.

**This exists because of a defect found twice on one morning.** `apps/web/thro.js` printed
"(PD-103)" to a moderator in the sentence explaining what a decision does, and the app's readiness
screen printed "(PD-127)" in the sentence about links. Both were written as citations — the habit of
a codebase where every sentence has a decision behind it — and both were rendered verbatim to a
person who has never heard of the ledger.

The rule is the founder's and is absolute: a decision number is how *we* refer to a decision, never
how THRØ speaks. Comments, doc comments and documentation are exactly where they belong and are not
touched here; only what is rendered is checked.

What is scanned:

  * Swift string literals under `packages/client-ios/Sources` — comments stripped first, so
    `/// … (PD-126)` above a function is fine and `"… (PD-126)"` inside it is not.
  * JavaScript string literals under `apps/web` — same rule.
  * The text of every `apps/web/*.html` page, with comments and `<script>` blocks removed.

What it does not prove: that a sentence is reachable, or that a number reaches a person by some
other route (a server message, a log shown in an interface). It catches the shape that was found.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SWIFT = ROOT / "packages/client-ios/Sources"
WEB = ROOT / "apps/web"
DECISION = re.compile(r"\bPD-\d{2,4}\b")
# ADR and OD are the same habit under different names, and would read the same way to a player.
OTHER = re.compile(r"\b(?:ADR|OD)-\d{2,4}\b")


def literals(source: str, quotes: str = '"'):
    """Every string literal in `source`, with comments removed. Line numbers kept.

    `quotes` is the set of characters that open a literal: Swift has only `"`, JavaScript has
    `\'`, `"` and the backtick — and the leak that prompted this check was in a single-quoted one,
    so a scanner that reads only double quotes would have passed it.
    """
    out, line, i, n = [], 1, 0, len(source)
    in_block = False
    while i < n:
        c = source[i]
        if c == "\n":
            line += 1; i += 1; continue
        if in_block:
            if source.startswith("*/", i):
                in_block = False; i += 2
            else:
                i += 1
            continue
        if source.startswith("/*", i):
            in_block = True; i += 2; continue
        if source.startswith("//", i):
            while i < n and source[i] != "\n":
                i += 1
            continue
        if c in quotes:
            # A Swift multi-line literal ("\u0022\u0022\u0022…") is still a literal; treat it as one run.
            triple = source.startswith(c * 3, i)
            i += 3 if triple else 1
            start_line, buf = line, []
            while i < n:
                if source[i] == "\\":
                    buf.append(source[i:i + 2]); i += 2; continue
                if triple and source.startswith(c * 3, i):
                    i += 3; break
                if not triple and source[i] == c:
                    i += 1; break
                if source[i] == "\n":
                    line += 1
                buf.append(source[i]); i += 1
            out.append((start_line, "".join(buf)))
            continue
        i += 1
    return out


def scan_code(paths, label, bad, quotes='"'):
    seen = 0
    for path in paths:
        seen += 1
        for line, text in literals(path.read_text(), quotes):
            for pattern, what in ((DECISION, "a decision number"), (OTHER, "a record number")):
                if pattern.search(text):
                    bad.append((path.relative_to(ROOT), line, what, text.strip()[:110]))
    if not seen:
        sys.exit(f"check_no_decision_numbers: no {label} found — the tree moved and this check stopped checking")
    return seen


def scan_html(bad):
    pages = sorted(WEB.glob("*.html"))
    if not pages:
        sys.exit("check_no_decision_numbers: no apps/web/*.html — the tree moved and this check stopped checking")
    for path in pages:
        text = re.sub(r"<!--.*?-->", "", path.read_text(), flags=re.S)
        text = re.sub(r"<script\b.*?</script>", "", text, flags=re.S | re.I)
        # A page's own CSS is code, not something a person reads; its comments cite decisions freely.
        text = re.sub(r"<style\b.*?</style>", "", text, flags=re.S | re.I)
        for i, line in enumerate(text.splitlines(), 1):
            for pattern, what in ((DECISION, "a decision number"), (OTHER, "a record number")):
                if pattern.search(line):
                    bad.append((path.relative_to(ROOT), i, what, line.strip()[:110]))
    return len(pages)


def main() -> int:
    if not SWIFT.is_dir():
        sys.exit(f"check_no_decision_numbers: {SWIFT} is not a directory")
    bad: list = []
    swift = scan_code(sorted(SWIFT.rglob("*.swift")), "Swift sources", bad)
    # Single quotes and backticks as well: the leak this check was written for was single-quoted.
    js = scan_code(sorted(WEB.glob("*.js")), "apps/web scripts", bad, quotes="\"'`")
    html = scan_html(bad)
    if bad:
        print("check_no_decision_numbers: a decision number is rendered to a person.\n")
        for path, line, what, text in bad:
            print(f"  {path}:{line} — {what} in something a person reads")
            print(f"    {text}")
        print("\nSay what the sentence means instead. The number belongs in the comment, not on the screen.")
        return 1
    print(f"check_no_decision_numbers: {swift} Swift files, {js} scripts and {html} pages say no decision number.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
