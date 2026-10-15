# Final per-pair table: house metric vs CER vs transliteration-aware recall/precision, plus rate and MMS confidence.
import difflib, json, re, sys
import numpy as np, soundfile as sf
from common import script_words, is_content, recall, ar_norm
from labels import true_cov, cer

W = json.load(open(sys.argv[1])); S = json.load(open("out/scripts.json")); A = json.load(open("out/align-mms-cuda.json"))


def house(ref, hyp):  # qc-voice.py's rule: difflib matching blocks over content words, no transliteration
    n = lambda t: [re.sub("^(و|ف|ب|ل)?ال", "", ar_norm(b).lower()) for _, b in script_words(t) if is_content(b)]
    a, b = n(ref), n(hyp)
    return sum(k.size for k in difflib.SequenceMatcher(a=a, b=b).get_matching_blocks()) / max(1, len(a))


order = "good benign noise repeat trunc drop splice babble wrong".split()
rows = []
for c, v in W.items():
    if c.startswith("_"): continue
    kind, sid = c.split("-")[:2]
    dur = sf.info(f"clips/{c}.wav").duration
    pairs = [(kind, sid)] + ([("wrong", o) for o in S if o != sid] if kind == "good" else [])
    for k, s in pairs:
        r = recall(S[s], [w[0] for w in v["words"]], 0.6)
        conf = "" if k == "wrong" else f"{np.mean([x[3] for x, (_, b) in zip(A[c], script_words(S[s])) if is_content(b)]):.2f}"
        rows.append((order.index(k), k, f"{sid}/{c.split('-')[4][:2]}", s, true_cov(c) if k != "wrong" else 0.0,
                     house(S[s], v["text"]), cer(S[s], v["text"]), r["recall"], r["precision"], len(S[s]) / dur, conf))
print("| kind | clip | script | true coverage | house match | CER | recall | precision | chars/s | MMS conf |")
print("|---|---|---|---|---|---|---|---|---|---|")
for r in sorted(rows):
    print(f"| {r[1]} | {r[2]} | {r[3]} | {r[4]:.2f} | {r[5]:.2f} | {r[6]:.2f} | **{r[7]:.2f}** | {r[8]:.2f} | {r[9]:.1f} | {r[10]} |")
