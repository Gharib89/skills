#!/usr/bin/env python3
"""Context per API call in the pinned super agent's transcripts.

    super-agent-context-per-wake.py <label>=<transcript.jsonl>...

Follows super-agent-wake-count.py (beside this file) and reuses its wake
split, cause() and changing-call tables. Context of a call is input plus cache
read plus cache write tokens. Prints the floors, the compactions, the growth
per wake, what a cap would save, spend by token type, the gaps between wakes
and the context by a session's day of life. Read-only.

One-off count for a wayfinder ticket: the scorecard script replaces it.
"""
import collections
import datetime
import importlib.util
import json
import pathlib
import re
import statistics as st
import sys

_spec = importlib.util.spec_from_file_location(
    "wake_count", pathlib.Path(__file__).with_name("super-agent-wake-count.py"))
o = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(o)

ROUTINE = ("watcher", "backstop")


def ts(s):
    return datetime.datetime.fromisoformat(s.replace("Z", "+00:00"))


def ctx(c):
    v = c["vals"]
    return v["in"] + v["cr"] + v["cw"]


def wt(v, scale=1.0):
    return scale * (v["in"] + 2 * v["cw"] + 0.1 * v["cr"]) + 5 * v["out"]


def read(label, path):
    """Same wake split as the original read(), keeping every API call."""
    wakes, background, seen, cur = [], {}, {}, None
    calls, compacts, seg = [], [], 0
    compact_now_since_wake = False
    slash = []  # (/compact user entries: origin kind)
    for line in open(path):
        try:
            e = json.loads(line)
        except ValueError:
            continue
        if e.get("isSidechain"):
            continue
        if e.get("type") == "system" and e.get("subtype") == "compact_boundary":
            md = e.get("compactMetadata") or {}
            seg += 1
            compacts.append({"grp": label, "ts": e["timestamp"], "trigger": md.get("trigger"),
                             "pre": md.get("preTokens"), "seg": seg, "last": calls[-1] if calls else None,
                             "tool": compact_now_since_wake, "origin": None, "first_after": None})
            continue
        if e.get("type") == "user":
            c = e["message"]["content"]
            t = o.text_of(c)
            if t is not None and t.lstrip().startswith("<command-name>/compact") and compacts:
                compacts[-1]["origin"] = (e.get("origin") or {}).get("kind") or "typed"
            if t is None or e.get("isCompactSummary") or e.get("isMeta") or t.lstrip().startswith(o.SKIP):
                continue
            cur = {"grp": label, "ts": e.get("timestamp", ""), "cause": o.cause(e, t.lstrip(), background),
                   "kinds": set(), "calls": [], "end": e.get("timestamp", "")}
            wakes.append(cur)
            compact_now_since_wake = False
        elif e.get("type") == "assistant" and cur is not None:
            m = e["message"]
            if m.get("model") == "<synthetic>":
                continue
            u = m.get("usage") or {}
            cc = u.get("cache_creation") or {}
            vals = {"in": u.get("input_tokens", 0), "cw": u.get("cache_creation_input_tokens", 0),
                    "cr": u.get("cache_read_input_tokens", 0), "out": u.get("output_tokens", 0),
                    "cw1h": cc.get("ephemeral_1h_input_tokens", 0), "cw5m": cc.get("ephemeral_5m_input_tokens", 0)}
            call = seen.get(m.get("id"))
            if call is None:
                call = {"grp": label, "wake": cur, "ts": e.get("timestamp", ""), "seg": seg, "vals": vals,
                        "model": m.get("model")}
                seen[m.get("id")] = call
                cur["calls"].append(call)
                calls.append(call)
                if compacts and compacts[-1]["first_after"] is None:
                    compacts[-1]["first_after"] = call
            else:
                call["vals"] = vals
            cur["end"] = e.get("timestamp", cur["end"])
            for b in m.get("content", []):
                if b.get("type") != "tool_use":
                    continue
                if b["name"] == "mcp__smart-compact__compact_now":
                    compact_now_since_wake = True
                if b["name"] == "Bash":
                    cmd = b["input"].get("command", "")
                    if b["input"].get("run_in_background"):
                        background[b["id"]] = cmd
                    if any(re.search(p, cmd) for p in o.CHANGING_BASH):
                        cur["kinds"].add(o.bash_kind(cmd))
                elif b["name"] in o.CHANGING_TOOLS:
                    cur["kinds"].add(o.CHANGING_TOOLS[b["name"]])
    return [w for w in wakes if w["calls"]], calls, compacts


