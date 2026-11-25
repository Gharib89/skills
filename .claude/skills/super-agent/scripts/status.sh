#!/usr/bin/env bash
# Print the super agent's status block from the ledger alone, and say whether it
# is worth posting. The block is the only report the owner reads: the super agent
# posts `block` as printed, never rewrites it, and posts nothing when `block` is
# empty.
#
#   status --ledger <file> [--quota <file>] [--instance <id>] [--fleet <file>] [--digest]
#
# The block opens with the needs-you message: the ledger's open needs printed in
# full, blocking needs first, each its question, its `Why:` line and its options
# from 1 (or where to answer it), set apart by blank lines (`needs_text` in
# lib/needs.sh). The rows follow after a blank line, in this order, an empty row
# left out: `Merged` (a ship entry whose PR merged and that no
# digest has listed yet), `Running` (an open entry, read as at its merge gate, in
# review, launched, running or at rest; a `task` entry reads `task:<slug> (task)`
# and an adopted one adds `(adopted)`; a steered entry, one whose newest message from
# outside its thread is the owner's, ends with `(you spoke last)`), `Yours` (an
# owner-run entry, `ledger take`, in any open stage, out of `Running`: its link, its pull
# request's state and how many days the owner has had it), `Waiting` (the waiting list, in its
# order), `Reviewer limit` (a repo whose hosted reviewer hit its usage limit: its
# batch is merging on the fallback reviewer only, until `ledger unlimit`). A
# Running ticket names the provider instance it launched on, where the ledger holds one.
# Each ticket is a Markdown link to its issue, a merged one's PR a second
# link. The ledger keeps the rows of the last block it printed (`status`), so a
# run knows whether any row changed since. A plain run (`reconcile` makes one on
# every wake) prints only the rows that changed, a row that emptied as
# `<row>: none` (needs that emptied as `Nothing needs you now.`), and a run with nothing
# changed prints none; `--digest` prints
# every row whatever changed (the owner's "status", the morning report, an
# emptied waiting list). Any printed block counts its Merged tickets as listed,
# so Merged holds only the merges since the last block.
#
# A need is printed with its alert mark: the needs print whenever one has no
# `alerted` yet, and status sets it. A blocking need alerted 4 working hours ago
# (hours on the fleet file's `work_week` days in local time, Mon to Fri without
# --fleet) is raised once more: status sets its `reminded` and the needs print
# again; never a third time. A need 0.46.0 pushed counts as alerted at its
# `since`. Each alert and reminder is a line in `needs-alerts.jsonl` beside the
# ledger, {at, event: alert|reminder, key, action, class}, which the scorecard
# counts.
#
# With --quota <file> (`quota`'s answer), a posted block ends with one `Quota <id>`
# line per provider instance: its weekly and 5 hour remaining as a percentage, or
# `unknown`. Those lines never make a block post: the figures move every wake, so
# only a changed row does.
#
# With --instance <id>, the provider instance the super agent's own thread runs on
# (`providerInstanceId` of `t3 thread show $T3CODE_THREAD_ID`), a posted block ends with
# `Super agent on <id>`, after any Quota lines. Like them it never makes a block post.
#
# stdout: {block, changed, raised: [{key, action, class, reminder}]}: `block` the
#         text to post ("" when nothing changed and no digest was asked, or when
#         a digest finds nothing open), `changed` true when the needs or a row
#         differ from the last printed block, `raised` the needs this block
#         alerts (`reminder` false) or reminds (true)
# exit: 0 a block or none · 2 usage, an unreadable or wrong-shaped ledger,
#       --quota or --fleet file, or a write that failed
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh" || { printf '{"error":"cannot source _lib.sh"}\n'; exit 2; }

usage='usage: status --ledger <file> [--quota <file>] [--instance <id>] [--fleet <file>] [--digest]'
sa_help "$usage" "$@"
ledger='' digest=false quota='' instance='' fleet=''
while [ $# -gt 0 ]; do
  case $1 in
    --digest) digest=true; shift; continue ;;
    --ledger) sa_flag_value "$usage" "${2:-}"; ledger=$2 ;;
    --quota) sa_flag_value "$usage" "${2:-}"; quota=$2 ;;
    --instance) sa_flag_value "$usage" "${2:-}"; instance=$2 ;;
    --fleet) sa_flag_value "$usage" "${2:-}"; fleet=$2 ;;
    *) sa_tooling "$usage" ;;
  esac
  shift 2
