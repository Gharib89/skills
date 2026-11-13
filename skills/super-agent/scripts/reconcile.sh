#!/usr/bin/env bash
# On a wake, compare the ledger with T3 and GitHub and report what changed, so
# the super agent judges from one JSON answer and not from child transcripts.
#
#   reconcile --ledger <file> [--stall-window <s>] [--remote <environment id>=<dir>]...
#             [--fleet <file>]
#
# Looks at every open entry's thread and PR (the same look `watch` takes),
# writes it into the entry as `observed`, the baseline the next `watch`
# compares against, and moves the entry's stage: a merged PR is `settled` once
# its thread is at rest and `merged` while the thread still runs (post-merge
# cleanup), a PR closed unmerged or a closed issue is `closed`, a running thread
# is `running`, a thread at rest with the ticket undone is `at-rest`. A
# `--kind triage` entry has no PR: it is `settled` when its thread has run and
# is at rest and the issue carries neither `needs-triage` nor `needs-info` (a grill
# waiting on the owner has the second). A settled `triage` entry is read again,
# thread only: one whose run count grew, or that runs, goes back to `at-rest` or
# `running` and is named in `woke`. A `--kind task` entry has no ticket: it is
# `running` while its thread runs and `settled` once the thread has run and is at
# rest, whatever any issue or PR says. Settling the
# thread in T3 is the super agent's act, on each entry `settled` names, and it
# never archives. It keeps each entry's stall count: +1 for a stall (a run that
# completed with no merged PR and no merge-gate summary, counted once per run,
# or a thread at rest `--stall-window` seconds, default 900, with no new run,
# counted again each window, neither once an entry is at 3, which is
# escalated), -1 for a real step (a run that ended in a
# merge-gate summary, or a PR opened since the last look), never below 0. The
# entry holds `judged_run`, the last run counted, and `rest_since`, when its
# rest began or its last stall was counted, which `watch` reads for its
# `stall-window` event. A thread holding a permission request is neither. A thread
# at rest whose last message ends on the waiting line (`sa_waiting_line`) inside the
# stall window counts as running: no stall, and its stage as a running thread's;
# past the window it is an ordinary rest. An entry whose thread, PR or issue cannot be read is reported in
# `errors`, its `error` set to the kind (cleared by the next good read), and
# left in its stage. The ledger is written once, atomically, after
# the last entry. An entry with an `environment_id` lives on a linked machine,
# where `t3 thread show` cannot reach: it is read from `<dir>/<thread id>.json`
# of the `--remote` for its environment, a file the super agent saved from
# `t3_thread_read`, and matched by id and worktree path like a local one. An
# environment with no `--remote`, a missing file or one that is not the
# thread's JSON is `thread-unreadable` for that environment's entries alone.
# It also reads the waiting list, the owner's queue (`ledger wait`): a row whose
# issue closed is dropped from the ledger and named in `dropped`, and the rows
# that could launch now are `ready`, in the list's order: no `--after` blocker or
# a blocker that merged (its entry `merged` or `settled`, or, with no such entry,
# its issue closed and not as not planned), and the repo under its ship cap, `max_ships` in the fleet
# file's `repos`, 3 without one, counting its open entries and the ready rows
# ahead. A ready row is a candidate: `place` still decides the machine. A row
# whose issue or blocker cannot be read stays, is not ready and is in `errors`,
# its `key` the waiting row and its `detail.key` the issue that could not be read.
# With `--fleet`, it also lists `unqueued`: an open issue in one of the fleet
# file's active repos, created since the earliest open entry launched (a batch is
# running), that no ledger entry of any stage, no waiting row and no claim comment
# holds. Each is listed once: the ledger keeps the keys it offered
# (`unqueued_offered`), so a later run leaves them out. Nothing is launched.
#
# The wake's actions are printed, not derived from the lists above: an entry that
# ends is marked `cleanup_owed` (a merged ship PR also `verify_owed`), and the rows
# below stay in every answer until the super agent clears the field with
# `ledger set <key> cleanup_owed false` (or `verify_owed false`).
#
# A merged ship entry whose ticket is a sub-issue gets one look at its parent (`parents_done`
# below): when the ticket reads closed and every sub-issue of the open parent is closed, the
# parent is listed once, for the super agent to close (reconcile itself closes nothing).
#
# Each run stamps `<ledger>.reconciled` with its epoch second, which `notify` reads
# to tell a super agent that answered a wake from one that did not.
#
# stdout: {ledger, checked, entries, stalled, settled, closed, at_rest, woke, ready,
#         dropped, unqueued, parents_done, cleanup, verify, escalate, errors}:
#         `entries` one {key, from, stage, stalls, observed} per open entry that
#         was read; `stalled` one {key, thread, stalls, reason} per stall counted
#         now, `reason` `run-completed` or `stall-window`;
#         `settled` one {key, thread, worktree, kind} per entry that ended; `closed` one
#         {key, thread, worktree, reason} (`pr-closed` or `issue-closed`);
#         `ready` one {key, order, after, reason, since} per waiting row that can launch;
#         `dropped` one {key, reason: `issue-closed`} per waiting row removed now;
#         `unqueued` one {key, title, created_at} per issue offered now (`[]` without
#         --fleet); `parents_done` one {key, title, sub_issues} per open parent issue
#         whose sub-issues are all closed, listed once (the ledger keeps `parents_offered`);
#         `cleanup` one {key, thread, worktree, kind, stage, environment_id} per
#         settled or closed entry still owing its cleanup (settle the thread, remove the
#         worktree); `verify` one {key, repo, number, pr, stage} per merged ship PR whose
#         criteria check is not recorded; `escalate` one {key, thread, reason, detail} per
#         entry only the owner can unblock and with no open need for its reason: `permission-hold`
#         (detail the pending count), `fault` (detail the error kind), `stall-cap` (an
#         entry at rest at 3 stalls), `pr-closed` or `issue-closed` (until its cleanup is
#         done); `at_rest` one {key, thread}; `woke` one {key, thread, kind} per settled
#         triage entry reopened now; `errors` one {key, kind, detail}, `kind`
#         `thread-unreadable`, `thread-mismatch`, `pr-unreadable`,
#         `issue-unreadable` (a waiting row's issue or its blocker's too), or
#         `claim-unreadable`, `repo-unreadable` for an `unqueued` read; `checked` counts the open entries it looked at
# exit: 0 a reconcile, errors in the answer included · 2 usage, an unreadable
#       ledger, or a write that failed
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh" || { printf '{"error":"cannot source _lib.sh"}\n'; exit 2; }

