import json, sys
from pathlib import Path
from common import recall
LAB = Path(__file__).parent
W = json.loads((LAB / sys.argv[1]).read_text()); S = json.loads((LAB / "out/scripts.json").read_text())
BLOCK = ("trunc", "drop", "splice", "babble", "wrong")
pairs = []
for clip, v in W.items():
    if clip.startswith("_"): continue
    kind, sid = clip.split("-")[:2]
    pairs.append((kind, sid, v)); pairs += [("wrong", o, v) for o in S if o != sid and kind == "good"]
for tau in (0.5, 0.6, 0.67, 0.75):
    R = []
    for kind, sid, v in pairs:
        r = recall(S[sid], [w[0] for w in v["words"]], tau)
        f1 = 2 * r["recall"] * r["precision"] / max(1e-9, r["recall"] + r["precision"])
        R.append((kind, r["recall"], r["precision"], f1, min(r["recall"], r["precision"])))
    for i, name in ((1, "recall"), (2, "prec"), (3, "F1"), (4, "min(R,P)")):
        g = [x[i] for x in R if x[0] in ("good", "benign")]; b = [x[i] for x in R if x[0] in BLOCK]
        rp = [round(x[i], 2) for x in R if x[0] == "repeat"]; nz = [round(x[i], 2) for x in R if x[0] == "noise"]
        print(f"tau {tau:4} {name:9} good min {min(g):.3f}  block max {max(b):.3f}  margin {min(g)-max(b):+.3f}  repeat {rp}  noise {nz}")
