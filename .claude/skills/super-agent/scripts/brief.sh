#!/usr/bin/env bash
# Print a launch brief: what every supervised thread is
# told after its owner-skill invocation line, so the waivers reach it word for
# word and no launch rewords them.
#
#   brief --fleet <file> --ledger <file> [--repo <owner/name>] [--machine <key>]
#         [--note <text>]
#
# --repo and --machine (the fleet key of the machine the thread runs on) select
# the scoped rulings and the fleet's `repos.<r>.brief` and `machines.<m>.brief`
# lines; without them only unscoped rulings print and the lock line names
# `<repo>`. --note adds one `Note for this ticket:` line.
#
# The brief also carries the waiting line (`sa_waiting_line` in `_lib.sh`), the fixed
# last line of a turn that ends only to wait on the run's own background work.
#
# Who rules on a hold outside the allowance is the fleet file's `merge_gate_ruler`,
# `owner` (the default) or `super-agent`: the brief names the one that decides,
# and tells the run to keep any ruling out of a PR body.
#
# The waivers are the fleet file's `waivers`, each `condition` verbatim, and the
# allowed calls are the ledger's `allowed` lines (the owner's dated rulings). The
# rulings the owner marked brief-bound (`ledger ruling --brief`) follow under
# `Owner rulings:`, each word for word. A fleet file with no waivers says so, so a
# hold is never read as waived.
#
# stdout: {brief, waivers, allowed, rulings, lines, gate_ruler}: `brief` the text to send,
#         `waivers`, `allowed`, `rulings` and `lines` how many of each it carries,
#         `gate_ruler` `owner` or `super-agent`
# exit: 0 a brief · 2 usage, or a fleet file or ledger that is unreadable
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh" || { printf '{"error":"cannot source _lib.sh"}\n'; exit 2; }

usage='usage: brief --fleet <file> --ledger <file> [--repo <owner/name>] [--machine <key>] [--note <text>]'
sa_help "$usage" "$@"
fleet='' ledger='' repo='' machine='' note=''
while [ $# -gt 0 ]; do
  case $1 in
    --fleet) sa_flag_value "$usage" "${2:-}"; fleet=$2; shift 2 ;;
    --ledger) sa_flag_value "$usage" "${2:-}"; ledger=$2; shift 2 ;;
    --repo) sa_flag_value "$usage" "${2:-}"; repo=$2; shift 2 ;;
    --machine) sa_flag_value "$usage" "${2:-}"; machine=$2; shift 2 ;;
    --note) sa_flag_value "$usage" "${2:-}"; note=$2; shift 2 ;;
    *) sa_tooling "$usage" ;;
  esac
done
[ -n "$fleet" ] && [ -n "$ledger" ] || sa_tooling "$usage"
[ -f "$fleet" ] || sa_tooling "$fleet: no such file, run setup"
jq -e '((.waivers // []) | type) == "array"' "$fleet" >/dev/null 2>&1 || sa_tooling "$fleet: not a fleet file (waivers must be an array)"
jq -e '(.merge_gate_ruler // "owner") | IN("owner", "super-agent")' "$fleet" >/dev/null 2>&1 \
  || sa_tooling "$fleet: merge_gate_ruler must be \"owner\" or \"super-agent\""
jq -e '((.repos // {}) | type == "object")
  and ([(.repos // {})[]?.brief, (.machines // {})[]?.brief] | all(. == null or (type == "array" and all(type == "string"))))' "$fleet" >/dev/null 2>&1 \
  || sa_tooling "$fleet: repos must be an object, and each brief under repos and machines an array of text lines"
allowed=$(bash "$(dirname "${BASH_SOURCE[0]}")/ledger.sh" --ledger "$ledger" allowed) || sa_tooling "cannot read the allowed calls from $ledger"
briefed=$(bash "$(dirname "${BASH_SOURCE[0]}")/ledger.sh" --ledger "$ledger" briefed) || sa_tooling "cannot read the rulings from $ledger"

jq -cn --slurpfile f "$fleet" --argjson a "$allowed" --argjson r "$briefed" --arg repo "$repo" --arg machine "$machine" --arg note "$note" --arg wl "$sa_waiting_line" \
  "$sa_jq_norm"'
  ($f[0].waivers // []) as $w | $a.allowed as $al
  | [$r.briefed[] | select(((.repo // null) == null or (.repo | norm_repo) == ($repo | norm_repo))
      and ((.machine // null) == null or .machine == $machine))] as $rl
  | ([(($f[0].repos // {}) | to_entries[] | select(.key | norm_repo == ($repo | norm_repo)) | .value.brief // [])[]?,
      (($f[0].machines // {})[$machine].brief // [])[]?]) as $fl
  | ($f[0].merge_gate_ruler // "owner") as $ruler
  | ($repo | norm_repo | split("/") | join("-")) as $lock
  | {brief: ([
      "Merge allowance: merge when /ship'"'"'s merge gate is clean, nothing wider.",
      "Standing waivers, the only holds you may pass without stopping:",
      (if ($w | length) == 0 then "  (none)" else ($w | to_entries[] | "  \(.key + 1). \(.value.condition)") end),
      "Any hold outside the merge allowance and these waivers stops at the gate: end with the gate state and the hold named, and do not work around it; \(if $ruler == "owner" then "the super agent escalates it to the owner" else "the super agent rules on it and reports to the owner" end).",
      "A ruling from the super agent or the owner arrives in your thread: act on it, and never write it into a PR body (the body records what you did and checked).",
      "Commands harmless to run (reads, tests, the repo'"'"'s own checks) need no hold.",
      "Other runs share this machine: stop only the processes you started, by their PID (never `pkill` or `pgrep` by name or pattern), and run the heavy check (the full suite, a container) under a per-repo lock and a memory cap: `flock /tmp/super-agent-\(if $lock == "" then "<repo>" else $lock end).lock systemd-run --user --scope -q -p MemoryMax=<G>G -p MemorySwapMax=0 <command>`.",
      (if ($al | length) == 0 then empty else "Calls the owner allowed, no hold needed:", ($al[] | "  \(.line)") end),
      (if ($rl | length) == 0 then empty else "Owner rulings:", ($rl[] | "  \(.date): \(.text)") end),
      (if ($fl | length) == 0 then empty else "Lines for this repo and machine:", ($fl[] | "  \(.)") end),
      (if $note == "" then empty else "Note for this ticket:", "  \($note)" end),
      "A turn that ends only to wait on your own background work (a check, a CI wait, a subagent) ends with this line, word for word, as its last line: `\($wl)` The watcher reads it as still working and wakes the super agent for no stall until the stall window has passed. Your final message is the PR URL and the gate state below, never this line.",
      "Work in the worktree you start in, on the branch it holds, and make no other: the PR is found by that branch.",
      "End your last message with the PR URL and the gate state."
    ] | join("\n")),
    waivers: ($w | length), allowed: ($al | length), rulings: ($rl | length), lines: ($fl | length), gate_ruler: $ruler}'
