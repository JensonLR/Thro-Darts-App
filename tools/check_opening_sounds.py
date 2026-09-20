#!/usr/bin/env python3
"""The opening's score cannot drift away from the opening.

**It had already drifted, and nothing said so.** `whoosh()` was rendered at 1.2 seconds with a
docstring giving the reason — *"the tracking shot's length"*. The tracking shot later became 1.4
seconds. The sound did not, so for however long that has been true the air ran out two tenths of a
second before the dart landed, under the loudest-looking part of the film. Nothing could have caught
it: a sound's length lived in a Python default argument, the film's length lived in a Swift array of
cut points, and no third thing looked at both.

Four things have to agree about how long a sound is, and this holds them together on every push:

  1. `OpeningSounds.seconds` in `LaunchSequence.swift`, which is what the film schedules against;
  2. `LENGTHS` in `docs/design/brand/render_sounds.py`, which is what gets rendered;
  3. the WAV files themselves, read out of their own headers — because a synthesiser that is never
     re-run leaves yesterday's file sitting next to today's number;
  4. `OpeningPreferences.soundFiles`, which is the list the app actually loads.

Two Swift tests hold the other end of it: that the whoosh's length **is** the flight segment rather
than a number that matches it today, and that the film is never silent for longer than 0.45 s between
the first sound and the cross-fade.

What this does not prove: that any of them sounds good. That needs the founder and a pair of speakers.
"""
import pathlib
import re
import struct
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SWIFT = ROOT / "packages/client-ios/Sources/ThroApp/LaunchSequence.swift"
SOUND_SWIFT = ROOT / "packages/client-ios/Sources/ThroApp/LaunchSound.swift"
PYTHON = ROOT / "docs/design/brand/render_sounds.py"
SOUNDS = ROOT / "apps/ios/ThroDarts/Sounds"
# A WAV is written to a whole number of samples, so a length can be out by up to half a sample.
TOLERANCE = 0.001


def table(path, opening, pattern):
    """Every `"name": number` pair inside the block that starts at `opening`."""
    text = path.read_text(encoding="utf-8")
    start = text.find(opening)
    if start < 0:
        raise SystemExit(f"{path.name}: no {opening!r} to read")
    # From the end of the opening, because the opening itself contains a bracket — `[String: Double]`
    # closes before the table has begun, and searching from `start` read an empty table and reported
    # every sound missing.
    start += len(opening)
    end = min(i for i in (text.find("]", start), text.find("}", start)) if i > 0)
    return {m.group(1): float(m.group(2)) for m in pattern.finditer(text[start:end])}


def wav_seconds(path):
    data = path.read_bytes()
    if data[:4] != b"RIFF" or data[8:12] != b"WAVE":
        raise SystemExit(f"{path.name}: not a WAV")
    at, rate, channels, bits, frames = 12, None, None, None, None
    while at + 8 <= len(data):
        kind = data[at:at + 4]
        (size,) = struct.unpack("<I", data[at + 4:at + 8])
        body = data[at + 8:at + 8 + size]
        if kind == b"fmt ":
            _, channels, rate, _, _, bits = struct.unpack("<HHIIHH", body[:16])
        elif kind == b"data":
            frames = size
        at += 8 + size + (size & 1)
    if not (rate and channels and bits and frames is not None):
        raise SystemExit(f"{path.name}: incomplete WAV")
    return frames / (rate * channels * bits // 8)


def main():
    swift = table(SWIFT, "public static let seconds: [String: Double] = [",
                  re.compile(r'"([a-z]+)":\s*([0-9.]+)'))
    python = table(PYTHON, "LENGTHS = {", re.compile(r'"thro-([a-z]+)":\s*([0-9.]+)'))
    loaded = re.search(r'public static let soundFiles = \[(.*?)\]',
                       SOUND_SWIFT.read_text(encoding="utf-8"), re.S)
    if not loaded:
        raise SystemExit("LaunchSound.swift: no soundFiles list to read")
    loaded = {name.removeprefix("thro-") for name in re.findall(r'"([^"]+)"', loaded.group(1))}

    problems = []
    if not swift:
        problems.append("LaunchSequence.swift: OpeningSounds.seconds is empty")
    for name in sorted(set(swift) | set(python) | loaded):
        where = []
        if name not in swift:
            where.append("OpeningSounds.seconds")
        if name not in python:
            where.append("render_sounds.py's LENGTHS")
        if name not in loaded:
            where.append("OpeningPreferences.soundFiles")
        file = SOUNDS / f"thro-{name}.wav"
        if not file.exists():
            where.append(f"{file.name}")
        if where:
            problems.append(f"{name}: missing from " + ", ".join(where))
            continue
        want, rendered, actual = swift[name], python[name], wav_seconds(file)
        if abs(want - rendered) > TOLERANCE:
            problems.append(f"{name}: the film schedules {want}s and the synthesiser renders "
                            f"{rendered}s")
        if abs(want - actual) > TOLERANCE:
            problems.append(f"{name}: the film schedules {want}s and {file.name} is "
                            f"{actual:.3f}s — re-run render_sounds.py")
        print(f"  {name:7s} {actual:5.2f}s")

    for problem in problems:
        print(f"FAIL {problem}", file=sys.stderr)
    if problems:
        raise SystemExit(1)
    print(f"{len(swift)} sounds: the film, the synthesiser, the files and the loader all agree")


if __name__ == "__main__":
    main()
