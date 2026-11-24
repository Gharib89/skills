#!/usr/bin/env python3
"""Count the pinned super agent's wakes and their token use from Claude Code transcripts.

    super-agent-wake-count.py [--split <label>:<iso-date>] <label>=<transcript.jsonl>...

A wake is a turn start: a user entry that is neither a tool result nor
compaction or slash-command boilerplate. Its turn runs to the next turn start.
Tokens are summed once per API call (the last entry of each message id), so
subagent calls and the compaction's own summary call are not counted.
`--split` reports a session's wakes from that date on as a separate group.

A wake "changed something" when its turn made a changing call (CHANGING_BASH,
CHANGING_TOOLS). Reconcile's own ledger writes and a watcher restart are not
changes. Weighted tokens use the relative prices input 1, cache write 2,
cache read 0.1, output 5.

One-off count for a wayfinder ticket: the scorecard script replaces it.
"""
import collections
import json
import re
import statistics
import sys

SKIP = ("<local-command-", "<command-name>/compact", "<command-name>/reload-skills", "<command-name>/model",
        "This session is being continued", "Base directory for this skill", "[Image:", "<system-reminder>",
        "(Re-invocation of")
LEDGER_WRITE = (r"ledger\.sh[^|;&\n]*?\s(add|adopt|set|rethread|ruling|pin|migrate-rulings|wait|unwait|need|pushed"
                r"|unneed|limit|unlimit|pause|unpause|drop|reset-stalls)\b")
CHANGING_BASH = [
    LEDGER_WRITE, r"launch\.sh", r"claim\.sh", r"worktree\.sh[^|;&\n]*\sremove", r"merge\.sh", r"cleanup\.sh",
    r"reply\.sh", r"intake\.sh", r"handover\.sh",
    r"\bgh\s+(issue|pr)\s+(edit|close|comment|create|reopen|merge|review|ready)",
    r"\bgh\s+api\b[^|;&\n]*(-X|--method)\s*(POST|PATCH|PUT|DELETE)", r"\bgh\s+api\b[^|;&\n]*\s-[fF]\s",
    r"\bgit\s+(commit|push|merge|worktree\s+(add|remove)|branch\s+-[dD])", r"\bt3\s+thread\s+(send|launch|interrupt)",
    r"chezmoi\s+apply", r"npx\s+skills",
]
CHANGING_TOOLS = {
    "mcp__t3-code__t3_thread_launch": "launch", "mcp__t3-code__t3_thread_send": "send",
    "mcp__t3-code__t3_thread_organize": "cleanup", "AskUserQuestion": "ask", "PushNotification": "ask",
    "mcp__t3-code__t3_thread_interrupt": "other", "mcp__t3-code__t3_thread_configure": "other",
    "mcp__t3-code__schedule_task": "other", "mcp__t3-code__delete_scheduled_task": "other",
    "mcp__t3-code__delegate_task": "other", "mcp__t3-code__link_pull_request": "other",
    "Write": "other", "Edit": "other", "Agent": "other", "Artifact": "other",
}
WATCHER = re.compile(r"watch(-fired|-thread|-\d+)?\.sh")
CAUSES = ["watcher", "backstop", "owner", "compaction resume", "other background", "other scheduled",
          "restart or harness", "other"]
M = 1e6


def text_of(content):
    if isinstance(content, str):
        return content
    if any(b.get("type") == "tool_result" for b in content):
        return None
    return " ".join(b.get("text", "") for b in content if b.get("type") == "text")


def cause(entry, text, background):
    kind = (entry.get("origin") or {}).get("kind")
    if text.startswith("<task-notification>"):
        m = re.search(r"<tool-use-id>(.*?)</tool-use-id>", text)
        cmd = background.get(m.group(1), "") if m else ""
        return "watcher" if WATCHER.search(cmd) or re.search(r"watch", text[:400], re.I) else "other background"
    if text.startswith("[T3 Code:"):
        if "scheduled task" not in text[:60]:
            return "other"
        return "backstop" if "Backstop:" in text or "Wake: reconcile" in text else "other scheduled"
    if text.startswith(("Wake: reconcile", "Backstop:")):
        return "backstop"
    if text.startswith(("Morning report", "Wake:", "Quota launch wake")):
        return "other scheduled"
    if kind == "plugin" or text.startswith("The smart-compact plugin"):
        return "compaction resume"
    if kind == "peer" or text.startswith("Another Claude session"):
        return "other"
    if text.startswith(("Note: the T3 server restarted", "[Your previous response", "Continue where you left off")):
        return "restart or harness"
    return "owner"


def bash_kind(cmd):
    if re.search(r"launch\.sh|t3\s+thread\s+launch", cmd):
        return "launch"
    if re.search(r"reply\.sh|t3\s+thread\s+send", cmd):
        return "send"
    if re.search(r"worktree\.sh|cleanup\.sh", cmd):
        return "cleanup"
    return "ledger" if re.search(LEDGER_WRITE, cmd) else "other"


