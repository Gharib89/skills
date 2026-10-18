#!/usr/bin/env bash
# PROTOTYPE: renders every composition build.mjs wrote, plus a second render of
# snapped s2 (determinism) and an edited s2 (one section re-rendered).
# usage: ./bench.sh <work dir>
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
w=$1
mkdir -p "$w/renders"
rm -rf "$w/snapped/s2edit"
cp -r "$w/snapped/s2" "$w/snapped/s2edit"
sed -i 's/>Documentation quality</>Docs that stay current</' "$w/snapped/s2edit/scenes/climate.html"
: >"$w/bench.jsonl"
for job in naive/whole naive/s1 naive/s2 naive/s3 snapped/whole snapped/s1 snapped/s2 snapped/s3 snapped/s2edit snapped/s2:again; do
  dir=${job%%:*}
  name=${job//[\/:]/-}
  node "$here/hf.mjs" "$w/$dir" "$w/renders/$name.mp4" --quality looks >>"$w/bench.jsonl"
done
# Lossless (CRF 0): the captured pictures themselves, free of encoder state.
for dir in snapped/whole snapped/s1 snapped/s2 snapped/s3; do
  node "$here/hf.mjs" "$w/$dir" "$w/renders/${dir//\//-}-crf0.mp4" --quality looks --crf 0 >>"$w/bench.jsonl"
done
