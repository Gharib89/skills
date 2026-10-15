# PROTOTYPE, throwaway: renders the narrator shortlist for the blind listening page (#662).
# Usage: render.py <stage>   stages: supertonic-scout | kokoro | edge | gemini
import asyncio, base64, json, sys, wave
from pathlib import Path

import numpy as np
import soundfile as sf

HERE = Path(__file__).parent
TEXT = {lang: (HERE / f"script/{lang}.txt").read_text().strip() for lang in ("en", "ar")}
RAW = HERE / "raw"


def kokoro():
    from kokoro import KPipeline
    for voice in ("af_bella", "bf_emma", "am_michael", "am_fenrir"):
        pipe = KPipeline(lang_code=voice[0], repo_id="hexgrad/Kokoro-82M")
        audio = np.concatenate([a for _, _, a in pipe(TEXT["en"], voice=voice)])
        sf.write(RAW / f"en-kokoro-{voice}.wav", audio, 24000)


def supertonic(presets, langs, tag=""):
    from supertonic import TTS
    tts = TTS(auto_download=True)
    for lang in langs:
        for p in presets:
            wav, _ = tts.synthesize(TEXT[lang], voice_style=tts.get_voice_style(voice_name=p), lang=lang)
            tts.save_audio(wav, str(RAW / f"{lang}-supertonic-{p}{tag}.wav"))


async def edge():
    import edge_tts
    for v in ("ar-EG-SalmaNeural", "ar-EG-ShakirNeural"):
        await edge_tts.Communicate(TEXT["ar"], v).save(str(RAW / f"ar-edge-{v}.mp3"))


def gemini():
    from google import genai
    c = genai.Client()
    style = "a clear, warm, friendly narrator explaining a software workflow"
    for lang, voice in (("en", "autonoe"), ("en", "charon"), ("ar", "ar-eg-csagent-2"), ("ar", "ar-eg-commercial-11")):
        r = c.interactions.create(
            model="gemini-3.8-flash-tts",
            input=[{"type": "user_input", "content": [{"type": "text", "text": TEXT[lang],
                    "annotations": [{"type": "speech_metadata", "style": style}]}]}],
            response_format={"type": "audio", "mime_type": "audio/l16", "sample_rate": 24000},
            generation_config={"speech_config": [{"voice": voice}]},
        )
        with wave.open(str(RAW / f"{lang}-gemini-{voice}.wav"), "wb") as w:
            w.setnchannels(1); w.setsampwidth(2); w.setframerate(24000)
            w.writeframes(base64.b64decode(r.output_audio.data))


if __name__ == "__main__":
    RAW.mkdir(exist_ok=True)
    stage = sys.argv[1]
    if stage == "kokoro": kokoro()
    elif stage == "supertonic-scout": supertonic([f"{g}{i}" for g in "FM" for i in range(1, 6)], ["en", "ar"], "-scout")
    elif stage == "edge": asyncio.run(edge())
    elif stage == "gemini": gemini()