def k(x):
    return f"{x / 1e3:.0f}k"


def med(xs):
    return st.median(xs) if xs else float("nan")


def label_of(w):
    if w["cause"] == "watcher":
        return "watcher changed something" if w["kinds"] else "watcher changed nothing"
    return w["cause"]


def main():
    S = {g: read(g, f) for g, f in (a.split("=", 1) for a in sys.argv[1:])}
    wakes = [w for g in S for w in S[g][0]]
    calls = [c for g in S for c in S[g][1]]
    comps = [c for g in S for c in S[g][2]]
    W = sum(wt(c["vals"]) for c in calls)
    print(f"HEADLINE wakes {len(wakes)} calls {len(calls)} weighted {W / 1e6:.1f}M")

    print("\n# 1 floors")
    fresh = [(g, S[g][1][0]) for g in S]
    for g, c in fresh:
        print(f"fresh {g} ctx {ctx(c)} in {c['vals']['in']} cr {c['vals']['cr']} cw {c['vals']['cw']} "
              f"wake cause {c['wake']['cause']} at {c['ts'][:16]}")
    print("fresh median", med([ctx(c) for _, c in fresh]))
    post = [c["first_after"] for c in comps if c["first_after"]]
    for g in S:
        xs = [c["first_after"] for c in S[g][2] if c["first_after"]]
        print(f"post-compaction {g} n {len(xs)}: " + " ".join(k(ctx(c)) for c in xs))
    print("post-compaction median", med([ctx(c) for c in post]), "min", min(ctx(c) for c in post), "max",
          max(ctx(c) for c in post), "n", len(post))
    print("post-compaction median cw", med([c["vals"]["cw"] for c in post]), "median cr",
          med([c["vals"]["cr"] for c in post]), "cr<10% share",
          sum(c["vals"]["cr"] < 0.1 * ctx(c) for c in post) / len(post))
    print("post-compaction first call is in wake of cause:",
          dict(collections.Counter(c["wake"]["cause"] for c in post)))

    print("\n# 2 compactions")
    for g in S:
        cs = S[g][2]
        print(f"{g} n {len(cs)} last-call ctx: " + " ".join(k(ctx(c["last"])) for c in cs)
              + " | preTokens: " + " ".join(k(c["pre"]) for c in cs))
    print("last-call ctx before compaction: median", med([ctx(c["last"]) for c in comps]), "min",
          min(ctx(c["last"]) for c in comps), "max", max(ctx(c["last"]) for c in comps))
    print("trigger field:", dict(collections.Counter(c["trigger"] for c in comps)))
    print("/compact entry origin:", dict(collections.Counter(c["origin"] for c in comps)))
    print("compact_now tool call in the wake before:", dict(collections.Counter(c["tool"] for c in comps)))
    print("by session tool-called:", {g: sum(c["tool"] for c in S[g][2]) for g in S})
    for thr in (100e3, 120e3, 150e3, 200e3):
        n = sum(ctx(c) > thr for c in calls)
        ww = sum(wt(c["vals"]) for c in calls if ctx(c) > thr)
        print(f"calls above {k(thr)}: {n} = {100 * n / len(calls):.1f}% of calls, {100 * ww / W:.1f}% of weighted spend")
    cx = sorted(ctx(c) for c in calls)
    print("call ctx p10/p50/p90", cx[len(cx) // 10], cx[len(cx) // 2], cx[9 * len(cx) // 10])

    print("\n# 3 growth per wake (next wake first-call ctx minus this wake's)")
    deltas = collections.defaultdict(list)
    skipped = 0
    for g in S:
        ws = S[g][0]
        for a, b in zip(ws, ws[1:]):
            if a["calls"][0]["seg"] != b["calls"][0]["seg"]:
                skipped += 1
                continue
            deltas[label_of(a)].append(ctx(b["calls"][0]) - ctx(a["calls"][0]))
    alld = [d for v in deltas.values() for d in v]
    for name in ["watcher changed nothing", "watcher changed something", "backstop", "owner", "compaction resume",
                 "other background", "other scheduled", "restart or harness", "other"]:
        v = deltas.get(name, [])
        if v:
            print(f"{name}: n {len(v)} median {med(v):.0f} mean {st.mean(v):.0f} p25 {sorted(v)[len(v) // 4]} "
                  f"p75 {sorted(v)[3 * len(v) // 4]} negative {sum(d < 0 for d in v)}")
    for name, sel in (("backstop changed nothing", False), ("backstop changed something", True)):
        v = []
        for g in S:
            ws = S[g][0]
            v += [ctx(b["calls"][0]) - ctx(a["calls"][0]) for a, b in zip(ws, ws[1:])
                  if a["cause"] == "backstop" and bool(a["kinds"]) == sel and a["calls"][0]["seg"] == b["calls"][0]["seg"]]
        print(f"{name}: n {len(v)} median {med(v):.0f} mean {st.mean(v):.0f}")
    print(f"all pairs: n {len(alld)} median {med(alld):.0f} mean {st.mean(alld):.0f} sum {sum(alld)}; "
          f"skipped {skipped} pairs across a compaction")

    print("\n# 4 counterfactual caps")
    rw = [c for c in calls if c["wake"]["cause"] in ROUTINE]
    Wr = sum(wt(c["vals"]) for c in rw)
    # growth totals
    seg_growth = 0
    for g in S:
        bysig = collections.defaultdict(list)
        for c in S[g][1]:
            bysig[c["seg"]].append(ctx(c))
        for v in bysig.values():
            seg_growth += max(v[-1] - v[0], 0)
    t0, t1 = min(ts(w["ts"]) for w in wakes), max(ts(w["end"]) for w in wakes)
    span = (t1 - t0).total_seconds() / 86400
    active = len({w["ts"][:10] for w in wakes})
    counts = collections.Counter(label_of(w) for w in wakes)
    med_growth = sum(counts[n] * med(deltas[n]) for n in counts if deltas.get(n))
    print(f"span days {span:.2f}, days with a wake {active}, compactions happened {len(comps)} "
          f"= {len(comps) / span:.2f}/span-day, {len(comps) / active:.2f}/active-day")
    print(f"growth: within-segment last-minus-first call {seg_growth / 1e6:.2f}M; sum of pair deltas "
          f"{sum(alld) / 1e6:.2f}M; median-by-cause x wakes {med_growth / 1e6:.2f}M")
    floor = med([ctx(c) for c in post])
    for cap in (100e3, 80e3, 60e3):
        new = sum(wt(c["vals"], min(1, cap / ctx(c))) for c in calls)
        newr = sum(wt(c["vals"], min(1, cap / ctx(c))) for c in rw)
        line = f"cap {k(cap)}: saved overall {100 * (1 - new / W):.1f}%, routine {100 * (1 - newr / Wr):.1f}%"
        for nm, gr in (("median-based", med_growth), ("pair-sum", sum(alld)), ("segment", seg_growth)):
            n = gr / (cap - floor) if cap > floor else float("inf")
            extra = max(n - len(comps), 0)
            cost = extra * 2 * floor
            line += (f" | {nm}: {n:.0f} compactions = {n / span:.1f}/span-day {n / active:.1f}/active-day, "
                     f"extra cost {cost / 1e6:.2f}M = {100 * cost / W:.1f}% of spend")
        print(line)
    print("floor used", floor)

    print("\n# 5 spend by token type")
    for nm, cs in (("overall", calls), ("routine", rw)):
        tot = sum(wt(c["vals"]) for c in cs)
        parts = {"input": sum(c["vals"]["in"] for c in cs), "cache write": 2 * sum(c["vals"]["cw"] for c in cs),
                 "cache read": 0.1 * sum(c["vals"]["cr"] for c in cs), "output": 5 * sum(c["vals"]["out"] for c in cs)}
        print(nm, f"{tot / 1e6:.1f}M", {p: f"{100 * v / tot:.1f}%" for p, v in parts.items()})
    print("cache write TTL split: 1h", sum(c["vals"]["cw1h"] for c in calls), "5m",
          sum(c["vals"]["cw5m"] for c in calls), "total cw", sum(c["vals"]["cw"] for c in calls))
    cold = [w for w in wakes if w["calls"][0]["vals"]["cr"] < 0.1 * ctx(w["calls"][0])]
    coldr = [w for w in cold if w["cause"] in ROUTINE]
    nr = sum(w["cause"] in ROUTINE for w in wakes)
    print(f"cold-cache wakes: {len(cold)} of {len(wakes)} = {100 * len(cold) / len(wakes):.1f}%; routine "
          f"{len(coldr)} of {nr} = {100 * len(coldr) / nr:.1f}%; by cause {dict(collections.Counter(w['cause'] for w in cold))}")
    coldw = sum(wt(c["vals"]) for w in cold for c in w["calls"][:1])
    print(f"weighted spend of the first call of cold wakes: {coldw / 1e6:.2f}M = {100 * coldw / W:.1f}%")
    part = [w for w in wakes if 0.1 * ctx(w["calls"][0]) <= w["calls"][0]["vals"]["cr"] < 0.9 * ctx(w["calls"][0])]
    print("wakes whose first call read 10-90% from cache:", len(part))

    print("\n# 6 gaps between consecutive wakes (within a session)")
    start, idle, coldgap = [], [], []
    for g in S:
        ws = S[g][0]
        for a, b in zip(ws, ws[1:]):
            s = (ts(b["ts"]) - ts(a["ts"])).total_seconds() / 60
            i = (ts(b["calls"][0]["ts"]) - ts(a["end"])).total_seconds() / 60
            start.append(s)
            idle.append(i)
            coldgap.append((i, b in cold, a["calls"][0]["seg"] != b["calls"][0]["seg"]))
    for nm, v in (("start to start", start), ("last call of one wake to first call of the next", idle)):
        print(f"{nm}: n {len(v)} median {med(v):.1f} min, >5 min {100 * sum(x > 5 for x in v) / len(v):.1f}%, "
              f">60 min {100 * sum(x > 60 for x in v) / len(v):.1f}%")
    for lo, hi in ((0, 5), (5, 60), (60, 1e9)):
        sel = [c for i, c, x in coldgap if lo < i <= hi or (lo == 0 and i <= 0)]
        if sel:
            print(f"idle gap {lo}-{hi} min: n {len(sel)} cold {sum(sel)} = {100 * sum(sel) / len(sel):.0f}%")
    print("cold wakes that are first after a compaction:", sum(c and x for _, c, x in coldgap), "of", sum(c for _, c, _ in coldgap))

    print("\n# 7 per day")
    bucket = collections.defaultdict(list)
    for g in S:
        ws = S[g][0]
        s0 = ts(ws[0]["ts"])
        life = (ts(ws[-1]["end"]) - s0).total_seconds() / 86400
        print(f"{g}: {ws[0]['ts'][:16]} to {ws[-1]['end'][:16]}, {life:.2f} days elapsed, "
              f"{len({w['ts'][:10] for w in ws})} calendar days with a wake, {len(S[g][2])} compactions")
        per = collections.defaultdict(list)
        for w in ws:
            d = int((ts(w["ts"]) - s0).total_seconds() // 86400) + 1
            per[min(d, 3)].append(ctx(w["calls"][0]))
            bucket[min(d, 3)].append(ctx(w["calls"][0]))
        print("   " + "; ".join(f"day {d}{'+' if d == 3 else ''}: n {len(v)} median {k(med(v))}" for d, v in sorted(per.items())))
    for d, v in sorted(bucket.items()):
        print(f"all sessions day {d}{'+' if d == 3 else ''}: wakes {len(v)} median first-call ctx {med(v):.0f}")
    # first 6 hours vs later, and segment-relative: wakes since last compaction
    early = collections.defaultdict(list)
    for g in S:
        s0 = ts(S[g][0][0]["ts"])
        for w in S[g][0]:
            h = (ts(w["ts"]) - s0).total_seconds() / 3600
            early["0-3h" if h < 3 else "3-12h" if h < 12 else "12-24h" if h < 24 else "24h+"].append(ctx(w["calls"][0]))
    print({b: (len(v), k(med(v))) for b, v in early.items()})


if __name__ == "__main__":
    main()
