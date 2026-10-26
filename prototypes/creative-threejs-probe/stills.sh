#!/bin/bash
# One still at frame 30 per composition per --gl mode.
cd "$(dirname "$0")" || exit
mkdir -p out/stills
for gl in angle angle-egl vulkan swangle; do
  for c in Opaque Transparent WebGPU; do
    f=30; [ "$c" = WebGPU ] && f=10
    if npx remotion still src/index.ts "$c" "out/stills/$c-$gl.png" --frame=$f --gl=$gl --log=error >"out/stills/$c-$gl.log" 2>&1; then
      echo "$c $gl ok"
    else
      echo "$c $gl FAIL: $(tail -3 out/stills/$c-$gl.log | tr '\n' ' ')"
    fi
  done
done
