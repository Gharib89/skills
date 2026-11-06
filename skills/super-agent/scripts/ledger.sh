#!/usr/bin/env bash
# Read and write the super agent's ledger: one entry per ticket it holds, plus
# the owner's dated rulings. The ledger is what a compacted or restarted super
# agent reads to know what it owns.
#
#   ledger --ledger <file> add --repo <owner/name> --number <n> --thread <id>
#          --worktree <path> --branch <name> [--machine <name>] [--model <id>]
#          [--effort <level>]
#   ledger --ledger <file> get <key>
#   ledger --ledger <file> list [--open]
#   ledger --ledger <file> set <key> <field> <json>
#   ledger --ledger <file> ruling <text>
#
# A key is `<owner/name>#<number>`. `--ledger` comes first and names the file,
# which a first `add` creates. `add` starts an entry at stage `launched`, stalls
# 0, observed null: `reconcile` fills `observed`, the baseline `watch` compares
# against. `set` takes any field
# but the entry's identity (key, repo, number); `stage` must be one of
# launched, running, at-rest, settled, closed. A write is a temp file beside the
# ledger, then a rename.
#
# stdout: `add` {ledger, key, entry}; `get` the entry; `list` {ledger, entries,
#         rulings}, `entries` an array of entries (`--open` leaves out settled
#         and closed ones); `set` {key, field, value}; `ruling` {ruling:
#         {date, text}}; any failure {error}
# exit: 0 ok · 1 the key is already in, or not in, the ledger, a stage outside
#       the list, or an identity field · 2 usage, a value that is not JSON, an
#       unreadable or wrong-shaped ledger, or a write that failed
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh" || { printf '{"error":"cannot source _lib.sh"}\n'; exit 2; }

usage='usage: ledger --ledger <file> add --repo <owner/name> --number <n> --thread <id> --worktree <path> --branch <name> [--machine <name>] [--model <id>] [--effort <level>] | get <key> | list [--open] | set <key> <field> <json> | ruling <text>'
sa_help "$usage" "$@"
[ "${1:-}" = --ledger ] || sa_tooling "$usage"
sa_flag_value "$usage" "${2:-}"; ledger=$2; shift 2
cmd=${1:-}; [ $# -gt 0 ] && shift

case $cmd in
  add)
    repo='' number='' thread='' worktree='' branch='' machine=local model='' effort=''
    while [ $# -gt 0 ]; do
      case $1 in
        --repo) sa_flag_value "$usage" "${2:-}"; repo=$2 ;;
        --number) sa_flag_value "$usage" "${2:-}"; number=$2 ;;
        --thread) sa_flag_value "$usage" "${2:-}"; thread=$2 ;;
        --worktree) sa_flag_value "$usage" "${2:-}"; worktree=$2 ;;
        --branch) sa_flag_value "$usage" "${2:-}"; branch=$2 ;;
        --machine) sa_flag_value "$usage" "${2:-}"; machine=$2 ;;
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
      --arg effort "$effort" --arg now "$now" \
      '{key: $k, repo: $repo, number: $n, thread: $t, worktree: $w, branch: $b, machine: $m,
        model: (if $model == "" then null else $model end),
        effort: (if $effort == "" then null else $effort end),
        stage: "launched", stalls: 0, observed: null, launched_at: $now, updated_at: $now}')
    sa_write "$ledger" "$(jq -c --arg k "$key" --argjson e "$entry" '.entries[$k] = $e' <<<"$doc")"
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
    jq -c --arg l "$ledger" --argjson open "$open" "$sa_jq_open"'{ledger: $l, entries: [.entries[] | select(($open | not) or is_open)], rulings}' <<<"$doc" ;;
  set)
    [ $# -eq 3 ] || sa_tooling "$usage"
    key=$1 field=$2
    value=$(jq -ce . <<<"$3" 2>/dev/null) || sa_tooling "the value is not JSON: $3"
    case $field in key|repo|number) sa_fail "$field is the entry's identity and cannot be set" ;; esac
    if [ "$field" = stage ]; then
      jq -ne --argjson v "$value" '$v | IN("launched", "running", "at-rest", "settled", "closed")' >/dev/null \
        || sa_fail "stage must be one of $sa_stages"
    fi
    sa_read "$ledger"
    jq -e --arg k "$key" '.entries[$k]' <<<"$doc" >/dev/null || sa_fail "$key is not in the ledger"
    now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    sa_write "$ledger" "$(jq -c --arg k "$key" --arg f "$field" --argjson v "$value" --arg now "$now" \
      '.entries[$k][$f] = $v | .entries[$k].updated_at = $now' <<<"$doc")"
    jq -cn --arg k "$key" --arg f "$field" --argjson v "$value" '{key: $k, field: $f, value: $v}' ;;
  ruling)
    [ $# -eq 1 ] || sa_tooling "$usage"
    sa_read "$ledger"
    ruling=$(jq -cn --arg d "$(date -u +%F)" --arg t "$1" '{date: $d, text: $t}')
    sa_write "$ledger" "$(jq -c --argjson r "$ruling" '.rulings += [$r]' <<<"$doc")"
    jq -cn --argjson r "$ruling" '{ruling: $r}' ;;
  *) sa_tooling "$usage" ;;
esac
