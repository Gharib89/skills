#!/usr/bin/env bash
# Answer whether one machine may take a launch now: a slot is free, its load
# is under its core count, its free RAM is above the per-thread floor, and the
# ticket's repo has no open ticket it must not run beside.
#
#   launch-check --fleet <file> --ledger <file> --machine <key> --load <n>
#                --free-gb <n> [--own <key>] [--key <ledger key>] [--repo <owner/name>
#                [--area <path>]... [--blocked-by <n>]...]
#
# --load and --free-gb are the machine's live 1-minute load and available RAM
# in GB, which `probe.sh` prints (`load1`, `free_gb`); the caller reads them
# where the machine is, since this script measures nothing. --own names the
# machine the ledger is on (`hostname` when omitted), where an entry added with
# the default machine `local` counts. A machine's slots in use are the open
# ledger entries on it. Its ceiling is its `slots` less its `reserve`, the slots
# kept for the owner's messages (setup proposes 1 for the super agent's own
# machine). The load limit is the machine's `max_load` (its cores when unset),
# the RAM floor the fleet file's `thread_ram_floor_gb` (4 when unset); load must
# be under the limit and free RAM above the floor. With --repo, an open ticket
# of the same repo refuses the launch when it blocks this one (`--blocked-by`
# names the open blocker numbers read from GitHub) or its areas overlap this
# one's: two paths overlap when one is the other or lies under it, and a ticket
# with no areas, either side, overlaps everything, since nothing says the work
# is apart. Different repos never refuse. With --repo, the repo's ship cap
# refuses too: the fleet file's `repos.<owner/name>.max_ships` (3 when unset)
# bounds the open tickets of that repo, ship and triage, on every machine
# together, not counting --key's.
#
# --key names a ledger entry to leave out of the slot count and the repo
# conflicts: a rethread of a ticket the ledger still holds.
# stdout: {machine, ok, refused, slots: {used, ceiling}, load: {value, limit},
#         free_gb: {value, floor}, repo: {conflicts}}: `refused` the checks that
#         failed, each one of slots, load, ram, repo, cap; `repo.conflicts` the keys
#         of the open tickets in the way; `cap` {open, max} (open 0 with no
#         --repo). A machine the fleet file lacks is
#         {error}
# exit: 0 the machine takes a launch · 1 it does not, or is not in the fleet
#       file · 2 usage, or a fleet file or ledger that is unreadable
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh" || { printf '{"error":"cannot source _lib.sh"}\n'; exit 2; }

usage='usage: launch-check --fleet <file> --ledger <file> --machine <key> --load <n> --free-gb <n> [--own <key>] [--key <ledger key>] [--repo <owner/name> [--area <path>]... [--blocked-by <n>]...]'
sa_help "$usage" "$@"
fleet='' ledger='' machine='' load='' free='' own='' key='' repo='' areas='[]' blockers='[]'
num() { case $1 in ''|.|*[!0-9.]*|*.*.*) sa_tooling "$usage" ;; esac; }
while [ $# -gt 0 ]; do
  case $1 in
    --fleet) sa_flag_value "$usage" "${2:-}"; fleet=$2 ;;
    --ledger) sa_flag_value "$usage" "${2:-}"; ledger=$2 ;;
    --machine) sa_flag_value "$usage" "${2:-}"; machine=$2 ;;
    --load) sa_flag_value "$usage" "${2:-}"; num "$2"; load=$2 ;;
    --free-gb) sa_flag_value "$usage" "${2:-}"; num "$2"; free=$2 ;;
    --own) sa_flag_value "$usage" "${2:-}"; own=$2 ;;
    --key) sa_flag_value "$usage" "${2:-}"; key=$2 ;;
    --repo) sa_flag_value "$usage" "${2:-}"; repo=$2 ;;
    --area) sa_flag_value "$usage" "${2:-}"; areas=$(jq -c --arg a "$2" '. + [$a]' <<<"$areas") ;;
    --blocked-by) sa_flag_value "$usage" "${2:-}"; case $2 in *[!0-9]*) sa_tooling "$usage" ;; esac
      blockers=$(jq -c --argjson n "$2" '. + [$n]' <<<"$blockers") ;;
    *) sa_tooling "$usage" ;;
  esac
  shift 2
