#!/usr/bin/env bash
# One identical lit Three.js scene (lit/scene.mjs), 4 s: five alternating rounds per mode, then frame hashes.
here="$(cd "$(dirname "$0")" && pwd)"
for i in 2 3 4 5 6; do
  bash "$here/render-one.sh" hflit "hflit-$i.mp4"
  COMP=lit bash "$here/render-one.sh" remotion "remlit-$i.mp4" --gl=angle
  COMP=lit bash "$here/render-one.sh" remotion "remlitsw-$i.mp4"
done
cd "$here/out" || exit 1
for f in hflit-*.mp4 remlit-*.mp4 remlitsw-*.mp4; do
  ffmpeg -loglevel error -i "$f" -map 0:v -f framemd5 - | grep -v '^#' | awk -F', ' '{print $NF}' >"${f%.mp4}.md5"
done
for p in hflit remlit; do
  for i in 2 3 4 5 6; do
    printf '%s run1 vs run%s: %s of %s frames differ\n' "$p" "$i" \
      "$(paste -d' ' "$p-1.md5" "$p-$i.md5" | awk '$1!=$2' | wc -l)" "$(wc -l <"$p-1.md5")"
  done
done
for i in 3 4 5 6; do
  printf 'remlitsw run2 vs run%s: %s frames differ\n' "$i" "$(paste -d' ' remlitsw-2.md5 "remlitsw-$i.md5" | awk '$1!=$2' | wc -l)"
done
printf 'hflit-1 vs remlit-1: %s frames differ\n' "$(paste -d' ' hflit-1.md5 remlit-1.md5 | awk '$1!=$2' | wc -l)"
