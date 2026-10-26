#!/usr/bin/env bash
# Five alternating rounds: HyperFrames default, Remotion default, Remotion --gl=angle.
here="$(cd "$(dirname "$0")" && pwd)"
for i in 1 2 3 4 5; do
  bash "$here/render-one.sh" hf "hf-$i.mp4"
  bash "$here/render-one.sh" remotion "rem-$i.mp4"
  bash "$here/render-one.sh" remotion "remangle-$i.mp4" --gl=angle
done
