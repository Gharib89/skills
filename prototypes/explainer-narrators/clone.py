# PROTOTYPE, throwaway: clone a consenting speaker's clip into Egyptian Arabic narration (#676).
# Usage: clone.py <model> <ref audio> <ref text> <out stem>   models: habibi | namaa | oddadmix
# Run habibi in .venv-habibi, namaa and oddadmix in .venv-chatterbox. One GPU job at a time.
# Prints wall time and peak GPU memory over the run's baseline (nvidia-smi sampled every 0.2 s).
import json, re, subprocess, sys, threading, time
from pathlib import Path

HERE = Path(__file__).parent
TEXT = (HERE / "script/ar.txt").read_text().strip()
model, ref, ref_text, stem = sys.argv[1:5]
ref = str(Path(ref).resolve())
out = HERE / "raw" / f"{stem}.wav"


def used_mib():
    return int(subprocess.run(["nvidia-smi", "--query-gpu=memory.used", "--format=csv,noheader,nounits"],
                              capture_output=True, text=True).stdout)


base, peak, done = used_mib(), [0], threading.Event()


def sample():
    while not done.wait(0.2):
        peak[0] = max(peak[0], used_mib())


threading.Thread(target=sample, daemon=True).start()
t0 = time.time()

if model == "habibi":
    subprocess.run([str(HERE / ".venv-habibi/bin/habibi-tts_infer-cli"), "-m", "Specialized", "-d", "EGY",
                    "-r", ref, "-s", ref_text, "-t", TEXT, "-o", str(out.parent), "-w", out.name], check=True)
else:
    import numpy as np
    import soundfile as sf
    from huggingface_hub import hf_hub_download
    from safetensors.torch import load_file
    from chatterbox.mtl_tts import ChatterboxMultilingualTTS
    repo = {"namaa": "NAMAA-Space/NAMAA-Egyptian-TTS", "oddadmix": "oddadmix/chatterbox-egyptian-v0"}[model]
    # model cards: the fine-tune is the T3 weights on top of the base multilingual model
    tts = ChatterboxMultilingualTTS.from_pretrained(device="cuda")
    tts.t3.load_state_dict(load_file(hf_hub_download(repo, "t3_mtl23ls_v2.safetensors"), device="cuda"))
    # model cards: ~300 characters per call, so render sentence by sentence
    parts = [s for s in re.split(r"(?<=[.،؟])\s+", TEXT) if s]
    gap = np.zeros(int(0.12 * tts.sr), np.float32)
    wav = np.concatenate([np.concatenate([tts.generate(p, language_id="ar", audio_prompt_path=ref).squeeze(0).cpu().numpy(), gap])
                          for p in parts])
    sf.write(out, wav, tts.sr)

done.set()
print(json.dumps({"stem": stem, "seconds_wall": round(time.time() - t0, 1), "peak_vram_mib": peak[0] - base}))
