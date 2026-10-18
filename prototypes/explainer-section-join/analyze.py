# PROTOTYPE: joins the section renders bench.sh wrote and measures the join.
# usage: uv run --with numpy python -I analyze.py <work dir>
# prints one JSON document; writes <work>/joined/ (the joined MP4s, the final
# muxed MP4 with chapters, frames at each join for the page)
import json, math, re, subprocess, sys
from pathlib import Path

import numpy as np

W = Path(sys.argv[1])
R = W / "renders"
J = W / "joined"
J.mkdir(exist_ok=True)
FPS = 30
plan = json.loads((W / "plan.json").read_text())
BAND = "crop=1680:104:120:908"  # the captions box


def run(*a, text=True):
    return subprocess.run(a, check=True, capture_output=True, text=text).stdout


def concat(parts, out):
    lst = out.with_suffix(".txt")
    lst.write_text("".join(f"file '{p}'\n" for p in parts))
    run("ffmpeg", "-y", "-v", "error", "-f", "concat", "-safe", "0", "-i", str(lst), "-map", "0:v", "-c", "copy", str(out))
    return out


def md5s(f, vf=None):
    a = ["ffmpeg", "-v", "error", "-i", str(f), "-map", "0:v"]
    if vf:
        a += ["-vf", vf]
    return [l.rsplit(",", 1)[1].strip() for l in run(*a, "-f", "framemd5", "-").splitlines() if l and not l.startswith("#")]


def packets(f):
    out = run("ffprobe", "-v", "error", "-select_streams", "v", "-show_entries", "packet=pts,flags", "-of", "csv=p=0", str(f))
    rows = [l.split(",") for l in out.splitlines() if l]
    return [int(p) for p, _ in rows], [i for i, (_, fl) in enumerate(rows) if "K" in fl]


def tb(f):
    return run("ffprobe", "-v", "error", "-select_streams", "v", "-show_entries", "stream=time_base", "-of", "csv=p=0", str(f)).strip()


def pcm(f, start=None, dur=None):
    a = ["ffmpeg", "-v", "error"]
    if start is not None:
        a += ["-ss", str(start), "-t", str(dur)]
    a += ["-i", str(f), "-map", "0:a", "-ac", "1", "-ar", "48000", "-f", "s16le", "-"]
    return np.frombuffer(subprocess.run(a, check=True, capture_output=True).stdout, dtype=np.int16).astype(np.float64)


def lag(ref, got, at, win=48000, search=4800):
    """Offset in samples of `got` against `ref` around sample `at`."""
    a = ref[at : at + win]
    best, arg = -1, 0
    for d in range(-search, search + 1, 8):
        b = got[at + d : at + d + win]
        if len(b) < win:
            continue
        c = float(np.dot(a, b))
        if c > best:
            best, arg = c, d
    for d in range(arg - 8, arg + 9):  # refine to the sample
        b = got[at + d : at + d + win]
        if len(b) == win and float(np.dot(a, b)) >= best:
            best, arg = float(np.dot(a, b)), d
    return arg


res = {}
for mode in ["naive", "snapped"]:
    secs = plan[mode]["sections"]
    whole = R / f"{mode}-whole.mp4"
    parts = [R / f"{mode}-s{i + 1}.mp4" for i in range(3)]
    joined = concat(parts, J / f"{mode}-joined.mp4")
    wm, jm = md5s(whole), md5s(joined)
    pm = [md5s(p) for p in parts]
    pts, keys = packets(joined)
    steps = sorted(set(np.diff(pts).tolist()))
    starts = np.cumsum([0] + [len(m) for m in pm])[:-1].tolist()
    same = sum(a == b for a, b in zip(wm, jm))
    # Where each section's frames sit in the whole render: the offset (in
    # frames) at which most of its frames match.
    offsets = []
    for i, m in enumerate(pm):
        best = max(range(-3, 4), key=lambda d: sum(1 for k, h in enumerate(m) if 0 <= starts[i] + k + d < len(wm) and wm[starts[i] + k + d] == h))
        hits = sum(1 for k, h in enumerate(m) if 0 <= starts[i] + k + best < len(wm) and wm[starts[i] + k + best] == h)
        offsets.append({"offset": best, "matching": hits, "of": len(m)})
    # Captions: each cue's first frame by its time, against where the band
    # changes in the joined and the whole render.
    html = (W / mode / "whole" / "index.html").read_text()
    cues = [float(x) for x in re.findall(r'<div class="cue clip" data-start="([\d.]+)"', html)]
    band_w, band_j = md5s(whole, BAND), md5s(joined, BAND)

    def lands(band):
        late = []
        for t in cues:
            f = math.ceil(t * FPS - 1e-6)
            if f > 0 and band[f] == band[f - 1]:
                # the change came off the expected frame: find it
                d = next((d for d in range(1, 4) if f + d < len(band) and band[f + d] != band[f + d - 1]), None)
                late.append({"t": t, "frame": f, "late_by": d})
        return {"cues": len(cues), "off_frame": late}

    res[mode] = {
        "frames": {"whole": len(wm), "joined": len(jm), "sections": [len(m) for m in pm], "planned": [s["frames"] for s in secs]},
        "identical_frames": f"{same}/{max(len(wm), len(jm))}",
        "section_offsets_in_whole": offsets,
        "joined_pts": {"time_base": tb(joined), "steps": steps, "keyframes_at_section_starts": all(s in keys for s in starts), "section_starts": starts},
        "opener_start_frames": [s["startFrames"] for s in secs],
        "captions_whole": lands(band_w),
        "captions_joined": lands(band_j),
    }

