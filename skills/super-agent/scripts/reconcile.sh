#!/usr/bin/env bash
# On a wake, compare the ledger with T3 and GitHub and report what changed, so
# the super agent judges from one JSON answer and not from child transcripts.
#
#   reconcile --ledger <file> [--stall-window <s>] [--remote <environment id>=<dir>]...
#             [--reads <dir>] [--fleet <file>] [--quota <file>] [--instance <id>]
#
# Looks at every open entry's thread and PR (the same look `watch` takes),
# writes it into the entry as `observed`, the baseline the next `watch`
# compares against, and moves the entry's stage: a merged PR is `settled` once
# its thread is at rest and `merged` while the thread still runs (post-merge
# cleanup), a PR closed unmerged or a closed issue is `closed`, a running thread
# is `running`, a thread at rest with the ticket undone is `at-rest`. A
# `--kind triage` entry has no PR: it is `settled` when its thread has run and
# is at rest and the issue carries neither `needs-triage` nor `needs-info` (a grill
# waiting on the owner has the second). A `triage` entry settled within the last
# `sa_settled_days` (7) days is read again, thread only: one whose run count grew, or that runs, goes back to `at-rest` or
# `running` and is named in `woke`. A `--kind task` entry has no ticket: it is
# `running` while its thread runs and `settled` once the thread has run and is at
# rest, whatever any issue or PR says, unless it is `interactive` (it waits on the
# owner: never settled on rest, no stall). An `owner_run` entry (`ledger take`) counts no
# stall and owes no cleanup: a ticket's is read from GitHub alone and settles on a merged
# PR or a closed issue, a task's is not read; after 3 days one `owner-run` escalate row
# asks "watch or drop?", listed once (`owner_run_reminded`). `resumed` (a second `adopt`
# of the thread) takes the thread's run count as judged. An entry whose newest message from
# outside its thread is the owner's, newer than its `held_since` (else `launched_at`), is
# `steered`: its stalls are 0 and no stall counts, so it is in no `stalled` row and gets no
# nudge, and after the stall window at rest (not at a merge-gate summary) one `owner-steered`
# escalate row asks "watch or take?", on every reconcile until a need with that reason is
# recorded, which also quiets `watch`. The author comes from `owner_at`
# in the thread's reply file (`reply.sh`): `<dir>/<thread id>.json` of `--reads` for a local
# entry, of its `--remote` for a remote one; a thread with no such file keeps its mark.
# Settling the
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
# past the window it is an ordinary rest. So is a thread at rest on a usage-limit line
# (`... limit · resets 6:10pm (Africa/Cairo)`), until its reset plus the window: T3 resumes it
# at the reset by itself. An entry whose thread, PR or issue cannot be read is reported in
# `errors`, its `error` set to the kind (cleared by the next good read), and
# left in its stage. An entry at `launching` (`launch` wrote it, `record` has not bound
# a thread to it) has no thread to read: it is listed in `launching`, not checked. The ledger is written once, after the last entry, by
# applying what this run changed to the ledger as it stands then
# (reconcile.d/write.sh), so a write made meanwhile is kept. An entry with an `environment_id` lives on a linked machine,
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
# `ledger set <key> cleanup_owed false` (or `verify_owed false`). An entry that
# ends is stamped `settled_at`; `sa_settled_days` later, with neither field owed, it moves
# whole to `<ledger>.archive.jsonl`, one JSON line each, and leaves the ledger.
#
# A merged ship entry whose ticket is a sub-issue gets one look at its parent (`parents_done`
# below): when the ticket reads closed and every sub-issue of the open parent is closed, the
# parent is listed once, for the super agent to close (reconcile itself closes nothing).
#
# Last, it runs `status` over the ledger it wrote (`--quota` and `--instance` go
# to it) and carries its answer as `status`: the status block's rows that changed
# since the last block, and the needs whose push has not gone out. The super agent
# posts `block` as printed and pushes each `unpushed` need: nothing else reports.
#
# Each run stamps `<ledger>.reconciled` with its epoch second, which the wake timer reads
# to tell a super agent that answered a wake from one that did not.
#
# stdout: {ledger, checked, entries, launching, stalled, settled, closed, at_rest, woke, ready,
#         dropped, unqueued, parents_done, cleanup, verify, escalate, errors, skill, status}:
#         `status` is `status`'s answer {block, changed, unpushed}, or {error}
#         when status failed after the write (the rest of the answer stands);
#         `skill` {loaded, source, stale}: the running super-agent copy's version
#         against the one on `sa_skill_source`'s default branch, `stale` true when
#         the running one is older, null when either version cannot be read;
#         `entries` one {key, from, stage, stalls, observed} per open entry that
#         was read; `launching` one {key, since} per entry still at `launching`, `since`
#         when `launch` wrote it: a launch whose thread was never recorded; `stalled` one {key, thread, stalls, reason} per stall counted
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
#         done), `owner-steered` (at rest past the window after the owner's message),
#         `owner-run` (once, 3 days after the owner took the entry, whatever its needs);
#         `at_rest` one {key, thread}; `woke` one {key, thread, kind} per settled
#         triage entry reopened now; `errors` one {key, kind, detail}, `kind`
#         `thread-unreadable`, `thread-mismatch`, `pr-unreadable`,
#         `issue-unreadable` (a waiting row's issue or its blocker's too), or
#         `claim-unreadable`, `repo-unreadable` for an `unqueued` read; `checked` counts the open entries it looked at
# exit: 0 a reconcile, errors in the answer included · 2 usage, an unreadable
#       ledger or --quota file (refused before any write), or a write that failed
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh" || { printf '{"error":"cannot source _lib.sh"}\n'; exit 2; }

