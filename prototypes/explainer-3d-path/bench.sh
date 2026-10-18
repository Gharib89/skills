#!/usr/bin/env bash
# PROTOTYPE: timed renders, alternating variants, 5 rounds.
#   live-gpu  live Three.js, HyperFrames' auto GPU probe (hardware here)
#   live-sw   live Three.js, --no-browser-gpu (SwiftShader); HyperFrames then
#             captures by screenshot, and at 3 workers stores every frame on
#             disk (about 4.5 GB for this slice) unless streaming is opted in
#   clip-cold the 3D clip rendered, then the composite with an empty frame cache
#   clip-warm the composite again, clip and frame cache reused
#   flat      the shipped 2D slice, the baseline
# usage: bench.sh <work dir> [first round] [first variant of that round]
set -euo pipefail
W=$1; FROM=${2:-1}; SKIP=${3:-}; H=$(dirname "$0"); O=$W/out; mkdir -p "$O"
log=$O/bench.jsonl
run() { node "$H/hf.mjs" "$@" --quiet 2>/dev/null | tail -1 >>"$log"; }
for i in $(seq "$FROM" 5); do
  if [ "$SKIP" != live-sw ]; then
  run "$W/live" "$O/live-gpu-$i.mp4"
  rm -rf "$W/fc-$i"
  t0=$(date +%s.%N)
  run "$W/clip3d" "$O/trails-3d-$i.mp4"
  cp "$O/trails-3d-$i.mp4" "$W/clip/trails-3d.mp4"
  run "$W/clip" "$O/clip-cold-$i.mp4" --frames-cache-dir "$W/fc-$i"
  echo "{\"variant\":\"clip-cold-total\",\"i\":$i,\"wall\":$(echo "$(date +%s.%N) - $t0" | bc)}" >>"$log"
  run "$W/clip" "$O/clip-warm-$i.mp4" --frames-cache-dir "$W/fc-$i"
  fi
  SKIP=
  HF_CAPTURE_PARALLEL_STREAM=true run "$W/live" "$O/live-sw-$i.mp4" --no-browser-gpu
  rm -rf "$W/fc-$i"
  run "$W/flat" "$O/flat-$i.mp4"
done
echo "done" >>"$log"
