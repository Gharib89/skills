# The `add` and `adopt` arms of `ledger`: record a thread's entry, and for `adopt` the
# thread read behind "Watch <thread>", sourced by it. They read the caller's $usage,
# $ledger, $cmd and $doc, which `ledger.sh` sets.

# shellcheck disable=SC2154,SC2034  # usage, ledger, cmd and doc come from ledger.sh and _lib.sh; the add flags are set in ledger_add and read by adopt_fill; read_kind and read_number are read by adopt_held and adopt_fill

# adopt_ticket_of_read: the ticket a thread's first user message names, from the read in
# $read_file: `/ship-run <n>` is a ship, `/triage <n>` a triage. Sets $read_kind and
# $read_number, both empty for a first message that is neither. A `--number` the message
# does not name is refused.
adopt_ticket_of_read() {
  local first
  read_kind='' read_number=''
  first=$(jq -r '[.items[]? | select(.type == "user_message")] | sort_by(.position) | first | .text // ""' "$read_file")
  if [[ $first =~ ^[[:space:]]*/(ship-run|triage)[[:space:]]+([0-9]+) ]]; then
    read_number=${BASH_REMATCH[2]}
    if [ "${BASH_REMATCH[1]}" = triage ]; then read_kind=triage; else read_kind=ship; fi
    [ -z "$number" ] || [ "$number" = "$read_number" ] || sa_tooling "--number $number is not the ticket the thread's first message names ($read_number)"
  fi
}

