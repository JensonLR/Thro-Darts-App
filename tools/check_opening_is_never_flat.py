#!/usr/bin/env python3
"""No frame of the opening is a flat colour, read off real screenshots.

**The defect this exists for happened, and every test in the repository was blind to it.** One
`wallFade = 1 - pRing` faded the beam, the pool and all four hundred specks together, and `pRing`
reaches 1 at t = 2.403 — so for the last 2.46 seconds, *half the running time*, the reveal, the name,
the tagline and the whole hold played on flat `#0F3D2E` with a vignette on it. Every value feeding the
frame was correct. Nothing asserted anything about the picture, because nothing could.

Nothing in the package tests can, either, and that is worth writing down: `ThroColor` is an
asset-catalogue colour and the catalogue does not resolve inside the client's macOS test bundle. A
frame rendered there comes back **entirely transparent** — the film drawn in invisible ink. Rendering
frames in a unit test and looking at them is not available at any price.

So this reads the real thing: PNGs off a real simulator, shot by `tools/shoot.sh --opening`, with the
real tokens and the real compositor. It asks two questions of each frame.

  1. **Is it a picture?** The spread between the brightest and dimmest of a grid of samples. A colour
     chip with a vignette on it cannot clear the floor; a lit room with a dart in it clears it easily.
     This starts when the film does, at the flight — **before that the frame must be flat**, and that
     is the other half of the check rather than an exemption. The opening's first frames are the
     launch screen's own green held still, so that iOS handing the app its window is not a visible
     cut. Texture there would be a seam on every cold start, which is the first thing anybody sees.

  2. **Is the lamp on?** The patch under the lamp against **its own mirror through the middle of the
     frame** — (0.5, 0.30) against (0.5, 0.70). That pairing is the whole trick. The vignette is a
     radial gradient about the centre, so it lands identically on both and cancels; the lamp lands on
     one of them. The first version of this compared the lamp with the frame's corners, put the
     defect back to prove it worked, and **the defect passed**: the vignette alone makes the middle
     of a frame 1.4x its corners, which was over the floor with the lamp completely out.

Usage:

    tools/shoot.sh out/opening --opening 0.15 0.90 1.85 2.90 3.60 4.40
    tools/check_opening_is_never_flat.py out/opening

What it does not prove: that the film is *beautiful*, or that it holds 60 Hz. It proves the lights
are on, which is the thing that went out once and would go out again unseen.
"""
import pathlib
import struct
import sys
import zlib

# The floor a real frame clears and a colour chip does not. Measured across the film: the dimmest
# frame of the opening as it stands is about 0.10, and the flat-green frame the defect produced
# measures 0.012 — almost all of which is the vignette.
FLAT_FLOOR = 0.045
# When the picture starts: `LaunchTimeline.standard.flight.start`. Before this the frame is the
# launch screen's flat green, held, and a frame with anything in it is a seam on every cold start.
MOVES_AT = 0.28
# How flat the hand-off has to be. The vignette is already easing in by then, so this is not zero.
HANDOFF_CEILING = 0.03
# How much brighter the lamp's patch must be than its mirror. With the lamp on this reads about
# 1.6x; with PD-174's defect restored it reads 1.00, because there is nothing there at all.
LAMP_MARGIN = 1.25
# The instants the lamp must be on for: after the ring is whole, which is where it used to go out.
LAMP_AFTER = 2.5


