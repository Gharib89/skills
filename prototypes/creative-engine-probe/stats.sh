#!/usr/bin/env bash
# Usage: stats.sh <results file>...: median and range of wall seconds per mode (prefix of the output name).
cat "$@" | grep -E '^(hf|remotion)' | awk '{n=$2; sub(/-[0-9a-z]+\.mp4$/, "", n); print n, $3}' | sort -k1,1 -k2,2n |
  awk '{v[$1]=v[$1] " " $2; c[$1]++} END{for (k in v){split(substr(v[k],2), a, " "); m=c[k]; med=(m%2)?a[(m+1)/2]:(a[m/2]+a[m/2+1])/2; printf "%-12s n=%d median %.2f s, range %.2f to %.2f\n", k, m, med, a[1], a[m]}}'
