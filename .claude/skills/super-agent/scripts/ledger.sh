#!/usr/bin/env bash
# Read and write the super agent's ledger: one entry per ticket it holds, plus
# the owner's dated rulings. The ledger is what a compacted or restarted super
# agent reads to know what it owns.
#
#   ledger --ledger <file> add --repo <owner/name> --number <n> --thread <id>
#          --worktree <path> --branch <name> [--kind ship|triage] [--machine <name>]
#          [--model <id>] [--effort <level>] [--area <path>]...
#   ledger --ledger <file> get <key>
#   ledger --ledger <file> list [--open]
#   ledger --ledger <file> set <key> <field> <json>
#   ledger --ledger <file> rethread <key> --thread <id> --worktree <path>
#          --branch <name> [--model <id>] [--effort <level>]
#   ledger --ledger <file> ruling <text> [--allow <call>]...
#   ledger --ledger <file> allowed
#   ledger --ledger <file> wait <key> --reason <text>
#   ledger --ledger <file> unwait <key>
#
# A key is `<owner/name>#<number>`. `--ledger` comes first and names the file,
# which a first `add` creates. `add` starts an entry at stage `launched`, stalls
# 0, observed null: `reconcile` fills `observed`, the baseline `watch` compares
# against, and `error`, the fault kind it last failed to read. `set` takes any
# field but the entry's identity (key, repo, number); `stage` must be one of
# launched, running, at-rest, merged, settled, closed. `rethread` points a
# ticket's entry at a fresh thread and starts its tracking over (stage
# launched, stalls 0, no observed state), so the key stays one entry. A write is
# a temp file beside the ledger, then a rename. A ruling is the owner's answer to a hold, dated; each
# `--allow` is a call the answer lets a supervised thread make without a hold,
# and `allowed` lists them as the lines the launch brief carries. `--machine`
# is the fleet file's key for the machine the thread runs on (`local` means the
# machine the ledger is on), and each `--area` a path the ticket's work touches,
# which placement reads to run two tickets of one repo side by side. A ticket
# that could not be placed is `wait`ed: a row in `waiting` (no thread, no
# stage, never watched) that the morning report lists, and that `add` or
# `unwait` removes. `--kind` is the owner skill the thread runs, `ship` (the
# default) or `triage`: a `triage` entry has no PR, and `reconcile` settles it
# when its run has completed and the issue no longer carries `needs-triage`.
#
# stdout: `add` {ledger, key, entry}; `get` the entry; `list` {ledger, entries,
#         rulings}, `entries` an array of entries (`--open` leaves out settled
#         and closed ones); `set` {key, field, value}; `rethread` {ledger, key, entry}; `ruling` {ruling:
#         {date, text, allow}}; `allowed` {allowed: [{date, call, line}]}; `wait`
#         {waiting: {key, repo, number, reason, since}}; `unwait` {key,
#         removed}; `list` also holds `waiting`; any failure {error}
# exit: 0 ok · 1 the key is already in, or not in, the ledger, a stage outside
#       the list, or an identity field · 2 usage, a value that is not JSON, an
#       unreadable or wrong-shaped ledger, or a write that failed
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh" || { printf '{"error":"cannot source _lib.sh"}\n'; exit 2; }

