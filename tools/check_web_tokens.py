#!/usr/bin/env python3
"""The web's copy of the tokens is the generated one, byte for byte.

`apps/web/tokens.css` is a copy rather than a link because a static host serves a directory and does
not follow one out of it. A copy drifts, so this fails the build the moment it does — the same bargain
`check_tokens_exist.py` makes for the app: the brand is generated in one place and consumed everywhere,
and nothing may quietly diverge from it.

Refresh with: cp packages/design-tokens/generated/tokens.css apps/web/tokens.css
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GENERATED = ROOT / "packages/design-tokens/generated/tokens.css"
WEB = ROOT / "apps/web/tokens.css"

def main() -> int:
    if not GENERATED.exists():
        print(f"  FAIL  {GENERATED.relative_to(ROOT)} is missing; run packages/design-tokens/build.py")
        return 1
    if not WEB.exists():
        print(f"  FAIL  {WEB.relative_to(ROOT)} is missing; copy the generated tokens into it")
        return 1
    if GENERATED.read_bytes() != WEB.read_bytes():
        print("  FAIL  apps/web/tokens.css has drifted from the generated tokens")
        print("        cp packages/design-tokens/generated/tokens.css apps/web/tokens.css")
        return 1
    print(f"check_web_tokens: the web's tokens are the generated ones ({len(WEB.read_text().splitlines())} lines)")
    return 0

if __name__ == "__main__":
    sys.exit(main())