# Determinism and the one-section fix (snapped).
s2, again, edit = (md5s(R / f"snapped-{n}.mp4") for n in ["s2", "s2-again", "s2edit"])
diff = [k for k, (a, b) in enumerate(zip(s2, edit)) if a != b]
climate = next(s for s in plan["snapped"]["scenes"] if s["id"] == "climate")
s2start = plan["snapped"]["sections"][1]["start"]
res["determinism_s2_rerender"] = f"{sum(a == b for a, b in zip(s2, again))}/{len(s2)} frames identical"
res["edit"] = {
    "changed_frames": len(diff),
    "first": diff[0] if diff else None,
    "last": diff[-1] if diff else None,
    "climate_scene_frames": [round((climate["start"] - s2start) * FPS), round((climate["start"] - s2start + climate["duration"]) * FPS)],
}
joined_edit = concat([R / "snapped-s1.mp4", R / "snapped-s2edit.mp4", R / "snapped-s3.mp4"], J / "snapped-joined-edit.mp4")

# Audio, mixed once: the joined video muxed with the whole narration, AAC
# encoded once, chapters at the section openers.
sn = plan["snapped"]
meta = J / "chapters.txt"
starts = res["snapped"]["joined_pts"]["section_starts"] + [res["snapped"]["frames"]["joined"]]
meta.write_text(";FFMETADATA1\n" + "".join(f"[CHAPTER]\nTIMEBASE=1/{FPS}\nSTART={starts[i]}\nEND={starts[i + 1]}\ntitle={s['opener']}\n" for i, s in enumerate(sn["sections"])))
final = J / "snapped-final.mp4"
run("ffmpeg", "-y", "-v", "error", "-i", str(J / "snapped-joined.mp4"), "-i", str(W / "snapped" / "whole" / "narration.wav"), "-f", "ffmetadata", "-i", str(meta), "-map", "0:v", "-map", "1:a", "-map_chapters", "2", "-c:v", "copy", "-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart", str(final))
probe = json.loads(run("ffprobe", "-v", "error", "-show_entries", "stream=codec_type,start_time,duration,nb_frames:chapter=start_time,end_time:chapter_tags=title", "-of", "json", str(final)))
fm = md5s(final)
chap = [{"title": c["tags"]["title"], "start": c["start_time"], "frame": round(float(c["start_time"]) * FPS)} for c in probe["chapters"]]
for c, i in zip(chap, range(3)):
    c["is_opener_frame0"] = fm[c["frame"]] == md5s(R / f"snapped-s{i + 1}.mp4")[0]
    c["changes_from_previous"] = c["frame"] == 0 or fm[c["frame"]] != fm[c["frame"] - 1]
ref = pcm(W / "snapped" / "whole" / "narration.wav")
got_final = pcm(final)
got_hf = pcm(R / "snapped-whole.mp4")
joins = [round(s["start"] * 48000) for s in sn["sections"][1:]]
res["audio_mux_once"] = {
    "streams": probe["streams"],
    "chapters": chap,
    "lag_samples_at_joins": [lag(ref, got_final, j) for j in joins],
    "lag_samples_at_end": lag(ref, got_final, len(ref) - 3 * 48000),
    "hyperframes_whole_lag_at_joins": [lag(ref, got_hf, j) for j in joins],
}
# Audio per section, joined: each section's narration slice AAC-encoded on
# its own and concatenated with -c copy, the shape a per-section mux takes.
parts = []
for i, s in enumerate(sn["sections"]):
    p = J / f"audio-s{i + 1}.m4a"
    run("ffmpeg", "-y", "-v", "error", "-ss", str(s["start"]), "-t", str(s["duration"]), "-i", str(W / "snapped" / "whole" / "narration.wav"), "-c:a", "aac", "-b:a", "192k", str(p))
    parts.append(p)
lst = J / "audio.txt"
lst.write_text("".join(f"file '{p}'\n" for p in parts))
per = J / "audio-per-section.m4a"
run("ffmpeg", "-y", "-v", "error", "-f", "concat", "-safe", "0", "-i", str(lst), "-c", "copy", str(per))
got_per = pcm(per)
res["audio_per_section"] = {
    "duration_s": round(len(got_per) / 48000, 4),
    "reference_s": round(len(ref) / 48000, 4),
    "lag_samples_at_joins": [lag(ref, got_per, j + 24000) for j in joins],
    "lag_samples_at_end": lag(ref, got_per, len(ref) - 3 * 48000),
}

# Frames around each join, for the page.
for mode in ["naive", "snapped"]:
    for i, s in enumerate(res[mode]["joined_pts"]["section_starts"][1:], start=2):
        for k in (s - 1, s):
            run("ffmpeg", "-y", "-v", "error", "-i", str(J / f"{mode}-joined.mp4"), "-vf", f"select=eq(n\\,{k}),scale=640:-1", "-frames:v", "1", str(J / f"{mode}-join{i}-{k}.png"))
print(json.dumps(res, indent=1))
