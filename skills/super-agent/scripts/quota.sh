#!/usr/bin/env bash
# Read every fleet-file provider's quota through the command setup probed and
# recorded for it, so routing never relies on documentation. No model turn is
# spent: Claude's `/usage` print, Codex's app-server `account/rateLimits/read`
# and agy's `/usage` JSON are all free reads.
#
#   quota --fleet <file> [--save <file> --wake <id>]
#
# --fleet is required, as every script's file is, so a bare call reads nothing
# off the machine's own config. A fleet-file provider is a T3 provider instance,
# its key the instance id, so two Claude instances are two entries and two
# readings. Each is read by its `driver` (its key when unset: an old file keyed
# `claude`, `codex`, `agy` still reads) through its `quota_command`, run once
# under a 30 s limit with the entry's `env` (an object, e.g. the account's
# `CLAUDE_CONFIG_DIR`, a leading `~` read as HOME) set, so the read is that
# instance's account and not the caller's: a Claude entry with no
# `CLAUDE_CONFIG_DIR` reads the default account. A `pi` instance's buckets are
# agy's, read through the agy parser. A
# read that fails, prints nothing readable or has no command is `unknown` with a
# reason, never an error: the router falls back to the default tier without
# asking. Auth is probed apart from quota: the entry's `auth_command`, run under
# the same `env`, exits 0 for a signed-in instance. A failure setup recorded
# (`auth: "failed"`) overrides a passing command only when its `auth_source` is
# `t3` (T3's own verdict, which a command that cannot tell the account apart
# would miss) and its `auth_checked` UTC time is under 24 h old. A command-sourced
# failure, a legacy bare one (no source or date) and an expired T3 one are not
# honored: the live command alone speaks, so a signed-back-in instance routes
# again without a hand edit. `SA_NOW` (an epoch) pins the clock for tests.
# Quota is read once per wake: with --save <file> and --wake <id> a read whose
# saved file holds that wake id is printed as saved, with no command run, and a
# new wake id reads again and replaces the file. The caller makes one id per
# wake, so every launch of that wake routes on the same read.
# The fleet file's `weekly_weight` (a number above 0) on a provider entry is
# carried to that provider's answer, and its top-level `five_hour_floor` and
# `weekly_reserve` (fractions 0 to 1) to `floors`, for `route` to rank and skip by.
#
# stdout: {read_at, wake, floors, providers: {<instance id>: {driver, status, reason, auth, auth_reason,
#         buckets}}}: `status` `available` or `unknown`, `reason` null or why;
#         `auth` `ok`, `failed` or `unknown`, `auth_reason` null or why;
#         `buckets` one {id, window, remaining, resets} per bucket, `window` `5h`
#         or `weekly`, `remaining` a fraction 0 to 1 (agy's buckets add `group`),
#         `resets` the provider's own reset time as text; a provider also
#         holds `weekly_weight` when the fleet entry sets one; `floors` is
#         {five_hour, weekly_reserve}, a key only where the file sets it;
#         `read_at` the UTC time of the read, `wake` the --wake id or null. Claude's ids are
#         `session`, `week` (all models) and `week-<model>`; Codex's are `session`
#         and `week`; agy's are its own bucket ids
# exit: 0 a read, unknown providers included · 2 usage, or a fleet file that is
#       missing, not JSON or has providers that are not an object
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh" || { printf '{"error":"cannot source _lib.sh"}\n'; exit 2; }

usage='usage: quota --fleet <file> [--save <file> --wake <id>]'
sa_help "$usage" "$@"
fleet_file='' save='' wake=''
while [ $# -gt 0 ]; do
  case $1 in
    --fleet) sa_flag_value "$usage" "${2:-}"; fleet_file=$2; shift 2 ;;
    --save) sa_flag_value "$usage" "${2:-}"; save=$2; shift 2 ;;
    --wake) sa_flag_value "$usage" "${2:-}"; wake=$2; shift 2 ;;
    *) sa_tooling "$usage" ;;
  esac
done
[ -n "$fleet_file" ] || sa_tooling "$usage"
{ [ -n "$save" ] && [ -n "$wake" ]; } || { [ -z "$save" ] && [ -z "$wake" ]; } || sa_tooling "$usage"
if [ -n "$save" ] && [ -f "$save" ] && jq -e --arg w "$wake" '.wake == $w' "$save" >/dev/null 2>&1; then
  jq -c . "$save"; exit 0
fi
[ -f "$fleet_file" ] || sa_tooling "$fleet_file: no such file, run setup"
jq -e . "$fleet_file" >/dev/null 2>&1 || sa_tooling "$fleet_file: not JSON"
jq -e '((.providers // {}) | type) == "object"' "$fleet_file" >/dev/null || sa_tooling "$fleet_file: providers must be an object"
jq -e '[.providers[]? | objects | .weekly_weight // 1 | type == "number" and . > 0] | all' "$fleet_file" >/dev/null || sa_tooling "$fleet_file: every weekly_weight must be a number above 0"
jq -e '[.five_hour_floor, .weekly_reserve | select(. != null) | type == "number" and . >= 0 and . <= 1] | all' "$fleet_file" >/dev/null || sa_tooling "$fleet_file: five_hour_floor and weekly_reserve must be fractions 0 to 1"

