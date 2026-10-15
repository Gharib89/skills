# faster-whisper word timestamps for every clip. Usage: whisper_run.py <model> <device> <compute> [glob] [prompt]
# prompt: none | script (initial_prompt = the clip's script, the biasing a QC must not rely on)
import json, sys, time
from pathlib import Path
from faster_whisper import WhisperModel
from common import load

LAB = Path(__file__).parent
model_id, device, compute = sys.argv[1:4]
glob = sys.argv[4] if len(sys.argv) > 4 else "*.wav"
prompt = sys.argv[5] if len(sys.argv) > 5 else "none"
scripts = json.loads((LAB / "out/scripts.json").read_text())
tag = f"{model_id.split('/')[-1]}-{device}-{prompt}"
outf = LAB / f"out/whisper-{tag}.json"
res = json.loads(outf.read_text()) if outf.exists() else {}
t0 = time.time()
m = WhisperModel(model_id, device=device, compute_type=compute)
load_s = time.time() - t0
audio_s = proc_s = 0
for f in sorted((LAB / "clips").glob(glob)):
    x = load(f)
    sid = f.stem.split("-")[1]
    t = time.time()
    segs, info = m.transcribe(x, language="ar", beam_size=5, word_timestamps=True,
                              initial_prompt=scripts[sid] if prompt == "script" else None)
    segs = list(segs)
    dt = time.time() - t
    audio_s += len(x) / 16000
    proc_s += dt
    res[f.stem] = {"text": " ".join(s.text.strip() for s in segs), "sec": round(dt, 2),
                   "logprob": [round(s.avg_logprob, 3) for s in segs],
                   "words": [[w.word.strip(), round(w.start, 3), round(w.end, 3), round(w.probability, 3)]
                             for s in segs for w in s.words]}
    print(f"{dt:6.2f}s {f.stem}: {res[f.stem]['text'][:80]}", flush=True)
res["_meta"] = {"load_s": round(load_s, 1), "audio_s": round(audio_s, 1), "proc_s": round(proc_s, 1),
                "rtf": round(proc_s / max(audio_s, 1e-9), 3)}
outf.write_text(json.dumps(res, ensure_ascii=False, indent=0))
print(res["_meta"])
