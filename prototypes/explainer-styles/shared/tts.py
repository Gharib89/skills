# PROTOTYPE, throwaway (#664): narrate script.json with Kokoro, one clip per scene, word timings from Kokoro's tokens.
import json
from pathlib import Path
import numpy as np, soundfile as sf
from kokoro import KPipeline

HERE = Path(__file__).parent
S = json.loads((HERE / "script.json").read_text())
SR, GAP = 24000, 0.3  # pause between scenes, seconds
pipe = KPipeline(lang_code=S["voice"][0], repo_id="hexgrad/Kokoro-82M")
audio, t, scenes = [], 0.0, []
for sc in S["scenes"]:
    words, parts = [], []
    for r in pipe(sc["text"], voice=S["voice"]):
        off = sum(len(p) for p in parts) / SR
        for tok in r.tokens:
            if tok.start_ts is None or not tok.text.strip(" ") or not any(c.isalnum() for c in tok.text):
                continue
            words.append({"w": tok.text + (tok.whitespace and "" or ""), "s": round(t + off + tok.start_ts, 3), "e": round(t + off + tok.end_ts, 3)})
        parts.append(r.audio.numpy())
    a = np.concatenate(parts)
    a = a[: int((words[-1]["e"] - t + 0.25) * SR)]  # trim Kokoro trailing silence
    dur = len(a) / SR
    scenes.append({"id": sc["id"], "start": round(t, 3), "end": round(t + dur, 3), "text": sc["text"], "words": words})
    audio += [a, np.zeros(int(GAP * SR), dtype=a.dtype)]
    t += dur + GAP
sf.write(HERE / "narration.wav", np.concatenate(audio), SR)
total = round(t + 0.4, 2)
(HERE / "timing.json").write_text(json.dumps({"duration": total, "scenes": scenes, "arabic": S["arabic"]}, ensure_ascii=False, indent=1))
print("duration", total); [print(s["id"], s["start"], s["end"], len(s["words"])) for s in scenes]
