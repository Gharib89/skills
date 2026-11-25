#!/usr/bin/env bash
# The wake timer: one tick of the systemd user timer that wakes the super agent
# when its own turn died (a limit stop, an auth error) or a host restart
# cancelled its watcher. No model runs and no heartbeat file is kept: the tick
# asks `watch.sh --owed` and reads the super agent's own thread (`own_thread` in
# the ledger) with the T3 CLI.
#
#   wake-timer [--ledger <file>] [--fleet <file>]
#
# With a watcher owed (`watcher` or `reconcile`) and the thread idle, it opens an
# outage and sends the thread one fixed line, `$wake_line` below. When the send
# fails, or no reconcile stamp (`<ledger>.reconciled`) follows the wake within
# the fleet file's notify delay (600 s when unset), it runs the fleet file's
# notify command with `SA_NOTIFY_MESSAGE` set. A running thread is left to the
# watch guard. A permission request pending on the thread for 600 s or more is
# notified, with no wake. A limit stop is held until its reset plus 600 s; a
# reset it cannot read falls through to a wake. With T3 not answering, or no
# notify command or own thread recorded, the desktop notifier (`notify-send`)
# stands in for the command. An outage gets one wake and at most one notify, and
# closes at the first reconcile at or after its opening, or when no watcher is
# owed any more. Its state is `wake-timer.state.json` beside the ledger.
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
# exit: 0 a tick, whatever it found · 2 usage, or a fleet file whose notify is
#       malformed
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh" || { printf '{"error":"cannot source _lib.sh"}\n'; exit 2; }
usage='usage: wake-timer [--ledger <file>] [--fleet <file>]'
sa_help "$usage" "$@"
[ $# -eq 0 ] || [ "$1" = --ledger ] || sa_tooling "$usage"
jq -cn '{owed: null, action: "none"}'
