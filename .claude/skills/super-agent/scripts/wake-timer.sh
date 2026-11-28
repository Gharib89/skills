#!/usr/bin/env bash
# The wake timer: one tick of the systemd user timer that wakes the super agent
# when its own turn died (a limit stop, an auth error) or a host restart
# cancelled its watcher. No model runs and no heartbeat file is kept: the tick
# asks `watch.sh --owed` and reads the super agent's own thread (`own_thread` in
# the ledger) with the T3 CLI.
#
#   wake-timer [--ledger <file>] [--fleet <file>]
#
# An outage opens at the first tick that finds a watcher owed (`watcher` or
# `reconcile`), bar a held limit stop. With the thread idle, it sends the
# thread one fixed line, `Wake timer: no watcher is running. Run pulse and
# restart the watcher.` When the send fails, or no reconcile stamp
# (`<ledger>.reconciled`) follows the wake within the fleet file's notify delay
# (600 s when unset), it runs the fleet file's notify command with
# `SA_NOTIFY_MESSAGE` set. A running thread is left to the watch guard. A
# permission request pending on the thread for 600 s or more is notified, with
# no wake. A limit stop is held until its reset plus 600 s, closing an outage
# open when the hold starts, so a hold is never counted; a reset it cannot
# read falls through to a wake. With T3 not answering, or no notify command or
# own thread recorded, the desktop notifier (`notify-send`) stands in for the
# command, as it does for a fleet file whose `notify` is malformed, a fault the
# message names. An outage gets one wake and at most one notify, and closes at
# the first reconcile at or after its opening, or when no watcher is owed any
# more. Its state is `wake-timer.state.json` beside the ledger; one that is no
# JSON object stops the tick with a desktop notice naming it, never a reset.
#
# Each outage is logged as JSON lines in `wake-timer.jsonl` beside the ledger:
# `{at, event}`, `event` `opened`, `wake`, `notify` (with `via` `command` or
# `desktop`, its `why` and `exit`) and `closed` (with `minutes`, opening to
# close), which the scorecard reads. Defaults: the ledger is
# `super-agent/ledger.json` under $XDG_STATE_HOME, the fleet file
# `super-agent/fleet.json` under $XDG_CONFIG_HOME. `guard.sh --install` prints
# the unit files that run it every 5 minutes.
#
# contract: bare-run
# stdout: {owed, action}: `owed` the `watch.sh --owed` answer (null when it
#         failed), `action` one of none, running, held, pending, waiting, wake,
#         notify or unjudged
# exit: 0 a tick, whatever it found · 2 usage
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh" || { printf '{"error":"cannot source _lib.sh"}\n'; exit 2; }

usage='usage: wake-timer [--ledger <file>] [--fleet <file>]'
sa_help "$usage" "$@"
ledger=${XDG_STATE_HOME:-$HOME/.local/state}/super-agent/ledger.json
fleet=$sa_default_fleet
while [ $# -gt 0 ]; do
  case $1 in
    --ledger) sa_flag_value "$usage" "${2:-}"; ledger=$2 ;;
    --fleet) sa_flag_value "$usage" "${2:-}"; fleet=$2 ;;
    *) sa_tooling "$usage" ;;
  esac
  shift 2
done
notify_cmd='' notify_delay=600
# A malformed notify must not silence the tick: nobody reads the journal, so the
# desktop notifier stands in and its message names the fault.
bad_notify=''
if [ -f "$fleet" ] && ! (sa_notify_read "$fleet") >/dev/null 2>&1; then bad_notify=" ($fleet: malformed notify)"
elif [ -f "$fleet" ]; then sa_notify_read "$fleet"; fi
wake_line='Wake timer: no watcher is running. Run pulse and restart the watcher.'
hold=600
dir=$(dirname "$ledger") now=$(sa_now_s)
log=$dir/wake-timer.jsonl statef=$dir/wake-timer.state.json
state='{}'
# A state file that is no JSON object is refused, never reset: a reset would
# forget the outage's wake and notify and send them again.
if [ -e "$statef" ] && ! state=$(jq -ce 'select(type == "object")' "$statef" 2>/dev/null); then
  notify-send "Super agent" "Super agent: $statef is no JSON object; the wake timer is stopped until it is fixed or removed" >/dev/null 2>&1 </dev/null
  jq -cn '{owed: null, action: "unjudged"}'; exit 0
fi

