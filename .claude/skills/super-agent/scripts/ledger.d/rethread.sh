# The `rethread` arm of `ledger`: points a ticket's entry at a fresh thread and
# starts its tracking over, sourced by it. It reads the caller's $usage and
# $ledger, which `ledger.sh` sets.

# shellcheck disable=SC2154  # usage and ledger come from ledger.sh

ledger_rethread() {
  local key thread worktree branch environment instance model effort kind areas now
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
  sa_lock "$ledger"; sa_read "$ledger"
  key=$(sa_key "$doc" "$key")
  jq -e --arg k "$key" '.entries[$k]' <<<"$doc" >/dev/null || sa_fail "$key is not in the ledger"
  case $key in task:*) ;; *) [ -n "$worktree" ] && [ -n "$branch" ] || sa_tooling "$usage" ;; esac
  now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  sa_update "$ledger" '.entries[$k] |= (.thread = $t | .worktree = $w | .branch = $b
      | .environment_id = (if $env == "" then null else $env end)
      | .instance_id = (if $inst == "" then null else $inst end)
      | .model = (if $m == "" then null else $m end) | .effort = (if $e == "" then null else $e end)
      | .stage = "launched" | .stalls = 0 | .observed = null | .error = null | .rest_since = null
      | .judged_run = 0 | del(.cleanup_owed, .verify_owed) | .kind = (if $kind == "" then .kind else $kind end) | .areas = ($areas // .areas)
      | .launched_at = $now | .updated_at = $now)' \
    --arg k "$key" --arg t "$thread" --arg w "$worktree" --arg b "$branch" --arg m "$model" \
    --arg e "$effort" --arg env "$environment" --arg inst "$instance" --arg now "$now" --arg kind "$kind" --argjson areas "${areas:-null}"
  jq -cn --arg l "$ledger" --arg k "$key" --argjson e "$(jq -c --arg k "$key" '.entries[$k]' <<<"$doc")" \
    '{ledger: $l, key: $k, entry: $e}'
}
