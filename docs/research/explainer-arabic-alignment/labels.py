# Ground-truth content coverage of a variant clip, and the #662 CER metric.
import json, re
import soundfile as sf
from common import script_words, is_content, ar_norm, lev
S = json.load(open("out/scripts.json")); A = json.load(open("out/align-mms-cuda.json"))


def true_cov(c):
    kind, sid = c.split("-")[:2]; g = "good-" + c.split("-", 1)[1]
    n = sf.info(f"clips/{g}.wav").duration
    keep = {"trunc": [(0, .65 * n)], "drop": [(0, .35 * n), (.65 * n, n)], "splice": [(0, .35 * n), (.65 * n, n)],
            "babble": []}.get(kind, [(0, n)])
    mids = [(r[1] + r[2]) / 2 for r, (_, b) in zip(A[g], script_words(S[sid])) if is_content(b)]
    return sum(any(a <= m <= b for a, b in keep) for m in mids) / len(mids)


def cer(ref, hyp):
    def n(s):
        s = re.sub("[ً-ْـ]", "", ar_norm(s.lower()))
        return " ".join(re.sub(r"[^\w\s]", " ", s.replace("الـ", "ال").replace("لـ", "ل")).split())
    r, h = n(ref), n(hyp)
    return lev(r, h) / len(r)
