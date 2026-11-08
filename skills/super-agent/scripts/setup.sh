#!/usr/bin/env bash
# Probe this machine, the linked T3 environments, GitHub and each provider's
# quota command, and propose the fleet file: the owner's machines, providers,
# accounts, active repos and standing waivers, which the launch reads instead of
# the skill text. --propose prints the proposal and writes nothing, so the owner
# reads it and confirms first; --write then writes it.
#
#   setup (--propose | --write) [--fleet <file>] [--name <machine>]
#         [--probe <environment id>=<reply file>]... [--instances <file>]
#         [--settings <file>]
#
# --fleet defaults to `super-agent/fleet.json` under $XDG_CONFIG_HOME
# (`~/.config` when unset), the user-scope path the owner keeps in their
# dotfiles. --name is this machine's key, `hostname` by default. A re-run
# merges: what a probe measured (cores, RAM, GPU, reachability, each provider's
# status, the GitHub accounts) is refreshed, and everything else (slots,
# thresholds, quota commands, active repos, waivers, any key the owner added)
# keeps the file's value, so an owner's edit survives (a quota command a
# previous setup recorded is kept too: fix one by hand in the file, or delete it
# there and re-run). A machine the file holds
# and T3 no longer lists is kept. A machine's slots are the lesser of half
# its cores and its RAM over the per-thread floor, at least 1, and this
# machine keeps 1 slot (`reserve`) for the owner's messages. This machine is
# measured by `probe.sh`. A linked machine is measured by the same probe run in
# a scratch thread there: setup cannot launch one, so the first call lists the
# reachable linked machines in `to_probe`, the caller runs the probe on each
# and saves each thread's reply to a file, and a second call passes each as
# `--probe <environment id>=<file>`. The reply's one JSON line is merged under
# that machine (cores, RAM, GPU, `clis`, `gh_logins`), and its slots, load
# threshold and `proposed_slots` are computed from it. A machine probed before
# keeps the file's slots and load threshold (the owner's edits) and only
# `proposed_slots` moves; one never probed takes the computed ones, since
# nobody could have chosen them. A machine that is unreachable keeps its
# previous facts and is probed on the next run that finds it reachable. The
# file holds environment ids only, never a host, user or key.
#
# --settings names T3's own settings file: a row has no `homePath` (measured), but
# `providerInstances.<id>.config.homePath` there is the Claude instance's account
# directory, used for a row that carries none.
#
# --instances names the saved answer of the `orchestrator_capabilities` tool (the
# whole answer, or its `providers` array): one row per T3 provider instance, each
# with `providerInstanceId`, `driverKind` and `constraints`, and optionally a
# `homePath`. Measured 2026-11-08: a row has no `enabled` flag (a disabled one
# says "Provider instance is disabled." in `constraints`), and an instance whose
# login is gone says "Provider is not authenticated." there. Each enabled row
# becomes a provider keyed by its instance id: `driver` (`claudeAgent` is
# `claude`; other kinds keep their name), `quota_command`, `env` (a Claude
# instance's `CLAUDE_CONFIG_DIR` from its `homePath`, else the owner's to set),
# `auth_command` (`claude auth status` for Claude), `status` and `reason` from
# running the quota command under that `env`, and `auth` (`ok`, `failed`,
# `unknown`) with `auth_reason`: T3's own verdict where its constraints give one,
# else the auth command's exit. A `pi` instance also gets `route` false (the
# owner's allowance to place a tier on it) and `models`, its `sonnet` and `opus`
# agy model ids; its quota is agy's. The legacy CLI-named `claude` and `codex`
# keys give way to instances of their drivers. The `agy` provider is still
# probed by its CLI. Without --instances the providers are the three CLIs, as
# before.
#
# stdout: {fleet_file, written, fleet, warnings, to_probe, instances}: `fleet` the merged
#         file as it is or would be written, `warnings` one string per probe
#         that failed (T3 environments, GitHub accounts, a reply that is no
#         probe); `to_probe` one {machine, environment_id} per reachable linked
#         machine no `--probe` covered; a provider whose quota command
#         fails is `unavailable` with a `reason` in `fleet.providers`, not a
#         warning; `instances` one {instance_id, driver, quota_source, auth,
#         auth_reason, status} per enabled instance
# exit: 0 a proposal or a write, failed probes included · 2 usage, a fleet file
#       that is not JSON or has a field of the wrong shape, a machine probe
#       (hostname, nproc, free, uptime) that failed, or a write that failed
#
# Linux only: the machine probes are GNU `nproc`, `free` and `timeout`.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh" || { printf '{"error":"cannot source _lib.sh"}\n'; exit 2; }

