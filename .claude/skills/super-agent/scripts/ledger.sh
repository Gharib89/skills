#!/usr/bin/env bash
# Read and write the super agent's ledger: one entry per ticket it holds, plus
# the owner's dated rulings. The ledger is what a compacted or restarted super
# agent reads to know what it owns.
#
#   ledger --ledger <file> add --repo <owner/name> --number <n> --thread <id>
#          --worktree <path> --branch <name> [--kind ship|triage] [--machine <name>]
#          [--environment <id>] [--instance <id>] [--model <id>] [--effort <level>] [--area <path>]...
#   ledger --ledger <file> add --task <slug> --thread <id> [--worktree <path>] [--branch <name>]
#          [--repo <owner/name>] [--machine <name>] [--environment <id>] [--instance <id>]
#          [--model <id>] [--effort <level>] [--area <path>]...
#   ledger --ledger <file> adopt <the same flags as add>
#   ledger --ledger <file> get <key>
#   ledger --ledger <file> list [--open]
#   ledger --ledger <file> set <key> <field> <json>
#   ledger --ledger <file> rethread <key> --thread <id> --worktree <path>
#          --branch <name> [--kind ship|triage|task] [--environment <id>] [--instance <id>]
#          [--model <id>] [--effort <level>] [--area <path>]...
#   ledger --ledger <file> ruling <text> [--allow <call>]... [--brief [--repo <owner/name>] [--machine <key>]]
#   ledger --ledger <file> allowed
#   ledger --ledger <file> briefed
#   ledger --ledger <file> wait <key> --reason <text> [--order <n>] [--after <key>]
#   ledger --ledger <file> unwait <key>
#   ledger --ledger <file> need <key> --action <text> [--reason <word>]
#   ledger --ledger <file> pushed <key>
#   ledger --ledger <file> unneed <key>
#   ledger --ledger <file> limit <owner/name> --reviewer <name>
#   ledger --ledger <file> unlimit <owner/name>
#
# A key is `<owner/name>#<number>`, or `task:<slug>` for a `task` entry. `--ledger` comes first and names the file,
# which a first `add` creates. `add` starts an entry at stage `launched`, stalls
# 0, observed null: `reconcile` fills `observed`, the baseline `watch` compares
# against, and `error`, the fault kind it last failed to read. `add` over an
# entry whose stage is `settled` or `closed` (a triaged ticket that now ships)
# replaces it; over any other entry it refuses. `set` takes any
# field but the entry's identity (key, repo, number) and `stage`, which only
# `reconcile` moves (`add` and `rethread` start one at launched). `rethread` points a
# ticket's entry at a fresh thread and starts its tracking over (stage
# launched, stalls 0, no observed state), so the key stays one entry; `--environment` names the new thread's linked
# machine, and without it the entry is this machine's again. `--kind` and
# `--area` replace the stored value when given and leave it when omitted; use
# `add` over a finished triage entry, `rethread` for a thread that failed. A write is
# a temp file beside the ledger, then a rename. A ruling is the owner's answer to a hold, dated; each
# `--allow` is a call the answer lets a supervised thread make without a hold,
# and `allowed` lists them as the lines the launch brief carries. `--brief` marks
# the ruling brief-bound: `briefed` lists those, and `brief` carries each one word
# for word, so a ruling the owner dated today (a reviewer that will not work, say)
# reaches every supervised thread without a hand-appended line. With `--brief`,
# `--repo` and `--machine` limit it to launches for that repo or machine. `--machine`
# is the fleet file's key for the machine the thread runs on (`local` means the
# machine the ledger is on), `--environment` the T3 environment id `place`
# returned for a linked machine (absent: this machine), which `reconcile` and
# `watch` read the entry's thread through, and each `--area` a path the ticket's work touches,
# which placement reads to run two tickets of one repo side by side. A ticket
# that could not be placed is `wait`ed: a row in `waiting` (no thread, no
# stage, never watched) that the morning report lists, and that `add` or
# `unwait` removes. The waiting list is also the owner's queue: a row takes an
# `--order` (a whole number of up to 9 digits, lowest first, 0 allowed; rows with none follow the
# ordered ones, oldest first) and an `--after <key>` blocker, another ticket that
# must merge first, which `reconcile` reads into its `ready` rows. A repeat
# `wait` keeps the order and blocker it is not given anew. `--kind` is the owner skill the thread runs, `ship` (the
# default) or `triage`: a `triage` entry has no PR, and `reconcile` settles it
# when its run has completed and the issue carries neither `needs-triage` nor `needs-info`.
# A `task` entry (`--task <slug>`, kind `task`) is any other thread the super agent
# launched (a grill, a deploy, a review): its key needs no issue number, `repo` and
# `number` are null unless `--repo` is given (so a remote task's PR is found by its
# `--branch`), and `reconcile` closes it on its thread's rest, never on an issue's or
# a PR's state. `adopt` takes `add`'s flags and records a thread someone else launched
# (`adopted` true, kind `task` unless `--repo` and `--number` name a ticket); the
# watcher and `reconcile` treat it like a launched one.
# A `need` is something only the owner can settle: one row in `needs` per key
# (the entry, or a waiting ticket), its one action, `since` when and whether its
# push went out. A repeat with the same action keeps `since` and `pushed`, a new
# action is a new need. `--reason` names the cause it answers: only that
# `escalate` row stays silent for it. `pushed` marks the push sent, `unneed` clears the need;
# `status` reads the rows. `--instance` is the T3 provider instance the thread
# launched on (route's `instance_id`), which `status` names on the Running row. A
# `limit` records that a repo's hosted reviewer answered a review request with a
# usage-limit notice: one row in `review_limits` per repo, its reviewer and
# `since`, the time of the first notice (`SA_NOW`, an epoch, pins the clock for
# tests). A repeat keeps the first row, so the time is the first notice's, and
# `status` says that repo's batch is merging on the fallback reviewer only while
# the row is open. `unlimit` clears it once a later run records that reviewer as
# landed, or the owner says so.
#
# stdout: `add` {ledger, key, entry}; `get` the entry; `list` {ledger, entries,
#         rulings}, `entries` an array of entries (`--open` leaves out settled
#         and closed ones); `set` {key, field, value}; `rethread` {ledger, key, entry}; `ruling` {ruling:
#         {date, text, allow, brief, repo, machine}}; `allowed` {allowed: [{date, call, line}]};
#         `briefed` {briefed: [{date, text, repo, machine}]}; `wait`
#         {waiting: {key, repo, number, reason, since, order, after}}; `unwait` {key,
#         removed}; `need` {need: {key, action, since, pushed}}; `pushed`
#         {need}; `unneed` {key, removed}; `limit` {limit: {repo, reviewer,
#         since}}; `unlimit` {repo, removed}; `list` also holds `waiting`,
#         `needs` and `review_limits`; any failure {error}
# exit: 0 ok · 1 the key is already in, or not in, the ledger, `stage`, or an
#       identity field · 2 usage, a value that is not JSON, an
#       unreadable or wrong-shaped ledger, or a write that failed
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh" || { printf '{"error":"cannot source _lib.sh"}\n'; exit 2; }

