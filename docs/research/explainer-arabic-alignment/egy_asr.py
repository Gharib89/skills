# Greedy CTC transcript from the Egyptian wav2vec2, in whisper_run.py's output shape (times unused).
import json, sys, time
from pathlib import Path
import torch
from transformers import Wav2Vec2ForCTC, Wav2Vec2Processor
from common import load
dev = sys.argv[1]
mid = "IbrahimAmin/egyptian-arabic-wav2vec2-xlsr-53"
p = Wav2Vec2Processor.from_pretrained(mid); m = Wav2Vec2ForCTC.from_pretrained(mid).to(dev).eval()
out, a, pr = {}, 0, 0
for f in sorted(Path("clips").glob("*.wav")):
    x = load(f); t = time.time()
    with torch.inference_mode():
        lg = m(p(x, sampling_rate=16000, return_tensors="pt").input_values.to(dev)).logits
    text = p.batch_decode(lg.argmax(-1))[0]
    pr += time.time() - t; a += len(x) / 16000
    out[f.stem] = {"text": text, "words": [[w, 0, 0, 1] for w in text.split()]}
out["_meta"] = {"rtf": round(pr / a, 3)}
Path(f"out/whisper-egyasr-{dev}.json").write_text(json.dumps(out, ensure_ascii=False))
print(out["_meta"])
