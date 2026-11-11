#!/usr/bin/env bash
# Measure the machine it runs on and print one JSON line: the fixed probe. Setup
# runs it here, and a scratch thread runs it on each linked machine, where the
# script text arrives in the thread's message because that machine has no
# checkout of this repo; placement runs it here for this machine's live load.
# Nothing in it reads or prints a host name, user, key or quota: a machine is
# known by its T3 environment id.
#
#   probe --json
#
# stdout: {cores, ram_gb, free_gb, load1, gpu, gpu_failed, clis, gh_logins}:
#         `ram_gb` rounded, `free_gb` the memory available now and `load1` the
#         1-minute load average, one decimal each; `gpu` the first GPU's name,
#         null with no `nvidia-smi`, and with one that fails null too and
#         `gpu_failed` true, since a failed read is no verdict; `clis` a boolean
#         per tool (claude, codex, agy, gh, bun); `gh_logins` the logins `gh`
#         holds for github.com, [] with none. A failure is {error}
# exit: 0 a probe · 2 `jq` missing, or `nproc`, `free` or `uptime` failed
#
# Linux only: see the operating system line in SKILL.md.
set -uo pipefail
usage='usage: probe --json'
fail() { printf '{"error":"%s"}\n' "$1"; printf '%s\n' "$1" >&2; exit 2; }
# Self-contained, since the script text travels to a machine with no checkout:
# it cannot source _lib.sh for its help.
if [ "${1:-}" = --help ] && [ $# -eq 1 ]; then
  printf '%s\n' "$usage"
  awk '/^# stdout:/ { f = 1 } f { if ($0 !~ /^#/ || /^# exit:/) exit; sub(/^# ?/, ""); print }' "${BASH_SOURCE[0]}"
  exit 0
fi
[ "${1:-}" = --json ] && [ $# -eq 1 ] || fail "$usage"
command -v jq >/dev/null || fail "jq not installed"
cores=$(nproc 2>/dev/null) || fail "nproc failed: cannot size this machine"
mem=$(free -m 2>/dev/null | awk '/^Mem:/ { print $2, $7 }')
[ -n "$mem" ] || fail "free -m failed: cannot size this machine"
load1=$(LC_ALL=C uptime 2>/dev/null | sed -n 's/.*load average: *\([0-9.]*\),.*/\1/p')
[ -n "$load1" ] || fail "uptime failed: cannot read the load"
gpu='' gpu_failed=false
if command -v nvidia-smi >/dev/null; then
  gpu=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null </dev/null | sed -n 1p)
  [ -n "$gpu" ] || gpu_failed=true
fi
clis='{}'
for c in claude codex agy gh bun; do
  if command -v "$c" >/dev/null; then v=true; else v=false; fi
  clis=$(jq -c --arg c "$c" --argjson v "$v" '.[$c] = $v' <<<"$clis")
done
logins='[]'
if command -v gh >/dev/null && acct=$(gh auth status --json hosts 2>/dev/null </dev/null); then
  logins=$(jq -c '[.hosts["github.com"][]?.login]' <<<"$acct" 2>/dev/null) || logins='[]'
fi
read -r total avail <<<"$mem"
jq -cn --argjson c "$cores" --argjson t "$total" --argjson a "$avail" --argjson l "$load1" \
  --arg g "$gpu" --argjson gf "$gpu_failed" --argjson clis "$clis" --argjson logins "$logins" \
  '{cores: $c, ram_gb: (($t + 512) / 1024 | floor), free_gb: ($a / 1024 * 10 | round / 10), load1: $l,
    gpu: (if $g == "" then null else $g end), gpu_failed: $gf, clis: $clis, gh_logins: $logins}'
