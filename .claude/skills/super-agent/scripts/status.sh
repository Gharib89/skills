#!/usr/bin/env bash
# Print the super agent's status block from the ledger alone, and say whether it
# is worth posting. The block is the only report the owner reads: the super agent
# posts `block` as printed, never rewrites it, and posts nothing when `block` is
# empty.
#
#   status --ledger <file> [--digest]
#
# Rows, in this order, an empty row left out: `Needs you` (the ledger's open
# needs, each its one action), `Merged` (a ship entry whose PR merged and that no
# digest has listed yet), `Running` (an open entry, read as at its merge gate, in
# review, launched, running or at rest), `Waiting` (the waiting list, in its
# order). Each ticket is a Markdown link to its issue, a merged one's PR a second
# link. The ledger keeps the rows of the last block it printed (`status`), so a
# run knows whether any row changed since. A plain run prints the block only when
# a row changed, and a run with nothing changed prints none; `--digest` prints
# the whole block whatever changed (the owner's "status", the morning report, an
# emptied waiting list) and then counts every Merged ticket as listed.
#
# stdout: {block, changed, unpushed: [{key, action, since}]}: `block` the text to
#         post ("" when nothing changed and no digest was asked, or when nothing
#         is open), `changed` true when a row differs from the last printed
#         block, `unpushed` the open needs whose push has not gone out, each of
#         which `ledger pushed` marks once sent
# exit: 0 a block or none · 2 usage, an unreadable or wrong-shaped ledger, or a
#       write that failed
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh" || { printf '{"error":"cannot source _lib.sh"}\n'; exit 2; }

usage='usage: status --ledger <file> [--digest]'
sa_help "$usage" "$@"
ledger='' digest=false
while [ $# -gt 0 ]; do
  case $1 in
    --digest) digest=true; shift; continue ;;
    --ledger) sa_flag_value "$usage" "${2:-}"; ledger=$2 ;;
    *) sa_tooling "$usage" ;;
  esac
  shift 2
done
[ -n "$ledger" ] || sa_tooling "$usage"
sa_read "$ledger"

# The rows as the ledger holds them now: {rows: {needs, merged, running, waiting}
# (a row absent when empty), merged_keys, unpushed}.
now=$(jq -c "$sa_jq_norm"'
  def short: sub("^[^/]*/"; "");
  def link($repo; $n): "[\($repo | short)#\($n)](https://github.com/\($repo)/issues/\($n))";
  def keylink: link(sub("#.*$"; ""); sub("^.*#"; ""));
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
      + row("Running"; [.entries[] | select(.stage | IN("launched", "running", "at-rest")) | "\(link(.repo; .number)) \(state)"]; ", ")
      + row("Waiting"; [(.waiting // [])[] | .key | keylink]; ", ")),
     merged_keys: [$merged[].key],
     unpushed: [(.needs // [])[] | select(.pushed != true) | {key, action, since}]}' <<<"$doc") \
  && [ -n "$now" ] || sa_tooling "$ledger: needs, waiting and entries are not the shapes status reads"

printed=$(jq -c '.status.rows // {}' <<<"$doc") || sa_tooling "$ledger: status is not an object"
changed=$(jq -r --argjson p "$printed" '.rows != $p' <<<"$now")
block=$(jq -r --argjson d "$digest" --argjson c "$changed" '
  if ($d or $c) then [("Needs you", "Merged", "Running", "Waiting") as $n | .rows[$n] // empty] | join("\n") else "" end' <<<"$now")

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