def read(label, path):
    wakes, background, seen, cur = [], {}, {}, None
    for line in open(path):
        try:
            e = json.loads(line)
        except ValueError:
            continue
        if e.get("isSidechain"):
            continue
        if e.get("type") == "user":
            t = text_of(e["message"]["content"])
            if t is None or e.get("isCompactSummary") or e.get("isMeta") or t.lstrip().startswith(SKIP):
                continue
            cur = {"grp": label, "ts": e.get("timestamp", ""), "cause": cause(e, t.lstrip(), background),
                   "tok": collections.Counter(), "models": set(), "kinds": set(), "api": 0, "chars": 0}
            wakes.append(cur)
        elif e.get("type") == "assistant" and cur is not None:
            m = e["message"]
            if m.get("model") == "<synthetic>":
                continue
            u = m.get("usage") or {}
            vals = {"in": u.get("input_tokens", 0), "cw": u.get("cache_creation_input_tokens", 0),
                    "cr": u.get("cache_read_input_tokens", 0), "out": u.get("output_tokens", 0)}
            prev = seen.get(m.get("id"))
            owner = prev[0] if prev else cur
            if prev:
                owner["tok"].subtract(prev[1])
            else:
                cur["api"] += 1
            owner["tok"].update(vals)
            seen[m.get("id")] = (owner, vals)
            cur["models"].add(m.get("model"))
            for b in m.get("content", []):
                if b.get("type") == "text":
                    cur["chars"] += len(b["text"])
                elif b.get("type") == "tool_use" and b["name"] == "Bash":
                    cmd = b["input"].get("command", "")
                    if b["input"].get("run_in_background"):
                        background[b["id"]] = cmd
                    if any(re.search(p, cmd) for p in CHANGING_BASH):
                        cur["kinds"].add(bash_kind(cmd))
                        if re.search(r"ledger\.sh[^|;&\n]*?\sneed\b", cmd):
                            cur["kinds"].add("ask")
                elif b.get("type") == "tool_use" and b["name"] in CHANGING_TOOLS:
                    cur["kinds"].add(CHANGING_TOOLS[b["name"]])
    return wakes


def total(t):
    return t["in"] + t["cw"] + t["cr"] + t["out"]


def weighted(t):
    return t["in"] + 2 * t["cw"] + 0.1 * t["cr"] + 5 * t["out"]


def main(argv):
    splits, wakes, groups = {}, [], []
    args = iter(argv)
    for a in args:
        if a == "--split":
            label, date = next(args).split(":", 1)
            splits[label] = date
            continue
        label, path = a.split("=", 1)
        groups.append(label)
        wakes += read(label, path)
    for label, date in splits.items():
        late = f"{label} from {date}"
        groups.insert(groups.index(label) + 1, late)
        for w in wakes:
            if w["grp"] == label and w["ts"] >= date:
                w["grp"] = late
    wakes = [w for w in wakes if w["api"]]
    routine = ("watcher", "backstop")
    for g in groups + ["ALL"]:
        ws = [w for w in wakes if g in ("ALL", w["grp"])]
        T, C = sum(total(w["tok"]) for w in ws), sum(weighted(w["tok"]) for w in ws)
        models = dict(collections.Counter(m for w in ws for m in w["models"]))
        print(f"\n## {g}: {len(ws)} wakes, {T / M:.1f}M tokens, {C / M:.1f}M weighted, models {models}")
        print("cause | wakes | no change | tokens M | weighted M | share | no-change weighted M | share")
        for c in CAUSES + ["routine", "all"]:
            sel = [w for w in ws if c == "all" or w["cause"] == c or (c == "routine" and w["cause"] in routine)]
            if not sel:
                continue
            nc = [w for w in sel if not w["kinds"]]
            k, knc = sum(weighted(w["tok"]) for w in sel), sum(weighted(w["tok"]) for w in nc)
            print(f"{c} | {len(sel)} | {len(nc)} | {sum(total(w['tok']) for w in sel) / M:.1f} | {k / M:.1f} "
                  f"| {100 * k / C:.0f}% | {knc / M:.1f} | {100 * knc / C:.0f}%")
        ch = [w for w in ws if w["cause"] in routine and w["kinds"]]
        book = [w for w in ch if w["kinds"] <= {"cleanup", "ledger"}]
        judged = [w for w in ch if w["kinds"] & {"send", "ask", "other"}]
        launch = [w for w in ch if w not in book and w not in judged]
        print("changed routine wakes: " + ", ".join(
            f"{name} {len(sel)} ({sum(weighted(w['tok']) for w in sel) / M:.1f}M, "
            f"{100 * sum(weighted(w['tok']) for w in sel) / C:.0f}%)"
            for name, sel in (("bookkeeping only", book), ("launch only", launch), ("send, ask or other", judged))))
    print("\n## Per wake: cause, changed, wakes, median API calls, median context per call k, median weighted k")
    for c in ("watcher", "backstop", "owner"):
        for changed in (False, True):
            sel = [w for w in wakes if w["cause"] == c and bool(w["kinds"]) == changed]
            if sel:
                ctx = statistics.median((total(w["tok"]) - w["tok"]["out"]) / w["api"] for w in sel)
                print(c, "changed" if changed else "no change", len(sel), statistics.median(w["api"] for w in sel),
                      round(ctx / 1e3), round(statistics.median(weighted(w["tok"]) for w in sel) / 1e3))
    print("\n## Per day: date, watcher, backstop, owner, routine wakes that changed nothing")
    days = collections.defaultdict(collections.Counter)
    for w in wakes:
        days[w["ts"][:10]][w["cause"]] += 1
        if w["cause"] in routine and not w["kinds"]:
            days[w["ts"][:10]]["nochange"] += 1
    for d in sorted(days):
        print(d, days[d]["watcher"], days[d]["backstop"], days[d]["owner"], days[d]["nochange"])


if __name__ == "__main__":
    main(sys.argv[1:])