usage='usage: reconcile --ledger <file> [--stall-window <s>] [--remote <environment id>=<dir>]... [--fleet <file>]'
sa_help "$usage" "$@"
ledger='' window=$sa_stall_window fleet=''
while [ $# -gt 0 ]; do
  case $1 in
    --fleet) sa_flag_value "$usage" "${2:-}"; fleet=$2; shift 2 ;;
    --remote) sa_flag_value "$usage" "${2:-}"; sa_remote_flag "$usage" "$2"; shift 2 ;;
    --ledger) sa_flag_value "$usage" "${2:-}"; ledger=$2; shift 2 ;;
    --stall-window) sa_flag_value "$usage" "${2:-}"; sa_window_flag "$usage" "$2"; window=$2; shift 2 ;;
    *) sa_tooling "$usage" ;;
  esac
done
[ -n "$ledger" ] || sa_tooling "$usage"
[ -z "$fleet" ] || jq -e '((.active_repos // []) | type == "array" and all(type == "string"))' "$fleet" >/dev/null 2>&1 \
  || sa_tooling "$fleet: not JSON, or active_repos is not an array of strings"

[ -z "$fleet" ] || jq -e '[(.repos // {})[]? | .max_ships // 1 | type == "number" and . >= 1 and . == floor] | all' "$fleet" >/dev/null 2>&1 \
  || sa_tooling "$fleet: every repos.<owner/name>.max_ships must be a whole number of 1 or more"

