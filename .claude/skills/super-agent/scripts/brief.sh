#!/usr/bin/env bash
# Print the standing part of a launch brief: what every supervised thread is
# told after its owner-skill invocation line, so the waivers reach it word for
# word and no launch rewords them.
#
#   brief --fleet <file> --ledger <file>
#
# The waivers are the fleet file's `waivers`, each `condition` verbatim, and the
# allowed calls are the ledger's `allowed` lines (the owner's dated rulings). A
# fleet file with no waivers says so, so a hold is never read as waived.
#
# stdout: {brief, waivers, allowed}: `brief` the text to send, `waivers` and
#         `allowed` how many of each it carries
# exit: 0 a brief · 2 usage, or a fleet file or ledger that is unreadable
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh" || { printf '{"error":"cannot source _lib.sh"}\n'; exit 2; }

usage='usage: brief --fleet <file> --ledger <file>'
sa_help "$usage" "$@"
fleet='' ledger=''
while [ $# -gt 0 ]; do
  case $1 in
    --fleet) sa_flag_value "$usage" "${2:-}"; fleet=$2; shift 2 ;;
    --ledger) sa_flag_value "$usage" "${2:-}"; ledger=$2; shift 2 ;;
    *) sa_tooling "$usage" ;;
  esac
done
[ -n "$fleet" ] && [ -n "$ledger" ] || sa_tooling "$usage"
[ -f "$fleet" ] || sa_tooling "$fleet: no such file, run setup"
jq -e '((.waivers // []) | type) == "array"' "$fleet" >/dev/null 2>&1 || sa_tooling "$fleet: not a fleet file (waivers must be an array)"
sa_read "$ledger"
allowed=$(bash "$(dirname "${BASH_SOURCE[0]}")/ledger.sh" --ledger "$ledger" allowed) || sa_tooling "cannot read the allowed calls from $ledger"

jq -cn --slurpfile f "$fleet" --argjson a "$allowed" '
  ($f[0].waivers // []) as $w | $a.allowed as $al
  | {brief: ([
      "Merge allowance: merge when /ship'"'"'s merge gate is clean, nothing wider.",
      "Standing waivers, the only holds you may pass without stopping:",
      (if ($w | length) == 0 then "  (none)" else ($w | to_entries[] | "  \(.key + 1). \(.value.condition)") end),
      "Any hold outside the merge allowance and these waivers stops at the gate: end with the gate state and the hold named, and do not work around it; the super agent escalates it to the owner.",
      "Commands harmless to run (reads, tests, the repo'"'"'s own checks) need no hold.",
      (if ($al | length) == 0 then empty else "Calls the owner allowed, no hold needed:", ($al[] | "  \(.line)") end),
      "Work in the worktree you start in, on the branch it holds, and make no other: the PR is found by that branch.",
      "End your last message with the PR URL and the gate state."
    ] | join("\n")),
    waivers: ($w | length), allowed: ($al | length)}'