# adopt_held <thread>: when an open entry already holds the thread, the entry is that
# one: no second row, and a flag or a read naming another ticket is refused (exit 1,
# naming the holder). An owner-run entry stops being owner-run (the mark, the observed
# baseline and the rest clock go, `resumed` has the next reconcile take the thread's
# run count as judged), its steered mark is cleared and its `held_since` restarted at
# `$now`, so the owner's earlier messages are not read as steering it, and its
# `owner-steered` need is cleared, so the next steer is asked about again. Answers and
# exits 0; returns 1 when no open entry holds the thread.
adopt_held() {
  local key named='' num
  key=$(jq -r --arg t "$1" "$sa_jq_open"'first(.entries[] | select(.thread == $t and is_open) | .key) // empty' <<<"$doc")
  [ -n "$key" ] || return 1
  if [ -n "$task" ]; then named="task:$task"
  else
    num=$number
    if [ -n "$read_file" ]; then adopt_ticket_of_read; num=${read_number:-$number}; fi
    [ -z "$num" ] || named=$(jq -r --arg k "$key" --arg n "$num" --arg r "$repo" "$sa_jq_norm"'.entries[$k] | if ((.number | tostring) == $n and ($r == "" or (.repo // "" | norm_repo) == ($r | norm_repo))) then $k else "\(.repo // "?")#\($n)" end' <<<"$doc")
  fi
  [ -z "$named" ] || [ "$named" = "$key" ] || sa_fail "thread $1 is held by $key, not $named: drop that entry first, or run adopt --thread $1 with no read and no ticket flags"
  sa_update "$ledger" "$sa_jq_norm"'.entries[$k] |= ((if .owner_run == true then .owner_run = false | del(.owner_run_since, .owner_run_reminded)
      | .observed = null | .rest_since = null | .resumed = true else . end)
      | .steered = false | .held_since = $now | .updated_at = $now)
    | .needs = ((.needs // []) | map(select(((.key | norm_repo) != ($k | norm_repo)) or .reason != "owner-steered")))' --arg k "$key" --arg now "$now"
  jq -cn --arg l "$ledger" --arg k "$key" --argjson e "$(jq -c --arg k "$key" '.entries[$k]' <<<"$doc")" '{ledger: $l, key: $k, entry: $e, existing: true}'
  exit 0
}

# adopt_fill: what the add flags left empty, from the thread read in $read_file (the
# `t3_thread_read` of the thread's first page, `afterPosition: -1`, which `ledger_add` has
# checked): the worktree and branch from the thread, and, unless `--task`
# names a task, the kind and number from the thread's first user message (`--number` only
# fills a missing number, and the message's kind wins over `--kind`), the repo from `--repo` or else the worktree's `origin` remote when it names
# github.com. A thread whose first message is neither a ticket call and no `--task` or
# `--number` is refused: a task needs its slug. Sets $worktree, $branch, $kind, $number
# and $repo. The pull request is not read: reconcile finds it by the branch.
adopt_fill() {
  local url
  [ -n "$worktree" ] || worktree=$(jq -r '.thread.worktreePath // empty' "$read_file")
  [ -n "$branch" ] || branch=$(jq -r '.thread.branch // empty' "$read_file")
  if [ -z "$task" ]; then
    adopt_ticket_of_read
    number=${read_number:-$number}
    [ -n "$number" ] || sa_tooling "the thread's first message is no /ship-run or /triage call: pass --task <slug>, or --repo and --number (and --kind) for a ticket's thread"
    kind=${read_kind:-$kind}
  fi
  [ -z "$task" ] || return 0
  if [ -z "$repo" ] && [ -n "$worktree" ]; then
    url=$(git -C "$worktree" remote get-url origin 2>/dev/null)
    url=${url%/}; url=${url%.git}
    if [[ $url =~ ^(git@github\.com:|(ssh|https)://(git@)?github\.com/)([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)$ ]]; then repo=${BASH_REMATCH[4]}; fi
  fi
  [ -n "$repo" ] || sa_tooling "the repo is unknown: pass --repo <owner/name> (the worktree has no github.com origin remote to read it from here)"
}

ledger_add() {
  repo='' number='' thread='' worktree='' branch='' machine='' environment='' instance='' model='' effort='' areas='[]' kind='' task='' adopted=false
  interactive=false launching=false read_file=''
  [ "$cmd" != adopt ] || adopted=true
  while [ $# -gt 0 ]; do
    case $1 in
      --interactive) interactive=true; shift; continue ;;
      --read) [ "$cmd" = adopt ] || sa_tooling "$usage"; sa_flag_value "$usage" "${2:-}"; read_file=$2 ;;
      --launching) [ "$cmd" = add ] || sa_tooling "$usage"; launching=true; shift; continue ;;
      --area) sa_flag_value "$usage" "${2:-}"; areas=$(jq -c --arg a "$2" '. + [$a]' <<<"$areas") ;;
      --repo) sa_flag_value "$usage" "${2:-}"; repo=$2 ;;
      --number) sa_flag_value "$usage" "${2:-}"; number=$2 ;;
      --thread) sa_flag_value "$usage" "${2:-}"; thread=$2 ;;
      --worktree) sa_flag_value "$usage" "${2:-}"; worktree=$2 ;;
      --branch) sa_flag_value "$usage" "${2:-}"; branch=$2 ;;
      --machine) sa_flag_value "$usage" "${2:-}"; machine=$2 ;;
      --environment) sa_flag_value "$usage" "${2:-}"; environment=$2 ;;
      --instance) sa_flag_value "$usage" "${2:-}"; instance=$2 ;;
      --kind) sa_flag_value "$usage" "${2:-}"; case $2 in ship|triage) kind=$2 ;; *) sa_tooling "$usage" ;; esac ;;
      --task) sa_flag_value "$usage" "${2:-}"; case $2 in *[!A-Za-z0-9._-]*) sa_tooling "$usage" ;; esac; task=$2 ;;
      --model) sa_flag_value "$usage" "${2:-}"; model=$2 ;;
      --effort) sa_flag_value "$usage" "${2:-}"; effort=$2 ;;
      *) sa_tooling "$usage" ;;
    esac
    shift 2
  done
  now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  if [ -n "$read_file" ]; then
    # "Watch <thread>": the thread comes from its read, which `--thread` may only repeat
    read_thread=$(jq -er '.thread.threadId | strings | select(length > 0)' "$read_file" 2>/dev/null) || sa_tooling "$read_file: not a t3_thread_read result"
    [ -z "$thread" ] || [ "$thread" = "$read_thread" ] || sa_tooling "--thread $thread is not the thread $read_file read ($read_thread)"
    thread=$read_thread
    jq -e '(.earlierPosition // null) == null' "$read_file" >/dev/null || sa_tooling "$read_file is not the thread's first page: read it again with afterPosition -1"
  fi
  if $adopted; then
    # the clock starts at adoption, and a thread the ledger holds is the same entry
    now=$(date -u -d "@$(sa_now_s)" +%Y-%m-%dT%H:%M:%SZ)
    if [ -n "$thread" ]; then sa_lock "$ledger"; sa_read "$ledger"; adopt_held "$thread"; fi
    [ -z "$read_file" ] || adopt_fill
  fi
  # a launching entry has no thread yet, and every other has one
  if $launching; then [ -z "$thread$worktree" ] || sa_tooling "$usage"; else [ -n "$thread" ] || sa_tooling "$usage"; fi
  # a task on a linked machine counts against that machine's slots, so it names it
  [ -z "$task" ] || [ -z "$environment" ] || [ -n "$machine" ] || sa_tooling "$usage"
  machine=${machine:-local}
  if [ -n "$task" ]; then
    # a task is no ticket: no number, and --kind would name an owner skill it does not run
    [ -z "$kind$number" ] || sa_tooling "$usage"
    kind=task key="task:$task"
  else
    # only a task runs a skill that waits on the owner
    ! $interactive || sa_tooling "$usage"
    kind=${kind:-ship}
    case $number in ''|*[!0-9]*) sa_tooling "$usage" ;; esac
    [ -n "$repo" ] && { [ -n "$worktree" ] || $launching; } && [ -n "$branch" ] || sa_tooling "$usage"
    key="$repo#$number"
  fi
  sa_lock "$ledger"; sa_read "$ledger"
  old=$(sa_key "$doc" "$key")
  jq -e --arg k "$old" '.entries[$k] and (.entries[$k].stage | IN("settled", "closed", "launching") | not)' <<<"$doc" >/dev/null && sa_fail "$key is already in the ledger"
  claim=null
  if [ -n "$read_file" ] && [ "$kind" = ship ]; then
    # a ship thread with no claim comment gets one, on the entry's machine
    own=$(jq -r '.own_thread // empty' <<<"$doc"); own=${own:-${T3CODE_THREAD_ID:-}}
    [ -n "$own" ] || sa_tooling "the super agent's own thread is unknown: run ledger self first, so the claim can name it"
    claim=$(bash "$(dirname "${BASH_SOURCE[0]}")/../claim.sh" --repo "$repo" --number "$number" --machine "$machine" --thread "$own" 2>/dev/null </dev/null); crc=$?
    if [ "$crc" -gt 1 ] || ! jq -e .status <<<"$claim" >/dev/null 2>&1; then sa_tooling "cannot claim $key: ${claim:-claim.sh answered nothing}"; fi
    claim=$(jq -c .status <<<"$claim")
  fi
  entry=$(jq -cn --arg k "$key" --arg repo "$repo" --argjson n "${number:-null}" --arg t "$thread" \
    --arg w "$worktree" --arg b "$branch" --arg m "$machine" --arg env "$environment" --arg inst "$instance" --arg model "$model" \
    --arg effort "$effort" --arg now "$now" --argjson areas "$areas" --arg kind "$kind" --argjson adopted "$adopted" --arg task "$task" --argjson ia "$interactive" \
    --argjson launching "$launching" \
    '{key: $k, repo: (if $repo == "" then null else $repo end), number: (if $task == "" then $n else null end),
      thread: (if $launching then null else $t end), worktree: (if $launching then null else $w end), branch: $b, machine: $m, areas: $areas, kind: $kind, adopted: $adopted,
      environment_id: (if $env == "" then null else $env end),
      instance_id: (if $inst == "" then null else $inst end),
      model: (if $model == "" then null else $model end),
      effort: (if $effort == "" then null else $effort end),
      stage: (if $launching then "launching" else "launched" end), stalls: 0, observed: null, launched_at: $now, updated_at: $now}
      + (if $ia then {interactive: true} else {} end)
      + (if $adopted then {held_since: $now} else {} end)')
  sa_update "$ledger" "$sa_jq_norm"'del(.entries[$old]) | .entries[$k] = $e | .waiting = ((.waiting // []) | map(select((.key | norm_repo) != ($k | norm_repo))))' \
    --arg k "$key" --arg old "$old" --argjson e "$entry"
  # a one-off task thread adopted new never got the contract line: its one adoption step-in carries it
  step=''
  ! $adopted || [ "$kind" != task ] || $interactive || step=$sa_task_contract
  jq -cn --arg l "$ledger" --arg k "$key" --argjson e "$entry" --argjson c "$claim" --arg st "$step" '{ledger: $l, key: $k, entry: $e}
    + (if $c == null then {} else {claim: $c} end) + (if $st == "" then {} else {step_in: $st} end)'
}
