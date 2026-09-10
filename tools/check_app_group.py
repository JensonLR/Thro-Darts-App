#!/usr/bin/env python3
"""Hold the App Group identifier to one value across every file that names it.

The app writes a small projection of the journal into a shared container and its widget extension
reads it. Three files have to agree on the container's name: the Swift that opens it, and the two
entitlements files that grant access to it.

**A disagreement produces no error anywhere.** `containerURL(forSecurityApplicationGroupIdentifier:)`
returns nil for a group this process is not in, and every path in `ThroProjectionStore` treats nil as
*there is nothing to say* — which is exactly right for a build without the capability and exactly
wrong when the cause is a typo. The app would write nothing, the widget would read nothing, and both
would look like a phone with no match on it. Nothing crashes, nothing logs, and the feature is
simply absent.

So the value is checked here, mechanically, in under a second, on Linux — and the check also holds
that both targets carry an entitlements file at all, and that the project points at them. A widget
extension whose entitlement was silently dropped from the build settings reads nothing for the same
reason and looks the same way.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]

SWIFT = "packages/client-ios/Sources/ThroLiveKit/Projection.swift"
# who -> (entitlements file, the Info.plist that sits in the same target's build settings). The
# second half is how the check knows HOW MANY configurations that target has: one entitlement for a
# target with two configurations is a Debug build with the App Group and a Release build without it,
# which is a widget that works on the developer's phone and is empty on TestFlight. Found by
# deleting one of the two and watching this pass.
ENTITLEMENTS = {
    "the app": ("apps/ios/Support/ThroDarts.entitlements", "Support/Info.plist"),
    "the widget extension": ("apps/ios/SupportLive/ThroLive.entitlements", "SupportLive/Info.plist"),
}
PROJECT = "apps/ios/ThroDarts.xcodeproj/project.pbxproj"

IN_SWIFT = re.compile(r'groupId\s*=\s*"([^"]+)"')
# <key>com.apple.security.application-groups</key><array><string>…</string>
IN_PLIST = re.compile(
    r"<key>\s*com\.apple\.security\.application-groups\s*</key>\s*<array>(.*?)</array>", re.S)
STRINGS = re.compile(r"<string>([^<]+)</string>")


def main() -> int:
    problems = []
    found = {}

    swift = ROOT / SWIFT
    if not swift.exists():
        print(f"{SWIFT} is missing — the projection moved and this check did not follow it.",
              file=sys.stderr)
        return 1
    match = IN_SWIFT.search(swift.read_text())
    if not match:
        problems.append(f"{SWIFT} no longer declares a groupId this check can read")
    else:
        found["the Swift"] = match.group(1)

    for who, (relative, _) in ENTITLEMENTS.items():
        path = ROOT / relative
        if not path.exists():
            problems.append(f"{relative} is missing, so {who} is in no App Group and the "
                            f"projection is invisible to it")
            continue
        block = IN_PLIST.search(path.read_text())
        if not block:
            problems.append(f"{relative} grants no application-groups at all")
            continue
        groups = STRINGS.findall(block.group(1))
        if len(groups) != 1:
            problems.append(f"{relative} names {len(groups)} groups; exactly one is expected")
            continue
        found[who] = groups[0]

    # The project has to actually build with them. An entitlements file nothing points at is a file.
    project = ROOT / PROJECT
    if project.exists():
        text = project.read_text()
        for who, (relative, plist) in ENTITLEMENTS.items():
            leaf = relative.split("apps/ios/", 1)[1]
            configurations = text.count(f"INFOPLIST_FILE = {plist};")
            granted = text.count(f"CODE_SIGN_ENTITLEMENTS = {leaf};")
            # The one deliberate exception: the `Personal` configuration, for a free Apple team that
            # cannot sign an App Group at all. It points at a *.personal.entitlements file that names
            # no group, it is never Release, and there is exactly one of it per target.
            personal_leaf = leaf.replace(".entitlements", ".personal.entitlements")
            personal = text.count(f"CODE_SIGN_ENTITLEMENTS = {personal_leaf};")
            personal_file = ROOT / "apps/ios" / personal_leaf
            if personal and (not personal_file.exists() or "application-groups" in personal_file.read_text()):
                problems.append(f"{personal_leaf} must exist and grant no App Group; it is the free-team build")
            if personal > 1:
                problems.append(f"{personal_leaf} is set in {personal} configurations; the Personal build is one configuration")
            if configurations == 0:
                problems.append(f"the Xcode project has no build configuration using {plist}")
            elif granted == 0:
                problems.append(f"nothing in the Xcode project sets CODE_SIGN_ENTITLEMENTS = {leaf}, "
                                f"so {who} ships without it and reads an empty container")
            elif granted + personal < configurations:
                problems.append(
                    f"{leaf} is set in {granted} of {who}'s {configurations} build configurations "
                    f"(plus {personal} Personal). The one without it builds with no App Group — which, if it is "
                    f"Release, is a widget that works in development and is empty on TestFlight")
            release_block = text[text.find("/* Begin XCBuildConfiguration section */"):]
            for m in __import__("re").finditer(r"CODE_SIGN_ENTITLEMENTS = " + __import__("re").escape(personal_leaf) + r";.*?name = (\w+);", release_block, __import__("re").S):
                if m.group(1) != "Personal":
                    problems.append(f"{personal_leaf} is used by the {m.group(1)} configuration; only Personal may build without the group")
    else:
        problems.append(f"{PROJECT} is missing")

    distinct = set(found.values())
    for who in sorted(found):
        print(f"  {who:<24} {found[who]}")
    if len(distinct) > 1:
        problems.append("these are not the same group: " + ", ".join(sorted(distinct)))

    if problems:
        print("\nThe App Group does not hold together:", file=sys.stderr)
        for problem in problems:
            print(f"  - {problem}", file=sys.stderr)
        print("\nNothing would fail at runtime: the app would write nothing, the widget would read "
              "nothing, and both would look like a phone with no match on it.", file=sys.stderr)
        return 1
    print(f"\nok: one App Group, named the same in {len(found)} places, and both targets build "
          f"with their entitlements.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