usage='usage: reconcile --ledger <file> [--stall-window <s>] [--remote <environment id>=<dir>]... [--reads <dir>] [--fleet <file>] [--quota <file>] [--instance <id>]'
sa_help "$usage" "$@"
# shellcheck disable=SC2034  # reads is read by reconcile.d/verdict.sh
ledger='' window=$sa_stall_window fleet='' quota='' reads='' status_flags=()
while [ $# -gt 0 ]; do
  case $1 in
    --fleet) sa_flag_value "$usage" "${2:-}"; fleet=$2; shift 2 ;;
    --remote) sa_flag_value "$usage" "${2:-}"; sa_remote_flag "$usage" "$2"; shift 2 ;;
    --reads) sa_flag_value "$usage" "${2:-}"; reads=$2; shift 2 ;;
    --ledger) sa_flag_value "$usage" "${2:-}"; ledger=$2; shift 2 ;;
    --quota|--instance) sa_flag_value "$usage" "${2:-}"; status_flags+=("$1" "$2"); [ "$1" = --instance ] || quota=$2; shift 2 ;;
    --stall-window) sa_flag_value "$usage" "${2:-}"; sa_window_flag "$usage" "$2"; window=$2; shift 2 ;;
    *) sa_tooling "$usage" ;;
  esac
done
[ -n "$ledger" ] || sa_tooling "$usage"
[ -z "$fleet" ] || jq -e '((.active_repos // []) | type == "array" and all(type == "string"))' "$fleet" >/dev/null 2>&1 \
  || sa_tooling "$fleet: not JSON, or active_repos is not an array of strings"

[ -z "$fleet" ] || jq -e '[(.repos // {})[]? | .max_ships // 1 | type == "number" and . >= 1 and . == floor] | all' "$fleet" >/dev/null 2>&1 \
  || sa_tooling "$fleet: every repos.<owner/name>.max_ships must be a whole number of 1 or more"

# A --quota file status cannot read is refused before any write, not after.
[ -z "$quota" ] || sa_quota_file "$quota"

