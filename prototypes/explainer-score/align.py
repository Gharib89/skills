# PROTOTYPE, throwaway: word timings for the narration, used to place the duck (#665).
import json, sys
from faster_whisper import WhisperModel
m = WhisperModel("small.en", device="cpu", compute_type="int8")
import soundfile as sf, numpy as np
from scipy.signal import resample_poly
a, sr = sf.read("raw/vo.wav", dtype="float32")
segs, _ = m.transcribe(resample_poly(a, 1, 3).astype(np.float32), word_timestamps=True, language="en")
words = [{"w": w.word.strip(), "s": round(w.start, 3), "e": round(w.end, 3)} for s in segs for w in s.words]
json.dump(words, open("raw/words.json", "w"), indent=0)
print(len(words), words[0], words[-1])
