#!/usr/bin/env python3
"""The ten faces the design system asks for are the ten the bundle carries.

**Every failure here is silent and looks like a design decision.** A font that is not registered
does not raise: iOS falls back to the system face, every screen still draws, and the app simply
looks like every other app — which is the founder's *"no generic slop anywhere"* arriving as a
build problem rather than a design one. There are three ways in, and the app can only notice the
first:

  1. a file listed in `UIAppFonts` that is not in the target — nothing loads, and
     `ThroFont.customFacesRegistered` reports it at runtime;
  2. a file in the target that `UIAppFonts` does not list — it ships, unregistered, and only that
     weight is missing, which reads as a design choice rather than a fault;
  3. a file whose **PostScript name** is not the one the Swift asks for — the family registers, the
     weight resolves to something else, and nothing anywhere is wrong enough to say so.

The third is why this reads the font files themselves rather than trusting their filenames. A
`.ttf` carries its PostScript name in its `name` table, and that name — not the filename — is what
`UIFont(name:)` matches. Swap Archivo-Medium's bytes for Archivo-Bold's under the same filename and
every list, every plist entry and every test still agrees; the app just gets bolder.

`ThroFont.embeddedFaces` is the list the design system means, so it is the one the bundle is held
to. Its licence files are not fonts and are not counted — but their presence is checked, because a
font shipped without the OFL text it requires is a licence problem rather than a rendering one.
"""
from __future__ import annotations

import pathlib
import re
import struct
import sys
import plistlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
PLIST = ROOT / "apps/ios/Support/Info.plist"
FONTS = ROOT / "apps/ios/ThroDarts/Fonts"
# The Apple TV target carries the same ten faces from the same folder — a folder *reference* in the
# Xcode project rather than a second copy, so the bytes cannot drift. What differs is only the path
# inside the bundle: a folder reference keeps its directory where a synchronised group flattens it.
# Held here too, because the failure is the same one and is just as silent on a wall as on a phone.
TV_PLIST = ROOT / "apps/ios/SupportTV/Info.plist"
TV_PREFIX = "Fonts/"
TYPOGRAPHY = ROOT / "packages/client-ios/Sources/ThroDesign/Typography.swift"

# Keys whose absence takes a whole surface away without an error anywhere. Each is paired with what
# stops working, so a future reader deleting one has to argue with the consequence rather than the
# key.
REQUIRED_KEYS = {
    "NSSupportsLiveActivities": "the Lock Screen and Dynamic Island scoreboard; without it "
                                "`Activity.request` refuses and the match is scored with nothing "
                                "on the Lock Screen",
    "NSCalendarsWriteOnlyAccessUsageDescription": "adding a fixture to the player's calendar; "
                                                  "without it iOS terminates the app at the moment "
                                                  "it asks",
    "UIAppFonts": "both brand type faces on every screen",
}

POSTSCRIPT_NAME = 6


def postscript_name(path: pathlib.Path) -> str | None:
    """The name `UIFont(name:)` matches, read out of the file's own `name` table."""
    data = path.read_bytes()
    if len(data) < 12:
        return None
    tables = struct.unpack(">H", data[4:6])[0]
    for index in range(tables):
        entry = 12 + index * 16
        if entry + 16 > len(data):
            return None
        tag, _, offset, _ = struct.unpack(">4sIII", data[entry:entry + 16])
        if tag != b"name":
            continue
        if offset + 6 > len(data):
            return None
        count, strings = struct.unpack(">HH", data[offset + 2:offset + 6])
        found = None
        for record in range(count):
            at = offset + 6 + record * 12
            if at + 12 > len(data):
                break
            platform, encoding, _, name_id, length, string_at = struct.unpack(
                ">HHHHHH", data[at:at + 12])
            if name_id != POSTSCRIPT_NAME:
                continue
            start = offset + strings + string_at
            raw = data[start:start + length]
            try:
                if platform == 3 or (platform == 0):
                    value = raw.decode("utf-16-be")
                else:
                    value = raw.decode("mac-roman" if encoding == 0 else "latin-1")
            except (UnicodeDecodeError, LookupError):
                continue
            # A Windows record is preferred where both exist; either is better than none.
            if platform == 3 or found is None:
                found = value.strip("\x00").strip()
        return found
    return None