sa_read "$ledger"
read_doc=$doc
# A batch is running while an entry is open: it began when the earliest of them launched.
batch_since=$(jq -r "$sa_jq_open"'[.entries[] | select(is_open) | .launched_at] | min // empty' <<<"$doc")
now_s=$(sa_now_s) now=$(date -u -d "@$now_s" +%Y-%m-%dT%H:%M:%SZ)
checked=0 entries='[]' errors='[]' stalled='[]' reminders='[]' steered_due='[]'
source "$(dirname "${BASH_SOURCE[0]}")/reconcile.d/verdict.sh" || sa_tooling "cannot source reconcile.d/verdict.sh"
fail() { # <kind> <detail>: record the error of the entry in $key
  errors=$(jq -c --arg k "$key" --arg kind "$1" --argjson d "$2" '. + [{key: $k, kind: $kind, detail: $d}]' <<<"$errors")
  doc=$(jq -c --arg k "$key" --arg kind "$1" '.entries[$k].error = $kind' <<<"$doc")
}
while IFS= read -r entry; do
  key=$(jq -r .key <<<"$entry")
  owner_run=$(jq -r '.owner_run == true' <<<"$entry") interactive=$(jq -r '.interactive == true' <<<"$entry")
  [ "$owner_run" != true ] || reconcile_owner_run_reminder "$entry"
  # an owner-run task's thread is the owner's until `drop`: nothing to read
  [ "$owner_run" = true ] && [ "$(jq -r '.kind // "ship"' <<<"$entry")" = task ] && continue
  checked=$((checked + 1))
  stage='' reason=''
  if [ "$owner_run" = true ]; then
    # an owner-run ticket's thread is the owner's: its end is read from GitHub alone
    active=false
    if ! sa_pr_of "$entry"; then fail "$obs_kind" "$obs_detail"; continue; fi
    obs=$(jq -c --argjson pr "$pr_obs" '(.observed // {}) + {pr: $pr}' <<<"$entry")
  elif ! sa_observe "$entry"; then fail "$obs_kind" "$obs_detail"; continue
  else
    # running, or at rest on the waiting line inside the window: still working
    active=$(jq -r --argjson w "$window" --argjson now "$now_s" "$sa_jq_active"'active($w; $now)' <<<"$obs")
  fi
  if [ "$(jq -r '.kind // "ship"' <<<"$entry")" = task ]; then
    # a task has no ticket: only its thread says whether it is done; an interactive
    # one waits on the owner at rest, so it leaves on `drop`
    if [ "$active" = true ]; then stage=running
    elif [ "$interactive" != true ] && [ "$(jq -r .run_count <<<"$obs")" -ge 1 ] && [ "$(jq -r .pending <<<"$obs")" -eq 0 ]; then stage=settled
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
            && [ "$(jq -r '.run_count // 0' <<<"$obs")" -ge 1 ] \
            && ! jq -e '[.labels[]?.name] | index("needs-triage") or index("needs-info")' <<<"$issue" >/dev/null; then stage=settled
        else stage=at-rest; fi ;;
    esac
  fi
  # an owner-run ticket ends on a merged PR or a closed issue, and otherwise keeps its stage
  if [ "$owner_run" = true ]; then
    if [ "$(jq -r .pr.state <<<"$obs")" = merged ] || [ "$reason" = issue-closed ]; then stage=settled; else stage=$(jq -r .stage <<<"$entry"); fi
    reason=''
  fi
  stall='' stalls=$(jq -r '.stalls // 0' <<<"$entry")
  # no stall is counted for an owner-run entry, nor for an interactive one (it waits on the owner)
  case $owner_run$interactive:$stage in falsefalse:running|falsefalse:at-rest) reconcile_judge ;; esac
  # an end owes the super agent its cleanup, and a merged ship PR a criteria check;
  # each stays owed until the super agent clears it (`ledger set <key> <field> false`)
  doc=$(jq -c --arg k "$key" --arg s "$stage" --argjson o "$obs" --arg now "$now" \
    '.entries[$k] |= (.stage = $s | .observed = $o | .error = null | .updated_at = $now | del(.resumed)
      | if $s == "settled" or $s == "closed" then .settled_at = $now | if .owner_run != true then .cleanup_owed = true else . end else . end
      | if (.kind // "ship") == "ship" and ($s == "merged" or $s == "settled") and $o.pr.state == "merged" and .verify_owed == null
        then .verify_owed = true else . end)' <<<"$doc")
  if [ -n "$stall" ]; then
    stalled=$(jq -c --arg k "$key" --arg t "$(jq -r .thread <<<"$entry")" --argjson n "$stalls" --arg r "$stall" \
      '. + [{key: $k, thread: $t, stalls: $n, reason: $r}]' <<<"$stalled")
  fi
  entries=$(jq -c --argjson e "$entry" --arg s "$stage" --arg r "$reason" --argjson o "$obs" --argjson n "$stalls" \
    '. + [{key: $e.key, thread: $e.thread, worktree: $e.worktree, kind: ($e.kind // "ship"), from: $e.stage, stage: $s, reason: $r, stalls: $n, observed: $o, owner_run: ($e.owner_run == true)}]' <<<"$entries")
done < <(jq -c "$sa_jq_open"'.entries[] | select(is_open and .stage != "launching")' <<<"$doc")
# A triage entry settled within the last sa_settled_days is read again (reconcile.d/woke.sh).
woke='[]'
source "$(dirname "${BASH_SOURCE[0]}")/reconcile.d/woke.sh" || sa_tooling "cannot source reconcile.d/woke.sh"
reconcile_woke
# Issues filed while a batch runs that nothing holds: offered once, then remembered.
unqueued='[]'
source "$(dirname "${BASH_SOURCE[0]}")/reconcile.d/unqueued.sh" || sa_tooling "cannot source reconcile.d/unqueued.sh"
reconcile_unqueued
# The waiting list: the owner's queue. A closed issue drops its row; a row is
# ready when its blocker merged and its repo has a free ship slot.
source "$(dirname "${BASH_SOURCE[0]}")/reconcile.d/waiting.sh" || sa_tooling "cannot source reconcile.d/waiting.sh"
reconcile_waiting
# A merged ship entry's spec parent, listed once when its sub-issues are all closed.
source "$(dirname "${BASH_SOURCE[0]}")/reconcile.d/parents.sh" || sa_tooling "cannot source reconcile.d/parents.sh"
parents_done='[]' parents_changed=0
reconcile_parents
if ! { [ "$checked" -eq 0 ] && [ "$woke" = '[]' ] && [ "$unqueued" = '[]' ] && [ "$dropped" = '[]' ] && [ "$parents_changed" -eq 0 ] && [ "$reminders" = '[]' ]; }; then
  source "$(dirname "${BASH_SOURCE[0]}")/reconcile.d/write.sh" || sa_tooling "cannot source reconcile.d/write.sh"
  reconcile_write
fi
sa_archive "$ledger" "$now_s"
# The stamp the wake timer reads: a reconcile ran, so a super agent is answering its wakes.
printf '%s\n' "$now_s" > "$ledger.reconciled" || sa_tooling "cannot write $ledger.reconciled"

sa_unlock
source "$(dirname "${BASH_SOURCE[0]}")/reconcile.d/answer.sh" || sa_tooling "cannot source reconcile.d/answer.sh"
reconcile_answer
