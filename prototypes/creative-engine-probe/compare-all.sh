#!/usr/bin/env bash
# For each mode, how many runs differ from run 1 and the most frames any run differs by (needs *.md5 from determinism.sh).
cd "$(dirname "$0")/out" || exit 1
for p in hf rem remangle hf60 rem60 remangle60; do
  runs=0 bad=0 worst=0
  for f in "$p"-[0-9]*.md5; do
    [ "$f" = "$p-1.md5" ] && continue
    runs=$((runs + 1))
    d=$(paste -d' ' "$p-1.md5" "$f" | awk '$1!=$2' | wc -l)
    [ "$d" -gt 0 ] && bad=$((bad + 1))
    [ "$d" -gt "$worst" ] && worst=$d
  done
  printf '%-11s %d runs vs run 1: %d differ, worst %d of %d frames\n' "$p" "$runs" "$bad" "$worst" "$(wc -l <"$p-1.md5")"
done
