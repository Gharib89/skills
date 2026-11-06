#!/usr/bin/env bash
# Wait until a supervised thread or its PR changes, then name the change and
# exit. Run it as a background command: it holds no tool call open, and its
# exit is what wakes the super agent.
#
#   watch [--ledger <file>] [--interval <s>] [--timeout <s>]
#
# Polls every open ledger entry, in ledger order, each `--interval` seconds
# (default 30). A change is a difference from the entry's `observed` baseline,
# which `reconcile` records: `pr-merged`, `pr-closed`, `pending-approval` (a
# permission hold, which wakes nothing by itself), `run-finished`, `run-started`.
# A thread that answers with another id or worktree path than the entry holds
# is `thread-mismatch`; a thread or PR it cannot read is `thread-unreadable` or
# `pr-unreadable`: a watcher that went quiet on those would be a silent stall.
# Settled and closed entries are not watched. Watch writes nothing, so an
# unreconciled change is reported again by the next watch.
#
# stdout: {key, thread, event, observed} for a change, `observed` the snapshot
#         {status, run_count, pending, pr: {number, state}}; {key, thread,
#         event, detail} for `thread-mismatch`, `thread-unreadable` and
#         `pr-unreadable`; {key: null, thread: null, event: "timeout",
#         watching} once --timeout passes, `watching` the keys it polled
# exit: 0 a change or the timeout · 1 no open entry, or one `reconcile` has not
#       observed yet · 2 usage, or an unreadable ledger
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh" || { printf '{"error":"cannot source _lib.sh"}\n'; exit 2; }

usage='usage: watch [--ledger <file>] [--interval <s>] [--timeout <s>]'
sa_help "$usage" "$@"
ledger='' interval=30 timeout=''
while [ $# -gt 0 ]; do
  case $1 in
    --ledger) sa_flag_value "$usage" "${2:-}"; ledger=$2; shift 2 ;;
    --interval) sa_flag_value "$usage" "${2:-}"; interval=$2; shift 2 ;;
    --timeout) sa_flag_value "$usage" "${2:-}"; timeout=$2; shift 2 ;;
    *) sa_tooling "$usage" ;;
  esac
done
case $interval in ''|0|*[!0-9]*) sa_tooling "$usage" ;; esac
case $timeout in *[!0-9]*) sa_tooling "$usage" ;; esac
[ -n "$ledger" ] || ledger=$(sa_default_ledger)

sa_read "$ledger"
open=$(jq -c '[.entries[] | select(.stage != "settled" and .stage != "closed")]' <<<"$doc")
[ "$(jq length <<<"$open")" -gt 0 ] || sa_fail "no open entry in the ledger $ledger"
unobserved=$(jq -r '[.[] | select(.observed == null) | .key] | first // empty' <<<"$open")
[ -z "$unobserved" ] || sa_fail "$unobserved has no observed state: run reconcile first"

# sa_event <observed> <snapshot>: the change from the baseline to the snapshot,
# the PR's end first since it outranks a run that finished with it.
sa_event() {
  jq -rn --argjson o "$1" --argjson n "$2" '
    if $n.pr.state == "merged" and $o.pr.state != "merged" then "pr-merged"
    elif $n.pr.state == "closed" and $o.pr.state != "closed" then "pr-closed"
    elif $n.pending > $o.pending then "pending-approval"
    elif $n.status != "running" and ($o.status == "running" or $n.run_count > $o.run_count) then "run-finished"
    elif $n.status == "running" and ($n.run_count > $o.run_count or $o.status != "running") then "run-started"
    else empty end'
}

start=$SECONDS
while :; do
  while IFS= read -r entry; do
    key=$(jq -r .key <<<"$entry") thread=$(jq -r .thread <<<"$entry")
    if sa_observe "$entry"; then
      event=$(sa_event "$(jq -c .observed <<<"$entry")" "$obs")
      [ -z "$event" ] && continue
      jq -cn --arg k "$key" --arg t "$thread" --arg e "$event" --argjson o "$obs" \
        '{key: $k, thread: $t, event: $e, observed: $o}'
    else
      jq -cn --arg k "$key" --arg t "$thread" --arg e "$obs_kind" --argjson d "$obs_detail" \
        '{key: $k, thread: $t, event: $e, detail: $d}'
    fi
    exit 0
  done < <(jq -c '.[]' <<<"$open")
  [ -n "$timeout" ] && [ $((SECONDS - start)) -ge "$timeout" ] && break
  sleep "$interval"
done
jq -cn --argjson o "$open" '{key: null, thread: null, event: "timeout", watching: [$o[].key]}'
