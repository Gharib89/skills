import json, re, os, sys
src, out = sys.argv[1], sys.argv[2]
r = json.load(open(src)); os.makedirs(out, exist_ok=True)
def w(name, text): open(f"{out}/{name}.txt", "w").write(text)
sysb = [b["text"] for b in r["system"]]
w("sys-0-identity", sysb[0])
s1 = sysb[1]; i = s1.find("# Claude in Chrome browser automation")
w("sys-1a-harness-core", s1[:i]); w("sys-1b-chrome-instructions", s1[i:])
s2 = sysb[2]; i = s2.find("<runtime_info>")
w("sys-2a-harness-dynamic", s2[:i]); w("sys-2b-t3-append", s2[i:])
tools = {t["name"]: json.dumps(t, ensure_ascii=False) for t in r["tools"]}
w("tool-Artifact", tools.pop("Artifact"))
t3 = "\n".join(v for k, v in tools.items() if k.startswith("mcp__t3"))
for k in [k for k in tools if k.startswith("mcp__t3")]: tools.pop(k)
w("tool-t3-two", t3)
for k in ("Agent", "AskUserQuestion", "Workflow", "Bash"): w(f"tool-{k}", tools.pop(k))
w("tool-rest", "\n".join(tools.values())); print("rest tools:", list(tools))
# first user message
m0 = r["messages"][0]["content"]
ins = next(b["text"] for b in m0 if "Codebase and user instructions" in b["text"])
idx = [(m.start(), m.group(1)) for m in re.finditer(r"Contents of (\S+) \(", ins)]
seg = {}
for n, (st, name) in enumerate(idx):
    en = idx[n+1][0] if n+1 < len(idx) else len(ins)
    key = "ins-global-claude-md" if name.endswith("/.claude/CLAUDE.md") else "ins-global-rules" if "/rules/" in name else "ins-project-claude-md"
    seg[key] = seg.get(key, "") + ins[st:en]
seg["ins-global-claude-md"] = ins[:idx[0][0]] + seg["ins-global-claude-md"]
for k, v in seg.items(): w(k, v)
for b in m0:
    t = b["text"]
    if t is ins: continue
    if "you can use the following context" in t: w("msg-context-email-git", t)
    elif t.startswith("<system-reminder>\nAttribution"): w("msg-attribution", t)
    elif t.startswith("<command-message>"): w("msg-command-line", t)
    elif t.startswith("Base directory for this skill"): w("skill-md", t)
    elif "SUMMARY" in t or t.startswith("This session is being continued"): w("compact-summary", t)
    else: print("UNSORTED m0 block", len(t), repr(t[:80]))
if len(sys.argv) > 3: sys.exit()
s = r["messages"][1]["content"][0]["text"]
parts = re.split(r'\n\n(?=(?:# Environment|You are powered|# Output Style|The following deferred|The following MCP servers require|Available agent types|# MCP Server Instructions|The following skills are available|Concise output style is active))', s)
names = ["sm-hook-last30days", "sm-environment", "sm-model", "sm-output-style", "sm-deferred-tools-list", "sm-mcp-auth-connecting", "sm-agent-types", "sm-mcp-instructions", "sm-skills-listing", "sm-tail-style-date"]
assert len(parts) == len(names), [p[:40] for p in parts]
for n, p in zip(names, parts): w(n, p)
# classify skills in the listing
sk = parts[8]; head, *items = re.split(r"\n(?=- [\w:.-]+(?: \([\w-]+\))?: )", sk)
cls = {"user": [], "project": [], "plugin": [], "builtin": []}
for it in items:
    name = re.match(r"- ([\w:.-]+?)(?: \([\w-]+\))?: ", it).group(1)
    base = name.split(":")[0]
    if ":" in name: c = "plugin"
    elif os.path.isdir(os.path.expanduser(f"~/.claude/skills/{name}")): c = "user"
    elif os.path.isdir(f".claude/skills/{name}"): c = "project"
    else: c = "builtin"
    cls[c].append(it)
for c, v in cls.items():
    w(f"skills-{c}", "\n".join(v)); print(c, len(v), sum(map(len, v)), [re.match(r"- ([\w:.-]+?)(?: \([\w-]+\))?: ", i).group(1) for i in v])
