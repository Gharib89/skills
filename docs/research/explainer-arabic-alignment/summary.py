# One line per Whisper run: does content-word recall at 0.8 classify like true coverage at 0.8?
import json, sys
import numpy as np, soundfile as sf
from common import script_words, is_content, recall
S = json.load(open("out/scripts.json")); A = json.load(open("out/align-mms-cuda.json"))
TAU = 0.6
def true_cov(c):
    kind, sid = c.split("-")[:2]; g = "good-" + c.split("-", 1)[1]
    n = sf.info(f"clips/{g}.wav").duration
    keep = {"trunc": [(0, .65 * n)], "drop": [(0, .35 * n), (.65 * n, n)], "splice": [(0, .35 * n), (.65 * n, n)],
            "babble": []}.get(kind, [(0, n)])
    mids = [(r[1] + r[2]) / 2 for r, (_, b) in zip(A[g], script_words(S[sid])) if is_content(b)]
    return sum(any(a <= m <= b for a, b in keep) for m in mids) / len(mids)
for f in sys.argv[1:]:
    W = json.load(open(f)); rows = []
    for c, v in W.items():
        if c.startswith("_"): continue
        sid = c.split("-")[1]; hyp = [w[0] for w in v["words"]]
        pairs = [(c.split("-")[0], S[sid], true_cov(c))]
        if c.startswith("good-"): pairs += [("wrong", S[o], 0.0) for o in S if o != sid]
        for kind, ref, t in pairs:
            r = recall(ref, hyp, TAU); rows.append((kind, t, r["recall"], r["precision"]))
    ok = [r for r in rows if r[0] != "noise"]
    wrong = [r for r in ok if (r[1] >= 0.8) != (r[2] >= 0.8)]
    good = [r for r in rows if r[0] in ("good", "benign")]
    err = [abs(r[2] - r[1]) for r in ok if r[0] in ("trunc", "drop", "splice")]
    rep = [r[3] for r in rows if r[0] == "repeat"]
    name = f[f.rfind("whisper-") + 8:-5]
    print(f"{name:46} rtf {W['_meta']['rtf']:.3f}  misclassified@0.8 {len(wrong)}/{len(ok)}"
          f"  good recall min {min(r[2] for r in good):.2f}  good prec min {min(r[3] for r in good):.2f}"
          f"  |recall-true| cuts {np.mean(err):.2f}  repeat prec {[round(x, 2) for x in rep]}")
    for r in wrong: print("     ", r)
