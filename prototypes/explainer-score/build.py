# PROTOTYPE, throwaway: blind letters, reveal key and the published page folder (#665).
# Reads clips/<variant>.m4a and raw/loudness.json (one line per mix.py run).
import json, random, shutil
from pathlib import Path

VARIANTS = {
    "synth-arranged": ("Code synth, arranged to the scenes", "Own code (motioncraft engine, MIT)",
                       "motioncraft music make, preset calm-punch (102 BPM, F, marimba), drop at 20.5 s: intro, groove and main sections built around the cut"),
    "synth-loop": ("Code synth, looped bed", "Own code (house gen-music.py)",
                   "The house pipeline's numpy bed (92 BPM, A minor pads, arp and beat sections), played from the top and cut at 30 s, blind to the scenes"),
    "ace-step": ("ACE-Step 1.5 2B turbo", "MIT weights and code, opt-in model",
                 "Instrumental at 100 BPM in F major so bar 10 lands on the end card at 24.0 s; DiT only, float32 on the CPU (on this RTX 2070 the GPU path is float16 and produced NaN), seed 665"),
}
loud = {r["name"]: r for r in map(json.loads, Path("raw/loudness.json").read_text().splitlines())}
names = [n for n in VARIANTS if n in loud]
random.Random(665).shuffle(names)
out = Path("page/out"); shutil.rmtree(out, ignore_errors=True); (out / "clips").mkdir(parents=True)
key = []
for letter, n in zip("ABC", names):
    shutil.copy(f"clips/{n}.m4a", out / f"clips/{letter}.mp4")
    title, lic, how = VARIANTS[n]
    key.append({"id": letter, "variant": n, "name": title, "licence": lic, "how": how,
                "lufs": loud[n]["lufs"], "true_peak": loud[n]["true_peak"], "bed_under_voice_db": loud[n]["bed_under_voice_db"]})
shutil.copy("clips/no-score.m4a", out / "clips/no-score.mp4")
r = loud["no-score"]
key.append({"id": "no-score", "variant": "no-score", "name": "No score", "licence": "n/a", "how": "Narration only",
            "lufs": r["lufs"], "true_peak": r["true_peak"], "bed_under_voice_db": None})
(out / "key.json").write_text(json.dumps(key, indent=1))
cut = json.loads(Path("raw/cut.json").read_text())
html = Path("page/index.html").read_text().replace("__CUT__", json.dumps(cut)).replace("__LETTERS__", json.dumps("ABC"[:len(names)]))
(out / "index.html").write_text(html)
print(json.dumps(key, indent=1))
