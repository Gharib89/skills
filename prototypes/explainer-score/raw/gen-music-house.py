"""Synthesize the original background music loop and sound effects (no samples, no third-party audio).

Usage: uv run --no-project --with numpy --with scipy --with soundfile python scripts/gen-music.py
Writes public/music/bed.wav and public/sfx/*.wav (48 kHz stereo).
"""

from pathlib import Path

import numpy as np
import soundfile as sf
from scipy.signal import butter, sosfilt

SR = 48000
OUT = __import__("pathlib").Path("raw/house")
rng = np.random.default_rng(7)


def note_hz(midi: float) -> float:
    return 440.0 * 2 ** ((midi - 69) / 12)


def lowpass(x, hz, order=2):
    return sosfilt(butter(order, hz, "low", fs=SR, output="sos"), x)


def highpass(x, hz, order=2):
    return sosfilt(butter(order, hz, "high", fs=SR, output="sos"), x)


def bandpass(x, lo, hi, order=2):
    return sosfilt(butter(order, [lo, hi], "band", fs=SR, output="sos"), x)


def env(n, a, r):
    """Attack/release envelope over n samples, a and r in seconds."""
    e = np.ones(n)
    na, nr = int(a * SR), int(r * SR)
    if na:
        e[:na] = np.linspace(0, 1, na)
    if nr:
        e[-nr:] *= np.linspace(1, 0, nr)
    return e


def saw(freq, n, detune=0.0):
    t = np.arange(n) / SR
    ph = (freq * (1 + detune)) * t
    return 2 * (ph - np.floor(ph + 0.5))


# ---------- music bed ----------
BPM = 92
BEAT = 60 / BPM
BAR = 4 * BEAT
# A minor: Am, F, C, G (i, VI, III, VII), then Am, F, Dm, E sus feel via G
PROG = [
    [57, 60, 64, 69],  # Am
    [53, 57, 60, 65],  # F
    [48, 55, 60, 64],  # C
    [55, 59, 62, 67],  # G
    [57, 60, 64, 69],  # Am
    [53, 57, 60, 65],  # F
    [50, 57, 62, 65],  # Dm
    [55, 59, 62, 67],  # G
]
SECTIONS = 4  # A (pads), B (pads + arp), C (pads + arp + beat), D (pads + beat)
bar_n = int(BAR * SR)
total = bar_n * len(PROG) * SECTIONS
L = np.zeros(total)
R = np.zeros(total)


def add(buf, start, sig):
    end = min(len(buf), start + len(sig))
    buf[start:end] += sig[: end - start]


for sec in range(SECTIONS):
    for bi, chord in enumerate(PROG):
        start = (sec * len(PROG) + bi) * bar_n
        # pad: detuned saws, low-passed, slow swell, stereo by detune sign
        n = bar_n + int(0.6 * SR)
        padL = np.zeros(n)
        padR = np.zeros(n)
        for m in chord:
            f = note_hz(m)
            padL += saw(f, n, -0.004) + 0.5 * saw(f / 2, n, 0.002)
            padR += saw(f, n, 0.004) + 0.5 * saw(f / 2, n, -0.002)
        e = env(n, 0.9, 0.9)
        add(L, start, lowpass(padL, 1100) * e * 0.035)
        add(R, start, lowpass(padR, 1100) * e * 0.035)
        # sub bass on the root, eighth-note pulse in sections C, D
        root = note_hz(chord[0] - 12)
        steps = 8 if sec >= 2 else 2
        for s in range(steps):
            n2 = int(BAR / steps * SR)
            t = np.arange(n2) / SR
            b = np.sin(2 * np.pi * root * t) * env(n2, 0.01, 0.12) * 0.11
            add(L, start + s * n2, b)
            add(R, start + s * n2, b)
        # arpeggio pluck in sections B, C: sixteenths across chord tones
        if sec in (1, 2):
            pattern = [0, 2, 1, 3, 2, 1, 3, 2]
            step = BEAT / 2
            for s in range(8):
                m = chord[pattern[s]] + 12
                n3 = int(0.35 * SR)
                t = np.arange(n3) / SR
                tone = (np.sin(2 * np.pi * note_hz(m) * t) + 0.3 * np.sin(4 * np.pi * note_hz(m) * t))
                pl = tone * np.exp(-t * 9) * 0.05
                pan = 0.5 + 0.35 * np.sin(s)
                off = start + int(s * step * SR)
                add(L, off, pl * (1 - pan) * 1.6)
                add(R, off, pl * pan * 1.6)
        # soft beat in sections C, D: kick on 1 and 3, hat on offbeats
        if sec >= 2:
            for beat in range(4):
                off = start + int(beat * BEAT * SR)
                if beat in (0, 2):
                    n4 = int(0.3 * SR)
                    t = np.arange(n4) / SR
                    f = 110 * np.exp(-t * 18) + 45
                    k = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 11) * 0.22
                    add(L, off, k)
                    add(R, off, k)
                hoff = off + int(BEAT / 2 * SR)
                n5 = int(0.05 * SR)
                h = highpass(rng.standard_normal(n5), 7000) * env(n5, 0.001, 0.045) * 0.03
                add(L, hoff, h * 0.8)
                add(R, hoff, h)

