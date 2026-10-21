"""Synthesizes Neon Stack's sound effects into assets/sfx (no third-party audio, no licensing).

Run: python3 tools/make_sfx.py
"""
import math
import random
import struct
import wave
from pathlib import Path

RATE = 22050
OUT = Path(__file__).resolve().parents[1] / "assets" / "sfx"


def sweep(f0, f1, dur, vol=0.5, decay=6.0, wave_shape="square"):
    """Pitch slide from f0 to f1 (exponential), with a decaying envelope."""
    n = int(RATE * dur)
    out, phase = [], 0.0
    for i in range(n):
        t = i / RATE
        f = f0 * (f1 / f0) ** (t / dur)
        phase += 2 * math.pi * f / RATE
        if wave_shape == "square":
            s = 1.0 if math.sin(phase) >= 0 else -1.0
            s *= 0.6
        elif wave_shape == "saw":
            s = ((phase / math.pi) % 2) - 1
        else:
            s = math.sin(phase)
        env = min(1.0, t / 0.003) * math.exp(-decay * t)
        out.append(vol * env * s)
    return out


def noise(dur, vol=0.3, decay=30.0, seed=1, lowpass=0.0):
    rng = random.Random(seed)
    out, prev = [], 0.0
    for i in range(int(RATE * dur)):
        v = rng.uniform(-1, 1)
        prev = prev * lowpass + v * (1 - lowpass)
        out.append(vol * prev * math.exp(-decay * i / RATE))
    return out


def mix(*tracks):
    """tracks: (start_seconds, samples)"""
    length = max(int(start * RATE) + len(s) for start, s in tracks)
    buf = [0.0] * length
    for start, s in tracks:
        o = int(start * RATE)
        for i, v in enumerate(s):
            buf[o + i] += v
    return buf


def save(name, samples):
    peak = max(1e-9, max(abs(v) for v in samples))
    scale = min(1.0, 0.9 / peak)
    with wave.open(str(OUT / f"{name}.wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(v * scale * 32767)) for v in samples))


OUT.mkdir(parents=True, exist_ok=True)

# Block lands: soft woody thump.
save("place", mix((0, sweep(180, 90, 0.12, vol=0.5, decay=28, wave_shape="sine")), (0, noise(0.05, vol=0.18, decay=70, seed=5, lowpass=0.5))))
# Overhang sliced off: short bright chop.
save("slice", mix((0, noise(0.09, vol=0.35, decay=45, seed=6, lowpass=0.2)), (0, sweep(1300, 600, 0.06, vol=0.15, decay=50, wave_shape="saw"))))
# Perfect drop: a bell chime, one step up a pentatonic scale per perfect in a row.
scale = [523.25, 587.33, 659.25, 783.99, 880.0, 1046.5, 1174.66, 1318.51]
for i, f in enumerate(scale):
    save(f"chime{i + 1}", mix((0, sweep(f, f, 0.6, vol=0.32, decay=5, wave_shape="sine")),
                              (0, sweep(f * 2, f * 2, 0.4, vol=0.12, decay=8, wave_shape="sine")),
                              (0, sweep(f * 3.01, f * 3.01, 0.2, vol=0.05, decay=14, wave_shape="sine"))))
# Missed block: falling buzz.
save("miss", mix((0, sweep(400, 70, 0.45, vol=0.4, decay=5, wave_shape="saw")), (0.05, noise(0.4, vol=0.3, decay=8, seed=3, lowpass=0.8))))
# Gem caught: sparkly up-arpeggio.
save("gem", mix(*[(i * 0.04, sweep(f, f * 1.01, 0.18, vol=0.22, decay=14, wave_shape="sine")) for i, f in enumerate([1046.5, 1318.51, 1567.98, 2093.0])]))
# Block widens after a perfect streak: soft upward swoosh.
save("regrow", sweep(300, 900, 0.25, vol=0.25, decay=6, wave_shape="sine"))
# Beam hits the boss.
save("bossHit", mix((0, sweep(1600, 200, 0.22, vol=0.35, decay=10, wave_shape="square")), (0, noise(0.2, vol=0.3, decay=14, seed=8, lowpass=0.6))))
# Boss warning: two-tone siren.
save("warning", mix(*[(i * 0.45, sweep(f, f, 0.4, vol=0.35, decay=1.5, wave_shape="saw")) for i, f in enumerate([440, 330, 440, 330])]))
# Inverter flip / gust change: quick wobble.
save("flip", mix((0, sweep(700, 350, 0.08, vol=0.25, decay=20, wave_shape="square")), (0.08, sweep(350, 700, 0.08, vol=0.25, decay=20, wave_shape="square"))))
# Boss down: long rumble with a bright tail.
save("bossDown", mix((0, noise(1.6, vol=0.6, decay=2.2, seed=4, lowpass=0.8)), (0, sweep(160, 30, 1.2, vol=0.5, decay=2.5, wave_shape="sine")),
                     *[(0.5 + i * 0.08, sweep(f, f, 0.5, vol=0.15, decay=5, wave_shape="sine")) for i, f in enumerate([523.25, 659.25, 783.99, 1046.5])]))
# Level clear: bright major fanfare.
save("levelClear", mix(*[(i * 0.11, sweep(f, f, 0.4 if i < 3 else 0.9, vol=0.3, decay=4 if i < 3 else 2.5)) for i, f in enumerate([392.0, 523.25, 659.25, 783.99])]))
# Game over: slow descending minor.
save("gameOver", mix(*[(i * 0.22, sweep(f, f * 0.97, 0.6, vol=0.35, decay=3.5, wave_shape="saw")) for i, f in enumerate([392.0, 311.13, 261.63, 196.0])]))
print("written:", sorted(p.name for p in OUT.glob("*.wav")))
