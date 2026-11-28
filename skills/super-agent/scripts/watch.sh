#!/usr/bin/env bash
# Wait until a supervised thread or its PR changes, then name the change and
# exit. Run it as a background command: it holds no tool call open, and its
# exit is what wakes the super agent.
#
#   watch --ledger <file> [--owed] [--interval <s>] [--timeout <s>] [--recheck <s>]
#         [--stall-window <s>] [--fleet <file>]
#
# Polls every open ledger entry, in ledger order, each `--interval` seconds
# (default 30). A change is a difference from the entry's `observed` baseline,
# which `reconcile` records: `pr-merged`, `pr-closed`, `pending-approval` (a
# permission hold, which wakes nothing by itself), `run-finished`, and
# `stall-window`, and for a remote entry whose machine cannot be read (below)
# `pr-opened` and `checks-finished`. A run
# starting is no event. A thread at rest whose last message ends on the waiting
# line (`sa_waiting_line`, `_lib.sh`) is still working: no `run-finished`, and its
# `stall-window` runs from when it rested (`rest_at`) while it waits. A PR that
# merged while its thread still runs raises `pr-merged` once, when the thread
# rests or `--stall-window` seconds after the merge, whichever comes first (a
# remote entry's is not held). A run that finished is looked at
# again `--recheck` seconds later (default 90) and reported only if the thread
# is still at rest, since a run that waits on its own background subagent starts
# again within about a minute (measured 2026-11-06). `stall-window` is an entry
# at rest with no change for `--stall-window` seconds (default 900) since
# `reconcile` stamped its `rest_since` (the later of that and `rest_at`, for a
# thread waiting on the waiting line, or `limit_reset`, the reset a usage-limit stop names, for
# a thread stopped on one: T3 resumes it then, so it raises no `run-finished` either); an entry already at 3 stalls is
# escalated, so its window stays quiet, and so does an owner-run or interactive entry's.
# An owner-run entry (`ledger take`) is read from GitHub alone and wakes only on its PR
# merging; an owner-run task is not read at all. A steered entry (the owner spoke last)
# keeps its `stall-window`, the wake on which reconcile lists its `owner-steered` row, once per
# window (timed from the later of its rest and `steered_asked_at`, the last reconcile that found it
# due; an entry with no rest, at a merge gate, has no window) until that need is recorded: with the need in the ledger its window is quiet.
# A thread that answers with another id or worktree path than the entry holds
# is `thread-mismatch`; a thread or PR it cannot read is `thread-unreadable` or
# `pr-unreadable`: a watcher that went quiet on those would be a silent stall.
# A failure `reconcile` already recorded on the entry (its `error`) is not
# reported again, so a restarted watcher does not wake on the same fault; such
# an entry stays in `watching` though it wakes nothing, and a fault that clears
# and returns between two reconciles stays quiet. An entry with no `observed`
# baseline is skipped and named in `unobserved`.
# An entry with an `environment_id` runs on a linked machine: each poll reads every
# open thread there in one SSH call (`sa_remote_read`, lib/remote.sh), over the
# machine's `ssh` string in `--fleet` (default `super-agent/fleet.json` under
# $XDG_CONFIG_HOME), and watches it like a local one. A machine that cannot be read
# (reason `ssh` for a failed call, `no-ssh` for no `ssh` string) leaves its entries
# watched from GitHub alone over their last baseline, marked `stale` (a merge is not
# held for a thread whose status is stale): a PR opening (`pr-opened`), the checks on its
# head commit finishing (`checks-finished`), a merge and a close. Once a machine has
# been unreadable for 300 s the watcher exits once with `machine-unreadable`; the
# offer is held in `<ledger>.ssh-down`, so a restarted watcher does not raise it
# again, and the next good read clears it silently. Each poll's failed read, each
# linked-machine rest it sees and the wake that reports one are lines of
# `remote-watch.jsonl` beside the ledger, which the scorecard counts.
# Settled and closed entries are not watched; a `merged` entry (PR merged,
# thread still running) is, and wakes `run-finished` when the thread rests, unless
# its `pr-merged` was held and has not been raised yet. The
# ledger is read again each poll, so an entry added mid-watch is watched from
# its next poll on (once `reconcile` has observed it). Only one watcher runs per
# ledger: its pid is held in `<ledger>.watch`, and a second start exits 1 naming
# the running one, so a backstop wake can start it blindly. Watch writes nothing
# else but the SSH state and log above, so an unreconciled change is reported again
# by the next watch. A super agent that stops answering its wakes is the wake
# timer's (`wake-timer.sh`).
#
# `--owed` (the other flags unused) is the one read-only answer to whether a
# watcher is owed, asked by the watch guard (`watch-guard.sh`): `watcher` when an
# open entry has been observed and no live watch.sh holds the lock, `reconcile`
# when open entries exist and none has been observed yet, else `none`. It takes
# no lock and writes nothing, and counts entries the way the watcher's own start
# does: a `launching` entry is no open entry here.
#
# stdout: {key, thread, event, observed} for a change, `observed` the snapshot
#         {status, run_count, pending, gate, waiting, rest_at, pr: {number, state[, merged_at, checks, head]}}; {key, thread,
#         event, detail} for `thread-mismatch`, `thread-unreadable` and
#         `pr-unreadable`; {key: null, thread: null, event: "machine-unreadable",
#         machine, reason, since} for a machine unreadable 300 s; {key: null, thread: null, event: "timeout",
#         watching, unobserved} once --timeout passes, `watching` the keys it
#         polled and `unobserved` the open keys it skipped
#         a watcher already running is {error, running: <pid, or null when
#         its lock reads empty>}
#         `--owed`: {owed: watcher|reconcile|none, open: <the open entries counted>}
#         `event` is one of pr-merged, pr-closed, pending-approval,
#         run-finished, stall-window, pr-opened, checks-finished,
#         thread-mismatch, thread-unreadable, pr-unreadable, machine-unreadable or timeout
# exit: 0 a change, the timeout or an `--owed` answer · 1 no open entry, none `reconcile` has
#       observed yet, or a watcher already running · 2 usage, an unreadable
#       ledger, or a lock it cannot take
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh" || { printf '{"error":"cannot source _lib.sh"}\n'; exit 2; }

