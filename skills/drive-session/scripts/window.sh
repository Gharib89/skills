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
# or, behind an interpreter or wrapper (`node`, `bash`, `env`, `timeout`, ...),
# any word after its leading flags, since a flag may take a value (`node -r
# dotenv/config x.mjs`), each split at the shell syntax glued to it (`;`, `&`,
# `|`, `(`, `>`). `ps` flattens quoting, newlines and the spaces in a path, so
# a line starting with an absolute path is also matched whole. The rule leans to
# over-reporting on purpose: a `bash -c` call that merely greps for a render
# script reads as running, which holds the window until the next `watch` wake,
# while a render it missed would be the failure this answers. Known gap:
# `check.sh` with a flag before `full`. It reads no roster and runs outside
# Herdr.
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

# A live table always lists ps itself: an empty or partial one is a failed read.
table=$(ps -eo pid=,args= 2>/dev/null) && [ -n "$table" ] \
  || ds_tooling "window: cannot read the process table"
running=$(awk '
  function strip(t) { gsub(/["\047)]/, "", t); return t }
  function base(t) { t = strip(t); sub(/.*\//, "", t); return t }
  function kind(t, next_word,   b) {
    b = base(t)
    if (b ~ /^real-render[a-z-]*(\.mjs)?$/) return "real-render"
    if (b ~ /^hyperframes(\.mjs)?$/ || strip(t) ~ /(^|\/)hyperframes\//) return "hyperframes"
    if (b ~ /^calibrate[a-z-]*(\.(mjs|sh))?$/) return "calibrate"
    if (b == "check.sh" && base(next_word) == "full") return "check.sh full"
    return ""
  }
  # ps flattens argv, so an absolute path holding a space reads as several words:
  # match the whole rest of the line, which may over-report (an editor handed an
  # absolute path to a render script) and never under-reports.
  function abskind(rest) {
    if (rest !~ /^\//) return ""
    if (rest ~ /^\/(.*\/)?real-render[a-z-]*(\.mjs)?( |$)/) return "real-render"
    if (rest ~ /^\/(.*\/)?hyperframes(\.mjs)?( |$)/ || rest ~ /^\/.*\/hyperframes\//) return "hyperframes"
    if (rest ~ /^\/(.*\/)?calibrate[a-z-]*(\.(mjs|sh))?( |$)/) return "calibrate"
    if (rest ~ /^\/(.*\/)?check\.sh full( |$)/) return "check.sh full"
    return ""
  }
  # A word may hold shell syntax glued to a program (`real-render.mjs;`, `x>o`,
  # `$(node`): check each piece between those characters.
  function wordkind(w, nw,   n, p, i, r) {
    sub(/[;&|)`<>].*/, "", nw)
    n = split(strip(w), p, /[;&|(`<>]/)
    for (i = 1; i <= n; i++) if (p[i] != "" && (r = kind(p[i], nw)) != "") return r
    return ""
  }
  BEGIN {
    n = split("node bash sh zsh npx bunx bun pnpm tsx python python3 uv env nohup timeout nice setsid time sudo xvfb-run", w, " ")
    for (i = 1; i <= n; i++) interpreter[w[i]] = 1
  }
  {
    i = 2; last = 2
    if (base($2) in interpreter) { i = 3; last = NF; while (i <= NF && $i ~ /^-/) i++ }
    k = ""
    for (m = i; k == "" && m <= last; m++) k = wordkind($m, $(m + 1))
    if (k == "") {
      rest = $i
      for (j = i + 1; j <= NF; j++) rest = rest " " $j
      k = abskind(rest)
    }
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