# Each parser reads the command's stdout and prints the bucket array, or nothing
# when the output holds no quota.
parse_claude() { # the `/usage` print is text inside the JSON's `.result`
  jq -c '[(.result // "" | split("\n")[]
      | capture("^Current (?<what>session|week \\((?<m>[^)]+)\\)): (?<used>[0-9]+)% used · resets (?<resets>.+)$")?
      | {id: (if .what == "session" then "session" elif .m == "all models" then "week" else "week-\(.m | ascii_downcase)" end),
         window: (if .what == "session" then "5h" else "weekly" end),
         remaining: ((100 - (.used | tonumber)) / 100), resets})]
    | select(length > 0)' 2>/dev/null
}
parse_codex() { # JSON lines; the answer to request 2 is the one that holds the limits
  jq -c -n '[inputs | select(.id == 2) | .result.rateLimits // empty | (.primary, .secondary) | select(. != null)
      | (.windowDurationMins | if . == 300 then "5h" elif . == 10080 then "weekly" else "\(.)m" end) as $w
      | {id: (if $w == "5h" then "session" elif $w == "weekly" then "week" else $w end), window: $w,
         remaining: ((100 - .usedPercent) / 100), resets: (.resetsAt | todate)}]
    | select(length > 0)' 2>/dev/null
}
parse_agy() {
  jq -c 'select(.status == "SUCCESS") | [.command.data.groups[]? | .name as $g | .buckets[]? | select(.remaining_fraction | type == "number")
      | {id, window, remaining: .remaining_fraction, resets: .reset_time, group: $g}]
    | select(length > 0)' 2>/dev/null
}

out='{}'
# One name per line, split without globbing: the owner wrote these keys.
IFS=$'\n' read -r -d '' -a names < <(jq -r '(.providers // {}) | keys[]' "$fleet_file") || true
for name in ${names[@]+"${names[@]}"}; do
  cfg=$(jq -c --arg n "$name" '.providers[$n] | if type == "object" then . else {} end' "$fleet_file")
  driver=$(jq -r --arg n "$name" '.driver // $n' <<<"$cfg")
  cmd=$(jq -r '.quota_command // empty' <<<"$cfg")
  status=unknown reason='' buckets='[]'
  sa_env_words "$driver" "$(jq -c '.env // {}' <<<"$cfg")"
  auth=unknown auth_reason='no auth command in the fleet file'
  auth_cmd=$(jq -r '.auth_command // empty' <<<"$cfg")
  if [ -n "$auth_cmd" ]; then
    if env ${env_args[@]+"${env_args[@]}"} timeout 15 bash -c "$auth_cmd" >/dev/null 2>&1 </dev/null; then auth=ok auth_reason=''
    else auth=failed auth_reason="auth command exited $?"; fi
  fi
  jq -e --argjson now "${SA_NOW:-null}" '.auth == "failed" and .auth_source == "t3" and ((.auth_checked // "" | try fromdateiso8601 catch 0) > ($now // now) - 86400)' <<<"$cfg" >/dev/null
  rec=$?
  if [ "$rec" -eq 0 ]; then
    auth=failed auth_reason=$(jq -r '.auth_reason // "recorded as failed by setup"' <<<"$cfg")
  elif [ "$rec" -ne 1 ]; then auth=unknown auth_reason='could not read the recorded auth verdict'
  fi
  if [ -z "$cmd" ]; then
    reason='no quota command in the fleet file'
  else
    raw=$(env ${env_args[@]+"${env_args[@]}"} timeout 30 bash -c "$cmd" 2>/dev/null </dev/null); rc=$?
    if [ "$rc" -ne 0 ]; then
      reason="quota command exited $rc"
    else
      case $driver in
        claude) parsed=$(parse_claude <<<"$raw") ;;
        codex) parsed=$(parse_codex <<<"$raw") ;;
        agy|pi) parsed=$(parse_agy <<<"$raw") ;;
        *) parsed='' reason="no parser for driver $driver" ;;
      esac
      if [ -n "$parsed" ]; then status=available buckets=$parsed
      else [ -n "$reason" ] || reason='quota command printed no quota'; fi
    fi
  fi
  out=$(jq -c --arg n "$name" --arg d "$driver" --arg s "$status" --arg r "$reason" --arg a "$auth" --arg ar "$auth_reason" --argjson b "$buckets" --argjson w "$(jq -c '.weekly_weight // null' <<<"$cfg")" \
    '.[$n] = {driver: $d, status: $s, reason: (if $r == "" then null else $r end),
      auth: $a, auth_reason: (if $ar == "" then null else $ar end), buckets: $b}
      + (if $w == null then {} else {weekly_weight: $w} end)' <<<"$out")
done
result=$(jq -cn --argjson p "$out" --argjson now "$(sa_epoch)" --arg w "$wake" \
  --slurpfile f "$fleet_file" '{read_at: (($now // now) | strftime("%Y-%m-%dT%H:%M:%SZ")), wake: (if $w == "" then null else $w end),
    floors: ({five_hour: $f[0].five_hour_floor, weekly_reserve: $f[0].weekly_reserve} | with_entries(select(.value != null))),
    providers: $p}')
[ -z "$save" ] || sa_write "$save" "$result"
printf '%s\n' "$result"
