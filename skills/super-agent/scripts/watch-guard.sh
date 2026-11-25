#!/usr/bin/env bash
# The watch guard: a Stop hook that refuses the super agent's turn end once while
# a watcher is owed. It asks `watch.sh --owed`, the one test of whether a watcher
# is owed. With a watcher owed (`watcher`, or `reconcile` first) it blocks the
# stop and names the open entries and the exact command to run; the stop that
# follows (the hook input's `stop_hook_active` true) passes. The super agent
# still starts the watcher itself, so a missing hook leaves the loop working.
#
#   watch-guard [--ledger <file>] [--fleet <file>]      (the Stop JSON on stdin)
#
# The ledger defaults to `super-agent/ledger.json` under $XDG_STATE_HOME and the
# fleet file to `super-agent/fleet.json` under $XDG_CONFIG_HOME. Each block, each
# stop passed with a watcher still owed and each stop it could not judge appends
# a JSON line `{at, event}` to `watch-guard.jsonl` beside the ledger, `event`
# `block`, `pass` or `unjudged` (with a `why`); the scorecard counts the first
# two. A hook that cannot judge (no `jq`, an unreadable ledger or input, a failed
# `watch.sh --owed`) allows the stop: a guard rail, never a gate on the turn.
# Written by `setup.sh --write` and every handover into the super agent folder's
# generated settings.
#
# contract: bare-run
# stdout: a block prints {decision: "block", reason}; anything else prints nothing
#         (a usage error prints its error JSON, which carries no decision)
# exit: 0 the stop is allowed, or blocked by the decision on stdout; always 0 (a
#       usage error is logged unjudged), since a Stop hook's exit 2 blocks the stop
set -uo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
state=${XDG_STATE_HOME:-$HOME/.local/state}/super-agent
ledger=$state/ledger.json fleet=${XDG_CONFIG_HOME:-$HOME/.config}/super-agent/fleet.json
# The log's place is known before _lib.sh (which needs jq) is sourced.
for ((i = 1; i < $#; i++)); do [ "${!i}" = --ledger ] && ledger=${*:i+1:1}; done
log=$(dirname "$ledger")/watch-guard.jsonl

# log <event> [<why>]: one line, written without jq so a missing jq still leaves one.
log() {
  local why=''
  [ -z "${2:-}" ] || why=",\"why\":\"$2\""
  { mkdir -p "$(dirname "$log")" && printf '{"at":"%s","event":"%s"%s}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" "$why" >> "$log"; } 2>/dev/null
  return 0
}
unjudged() { log unjudged "$1"; exit 0; }
# A usage error exits 2, which a Stop hook reads as a block with no way out.
trap '[ $? -ne 2 ] || unjudged "a usage error"' EXIT

command -v jq >/dev/null 2>&1 || unjudged "no jq"
source "$here/_lib.sh" || unjudged "cannot source _lib.sh"
usage='usage: watch-guard [--ledger <file>] [--fleet <file>]'
sa_help "$usage" "$@"
while [ $# -gt 0 ]; do
  case $1 in
    --ledger) sa_flag_value "$usage" "${2:-}"; ledger=$2 ;;
    --fleet) sa_flag_value "$usage" "${2:-}"; fleet=$2 ;;
    *) sa_tooling "$usage" ;;
  esac
  shift 2
done
input=$(cat)
active=$(jq -r 'if type == "object" and (.stop_hook_active | type) == "boolean" then .stop_hook_active else error("no boolean stop_hook_active") end' <<<"$input" 2>/dev/null) || unjudged "the hook input is not a JSON object with a boolean stop_hook_active"
[ -n "$active" ] || unjudged "the hook input is empty"
answer=$(bash "$here/watch.sh" --ledger "$ledger" --owed 2>/dev/null) || unjudged "watch.sh --owed failed"
owed=$(jq -r '.owed // empty' <<<"$answer" 2>/dev/null)
open=$(jq -r '.open // empty' <<<"$answer" 2>/dev/null)
case $owed in
  none) exit 0 ;;
  watcher|reconcile) ;;
  *) unjudged "watch.sh --owed answered no owed value" ;;
esac
if [ "$active" = true ]; then log pass; exit 0; fi

watcher="bash $(sa_shq "$here/watch.sh") --ledger $(sa_shq "$ledger") --fleet $(sa_shq "$fleet") --timeout 7000"
if [ "$owed" = reconcile ]; then
  what="$open open entries have no observed state yet. Run \`bash $(sa_shq "$here/reconcile.sh") --ledger $(sa_shq "$ledger") --fleet $(sa_shq "$fleet")\`, then start the watcher with \`$watcher\` (each remote entry also takes reconcile's \`--remote <environment id>=<dir>\`, as SKILL.md says)"
else
  what="$open open entries and no watcher is running. Start it with \`$watcher\`"
fi
log block
jq -cn --arg r "Watch guard: $what in the background (Bash run_in_background true, timeout 7200000), then end the turn." '{decision: "block", reason: $r}'
exit 0
