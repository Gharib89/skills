# Chatterbox VC: convert a narrator's render to an enrolled speaker's clip.
# backend.mjs runs it under `uv run` in the own-voice row's source folder.
#
#   vc.py <checkpoints> <cpu|cuda> <in.wav> <clip.wav> <out.wav>
#
# writes: <out.wav>, at the model's 24 kHz
# exit:   0 written · 1 chatterbox failed, its message on stderr
import sys
import torchaudio as ta
from chatterbox.vc import ChatterboxVC

ckpt, device, src, clip, out = sys.argv[1:6]
model = ChatterboxVC.from_local(ckpt, device)
ta.save(out, model.generate(audio=src, target_voice_path=clip), model.sr)
