#!/usr/bin/env python3
"""The pub wall never signs in, and that has to be a guard rather than a comment.

**What is being protected.** `ThroVenueKit` is the whole of the Apple TV app. A television in a pub
is the most exposed screen THRØ has: nobody owns it, nobody signs out of it, and whoever picks up
the remote is the operator. The thing that makes it safe is not a rule about what it draws — it is
that **it holds no credential**, so the only routes it can read are the unauthenticated ones, and
those name teams and venues and never a person (`Api.kt`, `authenticated = false`).

That is a structural guarantee and it is worth exactly as much as it is hard to break. Today it is
written in a comment at the top of `Wall.swift`. One `import` and one line of well-meaning code —
*"the wall could show the live leg if it just had a token"* — would remove it, the comment would
still be sitting there saying otherwise, and no test would fail. The Children's-code Standard 7
audit (`docs/legal/DEFAULTS_AUDIT.md`) leans on this property, so it needs to hold by itself.

**What this refuses.** Any mention in `ThroVenueKit` of the session store, a bearer token, the
keychain, or an authenticated endpoint id. The list is deliberately about *names*, not about
behaviour: a check that tried to reason about behaviour would be a type-checker, and a check that
can be defeated by renaming a symbol still catches the change that matters, because somebody adding
sign-in to a pub television reaches for exactly these words.

**And the live board.** `stream.match` is authenticated and stays that way until somebody decides
whether an under-18 fixture may be named on a pub wall (`docs/legal/DEFAULTS_AUDIT.md`, the open
decision). A room that wants it today AirPlays the phone, where a person is present and responsible.
"""

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
WALL = ROOT / "packages/client-ios/Sources/ThroVenueKit"

# What a credential is called in this codebase. Each is the name somebody would actually reach for.
FORBIDDEN = {
    "SessionStore": "the store that holds a signed-in session",
    "ThroSession": "a signed-in session",
    "Keychain": "the keychain, which is where a credential lives",
    "accessToken": "an access token",
    "refreshToken": "a refresh token",
    "Authorization": "the header a bearer token travels in",
    "Bearer": "a bearer token",
    "signIn": "signing in",
    "stream.match": "the authenticated live-match stream",
    "streamMatch": "the authenticated live-match stream",
}

# A comment may say these words — saying why the wall does not sign in requires naming the thing it
# does not do. Only code is checked, so the file's own explanation is not its own failure.
COMMENT = re.compile(r"^\s*(//|/\*|\*)")


def main() -> int:
    if not WALL.is_dir():
        print(f"no {WALL.relative_to(ROOT)} — has the Apple TV app moved?")
        return 1

    complaints = []
    for path in sorted(WALL.rglob("*.swift")):
        for number, line in enumerate(path.read_text().splitlines(), start=1):
            if COMMENT.match(line):
                continue
            code = line.split("//", 1)[0]
            for word, what in FORBIDDEN.items():
                if word in code:
                    complaints.append(
                        f"{path.relative_to(ROOT)}:{number} names {word} — {what}.\n"
                        f"    The pub wall must hold no credential: whoever picks up the remote is the\n"
                        f"    operator, and a television that can sign in can be pointed at a person."
                    )

    if complaints:
        print("The wall has learned to sign in:\n")
        for complaint in complaints:
            print(f"  {complaint}\n")
        return 1

    files = len(list(WALL.rglob("*.swift")))
    print(f"the wall never signs in — {files} files in ThroVenueKit hold no credential")
    return 0


if __name__ == "__main__":
    sys.exit(main())
