"""compact.py <label>=<jsonl>... : per compaction, the first call after it and the size (chars) of what was put back."""
import json, sys, collections, statistics as st
rows = []
for arg in sys.argv[1:]:
    label, path = arg.split("=", 1)
    cur, seen = None, set()
    for line in open(path):
        try: e = json.loads(line)
        except ValueError: continue
        if e.get("isSidechain"): continue
        t = e.get("type")
        if t == "system" and e.get("subtype") == "compact_boundary":
            md = e.get("compactMetadata") or {}
            cur = collections.Counter(); cur.update(label=0)
            cur = {"label": label, "ts": e["timestamp"][:16], "v": e.get("version"), "trigger": md.get("trigger"), "pre": md.get("preTokens"),
                   "c": collections.Counter(), "files": [], "done": False}
            rows.append(cur); continue
        if cur is None or cur["done"]: continue
        c = cur["c"]
        if t == "user":
            m = e["message"]["content"]
            txt = m if isinstance(m, str) else "".join(b.get("text", "") or json.dumps(b.get("content", "")) for b in m)
            if e.get("isCompactSummary"): c["summary"] += len(txt)
            elif isinstance(m, list) and any(b["type"] == "tool_result" for b in m): c["tool_result"] += len(txt)
            else: c["user_text"] += len(txt)
        elif t == "attachment":
            a = e["attachment"]; k = a.get("type")
            if k == "prompt_snapshot": continue
            n = len(json.dumps(a, ensure_ascii=False))
            if k == "file":
                c["files"] += n; cur["files"].append((a.get("filename", "?").split("/")[-1], n))
            else: c[k] += n
        elif t == "assistant":
            m = e["message"]
            if m.get("model") == "<synthetic>" or m["id"] in seen: continue
            seen.add(m["id"]); u = m["usage"]
            cur["ctx"] = u["input_tokens"] + u["cache_read_input_tokens"] + u["cache_creation_input_tokens"]
            cur["cr"], cur["cw"] = u["cache_read_input_tokens"], u["cache_creation_input_tokens"]; cur["done"] = True
rows = [r for r in rows if r.get("ctx")]
keys = ["summary", "files", "invoked_skills", "instructions", "skill_listing", "deferred_tools_delta", "deferred_tools_record", "mcp_instructions_delta", "agent_listing_delta", "user_text", "tool_result"]
other = lambda r: sum(v for k, v in r["c"].items() if k not in keys)
print("lab ts               ver     trig  pre    ctx    cr     cw   | " + " ".join(k[:9].rjust(9) for k in keys) + "     other  nfiles")
for r in rows:
    print(f'{r["label"]} {r["ts"]} {r["v"] or "":8s} {r["trigger"] or "":6s}{r["pre"] or 0:6d} {r["ctx"]:6d} {r["cr"]:6d} {r["cw"]:6d} | ' + " ".join(f'{r["c"][k]:9d}' for k in keys) + f' {other(r):9d} {len(r["files"]):3d}')
print("n", len(rows), "ctx median", st.median(r["ctx"] for r in rows), "min", min(r["ctx"] for r in rows), "max", max(r["ctx"] for r in rows))
for k in keys + ["other"]:
    v = [(r["c"][k] if k != "other" else other(r)) for r in rows]
    print(f"{k:24s} min {min(v):7d} median {int(st.median(v)):7d} max {max(v):7d}")
# least squares: ctx ~ a + b*total_chars
import math
xs = [sum(r["c"].values()) for r in rows]; ys = [r["ctx"] for r in rows]
mx, my = st.mean(xs), st.mean(ys); b = sum((x-mx)*(y-my) for x, y in zip(xs, ys)) / sum((x-mx)**2 for x in xs); a = my - b*mx
r2 = 1 - sum((y-(a+b*x))**2 for x, y in zip(xs, ys)) / sum((y-my)**2 for y in ys)
print(f"ctx = {a:.0f} + {b:.3f} * chars put back  (r2 {r2:.2f}); chars min {min(xs)} max {max(xs)}")
json.dump([{**{k: r[k] for k in ("label","ts","v","trigger","pre","ctx","cr","cw")}, "c": dict(r["c"]), "files": r["files"]} for r in rows], open("compactions.json", "w"))