def read_png(path):
    """Decode a non-interlaced 8-bit RGB/RGBA PNG to (width, height, rows of (r, g, b))."""
    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise SystemExit(f"{path}: not a PNG")
    pos, idat, width = 8, bytearray(), None
    while pos < len(data):
        (length,) = struct.unpack(">I", data[pos:pos + 4])
        kind = data[pos + 4:pos + 8]
        body = data[pos + 8:pos + 8 + length]
        if kind == b"IHDR":
            width, height, depth, colour, _, _, interlace = struct.unpack(">IIBBBBB", body)
            if depth != 8 or colour not in (2, 6) or interlace:
                raise SystemExit(f"{path}: expected an 8-bit non-interlaced colour PNG")
        elif kind == b"IDAT":
            idat += body
        elif kind == b"IEND":
            break
        pos += 12 + length
    if width is None:
        raise SystemExit(f"{path}: no header")
    channels = 3 if colour == 2 else 4
    raw = zlib.decompress(bytes(idat))
    stride = width * channels
    rows, previous, at = [], bytearray(stride), 0
    for _ in range(height):
        filter_kind = raw[at]
        line = bytearray(raw[at + 1:at + 1 + stride])
        at += 1 + stride
        for i in range(stride):
            a = line[i - channels] if i >= channels else 0
            b = previous[i]
            c = previous[i - channels] if i >= channels else 0
            if filter_kind == 1:
                line[i] = (line[i] + a) & 0xFF
            elif filter_kind == 2:
                line[i] = (line[i] + b) & 0xFF
            elif filter_kind == 3:
                line[i] = (line[i] + (a + b) // 2) & 0xFF
            elif filter_kind == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                line[i] = (line[i] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 0xFF
            elif filter_kind != 0:
                raise SystemExit(f"{path}: unknown row filter {filter_kind}")
        rows.append([tuple(line[i:i + 3]) for i in range(0, stride, channels)])
        previous = line
    return width, height, rows


def luminance(pixel):
    """WCAG 2.x relative luminance, the same arithmetic the design system uses."""
    out = 0.0
    for value, weight in zip(pixel, (0.2126, 0.7152, 0.0722)):
        v = value / 255
        out += weight * (v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4)
    return out


def sample(rows, width, height, x, y, radius=6):
    """The mean luminance of a small patch, so one stray speck of chalk is not a reading."""
    total, count = 0.0, 0
    for row in range(max(0, y - radius), min(height, y + radius + 1)):
        for column in range(max(0, x - radius), min(width, x + radius + 1)):
            total += luminance(rows[row][column])
            count += 1
    return total / count


def seconds_of(path):
    """`1_85.png` is t = 1.85 s. Returns None for a name that is not an instant."""
    try:
        return float(path.stem.replace("_", "."))
    except ValueError:
        return None


def main():
    if len(sys.argv) != 2:
        raise SystemExit(__doc__.strip().splitlines()[-1])
    folder = pathlib.Path(sys.argv[1])
    shots = sorted(p for p in folder.glob("*.png") if not p.stem.endswith("_small"))
    if not shots:
        raise SystemExit(f"{folder}: nothing to read — run tools/shoot.sh --opening first")

    problems, seen = [], 0
    for shot in shots:
        at = seconds_of(shot)
        if at is None:
            continue
        seen += 1
        width, height, rows = read_png(shot)
        # The status bar is the simulator's, not the film's, and it is the brightest thing on the
        # screen. Everything below it is the picture.
        top = int(height * 0.09)
        grid = [sample(rows, width, height, width * c // 9 + width // 18,
                       top + (height - top) * r // 9 + (height - top) // 18)
                for r in range(9) for c in range(9)]
        spread = max(grid) - min(grid)
        if at < MOVES_AT:
            lit = "held" if spread <= HANDOFF_CEILING else "SEAM"
            if spread > HANDOFF_CEILING:
                problems.append(f"{shot.name}: the launch-screen hand-off has {spread:.3f} of "
                                f"luminance in it — anything but the flat green is a visible cut "
                                f"when the app starts, ceiling {HANDOFF_CEILING}")
        else:
            lit = "flat" if spread < FLAT_FLOOR else "ok"
            if spread < FLAT_FLOOR:
                problems.append(f"{shot.name}: the frame is a colour chip — {spread:.3f} of luminance "
                                f"between its brightest and dimmest patch, floor {FLAT_FLOOR}")

        lamp_note = ""
        if at >= LAMP_AFTER:
            # Where the lamp settles: the design system's own (0.5, 0.30), which is where every
            # `ThroBoard` in the app is lit from — and the same point reflected through the middle of
            # the frame, which the vignette treats identically and the lamp does not reach.
            under = sample(rows, width, height, width // 2, int(height * 0.30), 26)
            mirror = sample(rows, width, height, width // 2, int(height * 0.70), 26)
            ratio = under / max(mirror, 1e-6)
            lamp_note = f", lamp {ratio:.2f}x its mirror"
            if ratio < LAMP_MARGIN:
                problems.append(f"{shot.name}: the lamp is out — the patch under it reads "
                                f"{ratio:.2f}x the same patch mirrored through the middle of the "
                                f"frame, which only the lamp can tell apart, floor {LAMP_MARGIN}x")
        print(f"  {at:5.2f}s  spread {spread:.3f} ({lit}){lamp_note}")

    if not seen:
        raise SystemExit(f"{folder}: no frames named as instants (expected 1_85.png and the like)")
    for problem in problems:
        print(f"FAIL {problem}", file=sys.stderr)
    if problems:
        raise SystemExit(1)
    print(f"{seen} frames of the opening: the hand-off held flat, nothing after {MOVES_AT}s a colour "
          f"chip, and the lamp on in everything past {LAMP_AFTER}s")


if __name__ == "__main__":
    main()
