#!/usr/bin/env bash
# For each prefix, compare decoded frames of run 1 against runs 2..5 (ffmpeg framemd5).
here="$(cd "$(dirname "$0")" && pwd)"
cd "$here/out" || exit 1
for f in *.mp4; do
  ffmpeg -loglevel error -i "$f" -map 0:v -f framemd5 - | grep -v '^#' | awk -F', ' '{print $NF}' >"${f%.mp4}.md5"
done
for p in hf rem remangle; do
  for i in 2 3 4 5; do
    printf '%s run1 vs run%s: %s of %s frames differ\n' "$p" "$i" \
      "$(paste -d' ' "$p-1.md5" "$p-$i.md5" | awk '$1!=$2' | wc -l)" "$(wc -l <"$p-1.md5")"
  done
done
printf 'rem vs remangle run1: %s frames differ\n' "$(paste -d' ' rem-1.md5 remangle-1.md5 | awk '$1!=$2' | wc -l)"
printf 'unique frames hf-1: %s, rem-1: %s\n' "$(sort -u hf-1.md5 | wc -l)" "$(sort -u rem-1.md5 | wc -l)"
