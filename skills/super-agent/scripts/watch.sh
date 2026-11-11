#!/usr/bin/env bash
# Wait until a supervised thread or its PR changes, then name the change and
# exit. Run it as a background command: it holds no tool call open, and its
# exit is what wakes the super agent.
#
#   watch --ledger <file> [--interval <s>] [--timeout <s>] [--recheck <s>]
#         [--stall-window <s>] [--remote <environment id>=<dir>]...
#
# Polls every open ledger entry, in ledger order, each `--interval` seconds
# (default 30). A change is a difference from the entry's `observed` baseline,
# which `reconcile` records: `pr-merged`, `pr-closed`, `pending-approval` (a
# permission hold, which wakes nothing by itself), `run-finished`, and
# `stall-window`. A remote entry adds `pr-opened` and `checks-finished`. A run
# starting is no event. A run that finished is looked at
# again `--recheck` seconds later (default 90) and reported only if the thread
# is still at rest, since a run that waits on its own background subagent starts
# again within about a minute (measured 2026-11-06). `stall-window` is an entry
# at rest with no change for `--stall-window` seconds (default 900) since
# `reconcile` stamped its `rest_since`; an entry already at 3 stalls is
# escalated, so its window stays quiet.
# A thread that answers with another id or worktree path than the entry holds
# is `thread-mismatch`; a thread or PR it cannot read is `thread-unreadable` or
# `pr-unreadable`: a watcher that went quiet on those would be a silent stall.
# A failure `reconcile` already recorded on the entry (its `error`) is not
# reported again, so a restarted watcher does not wake on the same fault; such
# an entry stays in `watching` though it wakes nothing, and a fault that clears
# and returns between two reconciles stays quiet. An entry with no `observed`
# baseline is skipped and named in `unobserved`.
# Settled and closed entries are not watched; a `merged` entry (PR merged,
# thread still running) is, and wakes `run-finished` when the thread rests. The
# ledger is read again each poll, so an entry added mid-watch is watched from
# its next poll on (once `reconcile` has observed it). Only one watcher runs per
# ledger: its pid is held in `<ledger>.watch`, and a second start exits 1 naming
# the running one, so a backstop wake can start it blindly. Watch writes nothing
# else, so an unreconciled change is reported again by the next watch. A remote
# entry (an `environment_id`) is woken from GitHub alone, found by its branch: a
# PR opening (`pr-opened`), the checks on its head commit finishing
# (`checks-finished`), a merge and a close. Its thread is not read between wakes:
# the baseline holds the thread `reconcile` read from the reply file on the last
# wake, so a remote thread's own finish reaches the super agent through the
# backstop schedule. `--remote` is accepted and unused here.
#
# stdout: {key, thread, event, observed} for a change, `observed` the snapshot
#         {status, run_count, pending, gate, pr: {number, state[, checks]}}; {key, thread,
#         event, detail} for `thread-mismatch`, `thread-unreadable` and
#         `pr-unreadable`; {key: null, thread: null, event: "timeout",
#         watching, unobserved} once --timeout passes, `watching` the keys it
#         polled and `unobserved` the open keys it skipped
#         a watcher already running is {error, running: <pid, or null when
#         its lock reads empty>}
# exit: 0 a change or the timeout · 1 no open entry, none `reconcile` has
#       observed yet, or a watcher already running · 2 usage, an unreadable
#       ledger, or a lock it cannot take
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh" || { printf '{"error":"cannot source _lib.sh"}\n'; exit 2; }

usage='usage: watch --ledger <file> [--interval <s>] [--timeout <s>] [--recheck <s>] [--stall-window <s>] [--remote <environment id>=<dir>]...'
sa_help "$usage" "$@"
ledger='' interval=30 timeout='' recheck=90 window=$sa_stall_window
while [ $# -gt 0 ]; do
  case $1 in
    --remote) sa_flag_value "$usage" "${2:-}"; sa_remote_flag "$usage" "$2"; shift 2 ;;
    --ledger) sa_flag_value "$usage" "${2:-}"; ledger=$2; shift 2 ;;
    --interval) sa_flag_value "$usage" "${2:-}"; interval=$2; shift 2 ;;
    --timeout) sa_flag_value "$usage" "${2:-}"; timeout=$2; shift 2 ;;
    --recheck) sa_flag_value "$usage" "${2:-}"; recheck=$2; shift 2 ;;
    --stall-window) sa_flag_value "$usage" "${2:-}"; sa_window_flag "$usage" "$2"; window=$2; shift 2 ;;
    *) sa_tooling "$usage" ;;
  esac
done
case $interval in ''|0|*[!0-9]*) sa_tooling "$usage" ;; esac
case $timeout in *[!0-9]*) sa_tooling "$usage" ;; esac
case $recheck in ''|*[!0-9]*) sa_tooling "$usage" ;; esac
[ -n "$ledger" ] || sa_tooling "$usage"

