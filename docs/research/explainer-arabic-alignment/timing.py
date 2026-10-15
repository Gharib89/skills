# Word timing accuracy on the good clips. Usage: timing.py <whisper-json>
# Ground truth 1: sentence onsets/offsets in the joined clips (known from the separate renders).
# Ground truth 2: pause edges found from the waveform energy (a word ends at a pause start, the next starts at its end).
# Plus pairwise agreement between methods on every script word.
import json, re, sys
from pathlib import Path
import numpy as np
from common import script_words, key, match, load, LATIN

LAB = Path(__file__).parent
W = json.loads((LAB / sys.argv[1]).read_text())
S = json.loads((LAB / "out/scripts.json").read_text())
sents = json.loads((LAB / "scripts.json").read_text())
SENTS = {"s1": sents["s1"], "s2a": sents["s2"][:1]}
truth = json.loads((LAB / "out/truth.json").read_text())
M = {m: json.loads((LAB / f"out/align-{m}-cuda.json").read_text()) for m in ("mms", "egy")}


def whisper_mapped(clip, sid):
    words = W[clip]["words"]
    sw = script_words(S[sid])
    res = match([key(b) for _, b in sw], [key(w[0]) for w in words], 0.5)
    return [[d, words[sp[0]][1], words[sp[1]][2], s] if sp else [d, None, None, 0] for (d, _), (s, sp) in zip(sw, res)]


def pauses(x, min_len=0.15, db=-35):
    f = 160
    e = np.array([np.sqrt(np.mean(x[i:i + f] ** 2)) + 1e-9 for i in range(0, len(x) - f, f)])
    quiet = 20 * np.log10(e / e.max()) < db
    out, i = [], 0
    while i < len(quiet):
        if quiet[i]:
            j = i
            while j < len(quiet) and quiet[j]:
                j += 1
            if (j - i) * 0.01 >= min_len and i > 0 and j < len(quiet):
                out.append((i * 0.01, j * 0.01))
            i = j
        else:
            i += 1
    return out


goods = sorted(c for c in W if c.startswith("good-"))
methods = {}
for c in goods:
    sid = c.split("-")[1]
    methods.setdefault("mms", {})[c] = M["mms"][c]
    methods.setdefault("egy", {})[c] = M["egy"][c]
    methods.setdefault("whisper", {})[c] = whisper_mapped(c, sid)

print("== coverage: script words given a time")
for m, d in methods.items():
    n = sum(len(v) for v in d.values()); t = sum(r[1] is not None for v in d.values() for r in v)
    print(f"{m:8} {t}/{n}")

print("\n== sentence edges vs ground truth (s1, s2a joined renders), ms")
for m, d in methods.items():
    errs = []
    for c, rows in d.items():
        sid = c.split("-")[1]
        if sid not in SENTS:
            continue
        k = 0
        for (on, off), s in zip(truth[c[5:]], SENTS[sid]):
            n = len(script_words(s))
            a, b = rows[k], rows[k + n - 1]
            if a[1] is not None:
                errs.append(("onset", (a[1] - on) * 1000))
            if b[2] is not None:
                errs.append(("offset", (b[2] - off) * 1000))
            k += n
    for kind in ("onset", "offset"):
        e = [round(v) for k2, v in errs if k2 == kind]
        print(f"{m:8} {kind:6} errors {e}")

print("\n== pause edges from the waveform, |error| ms (word end at pause start, next word start at pause end)")
for m, d in methods.items():
    allerr, en = [], []
    for c, rows in d.items():
        x = load(LAB / f"clips/{c}.wav")
        ends = [(r[2], r[0]) for r in rows if r[2] is not None]
        starts = [(r[1], r[0]) for r in rows if r[1] is not None]
        for ps, pe in pauses(x):
            e1, w1 = min(ends, key=lambda t: abs(t[0] - ps))
            e2, w2 = min(starts, key=lambda t: abs(t[0] - pe))
            allerr += [abs(e1 - ps) * 1000, abs(e2 - pe) * 1000]
            en += [abs(e1 - ps) * 1000 for _ in [0] if LATIN.search(w1)] + [abs(e2 - pe) * 1000 for _ in [0] if LATIN.search(w2)]
    a = np.array(allerr)
    print(f"{m:8} n={len(a)} median {np.median(a):.0f}  p90 {np.percentile(a, 90):.0f}  <=50ms {np.mean(a <= 50):.0%}  <=100ms {np.mean(a <= 100):.0%}"
          f"   English-term edges n={len(en)} median {np.median(en) if en else float('nan'):.0f}")

print("\n== pairwise agreement on every script word, |delta| ms (start and end)")
for a, b in (("mms", "egy"), ("mms", "whisper"), ("egy", "whisper")):
    for subset in ("all", "english"):
        d = []
        for c in goods:
            for ra, rb in zip(methods[a][c], methods[b][c]):
                if rb[1] is None or ra[1] is None or (subset == "english" and not LATIN.search(ra[0])):
                    continue
                d += [abs(ra[1] - rb[1]) * 1000, abs(ra[2] - rb[2]) * 1000]
        d = np.array(d)
        print(f"{a}-{b:8} {subset:7} n={len(d)} median {np.median(d):.0f}  p90 {np.percentile(d, 90):.0f}  <=100ms {np.mean(d <= 100):.0%}  <=200ms {np.mean(d <= 200):.0%}")

print("\n== English-term words: mean aligner confidence (content-word mean) on good clips")
for m in ("mms", "egy"):
    en = [r[3] for c in goods for r in M[m][c] if LATIN.search(r[0])]
    ar = [r[3] for c in goods for r in M[m][c] if not LATIN.search(r[0])]
    print(f"{m}: English terms {np.mean(en):.3f} (n={len(en)})  Arabic words {np.mean(ar):.3f} (n={len(ar)})")
