# shellcheck shell=bash
# shellcheck disable=SC2154  # the globals below are setup.sh's: existing, rows, claude_cmd and the like
# Sourced by setup.sh: its helpers for the T3 provider instances (see setup.sh).
# run_quota <command> <jq test that the output holds a quota> <cli> <env json>: run a
# quota command once under the instance's env into $q_status and $q_reason (JSON).
run_quota() {
  local out rc
  q_status=available q_reason=null
  if ! command -v "$3" >/dev/null; then
    q_status=unavailable q_reason=$(jq -cn --arg p "$3" '"\($p) is not installed"')
  else
    sa_env_words "$3" "$4"
    out=$(env ${env_args[@]+"${env_args[@]}"} timeout 30 bash -c "$1" 2>/dev/null </dev/null); rc=$?
    if [ "$rc" -ne 0 ]; then
      q_status=unavailable q_reason=$(jq -cn --argjson r "$rc" '"quota command exited \($r)"')
    elif ! jq -e -n "[inputs | $2] | any" <<<"$out" >/dev/null 2>&1; then
      q_status=unavailable q_reason='"quota command printed no quota"'
    fi
  fi
}
# One enabled T3 instance as a provider keyed by its instance id (see the header).
probe_instance() { # <row json>
  local row=$1 key drv cmd test cli authcmd env e t3auth='' reason=null auth=unknown extra='{}' n
  key=$(jq -r .providerInstanceId <<<"$row")
  drv=$(jq -r 'if .driverKind == "claudeAgent" then "claude" else .driverKind end' <<<"$row")
  e=$(jq -c --arg k "$key" '.providers[$k] // {}' <<<"$existing")
  cmd='' test='' cli='' authcmd=''
  case $drv in
    claude) cmd=$claude_cmd test=$claude_test cli=claude authcmd='claude auth status' ;;
    codex) cmd=$codex_cmd test=$codex_test cli=codex ;;
    # no plan-usage read exists for these (`grok usage` exits 1: run /usage inside grok); grok prints a
    # signed-in or signed-out line and exits 0 either way, so auth greps it. Cursor gets no CLI check: `agent`
    # on PATH is the Grok binary where Grok is installed, so its auth is T3's row alone (below)
    cursor) ;;
    grok) authcmd="grok models 2>&1 | grep -q '^You are logged in'" ;;
    pi) cmd=$agy_cmd test=$agy_test cli=agy
      extra=$(jq -cn --argjson r "$row" '{route: false, models: ({sonnet: ([$r.models[]?.id | select(test("claude-sonnet"))] | first), opus: ([$r.models[]?.id | select(test("claude-opus"))] | first)} | with_entries(select(.value != null)))}') ;;
  esac
  cmd=$(jq -r --arg d "$cmd" '.quota_command // $d' <<<"$e") authcmd=$(jq -r --arg d "$authcmd" '.auth_command // $d' <<<"$e")
  env=$(jq -c --argjson r "$row" '.env // (if $r.homePath != null and ($r.driverKind == "claudeAgent") then {CLAUDE_CONFIG_DIR: $r.homePath} else {} end)' <<<"$e")
  if [ -z "$cmd" ] && { [ "$drv" = cursor ] || [ "$drv" = grok ]; }; then
    q_status=unknown q_reason=$(jq -cn --arg d "$drv" '"no non-interactive usage read for driver \($d)"')
  elif [ -z "$cmd" ]; then
    q_status=unavailable q_reason=$(jq -cn --arg d "$drv" '"no quota reader for driver \($d)"')
  else
    run_quota "$cmd" "$test" "$cli" "$env"
  fi
  # T3's own verdict wins: a command that cannot tell the account apart would call a signed-out instance ok
  t3auth=$(jq -r '[.constraints[]? | strings | select(test("not authenticated"; "i"))] | first // empty' <<<"$row")
  if [ -n "$t3auth" ]; then auth=failed reason=$(jq -cn --arg r "$t3auth" '$r')
  elif [ "$drv" = cursor ] && [ -z "$authcmd" ]; then
    [ "$(jq '.constraints | length' <<<"$row")" -eq 0 ] && auth=ok
  elif [ -n "$authcmd" ] && command -v "${authcmd%% *}" >/dev/null; then
    sa_env_words "$drv" "$env"
    if env ${env_args[@]+"${env_args[@]}"} timeout 15 bash -c "$authcmd" >/dev/null 2>&1 </dev/null; then auth=ok
    else auth=failed reason=$(jq -cn --argjson r "$?" '"auth command exited \($r)"'); fi
  fi
  facts=$(jq -c --arg k "$key" --arg s "$q_status" --argjson r "$q_reason" --arg a "$auth" --argjson ar "$reason" \
    '.providers[$k] = {status: $s, reason: $r, auth: $a, auth_reason: $ar}' <<<"$facts")
  proposed=$(jq -c --arg k "$key" --arg d "$drv" --arg c "$cmd" --arg a "$authcmd" --argjson env "$env" --argjson x "$extra" \
    '.providers[$k] = ({driver: $d, quota_command: (if $c == "" then null else $c end)}
      + (if $a == "" then {} else {auth_command: $a} end) + (if $env == {} then {} else {env: $env} end) + $x)' <<<"$proposed")
  n=$(jq -r --arg d "$drv" '[.[] | select((if .driverKind == "claudeAgent" then "claude" else .driverKind end) == $d)] | length' <<<"$rows")
  if [ "$drv" = claude ] && [ "$n" -gt 1 ] && [ "$env" = '{}' ]; then
    warn "$key: no env set, so its quota and auth read the default account: set env.CLAUDE_CONFIG_DIR in the fleet file if it has its own"
  fi
}
