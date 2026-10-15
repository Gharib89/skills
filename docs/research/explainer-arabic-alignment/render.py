# Render Gemini 3.8 TTS Egyptian Arabic clips, one call per sentence (stock voices only).
import base64, json, sys, wave
from pathlib import Path
from google import genai
from google.genai import types
c = genai.Client(http_options=types.HttpOptions(timeout=90000))
STYLE = "a clear, warm, friendly narrator explaining a software workflow"
src, tag = sys.argv[1], sys.argv[2]
for sid, sents in json.loads(Path(src).read_text()).items():
    for voice in ("ar-eg-csagent-2", "ar-eg-commercial-11"):
        for k, text in enumerate(sents):
            out = Path(f"audio/{tag}-{sid}-{voice}-{k}.wav")
            if out.exists(): continue
            try:
              r = c.interactions.create(model="gemini-3.8-flash-tts",
                input=[{"type": "user_input", "content": [{"type": "text", "text": text,
                        "annotations": [{"type": "speech_metadata", "style": STYLE}]}]}],
                response_format={"type": "audio", "mime_type": "audio/l16", "sample_rate": 24000},
                generation_config={"speech_config": [{"voice": voice}]})
            except Exception as e:
                print("FAIL", out, type(e).__name__, flush=True); continue
            with wave.open(str(out), "wb") as w:
                w.setnchannels(1); w.setsampwidth(2); w.setframerate(24000)
                w.writeframes(base64.b64decode(r.output_audio.data))
            print(out, flush=True)
