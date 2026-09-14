#!/usr/bin/env python3
"""The Android client reaches a network in one place, to ask one question (PD-097).

**What is being protected.** Until 14 September 2026 the Android client had no network code at all, and the defaults
audit (`docs/legal/DEFAULTS_AUDIT.md`, §8) leaned on that as a structural fact: scoring needs no network and no account
(PD-012), and nothing on the phone could send anything anywhere. PD-097 gave it one reach outward — reading the notice
about people's information from THRØ's public web site, anonymously — and that is exactly the kind of change after
which a second reach arrives unnoticed: a crash reporter, an analytics call, a "just this once" request with the device
id in it. The package graph can no longer say "no network"; this says "only the notice".

**What this refuses.**
  * A network API anywhere in the Android client or the app target except `Notice.kt`: `java.net`, `javax.net`,
    `URLConnection`, a socket, OkHttp, Ktor, Retrofit, Volley, `android.net.http`, a `WebView`, the download manager.
  * A cookie handler anywhere, because `HttpURLConnection` sends a cookie only through one.
  * In `Notice.kt`, anything that identifies the phone or the person: Android's device id, the hardware's model or
    serial, the journal's device id, accounts, an advertising id.
  * Any permission, in any manifest of either module — debug builds included — other than `android.permission.INTERNET`.

The list is about *names*, as `check_the_wall_never_signs_in.py`'s is: somebody adding a second network call reaches for
exactly these words, and a check that tried to reason about behaviour would be a compiler.
"""

from __future__ import annotations

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCES = [ROOT / "packages/client-android/src/main", ROOT / "apps/android/app/src"]
NOTICE = ROOT / "packages/client-android/src/main/kotlin/thro/client/Notice.kt"
# Every manifest, debug variants included: a permission a debug build asks for is still asked for.
MANIFEST_ROOTS = [ROOT / "packages/client-android/src", ROOT / "apps/android/app/src"]

NETWORK = {
    r"\bjava\.net\.": "java.net",
    r"\bjavax\.net\.": "javax.net, which is where TLS sockets live",
    r"\b(Http|Https)?URLConnection\b": "a URL connection",
    r"\b(Datagram|Server|SSL)?Socket\b": "a socket",
    r"\bokhttp3?\b": "OkHttp",
    r"\bio\.ktor\b": "Ktor",
    r"\bretrofit2?\b": "Retrofit",
    r"\bcom\.android\.volley\b": "Volley",
    r"\bandroid\.net\.http\b": "android.net.http",
    r"\bWebView\b": "a WebView",
    r"\bDownloadManager\b": "the download manager",
}
COOKIES = {r"\bCookieHandler\b": "a cookie handler", r"\bCookieManager\b": "a cookie manager"}
IDENTIFIERS = {
    r"\bANDROID_ID\b": "Android's device id",
    r"\bSettings\.Secure\b": "the secure settings, where the device id lives",
    r"\bBuild\.(MODEL|SERIAL|DEVICE|FINGERPRINT|ID|getSerial)\b": "the hardware's identity",
    r"(?i)device_?id": "a device id",
    r"\bAccountManager\b|\bgetAccounts\b": "the phone's accounts",
    r"(?i)advertising_?id": "an advertising id",
}
PERMISSION = re.compile(r'<uses-permission[^>]*android:name="([^"]+)"')


def code_lines(path: pathlib.Path) -> list[tuple[int, str]]:
    """Lines that are code, not comments: a rule described in a comment is not a rule broken."""
    out = []
    for number, line in enumerate(path.read_text().splitlines(), start=1):
        stripped = line.strip()
        if stripped.startswith(("//", "*", "/*")):
            continue
        out.append((number, line))
    return out


def hits(path: pathlib.Path, patterns: dict[str, str]) -> list[str]:
    found = []
    for number, line in code_lines(path):
        for pattern, name in patterns.items():
            if re.search(pattern, line):
                found.append(f"{path.relative_to(ROOT)}:{number}: {name} — {line.strip()[:100]}")
    return found


def built(path: pathlib.Path) -> bool:
    return any(part.startswith("build") for part in path.parts)


def main() -> int:
    problems: list[str] = []
    if not NOTICE.exists():
        problems.append(f"{NOTICE.relative_to(ROOT)} is gone, so this check no longer knows where the one network call is")

    for base in SOURCES:
        for path in sorted(base.rglob("*")):
            if path.suffix not in (".kt", ".java") or built(path):
                continue
            problems += hits(path, COOKIES)
            if path == NOTICE:
                problems += hits(path, IDENTIFIERS)
            else:
                problems += hits(path, NETWORK)

    manifests = sorted(p for base in MANIFEST_ROOTS for p in base.rglob("AndroidManifest.xml") if not built(p))
    if not manifests:
        problems.append("no AndroidManifest.xml found, so no permission was checked")
    for manifest in manifests:
        for permission in PERMISSION.findall(manifest.read_text()):
            if permission != "android.permission.INTERNET":
                problems.append(f"{manifest.relative_to(ROOT)}: asks for {permission}; the client needs nothing but "
                                "the network, and that only for the notice")

    if problems:
        print("The Android client reaches further than the notice (PD-097):\n")
        for problem in problems:
            print(f"  {problem}")
        return 1
    print(f"the Android client reaches a network only in Notice.kt, sends nothing that identifies anybody, "
          f"and asks for no permission but the internet ({len(manifests)} manifests)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
