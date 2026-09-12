#!/usr/bin/env python3
"""Hold every place that names THRØ's public host to one arrangement — and switch them together.

**Buying the domain is meant to be the switch that turns the product public**, not a scavenger hunt
through four files. Three of them name a host, and they do not all name the *same* host once a real
domain exists, which is the trap this exists to close:

  - `render.yaml`            THRO_RP_ID — the relying party a passkey is bound to
  - `Info.plist`             THROAPIBaseURL — the host the app sends requests to
  - `ThroDarts.entitlements` webcredentials: — the domain the phone fetches the association file from

Before a domain there is one host and all three carry it. After a domain there are two, because a
registrable domain may serve its API from a subdomain: the app talks to `api.thro.uk` while the
relying party stays `thro.uk`, and WebAuthn permits that precisely because an RP ID may be a
registrable-domain suffix of the calling origin. On `onrender.com` it cannot — that name is on the
Public Suffix List, so two Render subdomains are two different registrable domains and cannot share
a passkey. That single fact is why web sign-in waits for the domain (PD-058).

So a plain find-and-replace across the repo is wrong: it would point the relying party at
`api.thro.uk` and quietly break every passkey. This script encodes the two legal arrangements.

    python3 tools/host.py                 check the repo is in one of them
    python3 tools/host.py --set thro.uk   move it to the domain arrangement
    python3 tools/host.py --set-free      move it back to the free-subdomain one

The rewrite destinations in `render.yaml` are deliberately NOT touched. They address the API
*service*, not the public name, and they stay on its own hostname whatever the front door is called.
"""
from __future__ import annotations

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
RENDER = ROOT / "render.yaml"
PLIST = ROOT / "apps/ios/Support/Info.plist"
ENTS = ROOT / "apps/ios/Support/ThroDarts.entitlements"

# The API service's own Render hostname. This is the free-tier public host AND, after a domain, the
# rewrite target that never changes — the API keeps answering on it either way.
API_SERVICE_HOST = "thro-api-staging.onrender.com"

RP_ID = re.compile(r"(- key: THRO_RP_ID\n\s+value: )(\S+)")
RP_ORIGINS = re.compile(r"(- key: THRO_RP_ORIGINS\n\s+value: )(\S+)")
BASE_URL = re.compile(r"(<key>THROAPIBaseURL</key>\s*\n\s*<string>)([^<]+)(</string>)")
WEBCRED = re.compile(r"(<string>webcredentials:)([^<]+)(</string>)")


def arrangement(domain: str | None) -> dict[str, str]:
    """The four values, for a domain or for the free subdomain.

    With a domain the app is given its own subdomain rather than being routed through the static
    site's rewrite: a CDN in front of `text/event-stream` is how a live match stream dies, and
    there is no reason to accept that hop once the names are ours to arrange (ADR-007).
    """
    if domain is None:
        return {
            "rp_id": API_SERVICE_HOST,
            "rp_origins": f"https://{API_SERVICE_HOST}",
            "base_url": f"https://{API_SERVICE_HOST}",
            "webcredentials": API_SERVICE_HOST,
        }
    return {
        "rp_id": domain,
        "rp_origins": f"https://{domain},https://api.{domain}",
        "base_url": f"https://api.{domain}",
        "webcredentials": domain,
    }


def read() -> dict[str, str | None]:
    render, plist, ents = RENDER.read_text(), PLIST.read_text(), ENTS.read_text()
    rp, origins = RP_ID.search(render), RP_ORIGINS.search(render)
    base, cred = BASE_URL.search(plist), WEBCRED.search(ents)
    return {
        "rp_id": rp.group(2) if rp else None,
        "rp_origins": origins.group(2) if origins else None,
        "base_url": base.group(2) if base else None,
        "webcredentials": cred.group(2) if cred else None,
    }


def guess_domain(found: dict[str, str | None]) -> str | None:
    """Which arrangement the repo is trying to be in, read from the relying party."""
    rp = found["rp_id"]
    return None if rp is None or rp == API_SERVICE_HOST else rp


