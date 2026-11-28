#!/usr/bin/env bash
# The machine check: one fixed, read-only check run on a fleet machine over its
# `ssh` string (a linked machine or a check-only one). There is no free-form
# command, so read-only is a property of this script: each check sends the one
# command below, and nothing here calls sudo.
#
#   machine-check [--fleet <file>] <machine> <check>
#
#   up                  the host answers
#   load                load average and memory
#   disk                filesystem use
#   gpu                 GPU name, memory and use
#   t3                  the T3 service's state and the CLI's version
#   clis                the agent CLIs' versions
#   process <name>      how many processes of that exact plain name run
#   log <unit> [lines]  a systemd unit's journal, system or user, or a file the
#                       fleet file lists under the machine's `logs`; 50 lines by
#                       default, at most 200
#
# --fleet defaults to `super-agent/fleet.json` under $XDG_CONFIG_HOME. One
# attempt, batch mode, a 6 second connect timeout and strict host keys
# (lib/ssh.sh): no retry, no fallback to a thread, and nothing it answers changes
# placement.
#
# stdout: {machine, check, result, output, reason}: `result` is `ok` (`output` what
#         the machine printed), `unreachable` (`reason` ssh's last error line, or
#         `unknown-host-key`), `needs-root` (the read was denied to this user; never
#         retried with sudo) or `failed` (`reason` the command's last error line)
# exit: 0 a check ran, whatever its result · 2 usage: an unknown check, a process
#       name that is no plain name, a log that is no unit and no listed file, a
#       line count over 200, a machine the fleet file lacks or one with no `ssh`
set -uo pipefail
here=$(dirname "${BASH_SOURCE[0]}")
source "$here/_lib.sh" || { printf '{"error":"cannot source _lib.sh"}\n'; exit 2; }
source "$here/lib/ssh.sh" || { printf '{"error":"cannot source lib/ssh.sh"}\n'; exit 2; }

usage='usage: machine-check [--fleet <file>] <machine> (up | load | disk | gpu | t3 | clis | process <name> | log <unit or file> [lines])'
sa_help "$usage" "$@"
fleet=$sa_default_fleet
if [ "${1:-}" = --fleet ]; then sa_flag_value "$usage" "${2:-}"; fleet=$2; shift 2; fi
[ $# -ge 2 ] || sa_tooling "$usage"
machine=$1 check=$2; shift 2

case $check in
  up|load|disk|gpu|t3|clis) [ $# -eq 0 ] || sa_tooling "$usage" ;;
  process) [ $# -eq 1 ] || sa_tooling "$usage"
    [[ $1 =~ ^[A-Za-z0-9_][A-Za-z0-9._-]*$ ]] || sa_tooling "process: '$1' is no plain process name" ;;
  log) [ $# -ge 1 ] && [ $# -le 2 ] || sa_tooling "$usage"
    lines=${2:-50}
    [[ $lines =~ ^[0-9]+$ ]] && [ "$lines" -ge 1 ] && [ "$lines" -le 200 ] || sa_tooling "log: lines must be 1 to 200, not '$lines'" ;;
  *) sa_tooling "$usage" ;;
esac

[ -f "$fleet" ] || sa_tooling "$fleet: no such file (run setup first)"
mj=$(jq -c --arg m "$machine" '.machines[$m] // empty | objects' "$fleet" 2>/dev/null)
[ -n "$mj" ] || sa_tooling "$fleet: $machine is not in machines"
target=$(jq -r '.ssh // empty | strings' <<<"$mj")
[ -n "$target" ] || sa_tooling "$machine has no ssh string in $fleet (run setup)"
jq -e '(.logs // []) | type == "array" and all(.[]; type == "string")' <<<"$mj" >/dev/null \
  || sa_tooling "$fleet: machines.$machine.logs must be an array of strings"
sa_ssh_target_ok "$target" || sa_tooling "$machine: ssh string '$target' starts with -, so ssh would read it as an option"

case $check in
  up) cmd='echo up' ;;
  load) cmd='cat /proc/loadavg && free -m' ;;
  disk) cmd='df -hP -x tmpfs -x devtmpfs -x squashfs -x overlay' ;;
  gpu) cmd='nvidia-smi --query-gpu=name,memory.used,memory.total,utilization.gpu --format=csv,noheader' ;;
  t3) cmd='systemctl --user is-active t3code.service; t3 --version' ;;
  clis) cmd='for c in claude codex agy gh t3; do printf "%s: " "$c"; if command -v "$c" >/dev/null; then "$c" --version 2>&1 | head -n1; else echo missing; fi; done' ;;
  # pgrep exits 1 on no match (printing 0); 2, 3 or 127 is a failed read
  process) cmd="pgrep -c -x -- $1; [ \$? -le 1 ]" ;;
  log)
    if jq -e --arg f "$1" '(.logs // []) | index($f)' <<<"$mj" >/dev/null; then
      cmd="tail -n $lines -- $(printf '%q' "$1")"
    elif [[ $1 =~ ^[A-Za-z0-9_][A-Za-z0-9@._:-]*$ ]]; then
      cmd="journalctl -n $lines --no-pager -u $1 --user-unit $1"
    else sa_tooling "log: '$1' is no unit name and no file listed under machines.$machine.logs"; fi ;;
esac

errf=$(mktemp) || sa_tooling "mktemp failed"
trap 'rm -f "$errf"' EXIT
out=$(ssh "${sa_ssh_opts[@]}" "$target" "$cmd" 2>"$errf" </dev/null); rc=$?
err=$(cat "$errf")
answer() { jq -cn --arg m "$machine" --arg c "$check" --arg r "$1" --arg o "$2" --arg why "$3" \
  '{machine: $m, check: $c, result: $r, output: (if $r == "ok" then $o else null end), reason: (if $why == "" then null else $why end)}'; }
if [ "$rc" = 255 ]; then answer unreachable '' "$(sa_ssh_reason "$err")"
# journalctl exits 0 and prints its hint whenever the system journal is closed to
# this user, so the hint means needs-root only when no entry came back
elif { grep -q 'not seeing messages from other users' <<<"$err" && ! grep -qv -e '^-- No entries --$' -e '^$' <<<"$out"; } \
  || { [ "$rc" != 0 ] && grep -qiE 'permission denied|insufficient permissions' <<<"$err"; }; then answer needs-root '' ''
elif [ "$rc" != 0 ]; then answer failed '' "$(sa_last_line "$err")"
else answer ok "$out" ''; fi
