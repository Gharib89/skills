# PROTOTYPE, throwaway: loudness-normalise the finalists into blind clips plus a reveal key (#662).
import json, random, subprocess
from pathlib import Path

HERE = Path(__file__).parent
SCORES = json.loads((HERE / "raw/scores.json").read_text())
# group -> [(raw stem, display name, licence class)]
GROUPS = {
    "en-female": [("en-kokoro-af_bella", "Kokoro af_bella", "Safe, local"),
                  ("en-kokoro-bf_emma", "Kokoro bf_emma", "Safe, local"),
                  ("en-supertonic-F3-scout", "Supertonic 3 F3", "Safe, local"),
                  ("en-omnivoice-teacher", "OmniVoice house teacher voice", "Opt-in, CC-BY-NC"),
                  ("en-gemini-autonoe", "Gemini 3.8 TTS Autonoe", "API, Gemini key")],
    "en-male": [("en-kokoro-am_michael", "Kokoro am_michael", "Safe, local"),
                ("en-kokoro-am_fenrir", "Kokoro am_fenrir", "Safe, local"),
                ("en-supertonic-M1-scout", "Supertonic 3 M1", "Safe, local"),
                ("en-gemini-charon", "Gemini 3.8 TTS Charon", "API, Gemini key")],
    "ar-female": [("ar-supertonic-F3-scout", "Supertonic 3 F3", "Safe, local"),
                  ("ar-edge-ar-EG-SalmaNeural", "Azure ar-EG-SalmaNeural (via edge-tts)", "API, Azure key"),
                  ("ar-gemini-ar-eg-csagent-2", "Gemini 3.8 TTS ar-eg-csagent-2", "API, Gemini key"),
                  ("ar-omnivoice-teacher", "OmniVoice house teacher voice", "Opt-in, CC-BY-NC")],
    "ar-male": [("ar-supertonic-M1-scout", "Supertonic 3 M1", "Safe, local"),
                ("ar-edge-ar-EG-ShakirNeural", "Azure ar-EG-ShakirNeural (via edge-tts)", "API, Azure key"),
                ("ar-gemini-ar-eg-commercial-11", "Gemini 3.8 TTS ar-eg-commercial-11", "API, Gemini key")],
}
out = HERE / "clips"
out.mkdir(exist_ok=True)
rng = random.Random(662)
key = {}
for group, voices in GROUPS.items():
    voices = voices[:]
    rng.shuffle(voices)
    key[group] = []
    for letter, (stem, name, lic) in zip("ABCDE", voices):
        src = next((HERE / "raw").glob(stem + ".*"))
        dst = out / f"{group}-{letter}.mp3"
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", str(src), "-af",
                        "silenceremove=start_periods=1:start_threshold=-50dB,loudnorm=I=-16:TP=-1.5:LRA=11",
                        "-ac", "1", "-ar", "44100", "-b:a", "96k", str(dst)], check=True)
        dur = float(subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", str(dst)],
                                   capture_output=True, text=True, check=True).stdout)
        key[group].append({"id": letter, "file": dst.name, "name": name, "licence": lic,
                           "seconds": round(dur, 1), "error_rate": SCORES[stem]["rate"]})
(out / "key.json").write_text(json.dumps(key, indent=1))
print(json.dumps(key, indent=1))
