#!/usr/bin/env bash
# Usage: render-one.sh <hf|remotion> <out-name> [extra args...]
# Renders the 10 s probe scene once and prints "<engine> <out> <wall seconds> <exit>".
set -u
here="$(cd "$(dirname "$0")" && pwd)"
engine="$1"; out="$here/out/$2"; shift 2
mkdir -p "$here/out" "$here/logs"
log="$here/logs/$(basename "$out").log"
export HYPERFRAMES_NO_TELEMETRY=1 DO_NOT_TRACK=1 HYPERFRAMES_NO_UPDATE_CHECK=1
start=$(date +%s.%N)
case "$engine" in
  hf*) (cd "$here/$engine" && ./node_modules/.bin/hyperframes render . -o "$out" --strict "$@") >"$log" 2>&1 ;;
  *) (cd "$here/remotion" && ./node_modules/.bin/remotion render src/index.ts "${COMP:-probe}" "$out" "$@") >"$log" 2>&1 ;;
esac
rc=$?
end=$(date +%s.%N)
printf '%s %s %.2f %d load1=%s\n' "$engine" "$(basename "$out")" "$(echo "$end - $start" | bc)" "$rc" "$(cut -d' ' -f1 /proc/loadavg)"