done
[ -n "$ledger" ] || sa_tooling "$usage"
sa_read "$ledger"
qdoc=null
if [ -n "$quota" ]; then
  sa_quota_file "$quota"
  qdoc=$(cat "$quota")
fi
week='[1,2,3,4,5]'
if [ -n "$fleet" ]; then
  week=$(sa_work_week "$fleet") || { printf '%s\n' "$week"; exit 2; }
fi

# The rows as the ledger holds them now: {rows: {"Needs you" (the needs-you message),
# Merged, Running, Yours, Waiting, "Reviewer limit"} (one absent when empty),
# merged_keys, raised}.
now=$(jq -c --argjson now "$(sa_now_s)" --argjson week "$week" "$sa_jq_norm$sa_jq_waiting$sa_jq_open$sa_jq_needs"'
  def short: sub("^[^/]*/"; "");
  def link($repo; $n): "[\($repo | short)#\($n)](https://github.com/\($repo)/issues/\($n))";
  def keylink: if startswith("task:") then . else link(sub("#.*$"; ""); sub("^.*#"; "")) end;
  def tlabel: (if .kind == "task" then "\(.key) (task)" else link(.repo; .number) end) + (if .adopted == true then " (adopted)" else "" end);
  def row($name; $items; $sep): if ($items | length) == 0 then {} else {($name): "\($name) (\($items | length)): \($items | join($sep))"} end;
  def state: if .observed.gate == true then "at its merge gate"
    elif .observed.pr.state == "open" then "in review"
    elif .stage == "launched" then "launched"
    elif .stage == "at-rest" then "at rest" else .stage end;
  def raise($r): {key, action, class: (if need_blocking then "blocking" else "offer" end), reminder: $r};
  if all((.needs // [])[]; (.key | type) == "string" and (.action | type) == "string") then . else error("needs") end
  | (.status.merged_ack // []) as $ack
  | [.entries[] | select((.kind // "ship") == "ship" and (.stage | IN("merged", "settled"))
      and (.key as $k | $ack | map(norm_repo) | index($k | norm_repo) | not))] as $merged
  | {rows: (((.needs // []) as $n | if ($n | length) > 0 then {"Needs you": ($n | needs_text)} else {} end)
      + row("Merged"; [$merged[] | "\(link(.repo; .number))" + (if .observed.pr.number then " PR [\(.observed.pr.number)](https://github.com/\(.repo)/pull/\(.observed.pr.number))" else "" end)]; ", ")
      + row("Running"; [.entries[] | select((.stage | IN("launched", "running", "at-rest")) and (.owner_run != true))
          | "\(tlabel) \(state)" + (if .instance_id then " on \(.instance_id)" else "" end) + (if .steered == true then " (you spoke last)" else "" end)]; ", ")
      + row("Yours"; [.entries[] | select(.owner_run == true and is_open)
          | "\(tlabel) \(if .observed.pr.state == "open" then "PR open" elif .observed.pr.state == "merged" then "PR merged" elif .observed.pr.state == "closed" then "PR closed" else "no PR" end), yours for \(
            (((.owner_run_since // .updated_at) | sub("[.][0-9]+Z$"; "Z") | fromdateiso8601) as $s | (($now - $s) / 86400 | floor)) as $d
            | if $d < 1 then "under a day" elif $d == 1 then "1 day" else "\($d) days" end)"]; ", ")
      + row("Waiting"; [waiting_list[] | .key | keylink]; ", ")
      + row("Reviewer limit"; [(.review_limits // [])[] | "\(.repo) merging on the fallback reviewer only (\(.reviewer) hit its usage limit at \(.since))"]; "; ")),
     merged_keys: [$merged[].key],
     raised: [(.needs // [])[] | need_alerted as $al
       | if $al == null then raise(false)
         elif need_blocking and .reminded == null
           and working_seconds($al | sub("[.][0-9]+Z$"; "Z") | fromdateiso8601; $now; $week) >= 4 * 3600 then raise(true)
         else empty end]}' <<<"$doc") \
  && [ -n "$now" ] || sa_tooling "$ledger: needs, waiting and entries are not the shapes status reads"

printed=$(jq -ec '(.status // {}) as $s | if ($s | type) == "object" and (($s.merged_ack // []) | type) == "array" then $s.rows // {} else error end' <<<"$doc") \
  || sa_tooling "$ledger: status is not an object with a merged_ack array"
changed=$(jq -r --argjson p "$printed" '.rows != $p' <<<"$now")
# A digest prints every row; a plain run only the rows that differ from the last
# block, a row that emptied as `<row>: none` (bar Merged, which empties by being
# listed). A need to raise prints the needs whatever changed.
block=$(jq -r --argjson d "$digest" --argjson p "$printed" --argjson q "$qdoc" --arg inst "$instance" '
  def pct: if . == null then "unknown" else "\((. * 100) | round)%" end;
  def bucket($p; $w): [$p.buckets[]? | select(if $w == "5h" then .window == "5h" else .window == "weekly" and (if $p.driver == "claude" then .id == "week" elif $p.driver == "pi" then ((.group // "") | startswith("Claude")) else true end) end)] | first | .remaining;
  . as $now
  | $now.rows["Needs you"] as $nt
  | [if $d or ($now.raised | length) > 0 then $nt // empty
     elif $nt == $p["Needs you"] then empty
     else $nt // "Nothing needs you now." end] as $needs
  | [("Merged", "Running", "Yours", "Waiting", "Reviewer limit") as $n
      | if $d then $now.rows[$n] // empty
        elif $now.rows[$n] == $p[$n] then empty
        elif $now.rows[$n] != null then $now.rows[$n]
        elif $n == "Merged" then empty
        else "\($n): none" end] as $rows
  | ([($q.providers // {}) | to_entries[] | "Quota \(.key): weekly \(bucket(.value; "weekly") | pct), 5 hour \(bucket(.value; "5h") | pct)"]) as $qlines
  | if ($needs + $rows | length) > 0 then
      $needs + ([$rows + $qlines + (if $inst == "" then [] else ["Super agent on \($inst)"] end) | join("\n")] | map(select(. != "")))
      | join("\n\n")
    else "" end' <<<"$now") \
  || sa_tooling "$quota: not a quota read"

# What the next run compares with. A printed block counts its Merged tickets as
# listed, so the next block lists only the merges since: the stored rows are the
# ones left after that. A raised need takes its alert or reminder mark, and a line
# in the alert log. The ledger was read unlocked, so a need re-recorded meanwhile in
# another case still matches its raised key.
if [ -n "$block" ]; then
  at=$(jq -rn --argjson s "$(sa_now_s)" '$s | todate')
  sa_update "$ledger" "$sa_jq_norm"'.status = {rows: ($n.rows | del(.Merged)), merged_ack: ((.status.merged_ack // []) + $n.merged_keys | unique)}
    | if ($n.raised | length) > 0 then .needs = [(.needs // [])[] | . as $x
        | ([$n.raised[] | select((.key | norm_repo) == ($x.key | norm_repo) and .action == $x.action)] | first) as $r
        | if $r == null then . elif $r.reminder then .reminded = $at else .alerted = $at end] else . end' --argjson n "$now" --arg at "$at"
  jq -c --arg at "$at" '.raised[] | {at: $at, event: (if .reminder then "reminder" else "alert" end), key, action, class}' <<<"$now" \
    >>"$(dirname "$ledger")/needs-alerts.jsonl" || sa_tooling "$(dirname "$ledger")/needs-alerts.jsonl: cannot append"
fi

jq -cn --arg b "$block" --argjson c "$changed" --argjson r "$(jq -c .raised <<<"$now")" '{block: $b, changed: $c, raised: $r}'
