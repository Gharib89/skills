"""req.py <jsonl> <timestamp-prefix> <out.json>: rebuild the API request logged at that time (system, tools, messages)."""
import json, sys
f, tsp, out = sys.argv[1:4]
blobs, shapes, reqs = {}, {}, []
for line in open(f):
    try: e = json.loads(line)
    except ValueError: continue
    t = e.get("type")
    if t == "api-request-blob": blobs[e["hash"]] = e["message"]
    elif t == "api-request-shape": shapes[e["shapeHash"]] = e["shape"]
    elif t == "api-request": reqs.append(e)
chain = []
for r in reqs:
    chain = chain[:r["keep"]] + r["tail"]
    if r["timestamp"].startswith(tsp): break
else: sys.exit("no request at " + tsp)
sh = shapes[r["shapeHash"]]
msgs = [blobs[h] for h in chain]
json.dump({"system": sh["system"], "tools": sh["tools"], "messages": msgs}, open(out, "w"), ensure_ascii=False)
print("system", [len(b["text"]) for b in sh["system"]], "tools", len(sh["tools"]), sum(len(json.dumps(t, ensure_ascii=False)) for t in sh["tools"]), [t["name"] for t in sh["tools"]])
for i, m in enumerate(msgs):
    c = m["content"]
    if isinstance(c, str): print(i, m["role"], "str", len(c), repr(c[:100])); continue
    for j, b in enumerate(c):
        txt = b.get("text") or json.dumps(b, ensure_ascii=False)
        print(f'{i} {m["role"]} [{j}] {b["type"]} {len(txt):6d} {txt[:120]!r}')
