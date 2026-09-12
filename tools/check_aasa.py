#!/usr/bin/env python3
"""Hold the association file to the paths the app can actually read.

A universal link that iOS accepts and the app cannot parse is the worst shape this feature has: the
phone leaves Safari, opens THRØ, and THRØ does nothing — which looks exactly like the app being
broken, on a link somebody shared. `ThroRoute(url:)` refuses an unknown path rather than guessing,
deliberately, so the refusal is silent by design and the mismatch has to be caught here.

So this reads both halves and holds them together:

  - **every path advertised** in `apple-app-site-association` must be one `ThroRoute`'s parser has a
    case for, and
  - **every head the parser accepts** must be advertised, or a link the app could handle is one the
    system will not deliver.

It also holds the file's own shape, because every one of these is a silent failure that Apple's CDN
will not tell anybody about: it must be valid JSON, it must have **no extension**, the app ID must
be `<Team ID>.<bundle id>` with the team and bundle this project actually builds, and there must be
no redirect-shaped nonsense in the components.

The Team ID is a public identifier — it appears in every provisioning profile — and is not a secret.
"""
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
AASA = ROOT / "services/links/.well-known/apple-app-site-association"
ROUTING = ROOT / "packages/client-ios/Sources/ThroApp/Routing.swift"
PROJECT = ROOT / "apps/ios/ThroDarts.xcodeproj/project.pbxproj"

# The heads `ThroRoute.init(url:)` switches on. Anchored on the tuple rather than on `case`,
# because a case may carry two patterns — `case ("m", let id?), ("match", let id?):` — and matching
# only the one after `case` saw the short form and not the alias. It reported `/match/*` as
# advertised-but-unreadable when the parser reads it perfectly well: the check was wrong, not the
# file, which is the failure mode a check has to be perturbed to find.
HEADS = re.compile(r'\(\s*"([a-z]+)"\s*,')
BODY = re.compile(r"public init\?\(url: URL\)\s*\{(.*?)\n    \}", re.S)
TEAM = re.compile(r"DEVELOPMENT_TEAM = (\w+);")
BUNDLE = re.compile(r"PRODUCT_BUNDLE_IDENTIFIER = ([\w.]+);")


def main() -> int:
    problems = []

    if AASA.suffix:
        problems.append(f"{AASA.name} has an extension. Apple fetches this path exactly; a "
                        f"`.json` on the end is a 404 and universal links silently never work.")

    try:
        document = json.loads(AASA.read_text())
    except FileNotFoundError:
        print(f"{AASA} is missing.", file=sys.stderr)
        return 1
    except json.JSONDecodeError as error:
        print(f"{AASA.name} is not valid JSON: {error}", file=sys.stderr)
        return 1

    details = document.get("applinks", {}).get("details", [])
    if len(details) != 1:
        print(f"expected exactly one details entry, found {len(details)}", file=sys.stderr)
        return 1
    detail = details[0]

    # The app ID is the team and the bundle this project actually builds, not a remembered pair.
    project = PROJECT.read_text()
    teams = set(TEAM.findall(project))
    bundles = set(BUNDLE.findall(project))
    # The APP's bundle, not the extension's. An extension's identifier is always the app's plus a
    # suffix, so the shortest is the app — and the rest are held to that rather than assumed, since
    # an extension whose identifier is not under the app's does not install at all.
    app_bundle = min(bundles, key=len) if bundles else ""
    for other in sorted(bundles - {app_bundle}):
        if not other.startswith(app_bundle + "."):
            problems.append(f"{other} is not under the app's identifier {app_bundle}; an extension "
                            f"whose identifier is not a suffix of its app's does not install")
    expected = {f"{team}.{app_bundle}" for team in teams} if app_bundle else set()
    advertised = set(detail.get("appIDs", []))
    if not expected:
        problems.append("the Xcode project names no team or bundle identifier this could check")
    elif advertised != expected:
        problems.append(f"appIDs is {sorted(advertised)}; the project builds {sorted(expected)}")

    # Every advertised path, and every head the parser has a case for.
    paths = [c.get("/", "") for c in detail.get("components", [])]
    if any(not p.startswith("/") for p in paths):
        problems.append(f"every component must be a path: {[p for p in paths if not p.startswith('/')]}")
    advertised_heads = {p.strip("/").split("/")[0] for p in paths if p.startswith("/")}

    body = BODY.search(ROUTING.read_text())
    parsed_heads = set(HEADS.findall(body.group(1))) if body else set()
    if not parsed_heads:
        problems.append(f"{ROUTING.name} no longer declares path cases this check can read")

    unreadable = advertised_heads - parsed_heads
    unadvertised = parsed_heads - advertised_heads
    if unreadable:
        problems.append(f"advertised but unreadable: {sorted(unreadable)} — iOS would open THRØ on "
                        f"these links and THRØ would do nothing, which looks like the app is broken")
    if unadvertised:
        problems.append(f"readable but unadvertised: {sorted(unadvertised)} — the app could handle "
                        f"these and the system would send them to Safari instead")

    print(f"{len(paths)} paths advertised, {len(parsed_heads)} heads the parser reads, "
          f"appIDs {sorted(advertised)}")

    if problems:
        print("\nThe association file and the app do not agree:", file=sys.stderr)
        for problem in problems:
            print(f"  - {problem}", file=sys.stderr)
        return 1
    print("ok: every advertised path is one this build can read, and every one it can read is "
          "advertised.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