usage='usage: watch --ledger <file> [--owed] [--interval <s>] [--timeout <s>] [--recheck <s>] [--stall-window <s>] [--fleet <file>]'
sa_help "$usage" "$@"
ledger='' interval=30 timeout='' recheck=90 window=$sa_stall_window owed=false
fleet="${XDG_CONFIG_HOME:-$HOME/.config}/super-agent/fleet.json"
while [ $# -gt 0 ]; do
  case $1 in
    --owed) owed=true; shift ;;
    --ledger) sa_flag_value "$usage" "${2:-}"; ledger=$2; shift 2 ;;
    --fleet) sa_flag_value "$usage" "${2:-}"; fleet=$2; shift 2 ;;
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

# load: the ledger's open, observed entries in $open and the open ones not yet
# observed in $unobserved, read afresh each poll.
load() {
  sa_read "$ledger"
  # a `launching` entry has no thread to read yet: reconcile lists it
  open=$(jq -c "$sa_jq_open"'[.entries[] | select(is_open and .stage != "launching")]' <<<"$doc")
  unobserved=$(jq -c '[.[] | select(.observed == null) | .key]' <<<"$open")
  # a steered entry whose owner-steered need is recorded has nothing left to wake for
  open=$(jq -c --argjson needs "$(jq -c '.needs // []' <<<"$doc")" "$sa_jq_norm"'[.[] | select(.observed != null)
      | . + {asked: (.steered == true and (.key as $k | any($needs[]; (.key | norm_repo) == ($k | norm_repo) and (.reason == null or .reason == "owner-steered"))))}]' <<<"$open")
}

# watcher_alive <lock>: the lock exists and reads empty (an unknown answer is no
# proof of a dead watcher) or holds the pid of a live watch.sh.
watcher_alive() {
  [ -e "$1" ] || return 1
  local p
  p=$(cat "$1" 2>/dev/null)
  [ -z "$p" ] || sa_pid_runs "$p" '*watch.sh*'
}

if $owed; then
  load
  alive=false
  ! watcher_alive "$ledger.watch" || alive=true
  jq -cn --argjson o "$open" --argjson u "$unobserved" --argjson a "$alive" \
    '{owed: (if ($o | length) > 0 then (if $a then "none" else "watcher" end)
             elif ($u | length) > 0 then "reconcile" else "none" end),
      open: (($o | length) + ($u | length))}'
  exit 0
fi

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
  pid=$(cat "$lock" 2>/dev/null)
  if watcher_alive "$lock"; then
    jq -cn --arg p "$pid" '{error: "a watcher already runs on this ledger", running: (if $p == "" then null else ($p | tonumber) end)}'
    printf 'a watcher already runs on this ledger (pid %s)\n' "${pid:-unknown}" >&2; exit 1
  fi
  rm -f "$lock"
  [ "$try" -lt 2 ] || sa_tooling "cannot take $lock"
done
rm -f "$mine"
trap '[ "$(cat "$lock" 2>/dev/null)" = "$$" ] && rm -f "$lock"' EXIT

load
[ "$(jq length <<<"$open")" -gt 0 ] || [ "$(jq length <<<"$unobserved")" -gt 0 ] \
  || sa_fail "no open entry in the ledger $ledger"
