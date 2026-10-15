# PROTOTYPE, throwaway: the 30 s cut's scene timings from the narration's sentences (#665).
import json
OFF, TOTAL = 3.0, 30.0
words = json.load(open("raw/words.json"))
scenes, start, text = [{"name": "Title card", "s": 0.0}], None, []
for w in words:
    if start is None: start = w["s"]
    text.append(w["w"])
    if w["w"].endswith("."):
        scenes.append({"name": " ".join(text), "s": round(OFF + start - 0.25, 2)}); start, text = None, []
scenes.append({"name": "End card", "s": round(OFF + words[-1]["e"] + 0.6, 2)})
for a, b in zip(scenes, scenes[1:] + [{"s": TOTAL}]): a["e"] = b["s"]
json.dump({"offset": OFF, "total": TOTAL, "scenes": scenes,
           "speech": [[round(OFF + w["s"], 3), round(OFF + w["e"], 3)] for w in words]}, open("raw/cut.json", "w"), indent=1)
for s in scenes: print(f'{s["s"]:6.2f}-{s["e"]:6.2f}  {s["name"][:60]}')
