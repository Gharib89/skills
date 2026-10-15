# Build the test set: good Gemini clips (sentence renders joined with known gaps, so sentence
# onsets and offsets are ground truth), benign variants that must pass, garbled variants that must block.
import json, subprocess, sys
from pathlib import Path
import numpy as np
import soundfile as sf
from common import load, SR

LAB = Path(__file__).parent
NARR = Path("/home/ribo/wip/projects/skills-explainer-narrators/prototypes/explainer-narrators")
VOICES = ("ar-eg-csagent-2", "ar-eg-commercial-11")
C = LAB / "clips"
C.mkdir(exist_ok=True)
rng = np.random.default_rng(684)


def trim(x, db=-35):
    f = 160  # 10 ms frames
    e = np.array([np.sqrt(np.mean(x[i:i + f] ** 2)) + 1e-9 for i in range(0, len(x) - f, f)])
    on = np.where(20 * np.log10(e / e.max()) > db)[0]
    return x[on[0] * f: (on[-1] + 1) * f]


def save(name, x):
    sf.write(C / f"{name}.wav", x.astype(np.float32), SR)


scripts = {}
truth = {}
good = {}
SETS = {"s1": json.loads((LAB / "scripts.json").read_text())["s1"],
        "s2a": json.loads((LAB / "scripts.json").read_text())["s2"][:1]}
for sid, sents in SETS.items():
    scripts[sid] = " ".join(sents)
    src = sid[:2]
    for v in VOICES:
        parts = [LAB / f"audio/good-{src}-{v}-{k}.wav" for k in range(len(sents))]
        if not all(p.exists() for p in parts):
            print("missing", sid, v)
            continue
        x, t, spans = np.zeros(int(0.3 * SR)), 0.3, []
        for p in parts:
            s = trim(load(p))
            spans.append([round(t, 3), round(t + len(s) / SR, 3)])
            x = np.concatenate([x, s, np.zeros(int(0.45 * SR))])
            t += len(s) / SR + 0.45
        save(f"good-{sid}-{v}", x)
        truth[f"{sid}-{v}"] = spans
        good[f"{sid}-{v}"] = x

scripts["p0"] = (NARR / "script/ar.txt").read_text().strip()
for v, f in zip(VOICES, ("ar-female-C.mp3", "ar-male-C.mp3")):
    x = load(NARR / "clips" / f)
    save(f"good-p0-{v}", x)
    good[f"p0-{v}"] = x

# variants
for name, x in good.items():
    n = len(x)
    save(f"trunc-{name}", x[: int(0.65 * n)])                                   # render cut off
    save(f"drop-{name}", np.concatenate([x[: int(0.35 * n)], x[int(0.65 * n):]]))  # 30 % skipped
    save(f"repeat-{name}", np.concatenate([x[: int(0.6 * n)], x[int(0.35 * n):]]))  # loop: 25 % said twice
    ch = int(0.25 * SR)                                                          # babble: each 250 ms reversed
    save(f"babble-{name}", np.concatenate([x[i:i + ch][::-1] for i in range(0, n, ch)]))
    other = [y for k, y in good.items() if k != name and k.split("-", 1)[1] == name.split("-", 1)[1]] or \
            [y for k, y in good.items() if k.split("-")[0] != name.split("-")[0]]
    o = other[0]
    if len(o) < 0.3 * n:
        o = np.tile(o, int(0.3 * n / len(o)) + 1)
    seg = o[int(0.5 * (len(o) - 0.3 * n)):][: int(0.3 * n)]                     # 30 % replaced by other words
    save(f"splice-{name}", np.concatenate([x[: int(0.35 * n)], seg, x[int(0.35 * n) + len(seg):]]))
    noise = rng.standard_normal(n) * np.sqrt(np.mean(x ** 2))                    # 0 dB SNR
    save(f"noise-{name}", x + noise)
    # benign: mp3 at 48 kbit/s, then 1.1x tempo; must still pass
    tmp = C / f"benign-{name}.mp3"
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ar", str(SR), "-ac", "1", "-i", "-", "-filter:a",
                    "atempo=1.1", "-b:a", "48k", str(tmp)], input=x.astype(np.float32).tobytes(), check=True)
    save(f"benign-{name}", load(tmp))
    tmp.unlink()

(LAB / "out").mkdir(exist_ok=True)
(LAB / "out/scripts.json").write_text(json.dumps(scripts, ensure_ascii=False, indent=1))
(LAB / "out/truth.json").write_text(json.dumps(truth, indent=1))
print(len(list(C.glob("*.wav"))), "clips")