usage='usage: ledger --ledger <file> add|adopt (--repo <owner/name> --number <n> --worktree <path> --branch <name> [--kind ship|triage] | --task <slug> [--worktree <path>] [--branch <name>] [--repo <owner/name>]) --thread <id> [--machine <name>] [--environment <id>] [--instance <id>] [--model <id>] [--effort <level>] [--area <path>]... | get <key> | list [--open] | set <key> <field> <json> | rethread <key> --thread <id> [--worktree <path>] [--branch <name>] [--kind ship|triage|task] [--environment <id>] [--instance <id>] [--model <id>] [--effort <level>] [--area <path>]... | ruling <text> [--allow <call>]... [--brief [--repo <owner/name>] [--machine <key>]] | allowed | briefed | wait <key> --reason <text> [--order <n>] [--after <key>] | unwait <key> | need <key> --action <text> [--reason <word>] | pushed <key> | unneed <key> | limit <owner/name> --reviewer <name> | unlimit <owner/name>'
sa_help "$usage" "$@"
[ "${1:-}" = --ledger ] || sa_tooling "$usage"
sa_flag_value "$usage" "${2:-}"; ledger=$2; shift 2
cmd=${1:-}; [ $# -gt 0 ] && shift

case $cmd in
  add|adopt)
    repo='' number='' thread='' worktree='' branch='' machine='' environment='' instance='' model='' effort='' areas='[]' kind='' task='' adopted=false
    [ "$cmd" != adopt ] || adopted=true
    while [ $# -gt 0 ]; do
      case $1 in
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
    [ -n "$thread" ] || sa_tooling "$usage"
    # a task on a linked machine counts against that machine's slots, so it names it
    [ -z "$task" ] || [ -z "$environment" ] || [ -n "$machine" ] || sa_tooling "$usage"
    machine=${machine:-local}
    if [ -n "$task" ]; then
      # a task is no ticket: no number, and --kind would name an owner skill it does not run
      [ -z "$kind$number" ] || sa_tooling "$usage"
      kind=task key="task:$task"
    else
      kind=${kind:-ship}
      case $number in ''|*[!0-9]*) sa_tooling "$usage" ;; esac
      [ -n "$repo" ] && [ -n "$worktree" ] && [ -n "$branch" ] || sa_tooling "$usage"
      key="$repo#$number"
    fi
    sa_read "$ledger"
    old=$(sa_key "$doc" "$key")
    jq -e --arg k "$old" '.entries[$k] and (.entries[$k].stage | IN("settled", "closed") | not)' <<<"$doc" >/dev/null && sa_fail "$key is already in the ledger"
    now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    entry=$(jq -cn --arg k "$key" --arg repo "$repo" --argjson n "${number:-null}" --arg t "$thread" \
      --arg w "$worktree" --arg b "$branch" --arg m "$machine" --arg env "$environment" --arg inst "$instance" --arg model "$model" \
      --arg effort "$effort" --arg now "$now" --argjson areas "$areas" --arg kind "$kind" --argjson adopted "$adopted" --arg task "$task" \
      '{key: $k, repo: (if $repo == "" then null else $repo end), number: (if $task == "" then $n else null end),
        thread: $t, worktree: $w, branch: $b, machine: $m, areas: $areas, kind: $kind, adopted: $adopted,
        environment_id: (if $env == "" then null else $env end),
        instance_id: (if $inst == "" then null else $inst end),
        model: (if $model == "" then null else $model end),
        effort: (if $effort == "" then null else $effort end),
        stage: "launched", stalls: 0, observed: null, launched_at: $now, updated_at: $now}')
    sa_write "$ledger" "$(jq -c --arg k "$key" --arg old "$old" --argjson e "$entry" "$sa_jq_norm"'del(.entries[$old]) | .entries[$k] = $e | .waiting = ((.waiting // []) | map(select((.key | norm_repo) != ($k | norm_repo))))' <<<"$doc")"
    jq -cn --arg l "$ledger" --arg k "$key" --argjson e "$entry" '{ledger: $l, key: $k, entry: $e}' ;;
  get)
    [ $# -eq 1 ] || sa_tooling "$usage"
    sa_read "$ledger"
    key=$(sa_key "$doc" "$1")
    jq -e --arg k "$key" '.entries[$k]' <<<"$doc" >/dev/null || sa_fail "$1 is not in the ledger"
    jq -c --arg k "$key" '.entries[$k]' <<<"$doc" ;;
  list)
    open=false
    case ${1:-} in --open) open=true; shift ;; esac
    [ $# -eq 0 ] || sa_tooling "$usage"
    sa_read "$ledger"
    jq -c --arg l "$ledger" --argjson open "$open" "$sa_jq_open$sa_jq_waiting"'{ledger: $l, entries: [.entries[] | select(($open | not) or is_open)], rulings, waiting: waiting_list, needs: (.needs // []), review_limits: (.review_limits // [])}' <<<"$doc" ;;
  set)
    [ $# -eq 3 ] || sa_tooling "$usage"
    key=$1 field=$2
    value=$(jq -c . <<<"$3" 2>/dev/null) && [ -n "$value" ] || sa_tooling "the value is not JSON: $3"
    case $field in
      key|repo|number) sa_fail "$field is the entry's identity and cannot be set" ;;
      stage) sa_fail "stage is moved by reconcile only (add and rethread start it at launched)" ;;
    esac
    sa_read "$ledger"
    key=$(sa_key "$doc" "$key")
    jq -e --arg k "$key" '.entries[$k]' <<<"$doc" >/dev/null || sa_fail "$key is not in the ledger"
    now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    sa_write "$ledger" "$(jq -c --arg k "$key" --arg f "$field" --argjson v "$value" --arg now "$now" \
      '.entries[$k][$f] = $v | .entries[$k].updated_at = $now' <<<"$doc")"
    jq -cn --arg k "$key" --arg f "$field" --argjson v "$value" '{key: $k, field: $f, value: $v}' ;;
  rethread)
    [ $# -ge 1 ] || sa_tooling "$usage"
    key=$1; shift; thread='' worktree='' branch='' environment='' instance='' model='' effort='' kind='' areas=''
    while [ $# -gt 0 ]; do
      case $1 in
        --area) sa_flag_value "$usage" "${2:-}"; areas=$(jq -c --arg a "$2" '(. // []) + [$a]' <<<"${areas:-null}") ;;
        --kind) sa_flag_value "$usage" "${2:-}"; case $2 in ship|triage|task) kind=$2 ;; *) sa_tooling "$usage" ;; esac ;;
        --thread) sa_flag_value "$usage" "${2:-}"; thread=$2 ;;
        --worktree) sa_flag_value "$usage" "${2:-}"; worktree=$2 ;;
        --branch) sa_flag_value "$usage" "${2:-}"; branch=$2 ;;
        --environment) sa_flag_value "$usage" "${2:-}"; environment=$2 ;;
        --instance) sa_flag_value "$usage" "${2:-}"; instance=$2 ;;
        --model) sa_flag_value "$usage" "${2:-}"; model=$2 ;;
        --effort) sa_flag_value "$usage" "${2:-}"; effort=$2 ;;
        *) sa_tooling "$usage" ;;
      esac
      shift 2
    done
    [ -n "$thread" ] || sa_tooling "$usage"
    sa_read "$ledger"
    key=$(sa_key "$doc" "$key")
    jq -e --arg k "$key" '.entries[$k]' <<<"$doc" >/dev/null || sa_fail "$key is not in the ledger"
    case $key in task:*) ;; *) [ -n "$worktree" ] && [ -n "$branch" ] || sa_tooling "$usage" ;; esac
    now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    doc=$(jq -c --arg k "$key" --arg t "$thread" --arg w "$worktree" --arg b "$branch" --arg m "$model" \
      --arg e "$effort" --arg env "$environment" --arg inst "$instance" --arg now "$now" --arg kind "$kind" --argjson areas "${areas:-null}" \
      '.entries[$k] |= (.thread = $t | .worktree = $w | .branch = $b
        | .environment_id = (if $env == "" then null else $env end)
        | .instance_id = (if $inst == "" then null else $inst end)
        | .model = (if $m == "" then null else $m end) | .effort = (if $e == "" then null else $e end)
        | .stage = "launched" | .stalls = 0 | .observed = null | .error = null | .rest_since = null
        | .judged_run = 0 | del(.cleanup_owed, .verify_owed) | .kind = (if $kind == "" then .kind else $kind end) | .areas = ($areas // .areas)
        | .launched_at = $now | .updated_at = $now)' <<<"$doc")
    sa_write "$ledger" "$doc"
    jq -cn --arg l "$ledger" --arg k "$key" --argjson e "$(jq -c --arg k "$key" '.entries[$k]' <<<"$doc")" \
      '{ledger: $l, key: $k, entry: $e}' ;;
  ruling)
    [ $# -ge 1 ] || sa_tooling "$usage"
    text=$1; shift; allow='[]' brief=false rrepo='' rmachine=''
    while [ $# -gt 0 ]; do
      case $1 in
        --brief) brief=true; shift ;;
        --repo) sa_flag_value "$usage" "${2:-}"; rrepo=$2; shift 2 ;;
        --machine) sa_flag_value "$usage" "${2:-}"; rmachine=$2; shift 2 ;;
        --allow) sa_flag_value "$usage" "${2:-}"; allow=$(jq -c --arg c "$2" '. + [$c]' <<<"$allow"); shift 2 ;;
        *) sa_tooling "$usage" ;;
      esac
    done
    { [ -z "$rrepo$rmachine" ] || [ "$brief" = true ]; } || sa_tooling "--repo and --machine scope a --brief ruling only"
    sa_read "$ledger"
    ruling=$(jq -cn --arg d "$(date -u +%F)" --arg t "$text" --argjson a "$allow" --argjson b "$brief" --arg r "$rrepo" --arg m "$rmachine" \
      '{date: $d, text: $t, allow: $a, brief: $b, repo: (if $r == "" then null else $r end), machine: (if $m == "" then null else $m end)}')
    sa_write "$ledger" "$(jq -c --argjson r "$ruling" '.rulings += [$r]' <<<"$doc")"
    jq -cn --argjson r "$ruling" '{ruling: $r}' ;;
  allowed)
    [ $# -eq 0 ] || sa_tooling "$usage"
    sa_read "$ledger"
    jq -c '{allowed: [.rulings[] | .date as $d | (.allow // [])[] | {date: $d, call: .,
      line: "Run `\(.)` without a hold: the owner allowed it on \($d)."}]}' <<<"$doc" ;;
  briefed)
    [ $# -eq 0 ] || sa_tooling "$usage"
    sa_read "$ledger"
    jq -c '{briefed: [.rulings[] | select(.brief == true) | {date, text, repo: (.repo // null), machine: (.machine // null)}]}' <<<"$doc" ;;
  wait)
    [ $# -ge 3 ] || sa_tooling "$usage"
    key=$1; shift; reason='' order='' after=''
    while [ $# -gt 0 ]; do
      case $1 in
        --reason) sa_flag_value "$usage" "${2:-}"; reason=$2 ;;
        --order) sa_flag_value "$usage" "${2:-}"; case $2 in ''|*[!0-9]*|??????????*) sa_tooling "$usage" ;; esac; order=$2 ;;
        --after) sa_flag_value "$usage" "${2:-}"; after=$2 ;;
        *) sa_tooling "$usage" ;;
      esac
      shift 2
    done
    [ -n "$reason" ] || sa_tooling "$usage"
    for k in "$key" ${after:+"$after"}; do
      case $k in */*#*[0-9]) ;; *) sa_tooling "$usage" ;; esac
      case ${k##*#} in *[!0-9]*) sa_tooling "$usage" ;; esac
    done
    jq -en --arg a "$after" --arg k "$key" "$sa_jq_norm"'($a|norm_repo)!=($k|norm_repo)' >/dev/null || sa_tooling "$usage"
    sa_read "$ledger"
    jq -e --arg k "$(sa_key "$doc" "$key")" '.entries[$k] | . != null and (.stage != "settled" and .stage != "closed")' <<<"$doc" >/dev/null && sa_fail "$key already has a thread in the ledger"
    # A repeat keeps the first `since` (how long it has waited is the report's
    # point) and the order and blocker it is not given anew (placement rewrites
    # a row's reason and knows neither).
    row=$(jq -cn --arg k "$key" --arg r "${key%#*}" --argjson n "${key##*#}" --arg why "$reason" --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      --arg order "$order" --arg after "$after" \
      --argjson old "$(jq -c --arg k "$key" "$sa_jq_norm"'(.waiting // []) | map(select((.key | norm_repo) == ($k | norm_repo))) | first // null' <<<"$doc")" \
      '{key: $k, repo: $r, number: $n, reason: $why, since: ($old.since // $now),
        order: (if $order != "" then ($order | tonumber) else $old.order end),
        after: (if $after != "" then $after else $old.after end)}')
    sa_write "$ledger" "$(jq -c --arg k "$key" --argjson w "$row" "$sa_jq_norm"'.waiting = ((.waiting // []) | map(select((.key | norm_repo) != ($k | norm_repo))) + [$w])' <<<"$doc")"
    jq -cn --argjson w "$row" '{waiting: $w}' ;;
  unwait)
    [ $# -eq 1 ] || sa_tooling "$usage"
    sa_read "$ledger"
    had=$(jq -r --arg k "$1" "$sa_jq_norm"'[(.waiting // [])[] | select((.key | norm_repo) == ($k | norm_repo))] | length > 0' <<<"$doc")
    [ "$had" != true ] || sa_write "$ledger" "$(jq -c --arg k "$1" "$sa_jq_norm"'.waiting = ((.waiting // []) | map(select((.key | norm_repo) != ($k | norm_repo))))' <<<"$doc")"
    jq -cn --arg k "$1" --argjson r "$had" '{key: $k, removed: $r}' ;;
  need|pushed|unneed|limit|unlimit)
    source "$(dirname "${BASH_SOURCE[0]}")/ledger.d/owner.sh" && ledger_owner "$cmd" "$@" ;;
  *) sa_tooling "$usage" ;;
esac
