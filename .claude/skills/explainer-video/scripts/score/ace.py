# ACE-Step 1.5 text to music for the score, DiT only (no 5 Hz LM). backend.mjs
# runs it under `uv run` in the ace-step row's source folder (ADR 0014).
#
#   ace.py <checkpoints> <cpu|cuda> <seconds> <seed> <caption> <out.wav>
#
# writes: <out.wav>, 48 kHz stereo; stderr: warnings and errors only
# exit:   0 written · 1 acestep failed, its message on stderr
import os
import shutil
import sys
import tempfile

ckpt, device, seconds, seed, caption, out = sys.argv[1:7]
os.environ["ACESTEP_CHECKPOINTS_DIR"] = ckpt
os.environ["ACESTEP_DISABLE_TQDM"] = "1"
os.environ["HF_HUB_OFFLINE"] = "1"

from loguru import logger

logger.remove()
logger.add(sys.stderr, level="WARNING")

import acestep.core.generation.handler.init_service_downloads as downloads
from acestep.handler import AceStepHandler
from acestep.inference import GenerationConfig, GenerationParams, generate_music

# The main model's presence check also wants the 5 Hz LM's weights, which a
# DiT-only run never loads; without them acestep downloads the whole repo.
downloads.check_main_model_exists = lambda _path: True

dit = AceStepHandler()
status, ok = dit.initialize_service(
    project_root=ckpt, config_path="acestep-v15-turbo", device=device
)
if not ok:
    sys.exit(status)
params = GenerationParams(
    caption=caption,
    lyrics="[Instrumental]",
    duration=float(seconds),
    seed=int(seed),
    thinking=False,
    use_cot_metas=False,
    use_cot_caption=False,
    use_cot_language=False,
)
config = GenerationConfig(
    batch_size=1, use_random_seed=False, seeds=[int(seed)], audio_format="wav"
)
with tempfile.TemporaryDirectory() as tmp:
    r = generate_music(dit, None, params, config, save_dir=tmp)
    if not r.success:
        sys.exit(r.error)
    shutil.move(r.audios[0]["path"], out)