usage='usage: ledger --ledger <file> add --repo <owner/name> --number <n> --thread <id> --worktree <path> --branch <name> [--kind ship|triage] [--machine <name>] [--model <id>] [--effort <level>] [--area <path>]... | get <key> | list [--open] | set <key> <field> <json> | rethread <key> --thread <id> --worktree <path> --branch <name> [--model <id>] [--effort <level>] | ruling <text> [--allow <call>]... | allowed | wait <key> --reason <text> | unwait <key>'
sa_help "$usage" "$@"
[ "${1:-}" = --ledger ] || sa_tooling "$usage"
sa_flag_value "$usage" "${2:-}"; ledger=$2; shift 2
cmd=${1:-}; [ $# -gt 0 ] && shift

case $cmd in
  add)
    repo='' number='' thread='' worktree='' branch='' machine=local model='' effort='' areas='[]' kind=ship
    while [ $# -gt 0 ]; do
      case $1 in
        --area) sa_flag_value "$usage" "${2:-}"; areas=$(jq -c --arg a "$2" '. + [$a]' <<<"$areas") ;;
        --repo) sa_flag_value "$usage" "${2:-}"; repo=$2 ;;
        --number) sa_flag_value "$usage" "${2:-}"; number=$2 ;;
        --thread) sa_flag_value "$usage" "${2:-}"; thread=$2 ;;
        --worktree) sa_flag_value "$usage" "${2:-}"; worktree=$2 ;;
        --branch) sa_flag_value "$usage" "${2:-}"; branch=$2 ;;
        --machine) sa_flag_value "$usage" "${2:-}"; machine=$2 ;;
        --kind) sa_flag_value "$usage" "${2:-}"; case $2 in ship|triage) kind=$2 ;; *) sa_tooling "$usage" ;; esac ;;
        --model) sa_flag_value "$usage" "${2:-}"; model=$2 ;;
        --effort) sa_flag_value "$usage" "${2:-}"; effort=$2 ;;
        *) sa_tooling "$usage" ;;
      esac
      shift 2
    done
    case $number in ''|*[!0-9]*) sa_tooling "$usage" ;; esac
    [ -n "$repo" ] && [ -n "$thread" ] && [ -n "$worktree" ] && [ -n "$branch" ] || sa_tooling "$usage"
    key="$repo#$number"
    sa_read "$ledger"
    jq -e --arg k "$key" '.entries[$k]' <<<"$doc" >/dev/null && sa_fail "$key is already in the ledger"
    now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    entry=$(jq -cn --arg k "$key" --arg repo "$repo" --argjson n "$number" --arg t "$thread" \
      --arg w "$worktree" --arg b "$branch" --arg m "$machine" --arg model "$model" \
      --arg effort "$effort" --arg now "$now" --argjson areas "$areas" --arg kind "$kind" \
      '{key: $k, repo: $repo, number: $n, thread: $t, worktree: $w, branch: $b, machine: $m, areas: $areas, kind: $kind,
        model: (if $model == "" then null else $model end),
        effort: (if $effort == "" then null else $effort end),
        stage: "launched", stalls: 0, observed: null, launched_at: $now, updated_at: $now}')
    sa_write "$ledger" "$(jq -c --arg k "$key" --argjson e "$entry" '.entries[$k] = $e | .waiting = ((.waiting // []) | map(select(.key != $k)))' <<<"$doc")"
    jq -cn --arg l "$ledger" --arg k "$key" --argjson e "$entry" '{ledger: $l, key: $k, entry: $e}' ;;
  get)
    [ $# -eq 1 ] || sa_tooling "$usage"
    sa_read "$ledger"
    jq -e --arg k "$1" '.entries[$k]' <<<"$doc" >/dev/null || sa_fail "$1 is not in the ledger"
    jq -c --arg k "$1" '.entries[$k]' <<<"$doc" ;;
  list)
    open=false
    case ${1:-} in --open) open=true; shift ;; esac
    [ $# -eq 0 ] || sa_tooling "$usage"
    sa_read "$ledger"
    jq -c --arg l "$ledger" --argjson open "$open" "$sa_jq_open"'{ledger: $l, entries: [.entries[] | select(($open | not) or is_open)], rulings, waiting: (.waiting // [])}' <<<"$doc" ;;
  set)
    [ $# -eq 3 ] || sa_tooling "$usage"
    key=$1 field=$2
    value=$(jq -c . <<<"$3" 2>/dev/null) && [ -n "$value" ] || sa_tooling "the value is not JSON: $3"
    case $field in key|repo|number) sa_fail "$field is the entry's identity and cannot be set" ;; esac
    if [ "$field" = stage ]; then
      jq -ne --argjson v "$value" '$v | IN("launched", "running", "at-rest", "merged", "settled", "closed")' >/dev/null \
        || sa_fail "stage must be one of $sa_stages"
    fi
    sa_read "$ledger"
    jq -e --arg k "$key" '.entries[$k]' <<<"$doc" >/dev/null || sa_fail "$key is not in the ledger"
    now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    sa_write "$ledger" "$(jq -c --arg k "$key" --arg f "$field" --argjson v "$value" --arg now "$now" \
      '.entries[$k][$f] = $v | .entries[$k].updated_at = $now' <<<"$doc")"
    jq -cn --arg k "$key" --arg f "$field" --argjson v "$value" '{key: $k, field: $f, value: $v}' ;;
  rethread)
    [ $# -ge 1 ] || sa_tooling "$usage"
    key=$1; shift; thread='' worktree='' branch='' model='' effort=''
    while [ $# -gt 0 ]; do
      case $1 in
        --thread) sa_flag_value "$usage" "${2:-}"; thread=$2 ;;
        --worktree) sa_flag_value "$usage" "${2:-}"; worktree=$2 ;;
        --branch) sa_flag_value "$usage" "${2:-}"; branch=$2 ;;
        --model) sa_flag_value "$usage" "${2:-}"; model=$2 ;;
        --effort) sa_flag_value "$usage" "${2:-}"; effort=$2 ;;
        *) sa_tooling "$usage" ;;
      esac
      shift 2
    done
    [ -n "$thread" ] && [ -n "$worktree" ] && [ -n "$branch" ] || sa_tooling "$usage"
    sa_read "$ledger"
    jq -e --arg k "$key" '.entries[$k]' <<<"$doc" >/dev/null || sa_fail "$key is not in the ledger"
    now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    doc=$(jq -c --arg k "$key" --arg t "$thread" --arg w "$worktree" --arg b "$branch" --arg m "$model" \
      --arg e "$effort" --arg now "$now" '.entries[$k] |= (.thread = $t | .worktree = $w | .branch = $b
        | .model = (if $m == "" then null else $m end) | .effort = (if $e == "" then null else $e end)
        | .stage = "launched" | .stalls = 0 | .observed = null | .error = null | .rest_since = null
        | .judged_run = 0 | .launched_at = $now | .updated_at = $now)' <<<"$doc")
    sa_write "$ledger" "$doc"
    jq -cn --arg l "$ledger" --arg k "$key" --argjson e "$(jq -c --arg k "$key" '.entries[$k]' <<<"$doc")" \
      '{ledger: $l, key: $k, entry: $e}' ;;
  ruling)
    [ $# -ge 1 ] || sa_tooling "$usage"
    text=$1; shift; allow='[]'
    while [ $# -gt 0 ]; do
      [ "$1" = --allow ] || sa_tooling "$usage"
      sa_flag_value "$usage" "${2:-}"; allow=$(jq -c --arg c "$2" '. + [$c]' <<<"$allow"); shift 2
    done
    sa_read "$ledger"
    ruling=$(jq -cn --arg d "$(date -u +%F)" --arg t "$text" --argjson a "$allow" '{date: $d, text: $t, allow: $a}')
    sa_write "$ledger" "$(jq -c --argjson r "$ruling" '.rulings += [$r]' <<<"$doc")"
    jq -cn --argjson r "$ruling" '{ruling: $r}' ;;
  allowed)
    [ $# -eq 0 ] || sa_tooling "$usage"
    sa_read "$ledger"
    jq -c '{allowed: [.rulings[] | .date as $d | (.allow // [])[] | {date: $d, call: .,
      line: "Run `\(.)` without a hold: the owner allowed it on \($d)."}]}' <<<"$doc" ;;
  wait)
    [ $# -eq 3 ] && [ "$2" = --reason ] || sa_tooling "$usage"
    key=$1; sa_flag_value "$usage" "$3"; reason=$3
    case $key in */*#*[0-9]) ;; *) sa_tooling "$usage" ;; esac
    case ${key##*#} in *[!0-9]*) sa_tooling "$usage" ;; esac
    sa_read "$ledger"
    jq -e --arg k "$key" '.entries[$k]' <<<"$doc" >/dev/null && sa_fail "$key already has a thread in the ledger"
    # A repeat keeps the first `since`: how long it has waited is the report's point.
    row=$(jq -cn --arg k "$key" --arg r "${key%#*}" --argjson n "${key##*#}" --arg why "$reason" --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      --argjson old "$(jq -c --arg k "$key" '(.waiting // []) | map(select(.key == $k)) | first // null' <<<"$doc")" \
      '{key: $k, repo: $r, number: $n, reason: $why, since: ($old.since // $now)}')
    sa_write "$ledger" "$(jq -c --arg k "$key" --argjson w "$row" '.waiting = ((.waiting // []) | map(select(.key != $k)) + [$w])' <<<"$doc")"
    jq -cn --argjson w "$row" '{waiting: $w}' ;;
  unwait)
    [ $# -eq 1 ] || sa_tooling "$usage"
    sa_read "$ledger"
    had=$(jq -r --arg k "$1" '[(.waiting // [])[] | select(.key == $k)] | length > 0' <<<"$doc")
    [ "$had" != true ] || sa_write "$ledger" "$(jq -c --arg k "$1" '.waiting = ((.waiting // []) | map(select(.key != $k)))' <<<"$doc")"
    jq -cn --arg k "$1" --argjson r "$had" '{key: $k, removed: $r}' ;;
  *) sa_tooling "$usage" ;;
esac
