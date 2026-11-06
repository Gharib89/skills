#!/usr/bin/env bash
# On a wake, compare the ledger with T3 and GitHub and report what changed, so
# the super agent judges from one JSON answer and not from child transcripts.
#
#   reconcile --ledger <file> [--stall-window <s>]
#
# Looks at every open entry's thread and PR (the same look `watch` takes),
# writes it into the entry as `observed`, the baseline the next `watch`
# compares against, and moves the entry's stage: a merged PR is `settled`, a PR
# closed unmerged or a closed issue is `closed`, a running thread is `running`,
# a thread at rest with the ticket undone is `at-rest`. Settling the thread in
# T3 is the super agent's act, on each entry `settled` names, and it never
# archives. It keeps each entry's stall count: +1 for a stall (a run that
# completed with no merged PR and no merge-gate summary, counted once per run,
# or a thread at rest `--stall-window` seconds, default 900, with no new run,
# counted again each window), -1 for a real step (a run that ended in a
# merge-gate summary, or a PR opened since the last look), never below 0. The
# entry holds `judged_run`, the last run counted, and `rest_since`, when its
# rest began or its last stall was counted, which `watch` reads for its
# `stall-window` event. A thread holding a permission request is neither. An entry whose thread, PR or issue cannot be read is reported in
# `errors`, its `error` set to the kind (cleared by the next good read), and
# left in its stage. The ledger is written once, atomically, after
# the last entry.
#
# stdout: {ledger, checked, entries, stalled, settled, closed, at_rest, errors}:
#         `entries` one {key, from, stage, stalls, observed} per open entry that
#         was read; `stalled` one {key, thread, stalls, reason} per stall counted
#         now, `reason` `run-completed` or `stall-window`;
#         `settled` one {key, thread, worktree} per merged entry; `closed` one
#         {key, thread, worktree, reason} (`pr-closed` or `issue-closed`);
#         `at_rest` one {key, thread}; `errors` one {key, kind, detail}, `kind`
#         `thread-unreadable`, `thread-mismatch`, `pr-unreadable` or
#         `issue-unreadable`; `checked` counts the open entries it looked at
# exit: 0 a reconcile, errors in the answer included · 2 usage, an unreadable
#       ledger, or a write that failed
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh" || { printf '{"error":"cannot source _lib.sh"}\n'; exit 2; }

usage='usage: reconcile --ledger <file> [--stall-window <s>]'
sa_help "$usage" "$@"
ledger='' window=$sa_stall_window
while [ $# -gt 0 ]; do
  case $1 in
    --ledger) sa_flag_value "$usage" "${2:-}"; ledger=$2; shift 2 ;;
    --stall-window) sa_flag_value "$usage" "${2:-}"; sa_window_flag "$usage" "$2"; window=$2; shift 2 ;;
    *) sa_tooling "$usage" ;;
  esac
done
[ -n "$ledger" ] || sa_tooling "$usage"

sa_read "$ledger"
now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
checked=0 entries='[]' errors='[]' stalled='[]'
fail() { # <kind> <detail>: record the error of the entry in $key
  errors=$(jq -c --arg k "$key" --arg kind "$1" --argjson d "$2" '. + [{key: $k, kind: $kind, detail: $d}]' <<<"$errors")
  doc=$(jq -c --arg k "$key" --arg kind "$1" '.entries[$k].error = $kind' <<<"$doc")
}
while IFS= read -r entry; do
  checked=$((checked + 1))
  key=$(jq -r .key <<<"$entry")
  if ! sa_observe "$entry"; then fail "$obs_kind" "$obs_detail"; continue; fi
  stage='' reason=''
  case $(jq -r .pr.state <<<"$obs") in
    merged) stage=settled ;;
    closed) stage=closed reason=pr-closed ;;
    *)
      repo=$(jq -r .repo <<<"$entry") number=$(jq -r .number <<<"$entry")
      issue=$(gh api "repos/$repo/issues/$number" 2>/dev/null </dev/null) || issue=''
      if ! jq -e '.state' <<<"$issue" >/dev/null 2>&1; then
        fail issue-unreadable "$(jq -cn --arg r "$repo" --argjson n "$number" '{repo: $r, number: $n}')"; continue
      fi
      if [ "$(jq -r .state <<<"$issue")" = closed ]; then stage=closed reason=issue-closed
      elif [ "$(jq -r .status <<<"$obs")" = running ]; then stage=running
      else stage=at-rest; fi ;;
  esac
  stall='' stalls=$(jq -r '.stalls // 0' <<<"$entry")
  case $stage in running|at-rest)
    verdict=$(jq -cn --argjson e "$entry" --argjson n "$obs" --arg now "$now" --argjson w "$window" '
      def down: if . > 0 then . - 1 else 0 end;
      ($now | fromdateiso8601) as $t
      | {stalls: ($e.stalls // 0), rest_since: $e.rest_since, judged_run: ($e.judged_run // 0), stall: null}
      | if $e.observed == null then .
        else
          (if $e.observed.pr.state == "none" and $n.pr.state == "open" then .stalls |= down else . end)
          | if $n.status == "running" or $n.pending > 0 then .rest_since = null
            elif $n.gate then
              (if $n.run_count > .judged_run then .stalls |= down | .judged_run = $n.run_count else . end) | .rest_since = null
            elif $n.run_count > .judged_run then
              .stalls += 1 | .judged_run = $n.run_count | .rest_since = $now | .stall = "run-completed"
            elif .rest_since == null then .rest_since = $now
            elif $t - (.rest_since | fromdateiso8601) >= $w then
              .stalls += 1 | .rest_since = $now | .stall = "stall-window"
            else . end
        end')
    stalls=$(jq -r .stalls <<<"$verdict") stall=$(jq -r '.stall // ""' <<<"$verdict")
    doc=$(jq -c --arg k "$key" --argjson v "$verdict" \
      '.entries[$k] |= (.stalls = $v.stalls | .rest_since = $v.rest_since | .judged_run = $v.judged_run)' <<<"$doc") ;;
  esac
  doc=$(jq -c --arg k "$key" --arg s "$stage" --argjson o "$obs" --arg now "$now" \
    '.entries[$k] |= (.stage = $s | .observed = $o | .error = null | .updated_at = $now)' <<<"$doc")
  if [ -n "$stall" ]; then
    stalled=$(jq -c --arg k "$key" --arg t "$(jq -r .thread <<<"$entry")" --argjson n "$stalls" --arg r "$stall" \
      '. + [{key: $k, thread: $t, stalls: $n, reason: $r}]' <<<"$stalled")
  fi
  entries=$(jq -c --argjson e "$entry" --arg s "$stage" --arg r "$reason" --argjson o "$obs" --argjson n "$stalls" \
    '. + [{key: $e.key, thread: $e.thread, worktree: $e.worktree, from: $e.stage, stage: $s, reason: $r, stalls: $n, observed: $o}]' <<<"$entries")
done < <(jq -c "$sa_jq_open"'.entries[] | select(is_open)' <<<"$doc")
[ "$checked" -eq 0 ] || sa_write "$ledger" "$doc"

jq -cn --arg l "$ledger" --argjson n "$checked" --argjson e "$entries" --argjson errs "$errors" --argjson st "$stalled" '
  def pick($stage; f): [$e[] | select(.stage == $stage) | f];
  {ledger: $l, checked: $n,
   entries: [$e[] | {key, from, stage, stalls, observed}],
   stalled: $st,
   settled: pick("settled"; {key, thread, worktree}),
   closed: pick("closed"; {key, thread, worktree, reason}),
   at_rest: pick("at-rest"; {key, thread}),
   errors: $errs}'