# gentle reverb-ish smear: a few decaying delays
for d, g in [(0.113, 0.25), (0.229, 0.18), (0.347, 0.12)]:
    k = int(d * SR)
    L[k:] += g * R[:-k]
    R[k:] += g * L[:-k]

mix = np.stack([L, R], axis=1)
# crossfade the tail into the head so the loop is seamless
xf = int(1.5 * SR)
mix[:xf] = mix[:xf] * np.linspace(0, 1, xf)[:, None] + mix[-xf:] * np.linspace(1, 0, xf)[:, None]
mix = mix[:-xf]
mix /= np.max(np.abs(mix)) / 0.7
(OUT / "music").mkdir(parents=True, exist_ok=True)
sf.write(OUT / "music" / "bed.wav", mix.astype(np.float32), SR)
print(f"bed.wav {len(mix) / SR:.1f}s")

# ---------- sound effects ----------
(OUT / "sfx").mkdir(parents=True, exist_ok=True)


def write(name, x, peak=0.6):
    x = x / np.max(np.abs(x)) * peak
    st = np.stack([x, x], axis=1) if x.ndim == 1 else x
    sf.write(OUT / "sfx" / f"{name}.wav", st.astype(np.float32), SR)
    print(f"{name}.wav {len(st) / SR:.2f}s")


# whoosh: noise through a band sweeping up then down
n = int(0.7 * SR)
t = np.arange(n) / SR
noise = rng.standard_normal(n)
out = np.zeros(n)
chunk = 480
for i in range(0, n, chunk):
    p = i / n
    centre = 300 + 3500 * np.sin(np.pi * p)
    seg = noise[max(0, i - 2048): i + chunk]
    filt = bandpass(seg, centre * 0.6, min(centre * 1.6, 20000))
    out[i: i + chunk] = filt[-len(out[i: i + chunk]):]
write("whoosh", out * np.sin(np.pi * t / t[-1]) ** 2, 0.5)

# tick: short soft click for reveals
n = int(0.05 * SR)
t = np.arange(n) / SR
write("tick", np.sin(2 * np.pi * 1800 * t) * np.exp(-t * 120), 0.35)

# pop: rising blip for card reveals
n = int(0.12 * SR)
t = np.arange(n) / SR
f = 500 + 700 * t / t[-1]
write("pop", np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 30), 0.35)

# chime: two bell partials for chapter cards
n = int(1.6 * SR)
t = np.arange(n) / SR
bell = sum(a * np.sin(2 * np.pi * f * t) * np.exp(-t * d) for f, a, d in
           [(880, 1, 3), (1320, 0.6, 4), (1760, 0.3, 6), (2640, 0.15, 8)])
bell2 = np.zeros(n)
off = int(0.18 * SR)
bell2[off:] = sum(a * np.sin(2 * np.pi * f * t[: n - off]) * np.exp(-t[: n - off] * d) for f, a, d in
                  [(1174.7, 1, 3), (1760, 0.5, 4), (2349, 0.25, 6)])
write("chime", bell + 0.8 * bell2, 0.45)

# riser: filtered noise swelling for chapter transitions
n = int(1.8 * SR)
t = np.arange(n) / SR
r = highpass(rng.standard_normal(n), 1500) * (t / t[-1]) ** 2.5
write("riser", r * env(n, 0.01, 0.08), 0.35)

# success: a major arpeggio for the merge moment
n = int(1.2 * SR)
t = np.arange(n) / SR
s = np.zeros(n)
for i, m in enumerate([69, 73, 76, 81]):
    o = int(i * 0.09 * SR)
    tt = t[: n - o]
    s[o:] += np.sin(2 * np.pi * note_hz(m) * tt) * np.exp(-tt * 4)
write("success", s, 0.45)
