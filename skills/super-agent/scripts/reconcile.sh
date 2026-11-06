#!/usr/bin/env bash
# On a wake, compare the ledger with T3 and GitHub and report what changed, so
# the super agent judges from one JSON answer and not from child transcripts.
#
#   reconcile --ledger <file>
#
# Looks at every open entry's thread and PR (the same look `watch` takes),
# writes it into the entry as `observed`, the baseline the next `watch`
# compares against, and moves the entry's stage: a merged PR is `settled`, a PR
# closed unmerged or a closed issue is `closed`, a running thread is `running`,
# a thread at rest with the ticket undone is `at-rest`. Settling the thread in
# T3 is the super agent's act, on each entry `settled` names, and it never
# archives. An entry whose thread, PR or issue cannot be read is reported in
# `errors`, its `error` set to the kind (cleared by the next good read), and
# left in its stage. The ledger is written once, atomically, after
# the last entry.
#
# stdout: {ledger, checked, entries, settled, closed, at_rest, errors}: `entries`
#         one {key, from, stage, observed} per open entry that was read;
#         `settled` one {key, thread, worktree} per merged entry; `closed` one
#         {key, thread, worktree, reason} (`pr-closed` or `issue-closed`);
#         `at_rest` one {key, thread}; `errors` one {key, kind, detail}, `kind`
#         `thread-unreadable`, `thread-mismatch`, `pr-unreadable` or
#         `issue-unreadable`; `checked` counts the open entries it looked at
# exit: 0 a reconcile, errors in the answer included · 2 usage, an unreadable
#       ledger, or a write that failed
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh" || { printf '{"error":"cannot source _lib.sh"}\n'; exit 2; }

usage='usage: reconcile --ledger <file>'
sa_help "$usage" "$@"
ledger=''
while [ $# -gt 0 ]; do
  case $1 in
    --ledger) sa_flag_value "$usage" "${2:-}"; ledger=$2; shift 2 ;;
    *) sa_tooling "$usage" ;;
  esac
done
[ -n "$ledger" ] || sa_tooling "$usage"

sa_read "$ledger"
now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
checked=0 entries='[]' errors='[]'
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
  doc=$(jq -c --arg k "$key" --arg s "$stage" --argjson o "$obs" --arg now "$now" \
    '.entries[$k] |= (.stage = $s | .observed = $o | .error = null | .updated_at = $now)' <<<"$doc")
  entries=$(jq -c --argjson e "$entry" --arg s "$stage" --arg r "$reason" --argjson o "$obs" \
    '. + [{key: $e.key, thread: $e.thread, worktree: $e.worktree, from: $e.stage, stage: $s, reason: $r, observed: $o}]' <<<"$entries")
done < <(jq -c "$sa_jq_open"'.entries[] | select(is_open)' <<<"$doc")
[ "$checked" -eq 0 ] || sa_write "$ledger" "$doc"

jq -cn --arg l "$ledger" --argjson n "$checked" --argjson e "$entries" --argjson errs "$errors" '
  def pick($stage; f): [$e[] | select(.stage == $stage) | f];
  {ledger: $l, checked: $n,
   entries: [$e[] | {key, from, stage, observed}],
   settled: pick("settled"; {key, thread, worktree}),
   closed: pick("closed"; {key, thread, worktree, reason}),
   at_rest: pick("at-rest"; {key, thread}),
   errors: $errs}'
