# The answer of `reconcile`, sourced by it once its write is done: it runs
# `status` over the ledger it wrote and prints every list the pass gathered.

# shellcheck disable=SC2154  # ledger, doc, status_flags and the lists come from reconcile.sh and _lib.sh

reconcile_answer() {
  local status skill
  # The write above already recorded the once-only lists as offered, so a failed
  # status is carried as `status.error`, never in place of this answer.
  status=$(bash "$(dirname "${BASH_SOURCE[0]}")/../status.sh" --ledger "$ledger" ${status_flags[@]+"${status_flags[@]}"} 2>/dev/null) \
    || status=$(jq -ce '{error}' <<<"$status" 2>/dev/null) || status='{"error":"status.sh failed"}'

  # The ledger goes in on stdin: one argument over 128 KiB (MAX_ARG_STRLEN) fails with "Argument list too long".
  skill=$(sa_skill_stale)
  jq -c --arg l "$ledger" --argjson n "$checked" --argjson e "$entries" --argjson errs "$errors" --argjson st "$stalled" --argjson wk "$woke" --argjson uq "$unqueued" --argjson rd "$ready" --argjson dr "$dropped" --argjson pd "$parents_done" --argjson rem "$reminders" --argjson sdue "$steered_due" --argjson sk "$skill" --argjson status "$status" "$sa_jq_norm"'
    . as $d |
    def pick($stage; f): [$e[] | select(.stage == $stage and (.owner_run | not)) | f];
    def entries: [$d.entries[]?];
    def needed($k; $r): [($d.needs // [])[] | select((.key | norm_repo) == ($k | norm_repo) and (.reason == null or .reason == $r))] | length > 0;
    {ledger: $l, checked: $n,
     entries: [$e[] | {key, from, stage, stalls, observed}],
     launching: [entries[] | select(.stage == "launching") | {key, since: .launched_at}],
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
       | (if .stage == "settled" or .owner_run == true then null
          elif .stage == "closed" then
            (if .cleanup_owed == true then {reason: (if .observed.pr.state == "closed" then "pr-closed" else "issue-closed" end), detail: null} else null end)
          elif (.observed.pending // 0) > 0 then {reason: "permission-hold", detail: .observed.pending}
          elif .error != null then {reason: "fault", detail: .error}
          elif (.key as $k | any($sdue[]; .key == $k)) then {reason: "owner-steered", detail: "at rest after your message: watch or take?"}
          elif .stage == "at-rest" and (.stalls // 0) >= 3 then {reason: "stall-cap", detail: .stalls}
          else null end) as $r
       | select($r != null and (needed(.key; $r.reason) | not)) | {key, thread, reason: $r.reason, detail: $r.detail}]
       + $rem,
     errors: $errs, skill: $sk, status: $status}' <<<"$doc"
}