def main() -> int:
    for path in (PLIST, FONTS, TYPOGRAPHY):
        if not path.exists():
            sys.exit(f"check_bundle_faces: {path} is not there")

    plist = plistlib.loads(PLIST.read_bytes())
    problems = []

    for key, what in REQUIRED_KEYS.items():
        if key not in plist:
            problems.append(f"{key} is missing from Info.plist, which takes away {what}.")

    listed = plist.get("UIAppFonts", [])
    on_disk = sorted(p.name for p in FONTS.glob("*.ttf"))

    for name in listed:
        if not (FONTS / name).is_file():
            problems.append(f"UIAppFonts lists {name} and there is no such file in "
                            f"{FONTS.relative_to(ROOT)}. Nothing registers, and every screen "
                            f"falls back to the system face.")
    for name in on_disk:
        if name not in listed:
            problems.append(f"{name} is in the target and UIAppFonts does not list it, so it "
                            f"ships unregistered. Only that weight goes missing, which reads as a "
                            f"design choice rather than a fault.")

    # The Apple TV, against the same folder and the same ten names.
    if not TV_PLIST.exists():
        problems.append(f"{TV_PLIST.relative_to(ROOT)} is missing, so the venue screen has no Info.plist")
    else:
        tv = plistlib.loads(TV_PLIST.read_bytes())
        tv_listed = tv.get("UIAppFonts", [])
        if not tv_listed:
            problems.append("the Apple TV target lists no UIAppFonts, so the biggest screen the brand "
                            "gets draws in the system face — silently, and looking like a decision.")
        for name in tv_listed:
            if not name.startswith(TV_PREFIX):
                problems.append(f"the Apple TV's UIAppFonts lists {name}; a folder reference keeps its "
                                f"directory, so every entry there needs the {TV_PREFIX} prefix or "
                                f"nothing registers.")
            elif not (FONTS / name[len(TV_PREFIX):]).is_file():
                problems.append(f"the Apple TV's UIAppFonts lists {name} and there is no such file in "
                                f"{FONTS.relative_to(ROOT)}.")
        for name in on_disk:
            if TV_PREFIX + name not in tv_listed:
                problems.append(f"{name} is in the shared folder and the Apple TV's UIAppFonts does not "
                                f"list it, so that weight ships unregistered on the wall.")

    # The list the design system actually asks for, read from its own source.
    swift = TYPOGRAPHY.read_text()
    block = re.search(r"embeddedFaces:\s*\[String\]\s*=\s*\[(.*?)\]", swift, re.S)
    if not block:
        sys.exit("check_bundle_faces: ThroFont.embeddedFaces could not be read, so this check has "
                 "nothing to hold the bundle to")
    wanted = re.findall(r'"([^"]+)"', block.group(1))
    if not wanted:
        sys.exit("check_bundle_faces: ThroFont.embeddedFaces is empty")

    present = {}
    for name in on_disk:
        found = postscript_name(FONTS / name)
        if found is None:
            problems.append(f"{name} has no readable PostScript name, so nothing can say which "
                            f"face it actually is.")
            continue
        present[found] = name

    for face in wanted:
        if face not in present:
            problems.append(
                f'ThroFont.embeddedFaces asks for "{face}" and no file in '
                f"{FONTS.relative_to(ROOT)} carries that PostScript name. It is the name — not the "
                f"filename — that UIFont matches, so this weight resolves to something else and "
                f"nothing reports it. Names present: {sorted(present)}"
            )
    for face, name in sorted(present.items()):
        if face not in wanted:
            problems.append(f'{name} carries the PostScript name "{face}", which the design '
                            f"system never asks for. Either it is the wrong file or the list is.")

    for licence in ("OFL-Archivo.txt", "OFL-IBMPlex.txt"):
        if not (FONTS / licence).is_file():
            problems.append(f"{licence} is not beside the fonts. Both families are shipped under "
                            f"the SIL Open Font Licence, which requires its text to travel with "
                            f"them.")

    if problems:
        print("The app bundle and the design system disagree about the type:")
        for problem in problems:
            print(f"  - {problem}")
        return 1

    print(f"check_bundle_faces: {len(wanted)} faces asked for, {len(present)} in the target, "
          f"names matched from the font files themselves; {len(REQUIRED_KEYS)} keys present")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
