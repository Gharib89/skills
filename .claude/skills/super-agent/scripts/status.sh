#!/usr/bin/env bash
# Print the super agent's status block from the ledger alone, and say whether it
# is worth posting. The block is the only report the owner reads: the super agent
# posts `block` as printed, never rewrites it, and posts nothing when `block` is
# empty.
#
#   status --ledger <file> [--quota <file>] [--digest]
#
# Rows, in this order, an empty row left out: `Needs you` (the ledger's open
# needs, each its one action), `Merged` (a ship entry whose PR merged and that no
# digest has listed yet), `Running` (an open entry, read as at its merge gate, in
# review, launched, running or at rest; a `task` entry reads `task:<slug> (task)`
# and an adopted one adds `(adopted)`), `Waiting` (the waiting list, in its
# order), `Reviewer limit` (a repo whose hosted reviewer hit its usage limit: its
# batch is merging on the fallback reviewer only, until `ledger unlimit`). A
# Running ticket names the provider instance it launched on, where the ledger holds one.
# Each ticket is a Markdown link to its issue, a merged one's PR a second
# link. The ledger keeps the rows of the last block it printed (`status`), so a
# run knows whether any row changed since. A plain run prints the block only when
# a row changed, and a run with nothing changed prints none; `--digest` prints
# the whole block whatever changed (the owner's "status", the morning report, an
# emptied waiting list) and then counts every Merged ticket as listed.
#
# With --quota <file> (`quota`'s answer), a posted block ends with one `Quota <id>`
# line per provider instance: its weekly and 5 hour remaining as a percentage, or
# `unknown`. Those lines never make a block post: the figures move every wake, so
# only a changed row does.
#
# stdout: {block, changed, unpushed: [{key, action, since}]}: `block` the text to
#         post ("" when nothing changed and no digest was asked, or when nothing
#         is open), `changed` true when a row differs from the last printed
#         block, `unpushed` the open needs whose push has not gone out, each of
#         which `ledger pushed` marks once sent
# exit: 0 a block or none · 2 usage, an unreadable or wrong-shaped ledger or
#       --quota file, or a write that failed
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh" || { printf '{"error":"cannot source _lib.sh"}\n'; exit 2; }

usage='usage: status --ledger <file> [--quota <file>] [--digest]'
sa_help "$usage" "$@"
ledger='' digest=false quota=
while [ $# -gt 0 ]; do
  case $1 in
    --digest) digest=true; shift; continue ;;
    --ledger) sa_flag_value "$usage" "${2:-}"; ledger=$2 ;;
    --quota) sa_flag_value "$usage" "${2:-}"; quota=$2 ;;
    *) sa_tooling "$usage" ;;
  esac
  shift 2
done
[ -n "$ledger" ] || sa_tooling "$usage"
sa_read "$ledger"
qdoc=null
if [ -n "$quota" ]; then
  [ -f "$quota" ] && jq -e '(.providers | type) == "object"' "$quota" >/dev/null 2>&1 || sa_tooling "$quota: not a quota read"
  qdoc=$(cat "$quota")
fi

# The rows as the ledger holds them now: {rows: {needs, merged, running, waiting}
# (a row absent when empty), merged_keys, unpushed}.
now=$(jq -c "$sa_jq_norm$sa_jq_waiting"'
  def short: sub("^[^/]*/"; "");
  def link($repo; $n): "[\($repo | short)#\($n)](https://github.com/\($repo)/issues/\($n))";
  def keylink: if startswith("task:") then . else link(sub("#.*$"; ""); sub("^.*#"; "")) end;
  def tlabel: (if .kind == "task" then "\(.key) (task)" else link(.repo; .number) end) + (if .adopted == true then " (adopted)" else "" end);
  def row($name; $items; $sep): if ($items | length) == 0 then {} else {($name): "\($name) (\($items | length)): \($items | join($sep))"} end;
  def state: if .observed.gate == true then "at its merge gate"
    elif .observed.pr.state == "open" then "in review"
    elif .stage == "launched" then "launched"
    elif .stage == "at-rest" then "at rest" else .stage end;
  (.status.merged_ack // []) as $ack
  | [.entries[] | select((.kind // "ship") == "ship" and (.stage | IN("merged", "settled"))
      and (.key as $k | $ack | map(norm_repo) | index($k | norm_repo) | not))] as $merged
  | {rows: (row("Needs you"; [(.needs // [])[] | "\(.key | keylink) \(.action)"]; "; ")
      + row("Merged"; [$merged[] | "\(link(.repo; .number))" + (if .observed.pr.number then " PR [\(.observed.pr.number)](https://github.com/\(.repo)/pull/\(.observed.pr.number))" else "" end)]; ", ")
      + row("Running"; [.entries[] | select(.stage | IN("launched", "running", "at-rest")) | "\(tlabel) \(state)" + (if .instance_id then " on \(.instance_id)" else "" end)]; ", ")
      + row("Waiting"; [waiting_list[] | .key | keylink]; ", ")
      + row("Reviewer limit"; [(.review_limits // [])[] | "\(.repo) merging on the fallback reviewer only (\(.reviewer) hit its usage limit at \(.since))"]; "; ")),
     merged_keys: [$merged[].key],
     unpushed: [(.needs // [])[] | select(.pushed != true) | {key, action, since}]}' <<<"$doc") \
  && [ -n "$now" ] || sa_tooling "$ledger: needs, waiting and entries are not the shapes status reads"

printed=$(jq -c '.status.rows // {}' <<<"$doc") || sa_tooling "$ledger: status is not an object"
changed=$(jq -r --argjson p "$printed" '.rows != $p' <<<"$now")
block=$(jq -r --argjson d "$digest" --argjson c "$changed" --argjson q "$qdoc" '
  def pct: if . == null then "unknown" else "\((. * 100) | round)%" end;
  def bucket($p; $w): [$p.buckets[]? | select(if $w == "5h" then .window == "5h" else .window == "weekly" and (if $p.driver == "claude" then .id == "week" elif $p.driver == "pi" then ((.group // "") | startswith("Claude")) else true end) end)] | first | .remaining;
  ([("Needs you", "Merged", "Running", "Waiting", "Reviewer limit") as $n | .rows[$n] // empty]) as $rows
  | ([($q.providers // {}) | to_entries[] | "Quota \(.key): weekly \(bucket(.value; "weekly") | pct), 5 hour \(bucket(.value; "5h") | pct)"]) as $qlines
  | if ($d or $c) and ($rows | length) > 0 then ($rows + $qlines) | join("\n") else "" end' <<<"$now") \
  || sa_tooling "$quota: not a quota read"

# What the next run compares with. A digest also counts its Merged tickets as
# listed, so the row it printed leaving is no change: the stored rows are the
# ones left after that.
if [ "$digest" = true ]; then
  doc=$(jq -c --argjson n "$now" '.status = {rows: ($n.rows | del(.Merged)), merged_ack: ((.status.merged_ack // []) + $n.merged_keys | unique)}' <<<"$doc") || sa_tooling "$ledger: status is not an object"
else
  doc=$(jq -c --argjson n "$now" '.status = {rows: $n.rows, merged_ack: (.status.merged_ack // [])}' <<<"$doc") || sa_tooling "$ledger: status is not an object"
fi
if [ "$digest" = true ] || [ "$changed" = true ]; then sa_write "$ledger" "$doc"; fi

jq -cn --arg b "$block" --argjson c "$changed" --argjson u "$(jq -c .unpushed <<<"$now")" '{block: $b, changed: $c, unpushed: $u}'
