#!/bin/bash
# seq.sh <comp> <gl> <run> [concurrency]: render all frames as PNG, print per-frame md5 to out/seq/<comp>-<gl>-<run>.md5
cd "$(dirname "$0")" || exit
c=$1; gl=$2; run=$3; conc=${4:-3}
d=out/seq/$c-$gl-$run
rm -rf "$d"; mkdir -p "$d"
start=$(date +%s.%N)
if ! npx remotion render src/index.ts "$c" "$d" --sequence --image-format=png --gl="$gl" --concurrency="$conc" --log=error >"$d.log" 2>&1; then
  echo "$c $gl $run FAIL: $(tail -3 "$d.log" | tr '\n' ' ')"; exit 1
fi
end=$(date +%s.%N)
(cd "$d" && md5sum *.png) > "$d.md5"
echo "$c $gl $run ok $(echo "$end - $start" | bc) s, $(wc -l < "$d.md5") frames"
