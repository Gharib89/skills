# PROTOTYPE: reads the bench renders.
#   times:       median and range of each variant's wall time
#   determinism: framemd5 of every render against the variant's first
#   frame codes: the 12-bit strip decoded from each trails frame, live against
#                clip, so a clip frame landing one frame early or late shows
#   look:        PSNR and SSIM of clip against live over the trails slot
# usage: python3 -I analyze.py <work dir>
import json, statistics, subprocess, sys
from pathlib import Path

W = Path(sys.argv[1]); O = W / "out"
FPS, START, DUR = 30, 29.55, 23.775
VARIANTS = ["live-gpu", "live-sw", "clip-cold", "clip-warm", "flat", "trails-3d"]

def ff(*a):
    return subprocess.run(["ffmpeg", "-v", "error", "-nostats", *a], capture_output=True, check=True)

rows = [json.loads(l) for l in (O / "bench.jsonl").read_text().splitlines() if l.startswith("{")]
times = {}
for r in rows:
    if "variant" in r:
        times.setdefault("clip-cold+clip", []).append(r["wall"]); continue
    name = Path(r["out"]).stem.rsplit("-", 1)[0]
    times.setdefault(name, []).append(r["wall"])
    assert r["code"] == 0, r
print("## wall time, s (median, range, n)")
for k, v in times.items():
    print(f"{k:16} {statistics.median(v):7.2f}  {min(v):7.2f} to {max(v):7.2f}  n={len(v)}")

def md5s(p):
    out = ff("-i", str(p), "-map", "0:v", "-f", "framemd5", "-").stdout.decode()
    return [l.split(",")[-1].strip() for l in out.splitlines() if l and not l.startswith("#")]

print("\n## determinism: frames differing from run 1")
first = {}
for v in VARIANTS:
    runs = sorted(O.glob(f"{v}-[0-9].mp4"))
    if not runs: continue
    hs = [md5s(p) for p in runs]
    first[v] = hs[0]
    diffs = [sum(a != b for a, b in zip(hs[0], h)) + abs(len(hs[0]) - len(h)) for h in hs[1:]]
    print(f"{v:10} runs={len(runs)} frames={len(hs[0])} differing={diffs}")
for a, b in [("clip-cold", "clip-warm"), ("live-gpu", "live-sw"), ("live-gpu", "clip-cold")]:
    if a in first and b in first:
        print(f"{a} vs {b}: {sum(x != y for x, y in zip(first[a], first[b]))} of {len(first[a])} frames differ")

def codes(p, x0=1920 - 14 * 12 - 24, y0=140 + 760 - 12 - 16, start=START):
    raw = ff("-ss", str(start), "-t", str(DUR), "-i", str(p),
             "-vf", f"crop=168:12:{x0}:{y0},format=gray", "-f", "rawvideo", "-").stdout
    fr = 168 * 12; out = []
    for k in range(len(raw) // fr):
        f = raw[k * fr:(k + 1) * fr]
        bits = [f[6 * 168 + 6 + 12 * i] < 128 for i in range(14)]
        out.append(None if not (bits[0] and bits[13]) else int("".join("1" if b else "0" for b in bits[1:13]), 2))
    return out

print("\n## frame codes over the trails slot")
live, clip, src = codes(O / "live-gpu-1.mp4"), codes(O / "clip-cold-1.mp4"), codes(O / "trails-3d-1.mp4", y0=760 - 12 - 16, start=0)
def steps(c):
    d = [b - a for a, b in zip(c, c[1:]) if a is not None and b is not None]
    return {s: d.count(s) for s in sorted(set(d))}
print("clip source first codes", src[:4], "steps", steps(src))
print("live  first codes", live[:4], "last", live[-3:], "steps", steps(live), "unreadable", live.count(None))
print("clip  first codes", clip[:4], "last", clip[-3:], "steps", steps(clip), "unreadable", clip.count(None))
off = [c - l for l, c in zip(live, clip) if l is not None and c is not None]
print("clip minus live offset:", {o: off.count(o) for o in sorted(set(off))})

print("\n## look: clip against live over the trails slot")
for name, flt in [("psnr", "psnr"), ("ssim", "ssim")]:
    r = subprocess.run(["ffmpeg", "-nostats", "-ss", str(START), "-t", str(DUR), "-i", str(O / "clip-cold-1.mp4"),
                        "-ss", str(START), "-t", str(DUR), "-i", str(O / "live-gpu-1.mp4"),
                        "-lavfi", f"[0:v]crop=1920:760:0:140[a];[1:v]crop=1920:760:0:140[b];[a][b]{flt}", "-f", "null", "-"],
                       capture_output=True, text=True)
    print(name, [l for l in r.stderr.splitlines() if "average" in l or "All:" in l][-1].split("] ")[-1])
print("\nsizes MB:", {p.name: round(p.stat().st_size / 1e6, 2) for p in [O / "live-gpu-1.mp4", O / "clip-cold-1.mp4", O / "trails-3d-1.mp4", O / "flat-1.mp4"] if p.exists()})
