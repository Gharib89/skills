# PROTOTYPE, throwaway: round 2 of #676, after the owner asked for "more energetic, fewer pauses,
# like Gemini but with my voice". Run in .venv-chatterbox.
#   namaa variants: split on sentence ends only (round 1 split at every Arabic comma and added a
#   0.12 s gap), trim each chunk's edge silence, raise exaggeration, lower cfg_weight (faster pacing).
#   vc: Chatterbox voice conversion of the Gemini winner's render into the owner's voice.
import json, re, time
from pathlib import Path

import librosa
import numpy as np
import soundfile as sf
import torch
from huggingface_hub import hf_hub_download
from safetensors.torch import load_file
from chatterbox.mtl_tts import ChatterboxMultilingualTTS
from chatterbox.vc import ChatterboxVC

HERE = Path(__file__).parent
ROOT = HERE.parent
REF = str(HERE / "ref/owner.wav")
TEXT = (ROOT / "script/ar.txt").read_text().strip()
PARTS = [s for s in re.split(r"(?<=\.)\s+", TEXT) if s]
VARIANTS = {"ar-tune-namaa-e07-c03": (0.7, 0.3), "ar-tune-namaa-e09-c03": (0.9, 0.3)}
runs = []

tts = ChatterboxMultilingualTTS.from_pretrained(device="cuda")
tts.t3.load_state_dict(load_file(hf_hub_download("NAMAA-Space/NAMAA-Egyptian-TTS", "t3_mtl23ls_v2.safetensors"), device="cuda"))
gap = np.zeros(int(0.25 * tts.sr), np.float32)  # one sentence-end breath
for stem, (ex, cfg) in VARIANTS.items():
    torch.manual_seed(676)
    t0 = time.time()
    chunks = []
    for p in PARTS:
        w = tts.generate(p, language_id="ar", audio_prompt_path=REF, exaggeration=ex, cfg_weight=cfg).squeeze(0).cpu().numpy()
        chunks += [librosa.effects.trim(w, top_db=40)[0], gap]
    sf.write(ROOT / f"raw/{stem}.wav", np.concatenate(chunks[:-1]), tts.sr)
    runs.append({"stem": stem, "seconds_wall": round(time.time() - t0, 1)})
del tts
torch.cuda.empty_cache()

vc = ChatterboxVC.from_pretrained(device="cuda")
t0 = time.time()
wav = vc.generate(str(ROOT / "clips/ar-male-C.mp3"), target_voice_path=REF)  # Gemini ar-eg-commercial-11, #662
sf.write(ROOT / "raw/ar-tune-vc-gemini-male.wav", wav.squeeze(0).numpy(), vc.sr)
runs.append({"stem": "ar-tune-vc-gemini-male", "seconds_wall": round(time.time() - t0, 1)})
runs = [{**r, "peak_vram_mib": round(torch.cuda.max_memory_allocated() / 2**20)} for r in runs]
(HERE / "runs-tune.jsonl").write_text("".join(json.dumps(r) + "\n" for r in runs))
print(*runs, sep="\n")