usage='usage: setup (--propose | --write) [--fleet <file>] [--name <machine>] [--probe <environment id>=<reply file>]... [--instances <file>] [--settings <file>]'
sa_help "$usage" "$@"
fleet_file="${XDG_CONFIG_HOME:-$HOME/.config}/super-agent/fleet.json"
name='' write=false mode='' replies='{}' instances_file='' settings_file=''
while [ $# -gt 0 ]; do
  case $1 in
    --fleet) sa_flag_value "$usage" "${2:-}"; fleet_file=$2; shift 2 ;;
    --name) sa_flag_value "$usage" "${2:-}"; name=$2; shift 2 ;;
    --probe) sa_flag_value "$usage" "${2:-}"; case $2 in *=?*) ;; *) sa_tooling "$usage" ;; esac
      replies=$(jq -c --arg k "${2%%=*}" --arg v "${2#*=}" '.[$k] = $v' <<<"$replies"); shift 2 ;;
    --instances) sa_flag_value "$usage" "${2:-}"; instances_file=$2; shift 2 ;;
    --settings) sa_flag_value "$usage" "${2:-}"; settings_file=$2; shift 2 ;;
    --propose) mode=propose; shift ;;
    --write) mode=write write=true; shift ;;
    *) sa_tooling "$usage" ;;
  esac
done
[ -n "$mode" ] || sa_tooling "$usage"
rows='[]'
if [ -n "$instances_file" ]; then
  [ -f "$instances_file" ] || sa_tooling "$instances_file: no such file"
  jq -e . "$instances_file" >/dev/null 2>&1 || sa_tooling "$instances_file: not JSON"
  rows=$(jq -c '(.providers // .) | if type == "array" then . else null end' "$instances_file")
  jq -e 'type == "array" and all(.[]; type == "object" and (.providerInstanceId | type) == "string" and (.driverKind | type) == "string")' <<<"$rows" >/dev/null 2>&1 \
    || sa_tooling "$instances_file: every row needs a providerInstanceId and a driverKind"
  # a row carries no home path: T3's settings file holds it, at providerInstances.<id>.config.homePath
  if [ -n "$settings_file" ]; then
    [ -f "$settings_file" ] || sa_tooling "$settings_file: no such file"
    jq -e '.providerInstances | type == "object"' "$settings_file" >/dev/null 2>&1 || sa_tooling "$settings_file: no providerInstances object"
    rows=$(jq -c --slurpfile t "$settings_file" '[.[] | . as $r | ($t[0].providerInstances[$r.providerInstanceId].config.homePath // null) as $h
      | if $r.homePath == null and ($h | type) == "string" then . + {homePath: $h} else . end]' <<<"$rows")
  fi
  # enabled: T3 reports a disabled instance in `constraints`, there is no flag
  rows=$(jq -c '[.[] | select([.constraints[]? | strings | test("disabled"; "i")] | any | not)]' <<<"$rows")