def check() -> int:
    found = read()
    missing = [k for k, v in found.items() if v is None and k != "rp_origins"]
    if missing:
        for k in missing:
            print(f"FAIL host: {k} is not where this script looks for it; the file's shape changed")
        return 1

    domain = guess_domain(found)
    want = arrangement(domain)
    where = "the domain arrangement" if domain else "the free-subdomain arrangement"

    problems = []
    if domain and domain.startswith("api."):
        print("FAIL host: THRO_RP_ID is " + domain + ", which is the API's subdomain, not the relying party.")
        print("  A passkey is bound to its RP ID. Binding them to api." + domain[4:] + " means a credential")
        print("  created on the website cannot be used by the app, and the reverse — the one arrangement")
        print("  owning a domain exists to avoid.")
        print("  fix: python3 tools/host.py --set " + domain[4:])
        return 1

    for key in ("rp_id", "base_url", "webcredentials"):
        if found[key] != want[key]:
            problems.append(f"  {key}: found {found[key]!r}, {where} wants {want[key]!r}")
    # Origins may be absent on the free tier, where the code defaults to https://<rp id>. With a
    # domain it must be present and must list both, or the app's own subdomain is refused.
    if domain and found["rp_origins"] != want["rp_origins"]:
        problems.append(f"  rp_origins: found {found['rp_origins']!r}, wants {want['rp_origins']!r}")

    # The rewrites address the API service and must not have been dragged along by a replace-all.
    render = RENDER.read_text()
    for line in render.splitlines():
        if "destination:" in line and API_SERVICE_HOST not in line:
            problems.append(f"  a rewrite no longer addresses the API service: {line.strip()}")

    if problems:
        print(f"FAIL host: the repo is in {where}, and these disagree with it:")
        print("\n".join(problems))
        print("  fix: python3 tools/host.py --set <domain>   (or --set-free)")
        return 1
    print(f"OK host: {where}, and all three places agree ({found['rp_id']}).")
    return 0


def apply(domain: str | None) -> int:
    want = arrangement(domain)
    render, plist, ents = RENDER.read_text(), PLIST.read_text(), ENTS.read_text()

    render = RP_ID.sub(lambda m: m.group(1) + want["rp_id"], render, count=1)
    if domain is None:
        # On the free subdomain the code's own default is https://<rp id>, which is exactly right,
        # so the line is removed rather than restated. A round trip is then the identity.
        render = re.sub(r"\n\s+- key: THRO_RP_ORIGINS\n\s+value: \S+", "", render, count=1)
    elif RP_ORIGINS.search(render):
        render = RP_ORIGINS.sub(lambda m: m.group(1) + want["rp_origins"], render, count=1)
    else:
        # Seat it directly after the relying party, which is the only place it means anything.
        render = RP_ID.sub(
            lambda m: m.group(1) + want["rp_id"] + f"\n      - key: THRO_RP_ORIGINS\n        value: {want['rp_origins']}",
            render, count=1)
    plist = BASE_URL.sub(lambda m: m.group(1) + want["base_url"] + m.group(3), plist, count=1)
    ents = WEBCRED.sub(lambda m: m.group(1) + want["webcredentials"] + m.group(3), ents, count=1)

    RENDER.write_text(render); PLIST.write_text(plist); ENTS.write_text(ents)

    print(f"host: set to {'the domain ' + domain if domain else 'the free subdomain'}")
    for k in ("rp_id", "rp_origins", "base_url", "webcredentials"):
        print(f"  {k} = {want[k]}")
    if domain:
        print()
        print("  Still yours to do, in Render's dashboard and your registrar:")
        print(f"    1. Add {domain} (and www) as a custom domain on thro-web.")
        print(f"    2. Add api.{domain} as a custom domain on the API service.")
        print("    3. Point the DNS as Render instructs — A records only. Render is IPv4-only,")
        print("       so delete any AAAA record or the site answers intermittently.")
        print("    4. Set THRO_RP_ID and THRO_RP_ORIGINS on the API service to the values above.")
        print("    5. Rebuild and ship the app.")
        print()
        print("  And tell your testers: a passkey is bound to its relying party, so every passkey")
        print("  registered under the old host stops working. Sign in with Apple is not domain-bound")
        print("  and survives the move, which is why testers should use it.")
    return 0


def main() -> int:
    args = sys.argv[1:]
    if not args:
        return check()
    if args[0] == "--set-free":
        return apply(None)
    if args[0] == "--set" and len(args) == 2:
        domain = args[1].strip().lower().removeprefix("https://").removeprefix("http://").rstrip("/")
        if domain.startswith("www."):
            print("FAIL host: name the registrable domain, not www — the relying party is thro.uk, not www.thro.uk")
            return 1
        if "." not in domain or domain.endswith(".onrender.com"):
            print("FAIL host: that is not a registrable domain THRØ can be a relying party for.")
            print("  onrender.com is on the Public Suffix List, so two Render subdomains cannot share a passkey.")
            return 1
        return apply(domain)
    print(__doc__)
    return 1


if __name__ == "__main__":
    sys.exit(main())