[ "$(jq length <<<"$open")" -gt 0 ] \
  || sa_fail "$(jq -r 'first' <<<"$unobserved") has no observed state: run reconcile first"

# change_of <observed> <snapshot>: the change from the baseline to the snapshot,
# the PR's end first since it outranks a run that finished with it.
change_of() {
  jq -rn --argjson o "$1" --argjson n "$2" --argjson w "$window" --argjson now "$(sa_now_s)" "$sa_jq_active"'
    (($n.pr.merged_at // null) | if . == null then 0 else (try fromdateiso8601 catch 0) end) as $merged
    # a merge with its thread still working is no wake yet: the thread resting
    # or the bound passing is the one event (a thread on a machine this poll could not read is `stale`, so not held)
    | if $n.pr.state == "merged" and $o.pr.state != "merged" then
        (if ($n.stale != true) and ($n | active($w; $now)) and $now - $merged < $w then empty else "pr-merged" end)
    elif $n.pr.state == "closed" and $o.pr.state != "closed" then "pr-closed"
    # a readable thread reports its own PR and checks; only a stale one is woken by them
    elif $n.stale == true and ($n.pr | has("checks")) and $n.pr.state == "open" and $o.pr.state == "none" then "pr-opened"
    elif $n.stale == true and ($n.pr | has("checks")) and $n.pr.state == "open" and $o.pr.state == "open" and $n.pr.checks == "done" and ($o.pr.checks != "done" or $o.pr.head != $n.pr.head) then "checks-finished"
    elif $n.pending > $o.pending then "pending-approval"
    elif ($n.waiting | not) and ($n.limit_reset == null) and $n.status != "running" and ($o.status == "running" or $n.run_count > $o.run_count) then "run-finished"
    else empty end'
}

# stall_window_of <entry> <snapshot>: `stall-window` for an entry that has rested
# past the window with nothing else to report. A rest on the waiting line is timed
# from the thread's own last update, since no `run-finished` woke a reconcile to
# stamp `rest_since`; a merged entry rests into `run-finished`, bar that one.
stall_window_of() {
  jq -rn --argjson e "$1" --argjson n "$2" --argjson w "$window" --argjson now "$(sa_now_s)" '
    # the window of a steered entry runs from the later of its rest and the wake that last asked
    ([$e.rest_since, (if $e.steered == true and $e.rest_since != null then $e.steered_asked_at else null end)] | map(select(. != null) | fromdateiso8601) | max) as $rs
    | (if $n.waiting then ([$rs, $n.rest_at] | map(select(. != null)) | max)
       elif $n.limit_reset != null then ([$rs, $n.limit_reset] | map(select(. != null)) | max) else $rs end) as $since
    | if $since != null and ($e.owner_run != true) and ($e.interactive != true) and ($e.asked != true) and ($n.pr.state != "merged" or $n.waiting) and ($e.stalls // 0) < 3 and $n.status != "running" and $n.pending == 0
       and $now - $since >= $w then "stall-window" else empty end'
}

# A linked machine that cannot be read: the 300 s offer's state and the scorecard's log.
down_file="$ledger.ssh-down" rlog="$(dirname "$ledger")/remote-watch.jsonl"
down_after=300
rest_logged='{}' # {<key>: <rest_at>}, each linked-machine rest logged once (Bash 3.2: no associative array)
rlog_line() { # <jq filter> [<jq args>...]: one line of the remote log, stamped `at`
  local f=$1; shift
  jq -cn --argjson now "$(sa_now_s)" "$@" "{at: (\$now | todate)} + ($f)" >> "$rlog" 2>/dev/null || true
}

# remote_poll: read every linked machine once (an owner-run entry's thread is the owner's,
# so not read); log and hold each unreadable one, drop every other machine (read fine,
# or no open entry left on it), and exit once with `machine-unreadable` past `down_after`.
remote_poll() {
  local state now m
  sa_remote_read "$fleet" "$(jq -c '[.[] | select(.owner_run != true)]' <<<"$open")"
  state=$(jq -c 'objects' "$down_file" 2>/dev/null) || state=''
  [ -n "$state" ] || state='{}'
  now=$(sa_now_s)
  while IFS= read -r m; do
    rlog_line '{event: "unreadable", machine: $d.machine, environment_id: $e, reason: $d.reason}' --argjson d "$(jq -c --arg e "$m" '.[$e]' <<<"$sa_remote_down")" --arg e "$m"
  done < <(jq -r 'keys[]' <<<"$sa_remote_down")
  state=$(jq -c --argjson d "$sa_remote_down" --argjson now "$now" '
    [$d | to_entries[] | {key: (.value.machine // .key), value: .value.reason}] as $down
    | with_entries(select(.key as $k | any($down[]; .key == $k)))
    | reduce $down[] as $x (.; .[$x.key] = (.[$x.key] // {since: $now, offered: false}) + {reason: $x.value})' <<<"$state")
  m=$(jq -r --argjson now "$now" --argjson a "$down_after" 'first(to_entries[] | select(.value.offered != true and $now - .value.since >= $a) | .key) // empty' <<<"$state")
  [ -z "$m" ] || state=$(jq -c --arg m "$m" '.[$m].offered = true' <<<"$state")
  if [ "$state" = '{}' ]; then rm -f "$down_file"; else printf '%s\n' "$state" > "$down_file"; fi
  [ -n "$m" ] || return 0
  jq -cn --arg m "$m" --argjson s "$state" '{key: null, thread: null, event: "machine-unreadable", machine: $m, reason: $s[$m].reason, since: ($s[$m].since | todate)}'
  exit 0
}

start=$SECONDS
while :; do
  load
  remote_poll
  while IFS= read -r entry; do
    key=$(jq -r .key <<<"$entry") thread=$(jq -r .thread <<<"$entry")
    read_ok=false event=''
    owner_run=$(jq -r '.owner_run == true' <<<"$entry")
    # an owner-run task's thread is the owner's until `drop`: nothing to read
    [ "$owner_run" = true ] && [ "$(jq -r '.kind // "ship"' <<<"$entry")" = task ] && continue
    env=$(jq -r '.environment_id // empty' <<<"$entry")
    if [ "$owner_run" = true ] || { [ -n "$env" ] && jq -e --arg e "$env" 'has($e)' <<<"$sa_remote_down" >/dev/null; }; then
      # owner-run, or on a machine this poll could not read: GitHub only, over the thread
      # fields of the last reconcile (`stale`); an owner-run thread is the owner's, so only its PR merging wakes
      if sa_pr_of "$entry"; then
        read_ok=true obs=$(jq -c --argjson pr "$pr_obs" '.observed + {pr: $pr, stale: true}' <<<"$entry")
        if [ "$owner_run" = true ]; then
          event=$(jq -rn --argjson e "$entry" --argjson n "$obs" 'if $n.pr.state == "merged" and $e.observed.pr.state != "merged" then "pr-merged" else empty end')
        else event=$(change_of "$(jq -c .observed <<<"$entry")" "$obs"); fi
      fi
    elif sa_observe "$entry"; then
      read_ok=true
      event=$(change_of "$(jq -c .observed <<<"$entry")" "$obs")
      if [ "$event" = run-finished ] && [ "$recheck" -gt 0 ]; then
        sleep "$recheck"
        # a fault in the second look is the answer, not the stale first one; a linked
        # machine that cannot be read again leaves the first look's answer, and the
        # poll's read is put back for the entries after this one
        recheck_down=false saved_lines=$sa_remote_lines saved_down=$sa_remote_down
        if [ -n "$env" ]; then
          sa_remote_read "$fleet" "[$entry]"
          ! jq -e --arg e "$env" 'has($e)' <<<"$sa_remote_down" >/dev/null || recheck_down=true
        fi
        if $recheck_down; then :
        elif sa_observe "$entry"; then event=$(change_of "$(jq -c .observed <<<"$entry")" "$obs"); else read_ok=false; fi
        sa_remote_lines=$saved_lines sa_remote_down=$saved_down
      fi
    fi
    if $read_ok; then
      # a linked-machine rest, logged once per rest this watcher sees, and the wake that reports it
      at_rest=''
      if [ -n "$env" ] && [ "$owner_run" != true ]; then
        at_rest=$(jq -r 'select(.stale != true and .status != "running" and .rest_at != null) | .rest_at' <<<"$obs")
        if [ -n "$at_rest" ] && [ "$(jq -r --arg k "$key" '.[$k] // empty' <<<"$rest_logged")" != "$at_rest" ]; then
          rest_logged=$(jq -c --arg k "$key" --arg r "$at_rest" '.[$k] = $r' <<<"$rest_logged")
          rlog_line '{event: "rest", key: $k, machine: $m, rest_at: ($r | tonumber | todate)}' --arg k "$key" --arg m "$(jq -r '.machine // .environment_id' <<<"$entry")" --arg r "$at_rest"
        fi
      fi
      [ -z "$event" ] && event=$(stall_window_of "$entry" "$obs")
      [ -z "$event" ] && continue
      [ -z "$at_rest" ] || rlog_line '{event: "wake", key: $k, machine: $m, rest_at: ($r | tonumber | todate), reported: $ev}' \
        --arg k "$key" --arg m "$(jq -r '.machine // .environment_id' <<<"$entry")" --arg r "$at_rest" --arg ev "$event"
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
