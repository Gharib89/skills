# PROTOTYPE, throwaway: Whisper round-trip error rate for every clip in raw/ (#662).
# English: word error rate. Arabic: character error rate (spelling of Egyptian words varies).
import json, re, subprocess, sys, unicodedata
from pathlib import Path

import numpy as np
from faster_whisper import WhisperModel

HERE = Path(__file__).parent
TEXT = {lang: (HERE / f"script/{lang}.txt").read_text() for lang in ("en", "ar")}


def norm(s, lang):
    s = unicodedata.normalize("NFKC", s.lower())
    if lang == "ar":
        s = re.sub("[ً-ْـ]", "", s)  # tashkeel, tatweel
        s = re.sub("[أإآ]", "ا", s).replace("ى", "ي").replace("ة", "ه").replace("الـ", "ال").replace("لـ", "ل")
    return re.sub(r"[^\w\s]", " ", s).split()


def edit(a, b):
    d = list(range(len(b) + 1))
    for i, x in enumerate(a, 1):
        p, d[0] = d[0], i
        for j, y in enumerate(b, 1):
            p, d[j] = d[j], min(d[j] + 1, d[j - 1] + 1, p + (x != y))
    return d[-1]


def rate(ref, hyp, lang):
    r, h = norm(ref, lang), norm(hyp, lang)
    if lang == "ar":
        r, h = list(" ".join(r)), list(" ".join(h))
    return edit(r, h) / len(r)


model = WhisperModel("deepdml/faster-whisper-large-v3-turbo-ct2", device="cpu", compute_type="int8")
out = {}
# optional args (#676): a glob inside raw/ and the output file
GLOB = sys.argv[1] if len(sys.argv) > 1 else "*.[wm][ap][v3]"
OUT = sys.argv[2] if len(sys.argv) > 2 else "raw/scores.json"
for f in sorted((HERE / "raw").glob(GLOB)):
    lang = f.name[:2]
    # decode with ffmpeg: faster-whisper's PyAV call breaks on this av version
    pcm = subprocess.run(["ffmpeg", "-v", "error", "-i", str(f), "-f", "f32le", "-ac", "1", "-ar", "16000", "-"], capture_output=True, check=True).stdout
    segs, _ = model.transcribe(np.frombuffer(pcm, np.float32), language=lang, beam_size=5)
    hyp = " ".join(s.text for s in segs)
    out[f.stem] = {"rate": round(rate(TEXT[lang], hyp, lang), 3), "hyp": hyp.strip()}
    print(f"{out[f.stem]['rate']:.3f}  {f.stem}", flush=True)
(HERE / OUT).write_text(json.dumps(out, ensure_ascii=False, indent=1))