# event <name> [<json fields>]: one log line.
event() {
  local f=${2:-}
  [ -n "$f" ] || f='{}'
  jq -cn --arg a "$(date -u -d "@$now" +%Y-%m-%dT%H:%M:%SZ)" --arg e "$1" --argjson f "$f" '{at: $a, event: $e} + $f' >> "$log"
}
put() { state=$(jq -c "$1" <<<"$state"); }
answer() { # <owed> <action>
  jq -cn --arg o "$1" --arg a "$2" '{owed: (if $o == "" then null else $o end), action: $a}'
  # Written whole, then renamed, so an interrupted tick leaves the old state.
  if [ "$state" = '{}' ]; then rm -f "$statef"; else printf '%s\n' "$state" > "$statef.tmp" && mv "$statef.tmp" "$statef"; fi
  exit 0
}
open_outage() { [ "$(jq -r '.opened // empty' <<<"$state")" ] || { put ".opened = $now"; event opened; }; }
# alarm <via: command|desktop> <why>: the outage's one notify.
alarm() {
  local via=$1 rc=0 msg="Super agent: $2$bad_notify"
  # already notified: nothing runs, so the tick only waits
  [ "$(jq -r '.notified // false' <<<"$state")" = false ] || answer "$owed" waiting
  [ -n "$notify_cmd" ] || via=desktop
  if [ "$via" = command ]; then
    SA_NOTIFY_MESSAGE=$msg bash -c "$notify_cmd" >/dev/null 2>&1 </dev/null || rc=$?
  else
    notify-send "Super agent" "$msg" >/dev/null 2>&1 </dev/null || rc=$?
  fi
  put '.notified = true'
  event notify "$(jq -cn --arg v "$via" --arg w "$2" --argjson r "$rc" '{via: $v, why: $w, exit: $r}')"
}

# A reconcile at or after the opening closes the outage.
stamp=$(cat "$ledger.reconciled" 2>/dev/null)
case $stamp in ''|*[!0-9]*) stamp=0 ;; esac
opened=$(jq -r '.opened // 0' <<<"$state")
close() { # <epoch>
  event closed "$(jq -cn --argjson m "$((($1 - opened + 30) / 60))" '{minutes: $m}')"
  state='{}'
}
if [ "$opened" -gt 0 ] && [ "$stamp" -ge "$opened" ]; then close "$stamp"; opened=0; fi

owed=$(bash "$(dirname "${BASH_SOURCE[0]}")/watch.sh" --ledger "$ledger" --owed 2>/dev/null | jq -r '.owed // empty' 2>/dev/null)
case $owed in
  watcher|reconcile) ;;
  none) [ "$opened" -eq 0 ] || close "$now"; answer none none ;;
  *) answer '' unjudged ;;
esac

# overdue: the wake went out a delay ago and no reconcile closed the outage.
late="no reconcile followed the wake timer's wake within ${notify_delay}s"
overdue() { local w; w=$(jq -r '.wake_at // empty' <<<"$state"); [ -n "$w" ] && [ $((now - w)) -ge "$notify_delay" ]; }

sa_read "$ledger"
own=$(jq -r '.own_thread // empty' <<<"$doc")
if [ -z "$own" ]; then open_outage; alarm desktop "a watcher is owed and the ledger holds no own_thread to wake"; answer "$owed" notify; fi
if ! sa_observe "$(jq -cn --arg t "$own" '{thread: $t}')"; then
  open_outage; alarm desktop "a watcher is owed and T3 does not answer for thread $own ($obs_kind)"; answer "$owed" notify
fi
reset=$(jq -r '.limit_reset // empty' <<<"$obs")
if [ -n "$reset" ] && [ "$now" -lt $((reset + hold)) ]; then
  # A held limit stop is never counted: an outage already open closes here.
  [ "$opened" -eq 0 ] || close "$now"
  answer "$owed" held
fi
open_outage

if [ "$(jq -r .pending <<<"$obs")" -gt 0 ]; then
  since=$(jq -r ".pending_since // $now" <<<"$state"); put ".pending_since = $since"
  [ $((now - since)) -ge "$hold" ] || answer "$owed" pending
  alarm command "a permission request has waited $(((now - since) / 60)) minutes on thread $own"; answer "$owed" notify
fi
put 'del(.pending_since)'
if [ "$(jq -r .status <<<"$obs")" = running ]; then
  ! overdue || { alarm command "$late"; answer "$owed" notify; }
  answer "$owed" running
fi
if [ -z "$(jq -r '.wake_at // empty' <<<"$state")" ]; then
  if t3 thread send "$own" "$wake_line" >/dev/null 2>&1 </dev/null; then
    put ".wake_at = $now"; event wake; answer "$owed" wake
  fi
  alarm command "the wake timer could not send its wake line to thread $own"; answer "$owed" notify
fi
overdue || answer "$owed" waiting
alarm command "$late"; answer "$owed" notify
