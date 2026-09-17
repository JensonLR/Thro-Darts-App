#!/usr/bin/env python3
"""Have a camera's own decoder read the QR codes this site draws (PD-121).

`apps/web/qr.js` is an encoder written out by hand, because the sign-in page loads nothing from anybody else. A
hand-written encoder is wrong in ways no test of its parts shows: a format bit in the wrong place still looks like a
QR code, and no phone will read it. So this draws real codes — one per version the encoder supports, the two-block
versions included — as PNGs, and asks macOS's Core Image detector, the decoder behind the iPhone's camera, what each
says. Every one must read back as exactly what went in.

It needs `node` and macOS (`swift`, Core Image). Anywhere else it says so and passes: the guard is for whoever changes
the encoder, and that person is at a Mac.
"""
import json
import pathlib
import platform
import shutil
import struct
import subprocess
import sys
import tempfile
import zlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
ENCODER = ROOT / "apps/web/qr.js"

# One text per version, 1 to 5: the last two are split over two Reed–Solomon blocks and interleaved.
TEXTS = [
    "THRO",                                                                   # version 1
    "https://thro.uk/x",                                                     # version 2
    "https://thro.uk/link/K7TQ2M",                                           # version 3 — the one the page draws
    "https://thro.uk/link/K7TQ2M?from=a-laptop-in-a-pub",                    # version 4
    "https://thro.uk/link/K7TQ2M?from=a-laptop-in-the-back-room-of-the-sun-inn",  # version 5
]

SWIFT = r'''
import Foundation
import CoreImage
var out: [String] = []
for path in CommandLine.arguments.dropFirst() {
    guard let image = CIImage(contentsOf: URL(fileURLWithPath: path)) else { out.append(""); continue }
    let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])!
    let found = detector.features(in: image).compactMap { ($0 as? CIQRCodeFeature)?.messageString }
    out.append(found.first ?? "")
}
let data = try! JSONSerialization.data(withJSONObject: out)
print(String(data: data, encoding: .utf8)!)
'''


def png(matrix, scale=10, quiet=4):
    n = len(matrix)
    size = (n + 2 * quiet) * scale
    rows = bytearray()
    for y in range(size):
        rows.append(0)
        r = y // scale - quiet
        for x in range(size):
            c = x // scale - quiet
            dark = 0 <= r < n and 0 <= c < n and matrix[r][c]
            rows.append(0 if dark else 255)

    def chunk(kind, data):
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 0, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(bytes(rows), 9)) + chunk(b"IEND", b""))


def main() -> int:
    if platform.system() != "Darwin" or not shutil.which("swift") or not shutil.which("node"):
        print("check_qr: needs macOS with swift and node to read the codes back; not checked here.")
        return 0
    script = "const q=require(process.argv[1]);console.log(JSON.stringify(JSON.parse(process.argv[2]).map(t=>q.matrix(t))))"
    drawn = subprocess.run(["node", "-e", script, str(ENCODER), json.dumps(TEXTS)], capture_output=True, text=True)
    if drawn.returncode != 0:
        print(f"check_qr: the encoder threw:\n{drawn.stderr}", file=sys.stderr)
        return 1
    matrices = json.loads(drawn.stdout)
    sizes = [len(m) for m in matrices]
    if sizes != [21, 25, 29, 33, 37]:
        print(f"check_qr: expected versions 1 to 5 (21, 25, 29, 33, 37 modules), drew {sizes}", file=sys.stderr)
        return 1
    with tempfile.TemporaryDirectory() as tmp:
        paths = []
        for i, m in enumerate(matrices):
            path = pathlib.Path(tmp) / f"qr{i}.png"
            path.write_bytes(png(m))
            paths.append(str(path))
        reader = pathlib.Path(tmp) / "read.swift"
        reader.write_text(SWIFT)
        read = subprocess.run(["swift", str(reader), *paths], capture_output=True, text=True)
        if read.returncode != 0:
            print(f"check_qr: the reader did not run:\n{read.stderr[-600:]}", file=sys.stderr)
            return 1
        said = json.loads(read.stdout.strip().splitlines()[-1])
    problems = [f"  version {i + 1}: drew {t!r}, the camera read {s!r}" for i, (t, s) in enumerate(zip(TEXTS, said)) if t != s]
    if problems:
        print("The QR codes this site draws do not read back:", file=sys.stderr)
        print("\n".join(problems), file=sys.stderr)
        return 1
    print(f"check_qr: {len(TEXTS)} codes drawn by apps/web/qr.js, versions 1 to 5, each read back exactly by Core Image.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
