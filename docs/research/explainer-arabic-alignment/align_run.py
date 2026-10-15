# CTC forced alignment of each clip's script. Usage: align_run.py <mms|egy> <cpu|cuda> [glob]
#   mms: torchaudio MMS_FA bundle (uroman romanisation, so Arabic and English share one Latin alphabet)
#   egy: IbrahimAmin/egyptian-arabic-wav2vec2-xlsr-53 (Arabic letters; English terms transliterated by rule)
import json, re, sys, time
from pathlib import Path
import torch, torchaudio.functional as F
from common import load, script_words, ar_norm, LETTER

LAB = Path(__file__).parent
method, device = sys.argv[1:3]
glob = sys.argv[3] if len(sys.argv) > 3 else "*.wav"
scripts = json.loads((LAB / "out/scripts.json").read_text())

EN2AR = (("tch", "تش"), ("sh", "ش"), ("ch", "تش"), ("th", "ث"), ("ph", "ف"), ("ck", "ك"), ("qu", "كو"),
         ("ce", "سي"), ("ci", "سي"), ("c", "ك"), ("g", "ج"), ("j", "ج"), ("k", "ك"), ("q", "ك"), ("x", "كس"),
         ("p", "ب"), ("v", "ف"), ("w", "و"), ("y", "ي"), ("z", "ز"), ("b", "ب"), ("d", "د"), ("f", "ف"),
         ("h", "ه"), ("l", "ل"), ("m", "م"), ("n", "ن"), ("r", "ر"), ("s", "س"), ("t", "ت"), ("a", "ا"),
         ("e", "ي"), ("i", "ي"), ("o", "و"), ("u", "و"))


def spoken(display):
    """Text as spoken: tatweel clitic joined, acronyms as letter names."""
    w = display.replace("ـ", "").replace(" ", "")
    return re.sub("[A-Z]{2,4}$", lambda m: "".join(LETTER[c] for c in m.group()), w)


def to_arabic(w):
    w = ar_norm(w)
    lat = re.sub("[^A-Za-z]", "", w).lower()
    if not lat:
        return w
    lat = re.sub("e$", "", lat)
    for a, b in EN2AR:
        lat = lat.replace(a, b)
    return re.sub("[A-Za-z]+", "", w) + re.sub(r"(.)\1+", r"\1", lat)


t0 = time.time()
if method == "mms":
    from torchaudio.pipelines import MMS_FA as B
    import uroman as ur
    U = ur.Uroman()
    model = B.get_model(with_star=False).to(device)
    vocab = B.get_dict(star=None)
    blank = 0

    def targets(word):
        return [vocab[c] for c in U.romanize_string(spoken(word)).lower() if c in vocab]

    def emit(x):
        with torch.inference_mode():
            e, _ = model(torch.from_numpy(x)[None].to(device))
        return torch.log_softmax(e, -1)
else:
    from transformers import Wav2Vec2ForCTC, Wav2Vec2Processor
    mid = "IbrahimAmin/egyptian-arabic-wav2vec2-xlsr-53"
    proc = Wav2Vec2Processor.from_pretrained(mid)
    model = Wav2Vec2ForCTC.from_pretrained(mid).to(device).eval()
    vocab = proc.tokenizer.get_vocab()
    blank = proc.tokenizer.pad_token_id

    def targets(word):
        return [vocab[c] for c in to_arabic(spoken(word)) if c in vocab]

    def emit(x):
        inp = proc(x, sampling_rate=16000, return_tensors="pt").input_values.to(device)
        with torch.inference_mode():
            return torch.log_softmax(model(inp).logits, -1)
load_s = time.time() - t0

out, audio_s, proc_s = {}, 0, 0
for f in sorted((LAB / "clips").glob(glob)):
    sid = f.stem.split("-")[1]
    words = [d for d, _ in script_words(scripts[sid])]
    x = load(f)
    t = time.time()
    em = emit(x)
    toks = [targets(w) for w in words]
    sep = [vocab["|"]] if method == "egy" else []  # egy was trained with a word separator
    flat = [t for i, tk in enumerate(toks) for t in (sep if i else []) + tk]
    ali, sc = F.forced_align(em, torch.tensor([flat], dtype=torch.int32, device=device), blank=blank)
    ali, sc = ali[0].cpu(), sc[0].exp().cpu()
    spans = F.merge_tokens(ali, sc, blank=blank)
    sec = len(x) / 16000 / em.shape[1]
    res, k = [], 0
    for w, tk in zip(words, toks):
        sp = spans[k:k + len(tk)]
        k += len(tk) + len(sep)
        res.append([w, round(sp[0].start * sec, 3), round(sp[-1].end * sec, 3),
                    round(sum(s.score * (s.end - s.start) for s in sp) / sum(s.end - s.start for s in sp), 3)])
    dt = time.time() - t
    audio_s += len(x) / 16000
    proc_s += dt
    out[f.stem] = res
out["_meta"] = {"load_s": round(load_s, 1), "audio_s": round(audio_s, 1), "proc_s": round(proc_s, 1),
                "rtf": round(proc_s / audio_s, 3)}
(LAB / f"out/align-{method}-{device}.json").write_text(json.dumps(out, ensure_ascii=False, indent=0))
print(out["_meta"])
