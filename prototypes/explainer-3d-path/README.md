# Explainer 3D path (PROTOTYPE, never merged)

Throwaway prototype for the wayfinder ticket
[3D path: live Three.js or cached clip insert](https://github.com/Gharib89/skills/issues/778).
It builds one 3D explainer scene both ways inside the real composer output and
measures them.

## What is here

- `trails3d.js`: dora-core's `trails` scene as a 3D exploded stack (Three.js
  0.186.1). Every state is a function of the scene timeline time: a closed-form
  orbit, seeded randomness, no clocks. HTML labels are projected from 3D points
  by the same camera math, so they can run live even over a clip insert. A
  12-bit frame-number strip in the corner proves which frame landed where.
- `build.mjs`: cuts a 72.145 s slice (scenes context, trails, rubric) out of
  `explainer-videos/explainers/dora-core/composition` and writes four
  HyperFrames compositions: `live`, `clip3d` (the WebGL layer alone, 1920x760),
  `clip` (that MP4 as a clip insert) and `flat` (the slice as shipped).
- `hf.mjs`: one `hyperframes render` through the skill's own tool cache and
  Chrome home with the composer's flags (`--strict --fps 30 --workers 3`).
- `bench.sh`: 5 rounds alternating live on the GPU, the clip insert cold and
  warm, live on SwiftShader, and the flat baseline.
- `analyze.py`: wall times, framemd5 determinism, frame-code alignment, and
  PSNR and SSIM of the clip insert against live.
- `vendor/three.global.js`: three 0.186.1 bundled as a global
  (`bun build --format=iife`).

## Run

```sh
node build.mjs <dora-core composition dir> <work>
# slice the narration into <work>/{live,clip,flat}/narration.wav:
#   ffmpeg -ss 26.69 -t 72.145 -i <composition>/narration.wav <work>/live/narration.wav
./bench.sh <work>
python3 -I analyze.py <work>
```

Measured output: `results.txt` (from `analyze.py` plus the probe runs) and
`bench.jsonl`. Published page: see the ticket's resolution comment.