sa_read "$ledger"
# A batch is running while an entry is open: it began when the earliest of them launched.
batch_since=$(jq -r "$sa_jq_open"'[.entries[] | select(is_open) | .launched_at] | min // empty' <<<"$doc")
now_s=$(sa_now_s) now=$(date -u -d "@$now_s" +%Y-%m-%dT%H:%M:%SZ)
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
  # running, or at rest on the waiting line inside the window: still working
  active=$(jq -r --argjson w "$window" --argjson now "$now_s" "$sa_jq_active"'active($w; $now)' <<<"$obs")
  if [ "$(jq -r '.kind // "ship"' <<<"$entry")" = task ]; then
    # a task has no ticket: only its thread says whether it is done
    if [ "$active" = true ]; then stage=running
    elif [ "$(jq -r .run_count <<<"$obs")" -ge 1 ] && [ "$(jq -r .pending <<<"$obs")" -eq 0 ]; then stage=settled
    else stage=at-rest; fi
  else
    case $(jq -r .pr.state <<<"$obs") in
      merged) if [ "$active" = true ]; then stage=merged; else stage=settled; fi ;;
      closed) stage=closed reason=pr-closed ;;
      *)
        repo=$(jq -r .repo <<<"$entry") number=$(jq -r .number <<<"$entry")
        issue=$(gh api "repos/$repo/issues/$number" 2>/dev/null </dev/null) || issue=''
        if ! jq -e '.state' <<<"$issue" >/dev/null 2>&1; then
          fail issue-unreadable "$(jq -cn --arg r "$repo" --argjson n "$number" '{repo: $r, number: $n}')"; continue
        fi
        if [ "$(jq -r .state <<<"$issue")" = closed ]; then stage=closed reason=issue-closed
        elif [ "$active" = true ]; then stage=running
        elif [ "$(jq -r '.kind // "ship"' <<<"$entry")" = triage ] \
            && [ "$(jq -r .run_count <<<"$obs")" -ge 1 ] \
            && ! jq -e '[.labels[]?.name] | index("needs-triage") or index("needs-info")' <<<"$issue" >/dev/null; then stage=settled
        else stage=at-rest; fi ;;
    esac
  fi
  stall='' stalls=$(jq -r '.stalls // 0' <<<"$entry")
  case $stage in running|at-rest)
    verdict=$(jq -cn --argjson e "$entry" --argjson n "$obs" --arg now "$now" --argjson w "$window" --argjson active "$active" '
      def down: if . > 0 then . - 1 else 0 end;
      ($now | fromdateiso8601) as $t
      | {stalls: ($e.stalls // 0), rest_since: $e.rest_since, judged_run: ($e.judged_run // 0), stall: null}
      | if $e.observed == null then .
        else
          (if $e.observed.pr.state == "none" and $n.pr.state == "open" then .stalls |= down else . end)
          | if $active or $n.pending > 0 then .rest_since = null
            elif $n.gate then
              (if $n.run_count > .judged_run then .stalls |= down | .judged_run = $n.run_count else . end) | .rest_since = null
            elif .stalls >= 3 then .judged_run = $n.run_count
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
  # an end owes the super agent its cleanup, and a merged ship PR a criteria check;
  # each stays owed until the super agent clears it (`ledger set <key> <field> false`)
  doc=$(jq -c --arg k "$key" --arg s "$stage" --argjson o "$obs" --arg now "$now" \
    '.entries[$k] |= (.stage = $s | .observed = $o | .error = null | .updated_at = $now
      | if $s == "settled" or $s == "closed" then .cleanup_owed = true else . end
      | if (.kind // "ship") == "ship" and ($s == "merged" or $s == "settled") and $o.pr.state == "merged" and .verify_owed == null
        then .verify_owed = true else . end)' <<<"$doc")
  if [ -n "$stall" ]; then
    stalled=$(jq -c --arg k "$key" --arg t "$(jq -r .thread <<<"$entry")" --argjson n "$stalls" --arg r "$stall" \
      '. + [{key: $k, thread: $t, stalls: $n, reason: $r}]' <<<"$stalled")
  fi
  entries=$(jq -c --argjson e "$entry" --arg s "$stage" --arg r "$reason" --argjson o "$obs" --argjson n "$stalls" \
    '. + [{key: $e.key, thread: $e.thread, worktree: $e.worktree, kind: ($e.kind // "ship"), from: $e.stage, stage: $s, reason: $r, stalls: $n, observed: $o}]' <<<"$entries")
done < <(jq -c "$sa_jq_open"'.entries[] | select(is_open)' <<<"$doc")
# A settled triage entry is read again, thread only: a grill that runs again
# after its owner answers must not go unwatched. An entry settled with no
# `observed` baseline has nothing to compare and is skipped, and an unreadable
# thread is left alone (a deleted one would otherwise error on every reconcile).
woke='[]'
while IFS= read -r entry; do
  key=$(jq -r .key <<<"$entry")
  sa_thread_only=1 sa_observe "$entry" || continue
  stage=$(jq -r 'if $e.observed.run_count == null then "" elif .status == "running" then "running" elif .run_count > $e.observed.run_count then "at-rest" else "" end' --argjson e "$entry" <<<"$obs")
  [ -n "$stage" ] || continue
  doc=$(jq -c --arg k "$key" --arg s "$stage" --argjson o "$obs" --arg now "$now" \
    '.entries[$k] |= (.stage = $s | .observed += $o | .rest_since = null | .updated_at = $now)' <<<"$doc")
  woke=$(jq -c --argjson e "$entry" '. + [{key: $e.key, thread: $e.thread, kind: $e.kind}]' <<<"$woke")
done < <(jq -c '.entries[] | select(.stage == "settled" and .kind == "triage")' <<<"$doc")
# Issues filed while a batch runs that nothing holds: offered once, then remembered.
unqueued='[]'
source "$(dirname "${BASH_SOURCE[0]}")/reconcile.d/unqueued.sh" || sa_tooling "cannot source reconcile.d/unqueued.sh"
reconcile_unqueued
# The waiting list: the owner's queue. A closed issue drops its row; a row is
# ready when its blocker merged and its repo has a free ship slot.
ready='[]' dropped='[]'
issue_read() { gh api "repos/$1/issues/$2" 2>/dev/null </dev/null; } # <owner/name> <number>
unreadable() { errors=$(jq -c --arg k "$1" --arg d "$2" '. + [{key: $k, kind: "issue-unreadable", detail: {key: $d}}]' <<<"$errors"); } # <row key> <the key that failed to read>
while IFS= read -r row; do
  key=$(jq -r .key <<<"$row") repo=$(jq -r .repo <<<"$row")
  issue=$(issue_read "$repo" "$(jq -r .number <<<"$row")") || issue=''
  state=$(jq -r '.state // empty' <<<"$issue" 2>/dev/null)
  if [ -z "$state" ]; then unreadable "$key" "$key"; continue; fi
  if [ "$state" = closed ]; then
    doc=$(jq -c --arg k "$key" "$sa_jq_norm"'.waiting |= map(select((.key | norm_repo) != ($k | norm_repo)))' <<<"$doc")
    dropped=$(jq -c --arg k "$key" '. + [{key: $k, reason: "issue-closed"}]' <<<"$dropped"); continue
  fi
  after=$(jq -r '.after // empty' <<<"$row")
  if [ -n "$after" ] && ! jq -e --arg k "$after" "$sa_jq_norm"'[.entries[] | select(.key | norm_repo == ($k | norm_repo)) | .stage] | any(IN("merged", "settled"))' <<<"$doc" >/dev/null; then
    blocker=$(issue_read "${after%#*}" "${after##*#}") || blocker=''
    bstate=$(jq -r '.state // empty' <<<"$blocker" 2>/dev/null)
    if [ -z "$bstate" ]; then unreadable "$key" "$after"; continue; fi
    # A closed issue means merged unless it was closed as not planned.
    [ "$bstate" = closed ] && [ "$(jq -r '.state_reason // empty' <<<"$blocker")" != not_planned ] || continue
  fi
  max=$([ -z "$fleet" ] || jq -r --arg r "$repo" "$sa_jq_norm"'[(.repos // {}) | to_entries[] | select(.key | norm_repo == ($r | norm_repo)) | .value.max_ships] | first // empty' "$fleet")
  used=$(jq -r --arg r "$repo" --argjson ready "$ready" "$sa_jq_open$sa_jq_norm"'[.entries[] | select(is_open and ((.repo // "") | norm_repo) == ($r | norm_repo))] | length + ([$ready[] | select(.repo | norm_repo == ($r | norm_repo))] | length)' <<<"$doc")
  [ "$used" -lt "${max:-3}" ] || continue
  ready=$(jq -c --argjson r "$row" '. + [$r | {key, repo, order, after, reason, since}]' <<<"$ready")
done < <(jq -c "$sa_jq_waiting"'waiting_list[]' <<<"$doc")
ready=$(jq -c 'map(del(.repo))' <<<"$ready")
# A merged ship entry's spec parent, listed once when its sub-issues are all closed.
source "$(dirname "${BASH_SOURCE[0]}")/reconcile.d/parents.sh" || sa_tooling "cannot source reconcile.d/parents.sh"
parents_done='[]' parents_changed=0
reconcile_parents
[ "$checked" -eq 0 ] && [ "$woke" = '[]' ] && [ "$unqueued" = '[]' ] && [ "$dropped" = '[]' ] && [ "$parents_changed" -eq 0 ] || sa_write "$ledger" "$doc"
# The stamp `notify` reads: a reconcile ran, so a super agent is answering its wakes.
printf '%s\n' "$now_s" > "$ledger.reconciled" || sa_tooling "cannot write $ledger.reconciled"

# The ledger goes in on stdin: one argument over 128 KiB (MAX_ARG_STRLEN) fails with "Argument list too long".
jq -c --arg l "$ledger" --argjson n "$checked" --argjson e "$entries" --argjson errs "$errors" --argjson st "$stalled" --argjson wk "$woke" --argjson uq "$unqueued" --argjson rd "$ready" --argjson dr "$dropped" --argjson pd "$parents_done" "$sa_jq_norm"'
  . as $d |
  def pick($stage; f): [$e[] | select(.stage == $stage) | f];
  def entries: [$d.entries[]?];
  def needed($k; $r): [($d.needs // [])[] | select((.key | norm_repo) == ($k | norm_repo) and (.reason == null or .reason == $r))] | length > 0;
  {ledger: $l, checked: $n,
   entries: [$e[] | {key, from, stage, stalls, observed}],
   stalled: $st,
   settled: pick("settled"; {key, thread, worktree, kind}),
   closed: pick("closed"; {key, thread, worktree, reason}),
   at_rest: pick("at-rest"; {key, thread}),
   woke: $wk,
   ready: $rd,
   dropped: $dr,
   unqueued: $uq,
   parents_done: $pd,
   cleanup: [entries[] | select((.stage == "settled" or .stage == "closed") and .cleanup_owed == true)
     | {key, thread, worktree, kind: (.kind // "ship"), stage, environment_id: (.environment_id // null)}],
   verify: [entries[] | select((.kind // "ship") == "ship" and .verify_owed == true and (.stage == "merged" or .stage == "settled"))
     | {key, repo, number, pr: .observed.pr.number, stage}],
   escalate: [entries[]
     | (if .stage == "settled" then null
        elif .stage == "closed" then
          (if .cleanup_owed == true then {reason: (if .observed.pr.state == "closed" then "pr-closed" else "issue-closed" end), detail: null} else null end)
        elif (.observed.pending // 0) > 0 then {reason: "permission-hold", detail: .observed.pending}
        elif .error != null then {reason: "fault", detail: .error}
        elif .stage == "at-rest" and (.stalls // 0) >= 3 then {reason: "stall-cap", detail: .stalls}
        else null end) as $r
     | select($r != null and (needed(.key; $r.reason) | not)) | {key, thread, reason: $r.reason, detail: $r.detail}],
   errors: $errs}' <<<"$doc"
