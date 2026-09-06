#!/usr/bin/env python3
"""The embedded fonts, their licences and the brand assets agree with the code (PD-006).

Checks, and fails on the first that does not hold:
  - every file under UIAppFonts in Support/Info.plist exists in ThroDarts/Fonts, and every .ttf there is listed;
  - each face's PostScript name (name table ID 6) is in ThroFont.embeddedFaces, and vice versa;
  - each face's family (name ID 16, else 1) is one of the two families the type layer asks the system for;
  - each family's SIL Open Font License text is beside the files;
  - the launch screen's colour and image sets exist in the asset catalogue, and the icon is 1024 x 1024 RGB.
Run from anywhere: python3 apps/ios/check_fonts.py
"""
import plistlib, pathlib, re, struct, sys

ROOT = pathlib.Path(__file__).resolve().parent
REPO = ROOT.parent.parent
FONTS = ROOT / "ThroDarts" / "Fonts"
ASSETS = ROOT / "ThroDarts" / "Assets.xcassets"
SWIFT = REPO / "packages/client-ios/Sources/ThroDesign/Typography.swift"
failures = []

def fail(msg):
    failures.append(msg); print("FAIL:", msg)

def names(path):
    d = path.read_bytes()
    num = struct.unpack(">H", d[4:6])[0]
    tables = {}
    for i in range(num):
        off = 12 + 16 * i
        tables[d[off:off + 4].decode("latin1")] = struct.unpack(">II", d[off + 8:off + 16])
    toff, _ = tables["name"]
    _, count, str_off = struct.unpack(">HHH", d[toff:toff + 6])
    out = {}
    for i in range(count):
        r = toff + 6 + 12 * i
        pid, eid, lid, nid, ln, so = struct.unpack(">HHHHHH", d[r:r + 12])
        if pid == 3 and lid == 0x409:
            out[nid] = d[toff + str_off + so:toff + str_off + so + ln].decode("utf-16-be")
    return out

plist = plistlib.loads((ROOT / "Support" / "Info.plist").read_bytes())
listed = plist.get("UIAppFonts", [])
present = sorted(p.name for p in FONTS.glob("*.ttf"))
for f in listed:
    if not (FONTS / f).exists(): fail(f"UIAppFonts lists {f}, which is not in {FONTS.relative_to(REPO)}")
for f in present:
    if f not in listed: fail(f"{f} is in the Fonts folder but not under UIAppFonts, so it would ship unregistered")

swift = SWIFT.read_text()
m = re.search(r"embeddedFaces: \[String\] = \[(.*?)\]", swift, re.S)
swift_faces = set(re.findall(r'"([^"]+)"', m.group(1))) if m else set()
families = {re.search(r'uiFamily = "([^"]+)"', swift).group(1), re.search(r'sportFamily = "([^"]+)"', swift).group(1)}
file_faces = set()
for f in present:
    n = names(FONTS / f)
    ps, fam = n.get(6), n.get(16) or n.get(1)
    file_faces.add(ps)
    if fam not in families: fail(f"{f}: family {fam!r} is not one the type layer asks for ({sorted(families)})")
if swift_faces != file_faces:
    fail(f"ThroFont.embeddedFaces and the shipped faces differ: only in Swift {sorted(swift_faces - file_faces)}, only in files {sorted(file_faces - swift_faces)}")

for lic, needle in (("OFL-Archivo.txt", "Archivo"), ("OFL-IBMPlex.txt", "IBM")):
    p = FONTS / lic
    if not p.exists(): fail(f"{lic} is missing; the licence must travel with the fonts")
    else:
        t = p.read_text(errors="replace")
        if "SIL OPEN FONT LICENSE Version 1.1" not in t or needle not in t.splitlines()[0]:
            fail(f"{lic} is not the SIL Open Font License 1.1 text for {needle}")

launch = plist.get("UILaunchScreen", {})
if "UIColorName" not in launch: fail("UILaunchScreen has no UIColorName; the static launch screen is the brand field (PD-007)")
for key, folder in (("UIColorName", ".colorset"), ("UIImageName", ".imageset")):
    if key in launch and not (ASSETS / f"{launch[key]}{folder}" / "Contents.json").exists():
        fail(f"UILaunchScreen.{key} = {launch[key]!r} has no {folder} in the asset catalogue")
icon = ASSETS / "AppIcon.appiconset" / "AppIcon.png"
if not icon.exists(): fail("AppIcon.png is missing")
else:
    d = icon.read_bytes()
    w, h, depth, ctype = struct.unpack(">IIBB", d[16:26])
    if (w, h, depth, ctype) != (1024, 1024, 8, 2):
        fail(f"AppIcon.png is {w}x{h} depth {depth} colour type {ctype}; App Store icons are 1024x1024 RGB without alpha")

if failures:
    sys.exit(1)
print(f"OK: {len(present)} faces listed and shipped, {len(file_faces)} PostScript names agree with ThroFont, licences present, launch assets and icon in place")
