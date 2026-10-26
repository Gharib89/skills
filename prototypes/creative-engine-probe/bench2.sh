#!/usr/bin/env bash
# Second batch: five more alternating 10 s rounds, then three alternating 60 s rounds.
here="$(cd "$(dirname "$0")" && pwd)"
for i in 6 7 8 9 10; do
  bash "$here/render-one.sh" hf "hf-$i.mp4"
  bash "$here/render-one.sh" remotion "rem-$i.mp4"
  bash "$here/render-one.sh" remotion "remangle-$i.mp4" --gl=angle
done
for i in 1 2 3; do
  bash "$here/render-one.sh" hf60 "hf60-$i.mp4"
  COMP=probe60 bash "$here/render-one.sh" remotion "rem60-$i.mp4"
  COMP=probe60 bash "$here/render-one.sh" remotion "remangle60-$i.mp4" --gl=angle
done
