# PROTOTYPE, throwaway: ACE-Step 1.5 2B turbo score for the 30 s cut (#665).
# 100 BPM puts bar 10 on the end card at 24.0 s (10 bars x 2.4 s). DiT only, CPU offload:
# the <=6 GB tier this 8 GB card falls into while other GPU work holds about 2 GB. The RTX 2070 has
# no bfloat16 and float16 overflows to NaN, so this runs on the CPU in float32.
# Run from ace-step/: uv run python ../ace.py
import os, sys
DEVICE = "cpu"  # float32; CUDA on this card is forced to float16, which NaNs (ACESTEP_DTYPE is read nowhere)
from acestep.handler import AceStepHandler
from acestep.inference import GenerationParams, GenerationConfig, generate_music

dit = AceStepHandler()
status, ok = dit.initialize_service(project_root=os.getcwd(), config_path="acestep-v15-turbo", device=DEVICE,
                                    offload_to_cpu=DEVICE == "cuda", quantization=None)
print(status); ok or sys.exit(1)
params = GenerationParams(
    caption="calm instrumental background music for a software tutorial video, soft electric piano, "
            "warm bass, light brushed drums, gentle and unobtrusive, steady groove, no vocals",
    instrumental=True, bpm=100, keyscale="F major", timesignature="4", duration=30, seed=665, thinking=False,
    use_cot_metas=False, use_cot_caption=False, use_cot_language=False)
r = generate_music(dit, None, params, GenerationConfig(batch_size=1, use_random_seed=False, seeds=[665], audio_format="wav"),
                   save_dir="../raw/ace")
print(r.success, r.error if not r.success else [a["path"] for a in r.audios])
