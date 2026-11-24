#!/usr/bin/env bash
# tokall.sh <dir>: token count of every part file, minus the 937-token empty-request baseline ("x" reads 938).
cd "$(dirname "$0")" || exit 1
for f in "$1"/*.txt; do
  [ -s "$f" ] || continue
  n=$(basename "$f" .txt); grep -q "^$n	" "$1/tokens.tsv" 2>/dev/null && continue
  for _ in 1 2 3; do
    t=$(./tok.sh "$f" | jq -r '.in // empty' 2>/dev/null); [ -n "$t" ] && break
  done
  printf '%s\t%s\t%s\n' "$n" "$(wc -c < "$f")" "$(( ${t:-0} - 937 ))" >> "$1/tokens.tsv"
done
sort -t$'\t' -k3 -n -r "$1/tokens.tsv"