fi
[ -n "$name" ] || name=$(hostname 2>/dev/null) || sa_tooling "cannot read this machine's name: pass --name"
existing='{}'
if [ -f "$fleet_file" ]; then
  jq -e . "$fleet_file" >/dev/null 2>&1 || sa_tooling "$fleet_file: not JSON"
  # A wrong shape would be dropped silently by the merge below, so it is refused by name.
  bad=$(jq -r 'if type != "object" then "the file must be an object"
    elif ((.machines // {}) | type) != "object" then "machines must be an object"
    elif ((.providers // {}) | type) != "object" then "providers must be an object"
    elif ([(.providers // {})[] | objects | .quota_command | select(. != null and type != "string")] | length) > 0 then "quota_command must be a string"
    elif ((.waivers // []) | type) != "array" then "waivers must be an array"
    elif ((.active_repos // []) | type) != "array" then "active_repos must be an array"
    elif ((if .work_week == null then [1] else .work_week end) | type == "array" and length > 0 and length == (unique | length) and all(type == "number" and . >= 0 and . <= 6 and . == floor)) | not then "work_week must be a non-empty list of distinct weekday numbers 0 to 6"
    else empty end' "$fleet_file")
  [ -z "$bad" ] || sa_tooling "$fleet_file: $bad"
  existing=$(cat "$fleet_file")
fi

floor_gb=4
warnings='[]'
warn() { warnings=$(jq -c --arg w "$1" '. + [$w]' <<<"$warnings"); }

# One machine's facts and proposal from a probe line: slots the lesser of half
# its cores and its RAM over the floor, at least 1. A GPU read that failed is
# left out of the facts, so the file keeps what it holds.
machine_jq='def machine($p; $gb; $extra):
  ([([($p.cores / 2 | floor), ($p.ram_gb / $gb | floor)] | min), 1] | max) as $slots
  | {facts: ({probed: true, cores: $p.cores, ram_gb: $p.ram_gb, clis: $p.clis, gh_logins: $p.gh_logins, proposed_slots: $slots}
             + (if $p.gpu_failed then {} else {gpu: $p.gpu} end)),
     proposal: ({slots: $slots, max_load: $p.cores, gpu: null} + $extra)};'

# This machine, measured by the same probe a linked machine runs.
probe_out=$(bash "$(dirname "${BASH_SOURCE[0]}")/probe.sh" --json 2>/dev/null </dev/null) \
  || sa_tooling "$(jq -r '.error // "probe.sh failed"' <<<"$probe_out" 2>/dev/null || echo "probe.sh failed")"
local_m=$(jq -c "$machine_jq"' machine(.; $f; {reserve: 1})' --argjson f "$floor_gb" <<<"$probe_out")
! jq -e .gpu_failed >/dev/null <<<"$probe_out" || warn "nvidia-smi failed: gpu left as the file has it"
facts=$(jq -cn --arg n "$name" --argjson m "$local_m" '{machines: {($n): $m.facts}}')
proposed=$(jq -cn --arg n "$name" --argjson m "$local_m" --argjson f "$floor_gb" \
  '{machines: {($n): $m.proposal}, thread_ram_floor_gb: $f, active_repos: [], work_week: [1,2,3,4,5],
    waivers: [
      {id: "codex-usage-limit", condition: "Codex answers a review request with a usage-limit notice: drive the fallback reviewer and record Codex as not landed; do not hold the merge gate for it."},
      {id: "offline-live-e2e", condition: "A live end-to-end proof needs a real T3 server or other machines: prove it through the scripts over fake CLIs and say so in the PR body."},
      {id: "last-fix-after-cap", condition: "The last fix after the review cap is reached may merge without another review round: record it in the PR body."}]}')

# Linked T3 environments: each is a machine this super agent may launch on. A
# reachable one is probed through a scratch thread there (the caller runs it, see
# the header), an unreachable one only has its reachability recorded.
to_probe='[]'
if raw=$(t3 environment list --json 2>/dev/null </dev/null) \
    && envs=$(grep '^\[' <<<"$raw" | tail -1) && jq -e 'type == "array"' <<<"$envs" >/dev/null 2>&1; then
  facts=$(jq -c --argjson e "$envs" '.machines += ([$e[] | {key: .label, value: {environment_id: .environmentId, reachable: (.status == "reachable")}}] | from_entries)' <<<"$facts")
  proposed=$(jq -c --argjson e "$envs" '.machines += ([$e[] | {key: .label, value: {probed: false, slots: 1}}] | from_entries)' <<<"$proposed")
  while IFS=$'\t' read -r label id reachable; do
    if [ -n "$(jq -r --arg i "$id" '.[$i] // empty' <<<"$replies")" ]; then
      [ "$reachable" = true ] || { warn "$label: unreachable, so its probe reply was not merged"; continue; }
      reply=$(jq -r --arg i "$id" '.[$i]' <<<"$replies")
      line=$(grep '^{' "$reply" 2>/dev/null | tail -1)
      if ! jq -e '(.cores | type) == "number" and (.ram_gb | type) == "number"' <<<"$line" >/dev/null 2>&1; then
        warn "$label: no probe line in $reply${line:+: $(jq -r '.error // empty' <<<"$line" 2>/dev/null)}"; continue
      fi
      m=$(jq -c "$machine_jq"' machine(.; $f; {})' --argjson f "$floor_gb" <<<"$line")
      first=$(jq -r --arg l "$label" '.machines[$l].probed // false | not' <<<"$existing")
      facts=$(jq -c --arg l "$label" --argjson m "$m" '.machines[$l] += $m.facts' <<<"$facts")
      proposed=$(jq -c --arg l "$label" --argjson m "$m" '.machines[$l] = $m.proposal' <<<"$proposed")
      # Slots nobody chose (never probed) give way to the computed ones.
      [ "$first" != true ] || existing=$(jq -c --arg l "$label" 'if .machines[$l] then del(.machines[$l].slots, .machines[$l].max_load) else . end' <<<"$existing")
    elif [ "$reachable" = true ]; then
      to_probe=$(jq -c --arg l "$label" --arg i "$id" '. + [{machine: $l, environment_id: $i}]' <<<"$to_probe")
    fi
  done < <(jq -r '.[] | [.label, .environmentId, (.status == "reachable")] | @tsv' <<<"$envs")
else
  warn "t3 environment list failed: no linked machines recorded"
fi

# GitHub accounts, the active one marked.
if acct=$(gh auth status --json hosts 2>/dev/null </dev/null) \
    && jq -e '.hosts["github.com"] | type == "array"' <<<"$acct" >/dev/null 2>&1; then
  facts=$(jq -c --argjson a "$acct" '.github_accounts = [$a.hosts["github.com"][] | {login, active}]' <<<"$facts")
else
  warn "gh auth status failed: no GitHub accounts recorded"
fi

# Each provider's quota command, run once. It is recorded as the owner reads it
# back, and the provider is `unavailable` with the reason when it does not print
# a quota: the router skips it, and the owner can fix the command in the file
# and re-run, which probes the command the file holds.
# The server exits on end of input before it answers request 2 (measured, codex
# 0.166.0), so the requests are followed by a `sleep` that holds stdin open.
codex_cmd="{ printf '%s\\n' '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"clientInfo\":{\"name\":\"super-agent\",\"version\":\"0\"}}}' '{\"jsonrpc\":\"2.0\",\"method\":\"initialized\"}' '{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"account/rateLimits/read\"}' ; sleep 4; } | timeout 15 codex app-server"
# run_quota and probe_instance (a T3 instance as a provider) live apart: the
# functions read this script's variables and write $facts, $proposed and $warnings.
source "$(dirname "${BASH_SOURCE[0]}")/setup.d/instances.sh" || { printf '{"error":"cannot source setup.d/instances.sh"}\n'; exit 2; }
# provider: <name> <quota command> <jq test that the output holds a quota>
probe_provider() {
  local p=$1 cmd test=$3
  cmd=$(jq -r --arg p "$p" --arg d "$2" '.providers[$p].quota_command // $d' <<<"$existing")
  run_quota "$cmd" "$test" "$p" '{}'
  facts=$(jq -c --arg p "$p" --arg s "$q_status" --argjson r "$q_reason" \
    '.providers[$p] = {status: $s, reason: $r}' <<<"$facts")
  proposed=$(jq -c --arg p "$p" --arg c "$cmd" '.providers[$p] = {driver: $p, quota_command: $c}' <<<"$proposed")
}
claude_cmd='claude -p "/usage" --output-format json' claude_test='(.result | type) == "string"'
codex_test='.id == 2 and (.result.rateLimits | type) == "object"' agy_cmd='agy -p /usage --output-format json' agy_test='.status == "SUCCESS"'

while IFS= read -r row; do [ -z "$row" ] || probe_instance "$row"; done < <(jq -c '.[]' <<<"$rows")
# the CLI-named providers, for each driver no instance covers
covered() { jq -e --arg d "$1" 'any(.[]; (if .driverKind == "claudeAgent" then "claude" else .driverKind end) == $d)' <<<"$rows" >/dev/null; }
covered claude || probe_provider claude "$claude_cmd" "$claude_test"
covered codex || probe_provider codex "$codex_cmd" "$codex_test"
probe_provider agy "$agy_cmd" "$agy_test"

# A legacy CLI-named claude or codex key gives way to the instances of its driver: route
# would otherwise launch on an instance T3 does not have.
for d in claude codex; do
  covered "$d" && ! jq -e --arg d "$d" 'any(.[]; .providerInstanceId == $d)' <<<"$rows" >/dev/null \
    && existing=$(jq -c --arg d "$d" 'del(.providers[$d])' <<<"$existing")
done

# proposal < the file's own values < the probed facts
merged=$(jq -cn --argjson p "$proposed" --argjson e "$existing" --argjson f "$facts" '$p * $e * $f')

if $write; then sa_write "$fleet_file" "$merged"; fi
jq -cn --arg f "$fleet_file" --argjson w "$write" --argjson m "$merged" --argjson warn "$warnings" --argjson p "$to_probe" --argjson rows "$rows" \
  '{fleet_file: $f, written: $w, fleet: $m, warnings: $warn, to_probe: $p,
    instances: [$rows[] | .providerInstanceId as $k | $m.providers[$k] as $v
      | {instance_id: $k, driver: $v.driver,
         quota_source: (if ($v.env // {}) == {} then (if $v.driver == "claude" then "the default account" else "the caller\u0027s own account" end) else ($v.env | to_entries | map("\(.key)=\(.value)") | join(" ")) end),
         auth: $v.auth, auth_reason: $v.auth_reason, status: $v.status}]}'
