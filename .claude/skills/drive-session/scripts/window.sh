#!/usr/bin/env bash
# Report whether a render, a calibration or a full check is running on this
# machine, so the supervisor hands the quiet window on only when none is: a
# session asked for the window, and the hand-off came at 00:03 on 10-22 while a
# probe still ran.
#
#   window
#
# Reads the process table once and names each process it holds: a
# `real-render*` script, `hyperframes`, a `calibrate*` script, or `check.sh`
# given `full`. A process counts by the program it runs, which is its first word
# or, behind an interpreter (`node`, `bash`, `npx`, ...), the first word after
# its flags: an editor or a `grep` that merely names the file is no render. It
# reads no roster and runs outside Herdr.
#
# stdout: {running: []} when nothing runs; else {error, running}, `running`
#         one {pid, name} per process in table order, `name` one of
#         `real-render`, `hyperframes`, `calibrate`, `check.sh full`
# exit: 0 nothing running · 1 something runs (the answer is also on stderr) · 2
#       usage, ps missing, or a process table it cannot read (ps failing or
#       printing nothing)
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh" || { printf '{"error":"cannot source _lib.sh"}\n'; exit 2; }

usage='usage: window'
ds_help "$usage" "$@"
[ $# -eq 0 ] || ds_tooling "$usage"
command -v ps >/dev/null || ds_tooling "ps not installed"

table=$(ps -eo pid=,args= 2>/dev/null)
# A live table always lists ps itself: an empty one is a failed read, never "nothing runs".
[ -n "$table" ] || ds_tooling "window: cannot read the process table"
running=$(awk '
  function strip(t) { gsub(/["\047]/, "", t); return t }
  function base(t) { t = strip(t); sub(/.*\//, "", t); return t }
  function kind(t, next_word,   b) {
    b = base(t)
    if (b ~ /^real-render[a-z-]*(\.mjs)?$/) return "real-render"
    if (b ~ /^hyperframes(\.mjs)?$/ || strip(t) ~ /(^|\/)hyperframes\//) return "hyperframes"
    if (b ~ /^calibrate[a-z-]*(\.(mjs|sh))?$/) return "calibrate"
    if (b == "check.sh" && base(next_word) == "full") return "check.sh full"
    return ""
  }
  BEGIN { n = split("node bash sh zsh npx bunx bun pnpm tsx python python3 uv", w, " "); for (i = 1; i <= n; i++) interpreter[w[i]] = 1 }
  {
    i = 2
    if (base($2) in interpreter) { i = 3; while (i <= NF && $i ~ /^-/) i++ }
    k = kind($i, $(i + 1))
    if (k != "") print $1 "\t" k
  }' <<<"$table" | jq -Rn '[inputs | split("\t") | {pid: (.[0] | tonumber), name: .[1]}]') \
  || ds_tooling "window: cannot read the process table"

if [ "$(jq length <<<"$running")" -eq 0 ]; then
  jq -cn '{running: []}'
  exit 0
fi
msg="a render, calibration or check is running: $(jq -r 'map("\(.name) (pid \(.pid))") | join(", ")' <<<"$running")"
jq -c --arg e "$msg" '{error: $e, running: .}' <<<"$running"
printf '%s\n' "$msg" >&2
exit 1