# One watcher per ledger. The pid is written to a temp file and linked to the
# lock, which is atomic and never leaves an empty lock for a second start to
# misread; a lock whose pid is gone is a dead watcher's, taken over once. A lock
# that reads empty is kept, since an unknown answer is no proof of a dead one. A
# live pid counts only when its command line is a watch.sh, so a pid reused by
# another process after a kill or a reboot does not block every later start.
lock="$ledger.watch"
mine=$(mktemp "$lock.XXXXXX") || sa_tooling "cannot take $lock"
trap 'rm -f "$mine"' EXIT
printf '%s\n' "$$" > "$mine"
for try in 1 2; do
  if ln "$mine" "$lock" 2>/dev/null; then break; fi
  pid=$(cat "$lock" 2>/dev/null) args=''
  # /bin/ps by its full path, which Linux and macOS both ship, and which the
  # tests' fake `ps` on PATH does not shadow.
  [ -z "$pid" ] || args=$(/bin/ps -p "$pid" -o args= 2>/dev/null)
  if [ -z "$pid" ] || [[ $args == *watch.sh* ]]; then
    jq -cn --arg p "$pid" '{error: "a watcher already runs on this ledger", running: (if $p == "" then null else ($p | tonumber) end)}'
    printf 'a watcher already runs on this ledger (pid %s)\n' "${pid:-unknown}" >&2; exit 1
  fi
  rm -f "$lock"
  [ "$try" -lt 2 ] || sa_tooling "cannot take $lock"
done
rm -f "$mine"
trap '[ "$(cat "$lock" 2>/dev/null)" = "$$" ] && rm -f "$lock"' EXIT

# load: the ledger's open, observed entries in $open and the open ones not yet
# observed in $unobserved, read afresh each poll.
load() {
  sa_read "$ledger"
  open=$(jq -c "$sa_jq_open"'[.entries[] | select(is_open)]' <<<"$doc")
  unobserved=$(jq -c '[.[] | select(.observed == null) | .key]' <<<"$open")
  open=$(jq -c '[.[] | select(.observed != null)]' <<<"$open")
}
load
[ "$(jq length <<<"$open")" -gt 0 ] || [ "$(jq length <<<"$unobserved")" -gt 0 ] \
  || sa_fail "no open entry in the ledger $ledger"
[ "$(jq length <<<"$open")" -gt 0 ] \
  || sa_fail "$(jq -r 'first' <<<"$unobserved") has no observed state: run reconcile first"

# change_of <observed> <snapshot>: the change from the baseline to the snapshot,
# the PR's end first since it outranks a run that finished with it.
change_of() {
  jq -rn --argjson o "$1" --argjson n "$2" '
    if $n.pr.state == "merged" and $o.pr.state != "merged" then "pr-merged"
    elif $n.pr.state == "closed" and $o.pr.state != "closed" then "pr-closed"
    elif ($n.pr | has("checks")) and $n.pr.state == "open" and $o.pr.state == "none" then "pr-opened"
    elif ($n.pr | has("checks")) and $n.pr.state == "open" and $o.pr.state == "open" and $n.pr.checks == "done" and $o.pr.checks != "done" then "checks-finished"
    elif $n.pending > $o.pending then "pending-approval"
    elif $n.status != "running" and ($o.status == "running" or $n.run_count > $o.run_count) then "run-finished"
    else empty end'
}

# stall_window_of <entry> <snapshot>: `stall-window` for an entry that has rested
# past the window with nothing else to report.
stall_window_of() {
  jq -rn --argjson e "$1" --argjson n "$2" --argjson w "$window" --argjson now "$(date -u +%s)" '
    if $e.rest_since != null and $n.pr.state != "merged" and ($e.stalls // 0) < 3 and $n.status != "running" and $n.pending == 0
       and $now - ($e.rest_since | fromdateiso8601) >= $w then "stall-window" else empty end'
}

start=$SECONDS
while :; do
  load
  while IFS= read -r entry; do
    key=$(jq -r .key <<<"$entry") thread=$(jq -r .thread <<<"$entry")
    read_ok=false event=''
    if [ -n "$(jq -r '.environment_id // empty' <<<"$entry")" ]; then
      # remote: GitHub only, over the thread fields of the last reconcile
      if sa_pr_of "$entry"; then
        read_ok=true obs=$(jq -c --argjson pr "$pr_obs" '.observed + {pr: $pr}' <<<"$entry")
        event=$(change_of "$(jq -c .observed <<<"$entry")" "$obs")
      fi
    elif sa_observe "$entry"; then
      read_ok=true
      event=$(change_of "$(jq -c .observed <<<"$entry")" "$obs")
      if [ "$event" = run-finished ] && [ "$recheck" -gt 0 ]; then
        sleep "$recheck"
        # a fault in the second look is the answer, not the stale first one
        if sa_observe "$entry"; then event=$(change_of "$(jq -c .observed <<<"$entry")" "$obs"); else read_ok=false; fi
      fi
    fi
    if $read_ok; then
      [ -z "$event" ] && event=$(stall_window_of "$entry" "$obs")
      [ -z "$event" ] && continue
      jq -cn --arg k "$key" --arg t "$thread" --arg e "$event" --argjson o "$obs" \
        '{key: $k, thread: $t, event: $e, observed: $o}'
    else
      [ "$(jq -r '.error // ""' <<<"$entry")" = "$obs_kind" ] && continue
      jq -cn --arg k "$key" --arg t "$thread" --arg e "$obs_kind" --argjson d "$obs_detail" \
        '{key: $k, thread: $t, event: $e, detail: $d}'
    fi
    exit 0
  done < <(jq -c '.[]' <<<"$open")
  [ -n "$timeout" ] && [ $((SECONDS - start)) -ge "$timeout" ] && break
  sleep "$interval"
done
jq -cn --argjson o "$open" --argjson u "$unobserved" \
  '{key: null, thread: null, event: "timeout", watching: [$o[].key], unobserved: $u}'
