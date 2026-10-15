# PROTOTYPE, throwaway: one duck and one master for every score variant (#665).
# Usage: mix.py <name> <bed.wav|none>   writes clips/<name>.m4a and prints its loudness.
import json, re, subprocess, sys
import numpy as np, soundfile as sf
from scipy.signal import resample_poly

SR, CUT = 48000, json.load(open("raw/cut.json"))
N = int(CUT["total"] * SR)
name, bed_path = sys.argv[1], sys.argv[2]

def lufs(path):
    out = subprocess.run(["ffmpeg", "-nostats", "-i", path, "-af", "ebur128=peak=true", "-f", "null", "-"],
                         capture_output=True, text=True).stderr
    tail = out[out.rfind("Summary:"):]
    return float(re.search(r"I:\s+(-?[\d.]+) LUFS", tail).group(1)), float(re.search(r"Peak:\s+(-?[\d.]+) dBFS", tail).group(1))

vo, sr = sf.read("raw/vo.wav", dtype="float64")
voice = np.zeros(N); o = int(CUT["offset"] * SR); voice[o:o + len(vo)] = vo
voice = np.stack([voice, voice], 1)

if bed_path != "none":
    bed, sr = sf.read(bed_path, dtype="float64", always_2d=True)
    if sr != SR: bed = resample_poly(bed, SR, sr, axis=0)
    if bed.shape[1] == 1: bed = np.repeat(bed, 2, 1)
    bed = np.pad(bed, ((0, max(0, N - len(bed))), (0, 0)))[:N]
    # Same pre-duck level for every bed: -20 LUFS integrated over the cut.
    sf.write("raw/_bed.wav", bed, SR); i, _ = lufs("raw/_bed.wav"); bed *= 10 ** ((-20 - i) / 20)
    # Gain curve from word timings: 0 dB on the cards, -6 dB in gaps, -15 dB under speech,
    # dropping 150 ms before a phrase and recovering over 400 ms after it.
    phrases = []
    for s, e in CUT["speech"]:
        if phrases and s - phrases[-1][1] < 0.35: phrases[-1][1] = e
        else: phrases.append([s, e])
    t = np.arange(N) / SR
    db = np.full(N, -6.0)
    db[t < CUT["offset"] - 0.15] = 0.0; db[t > CUT["scenes"][-1]["s"]] = 0.0
    for s, e in phrases: db[(t >= s - 0.15) & (t <= e)] = -15.0
    k = int(0.4 * SR); db = np.convolve(np.pad(db, (k, k), mode="edge"), np.ones(k) / k, "same")[k:-k]
    fade = np.clip((CUT["total"] - t) / 2.0, 0, 1)  # 2 s tail fade
    bed *= (10 ** (db / 20) * fade)[:, None]
    # Bed level under speech relative to the voice, measured on the speech spans only.
    mask = np.zeros(N, bool)
    for s, e in phrases: mask[int(s * SR):int(e * SR)] = True
    under = 10 * np.log10(np.mean(bed[mask] ** 2) / np.mean(voice[mask] ** 2))
else:
    bed, under = np.zeros_like(voice), None

sf.write("raw/_mix.wav", voice + bed, SR, subtype="FLOAT")
first = subprocess.run(["ffmpeg", "-i", "raw/_mix.wav", "-af", "loudnorm=I=-14:TP=-1.5:LRA=11:print_format=json",
                        "-f", "null", "-"], capture_output=True, text=True).stderr
m = json.loads(first[first.rfind("{"):first.rfind("}") + 1])
af = (f"loudnorm=I=-14:TP=-1.5:LRA=11:measured_I={m['input_i']}:measured_TP={m['input_tp']}:"
      f"measured_LRA={m['input_lra']}:measured_thresh={m['input_thresh']}:offset={m['target_offset']}:linear=true")
out = f"clips/{name}.m4a"
subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", "raw/_mix.wav", "-af", af, "-ar", "48000",
                "-c:a", "aac", "-b:a", "192k", out], check=True)
i, tp = lufs(out)
print(json.dumps({"name": name, "lufs": i, "true_peak": tp, "bed_under_voice_db": None if under is None else round(under, 1)}))
