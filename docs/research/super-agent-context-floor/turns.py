"""turns.py <label>=<jsonl>... : the calls after each fresh start and each compaction, with what sits between them."""
import json, sys
LIMIT = 7
def short(x, n=90): return " ".join(str(x).split())[:n]
for arg in sys.argv[1:]:
    label, path = arg.split("=", 1)
    seen, pending, n_after, mode = set(), [], None, None
    print(f"\n##### {label}")
    for line in open(path):
        try: e = json.loads(line)
        except ValueError: continue
        if e.get("isSidechain"): continue
        t = e.get("type")
        if n_after is None and t in ("user",) and mode is None:
            mode = "fresh"; n_after = 0; print(f"== fresh start {e.get('timestamp')} v{e.get('version')}")
        if t == "system" and e.get("subtype") == "compact_boundary":
            md = e.get("compactMetadata") or {}
            print(f"== compaction {e.get('timestamp')} trigger={md.get('trigger')} pre={md.get('preTokens')} v{e.get('version')} md={ {k:v for k,v in md.items() if k not in ('trigger','preTokens')} }".replace("\n"," ")[:400])
            n_after = 0; pending = []; continue
        if n_after is None or n_after >= LIMIT: continue
        if t == "user":
            c = e["message"]["content"]
            if isinstance(c, str): pending.append(f"user-text[{len(c)}]{' SUMMARY' if e.get('isCompactSummary') else ''}{' meta' if e.get('isMeta') else ''} {short(c,70)}")
            else:
                for b in c:
                    if b["type"] == "tool_result":
                        cc = b.get("content"); s = cc if isinstance(cc, str) else json.dumps(cc)
                        pending.append(f"tool_result[{len(s)}] {short(s,60)}")
                    elif b["type"] == "text":
                        pending.append(f"user-text[{len(b['text'])}]{' SUMMARY' if e.get('isCompactSummary') else ''}{' meta' if e.get('isMeta') else ''} {short(b['text'],70)}")
        elif t == "attachment":
            a = e["attachment"];
            extra = a.get("filename") or a.get("hookName") or a.get("skillName") or ""
            pending.append(f"att:{a.get('type')}[{len(json.dumps(a))}] {extra}")
        elif t == "assistant":
            m = e["message"]
            if m.get("model") == "<synthetic>": continue
            for b in m["content"]:
                if b["type"] == "tool_use": pending.append(f"  -> {b['name']} {short(json.dumps(b['input']),110)}")
            if m["id"] in seen: continue
            seen.add(m["id"]); u = m["usage"]
            ctx = u["input_tokens"] + u["cache_read_input_tokens"] + u["cache_creation_input_tokens"]
            for p in pending[:-0 or None]:
                if not p.startswith("  ->"): print("     ", p)
            print(f"  call {n_after+1}: ctx={ctx} (cr={u['cache_read_input_tokens']} cw={u['cache_creation_input_tokens']} in={u['input_tokens']}) out={u['output_tokens']} {m.get('model')}")
            for p in pending:
                if p.startswith("  ->"): print("     ", p)
            pending = []; n_after += 1