done
[ -n "$fleet" ] && [ -n "$ledger" ] && [ -n "$machine" ] && [ -n "$load" ] && [ -n "$free" ] || sa_tooling "$usage"
{ [ -n "$repo" ] || { [ "$areas" = '[]' ] && [ "$blockers" = '[]' ]; }; } || sa_tooling "$usage"
[ -f "$fleet" ] || sa_tooling "$fleet: no such file"
jq -e '(.machines | type) == "object"' "$fleet" >/dev/null 2>&1 || sa_tooling "$fleet: not a fleet file (machines must be an object)"
[ -n "$own" ] || own=$(hostname 2>/dev/null) || sa_tooling "cannot read this machine's name: pass --own"
jq -e '[(.repos // {})[]? | .max_ships // 1 | type == "number" and . >= 1 and . == floor] | all' "$fleet" >/dev/null \
  || sa_tooling "$fleet: every repos.<owner/name>.max_ships must be a whole number of 1 or more"
jq -e --arg m "$machine" '.machines[$m] | type == "object"' "$fleet" >/dev/null || sa_fail "$machine is not in the fleet file"
sa_read "$ledger"

out=$(jq -cn --slurpfile fleet "$fleet" --argjson doc "$doc" --arg m "$machine" --arg own "$own" --arg key "$key" \
  --argjson load "$load" --argjson free "$free" --arg repo "$repo" --argjson areas "$areas" --argjson blockers "$blockers" \
  "$sa_jq_open$sa_jq_norm"'
  def under($a; $b): ($a | norm_path) as $x | ($b | norm_path) as $y
    | $x == $y or ($x | startswith($y + "/")) or ($y | startswith($x + "/"));
  $fleet[0] as $f | $f.machines[$m] as $mm
  | [$doc.entries[] | select(is_open) | select((.key | norm_repo) != ($key | norm_repo))] as $open
  | ([$open[] | select(.machine == $m or (.machine == "local" and $m == $own))] | length) as $used
  | (($mm.slots // 1) - ($mm.reserve // 0)) as $ceiling
  | ($mm.max_load // $mm.cores // 0) as $limit
  | ($f.thread_ram_floor_gb // 4) as $floor
  | ([$open[] | select($repo != "" and ((.repo // "") | norm_repo) == ($repo | norm_repo))
      | select((.number as $n | $blockers | index($n)) != null
          or ((.areas // []) as $theirs | ($theirs | length) == 0 or ($areas | length) == 0
              or ([$theirs[] as $t | $areas[] as $a | under($a; $t)] | any)))
      | .key]) as $conflicts
  | ([($f.repos // {}) | to_entries[] | select((.key | norm_repo) == ($repo | norm_repo)) | .value.max_ships] | first // 3) as $max
  | ([$open[] | select($repo != "" and ((.repo // "") | norm_repo) == ($repo | norm_repo))] | length) as $repoopen
  | ([(if $used < $ceiling then empty else "slots" end),
      (if $load < $limit then empty else "load" end),
      (if $free > $floor then empty else "ram" end),
      (if ($conflicts | length) == 0 then empty else "repo" end),
      (if $repo != "" and $repoopen >= $max then "cap" else empty end)]) as $refused
  | {machine: $m, ok: ($refused | length == 0), refused: $refused,
     slots: {used: $used, ceiling: $ceiling}, load: {value: $load, limit: $limit},
     free_gb: {value: $free, floor: $floor}, repo: {conflicts: $conflicts},
     cap: {open: $repoopen, max: $max}}') \
  || sa_tooling "$fleet or $ledger cannot be read"
printf '%s\n' "$out"
jq -e .ok >/dev/null <<<"$out"
