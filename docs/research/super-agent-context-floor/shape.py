"""shape.py <jsonl>... : the first logged API request of each transcript as named parts with character counts, side by side."""
import json, re, sys, collections
SEC = r'\n\n(?=(?:# Environment|You are powered|# Output Style|The following deferred|The following MCP servers require|The following MCP servers are still|Available agent types|# MCP Server Instructions|The following skills are available|Concise output style is active|SessionStart|Today|When you launch))'
def parts(path):
    blobs, shapes, req = {}, {}, None
    for line in open(path):
        try: e = json.loads(line)
        except ValueError: continue
        t = e.get("type")
        if t == "api-request-blob": blobs[e["hash"]] = e["message"]
        elif t == "api-request-shape": shapes[e["shapeHash"]] = e["shape"]
        elif t == "api-request" and req is None and e.get("querySource") in ("sdk", "repl_main_thread", "print", None) : req = e
        elif t == "api-request" and req is None: print("skip source", e.get("querySource"), file=sys.stderr)
    out = collections.OrderedDict()
    sh = shapes[req["shapeHash"]]
    for i, b in enumerate(sh["system"]):
        t = b["text"]; j = t.find("# Claude in Chrome browser automation")
        if j >= 0: out[f"system[{i}] core"] = j; out["system: chrome instructions"] = len(t) - j
        elif "<runtime_info>" in t: j = t.find("<runtime_info>"); out[f"system[{i}] core"] = j; out["system: T3 append"] = len(t) - j
        else: out[f"system[{i}]"] = len(t)
    for t in sh["tools"]: out["tool " + t["name"]] = len(json.dumps(t, ensure_ascii=False))
    for h in req["tail"]:
        c = blobs[h]["content"]
        for b in ([{"type": "text", "text": c}] if isinstance(c, str) else c):
            t = b.get("text", "")
            if "Codebase and user instructions" in t:
                idx = [(m.start(), m.group(1)) for m in re.finditer(r"Contents of (\S+) \(", t)]
                for n, (st, name) in enumerate(idx):
                    en = idx[n+1][0] if n+1 < len(idx) else len(t)
                    k = "ins: global CLAUDE.md" if name.endswith("/.claude/CLAUDE.md") else "ins: global rules" if "/rules/" in name else "ins: project CLAUDE.md"
                    out[k] = out.get(k, 0) + en - st
            elif "you can use the following context" in t: out["msg: context (email, git status)"] = len(t)
            elif len(t) > 3000 or t.startswith("SessionStart") or "# Environment" in t:
                for p in re.split(SEC, t):
                    k = "sm: " + " ".join(p[:46].split())
                    if p.startswith("The following skills are available"): k = "sm: skills listing"
                    out[k] = out.get(k, 0) + len(p)
            else: out["msg: " + " ".join(t[:40].split())] = len(t)
    return out
cols = [parts(p) for p in sys.argv[1:]]
keys = []
for c in cols:
    for k in c:
        if k not in keys: keys.append(k)
for k in keys: print(" ".join(f"{c.get(k, 0):7d}" for c in cols), k)
print(" ".join(f"{sum(c.values()):7d}" for c in cols), "TOTAL chars")
