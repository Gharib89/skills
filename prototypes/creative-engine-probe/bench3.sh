#!/usr/bin/env bash
# Five more alternating 60 s rounds, then one GPU-sampled 60 s render per mode.
here="$(cd "$(dirname "$0")" && pwd)"
for i in 4 5 6 7 8; do
  bash "$here/render-one.sh" hf60 "hf60-$i.mp4"
  COMP=probe60 bash "$here/render-one.sh" remotion "rem60-$i.mp4"
  COMP=probe60 bash "$here/render-one.sh" remotion "remangle60-$i.mp4" --gl=angle
done
bash "$here/gpu-sample.sh" hf60 hf60-gpu.mp4
COMP=probe60 bash "$here/gpu-sample.sh" remotion rem60-gpu.mp4
COMP=probe60 bash "$here/gpu-sample.sh" remotion remangle60-gpu.mp4 --gl=angle
