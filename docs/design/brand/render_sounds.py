"""The opening's four sounds, synthesised (PD-007, PD-182): a whoosh for the flight, a thud for the dart
in the board, a chalk scratch for the ring drawing itself, and the room the strike wakes up. Pure Python,
deterministic, 44.1 kHz 16-bit mono WAV. These are placeholders in the honest sense — physically shaped,
mixed for the sequence, and meant to be replaced by recorded foley under the same filenames when the
founder has it.

**The lengths are not free parameters.** Each one is a stretch of the film, and `LaunchTimeline.cues`
schedules against the same numbers so that something can ask whether the film is ever silent.
`tools/check_opening_sounds.py` holds this table against `OpeningSounds.seconds` in the Swift and
against the lengths of the files actually written, because the whoosh had already drifted once: it was
rendered at 1.2 s for a flight that had since become 1.4, so the air ran out before the dart landed.

  python3 docs/design/brand/render_sounds.py <repo root>
"""
import math, random, struct, sys, os

SR = 44100

# The lengths the film expects. Mirrored by `OpeningSounds.seconds` in LaunchSequence.swift.
LENGTHS = {
    "thro-whoosh": 1.40,   # the flight, exactly: 1.68 - 0.28
    "thro-thud": 0.75,
    "thro-chalk": 0.80,
    "thro-room": 3.18,     # the strike to the end of the cross-fade: 4.86 - 1.68
}

def write_wav(path, samples, peak_db):
    peak = max(1e-9, max(abs(s) for s in samples))
    gain = (10 ** (peak_db / 20)) / peak
    n = len(samples); fade = int(0.002 * SR)
    out = bytearray()
    for i, s in enumerate(samples):
        env = min(1.0, i / fade, (n - 1 - i) / fade)      # 2 ms fades against clicks
        v = max(-1.0, min(1.0, s * gain * env))
        out += struct.pack("<h", int(v * 32767))
    header = b"RIFF" + struct.pack("<I", 36 + len(out)) + b"WAVE"
    header += b"fmt " + struct.pack("<IHHIIHH", 16, 1, 1, SR, SR * 2, 2, 16)
    header += b"data" + struct.pack("<I", len(out))
    open(path, "wb").write(header + out)

def lowpass(x, fc):
    """One-pole low-pass; fc may be a list (per-sample cutoff)."""
    y = 0.0; out = []
    for i, v in enumerate(x):
        f = fc[i] if isinstance(fc, list) else fc
        a = 1 - math.exp(-2 * math.pi * f / SR)
        y += a * (v - y); out.append(y)
    return out

def highpass(x, fc):
    lp = lowpass(x, fc); return [a - b for a, b in zip(x, lp)]

def noise(n, seed):
    r = random.Random(seed); return [r.gauss(0, 1) for _ in range(n)]

def smoothstep(t): t = max(0.0, min(1.0, t)); return t * t * (3 - 2 * t)

def whoosh(duration):
    """Air past a spinning dart: band-limited noise whose centre sweeps upward as it closes, swelling
    into the moment of impact and cut there."""
    n = int(duration * SR); x = noise(n, 1)
    centre = [350 + 2600 * (i / n) ** 1.6 for i in range(n)]
    band = highpass(lowpass(x, centre), [c * 0.45 for c in centre])
    out = []
    for i, v in enumerate(band):
        t = i / n
        env = (t ** 2.4) * (1 - smoothstep((t - 0.93) / 0.07))       # swell, then the cut at impact
        flutter = 1 + 0.18 * math.sin(2 * math.pi * 11 * t * duration + 0.4)   # the flights' spin
        out.append(v * env * flutter)
    return out

def thud(duration):
    """A dart into sisal: a short bright click of the point, a dull body with two low resonances, a
    breath of fibre noise, and a soft clip for weight."""
    n = int(duration * SR); out = []
    click = lowpass(noise(n, 2), 3200); fibre = lowpass(noise(n, 3), 900)
    for i in range(n):
        t = i / SR
        body = (0.9 * math.sin(2 * math.pi * 72 * t) * math.exp(-t / 0.13)
                + 0.5 * math.sin(2 * math.pi * 121 * t + 0.6) * math.exp(-t / 0.075)
                + 0.25 * math.sin(2 * math.pi * 236 * t + 1.1) * math.exp(-t / 0.038))
        v = body + 0.9 * click[i] * math.exp(-t / 0.006) + 0.35 * fibre[i] * math.exp(-t / 0.03)
        out.append(math.tanh(1.6 * v))
    return out

def chalk(duration):
    """Chalk drawing a ring on a board: gritty high noise gated by a telegraph flicker, louder through
    the middle of the stroke where the hand moves fastest."""
    n = int(duration * SR); x = highpass(noise(n, 4), 1700); x = lowpass(x, 7000)
    r = random.Random(5); gate = 1.0; out = []
    for i, v in enumerate(x):
        if r.random() < 0.0028: gate = 0.35 if gate > 0.6 else 1.0      # ~120 Hz grit flicker
        t = i / n
        env = math.sin(math.pi * t) ** 1.4 * (0.75 + 0.25 * math.sin(2 * math.pi * 5.5 * t * duration))
        out.append(v * gate * env)
    return out

def room(duration):
    """The room the dart landed in.

    **The film used to end in silence.** The chalk scratch stops at 2.86 s and nothing else sounds: the
    letters are struck with a haptic each and no noise, the tagline tracks in, and the picture holds for
    a full second — two seconds of a five-second title sequence, all of its resolution, played with the
    room switched off while the line on screen promises the world stage.

    This is not a sting and not a chord. It is the thing a thud into sisal actually leaves behind: a low
    bed with two long resonances in it, a quiet band of air above them, and a slow fall away at the end
    so the hand-over to Home is into silence rather than off a cliff. It starts on the strike, because
    that is what wakes a room up."""
    n = int(duration * SR)
    low = lowpass(noise(n, 6), 150)
    air = lowpass(highpass(noise(n, 7), 260), 760)
    out = []
    for i in range(n):
        t = i / SR; u = i / n
        body = (0.85 * math.sin(2 * math.pi * 54.5 * t) * math.exp(-t / 1.9)
                + 0.45 * math.sin(2 * math.pi * 81.7 * t + 0.9) * math.exp(-t / 1.25))
        swell = smoothstep(t / 0.35)                       # the strike opens it
        fall = 1 - smoothstep((u - 0.78) / 0.22)           # and the cross-fade closes it
        drift = 0.86 + 0.14 * math.sin(2 * math.pi * 0.37 * t)
        out.append((3.4 * low[i] + body + 0.55 * air[i] * drift) * swell * fall)
    return out

if __name__ == "__main__":
    root = sys.argv[1]; d = os.path.join(root, "apps/ios/ThroDarts/Sounds"); os.makedirs(d, exist_ok=True)
    # Levels: the thud is the film's loudest moment, the room sits well under everything as a bed.
    for name, make, peak in [("thro-whoosh", whoosh, -9.0), ("thro-thud", thud, -1.5),
                             ("thro-chalk", chalk, -15.0), ("thro-room", room, -21.0)]:
        write_wav(os.path.join(d, name + ".wav"), make(LENGTHS[name]), peak)
    print("wrote " + ", ".join(LENGTHS) + " to", d)
