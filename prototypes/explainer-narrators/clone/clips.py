# PROTOTYPE, throwaway: blind clips for the clone listening page (#676): the owner's three clones
# beside the two Gemini winners from #662, loudness-normalised, plus a reveal key.
# Round 2 (`clips.py 2`): the owner's top clone tuned for energy and pace, and a voice conversion of Gemini.
import json, random, shutil, subprocess, sys
from pathlib import Path

ROUND = sys.argv[1] if len(sys.argv) > 1 else "1"

HERE = Path(__file__).parent
ROOT = HERE.parent
SCORES = {**json.loads((ROOT / "raw/scores-clone.json").read_text()), **json.loads((ROOT / "raw/scores-tune.json").read_text())}
RUNS = {json.loads(l)["stem"]: json.loads(l) for f in ("runs.jsonl", "runs-tune.jsonl") for l in (HERE / f).read_text().splitlines()}
GEMINI = {g["name"]: g for grp in ("ar-female", "ar-male") for g in json.loads((ROOT / "clips/key.json").read_text())[grp]}
VOICES = [  # (source, display name, licence class)
    ("ar-clone-habibi-egy", "Habibi-TTS EGY, clone of your clip", "Clone opt-in, Apache-2.0 weights"),
    ("ar-clone-namaa", "NAMAA-Egyptian-TTS (Chatterbox), clone of your clip", "Clone opt-in, MIT weights"),
    ("ar-clone-oddadmix", "chatterbox-egyptian-v0, clone of your clip", "Clone opt-in, MIT weights"),
    ("Gemini 3.8 TTS ar-eg-csagent-2", "Gemini 3.8 TTS ar-eg-csagent-2 (female)", "API, Gemini key"),
    ("Gemini 3.8 TTS ar-eg-commercial-11", "Gemini 3.8 TTS ar-eg-commercial-11 (male)", "API, Gemini key"),
]
if ROUND == "2":
    VOICES = [
        ("ar-clone-namaa", "Round 1 NAMAA clone (exaggeration 0.5, cfg 0.5, comma splits)", "Clone opt-in, MIT weights"),
        ("ar-tune-namaa-e07-c03", "NAMAA clone, exaggeration 0.7, cfg 0.3, sentence splits", "Clone opt-in, MIT weights"),
        ("ar-tune-namaa-e09-c03", "NAMAA clone, exaggeration 0.9, cfg 0.3, sentence splits", "Clone opt-in, MIT weights"),
        ("ar-tune-vc-gemini-male", "Gemini ar-eg-commercial-11 converted to your voice (Chatterbox VC)", "API, Gemini key, then local VC, MIT"),
        ("Gemini 3.8 TTS ar-eg-commercial-11", "Gemini 3.8 TTS ar-eg-commercial-11 (male)", "API, Gemini key"),
    ]
out = HERE / "page/clips"
out.mkdir(parents=True, exist_ok=True)
random.Random(676 + int(ROUND)).shuffle(VOICES)
key = []
for letter, (src, name, lic) in zip("ABCDE", VOICES):
    dst = out / f"ar-{letter}.mp3"
    if src in GEMINI:  # already normalised by clips.py on #662
        shutil.copy(ROOT / "clips" / GEMINI[src]["file"], dst)
        rate, cost = GEMINI[src]["error_rate"], "API call"
    else:
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", str(ROOT / "raw" / f"{src}.wav"), "-af",
                        "silenceremove=start_periods=1:start_threshold=-50dB,loudnorm=I=-16:TP=-1.5:LRA=11",
                        "-ac", "1", "-ar", "44100", "-b:a", "96k", str(dst)], check=True)
        rate = SCORES[src]["rate"]
        cost = f"{RUNS[src]['seconds_wall']} s wall, {RUNS[src]['peak_vram_mib']} MiB VRAM"
        if src == "ar-tune-vc-gemini-male":
            cost = "Gemini API call, then " + cost
    dur = float(subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", str(dst)],
                               capture_output=True, text=True, check=True).stdout)
    key.append({"id": letter, "file": dst.name, "name": name, "licence": lic, "cost": cost,
                "seconds": round(dur, 1), "error_rate": rate})
(HERE / "page/key.json").write_text(json.dumps(key, indent=1))
print(json.dumps(key, indent=1))
