#!/usr/bin/env bash
# Probe this machine, the linked T3 environments, GitHub and each provider's
# quota command, and propose the fleet file: the owner's machines, providers,
# accounts, active repos and standing waivers, which the launch reads instead of
# the skill text. --propose prints the proposal and writes nothing, so the owner
# reads it and confirms first; --write then writes it.
#
#   setup (--propose | --write) [--fleet <file>] [--name <machine>]
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
# and T3 no longer lists is kept. This machine's slots are the lesser of half
# its cores and its RAM over the per-thread floor, at least 1; a linked machine
# is probed from its own `setup` run, so it starts at 1 slot.
#
# stdout: {fleet_file, written, fleet, warnings}: `fleet` the merged file as it
#         is or would be written, `warnings` one string per probe that failed
#         (T3 environments, GitHub accounts); a provider whose quota command
#         fails is `unavailable` with a `reason` in `fleet.providers`, not a
#         warning
# exit: 0 a proposal or a write, failed probes included · 2 usage, a fleet file
#       that is not JSON or has a field of the wrong shape, a machine probe
#       (hostname, nproc, free) that failed, or a write that failed
#
# Linux only: the machine probes are GNU `nproc`, `free` and `timeout`.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh" || { printf '{"error":"cannot source _lib.sh"}\n'; exit 2; }

usage='usage: setup (--propose | --write) [--fleet <file>] [--name <machine>]'
sa_help "$usage" "$@"
fleet_file="${XDG_CONFIG_HOME:-$HOME/.config}/super-agent/fleet.json"
name='' write=false mode=''
while [ $# -gt 0 ]; do
  case $1 in
    --fleet) sa_flag_value "$usage" "${2:-}"; fleet_file=$2; shift 2 ;;
    --name) sa_flag_value "$usage" "${2:-}"; name=$2; shift 2 ;;
    --propose) mode=propose; shift ;;
    --write) mode=write write=true; shift ;;
    *) sa_tooling "$usage" ;;
  esac
done
[ -n "$mode" ] || sa_tooling "$usage"
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
    else empty end' "$fleet_file")
  [ -z "$bad" ] || sa_tooling "$fleet_file: $bad"
  existing=$(cat "$fleet_file")
fi

floor_gb=4
warnings='[]'
warn() { warnings=$(jq -c --arg w "$1" '. + [$w]' <<<"$warnings"); }

# This machine. A missing GPU tool is no GPU, not a failure.
cores=$(nproc 2>/dev/null) || sa_tooling "nproc failed: cannot size this machine"
ram_mb=$(free -m 2>/dev/null | awk '/^Mem:/ { print $2 }')
[ -n "$ram_mb" ] || sa_tooling "free -m failed: cannot size this machine"
ram_gb=$(( (ram_mb + 512) / 1024 ))
# A missing tool is no GPU, but a tool that is there and fails is unknown, so
# the file keeps what it holds: a failed read is never a verdict.
gpu_fact='{"gpu":null}'
if command -v nvidia-smi >/dev/null; then
  if gpu=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null </dev/null | sed -n 1p) && [ -n "$gpu" ]; then
    gpu_fact=$(jq -cn --arg g "$gpu" '{gpu: $g}')
  else
    gpu_fact='{}'; warn "nvidia-smi failed: gpu left as the file has it"
  fi
fi
slots=$(( cores / 2 < ram_gb / floor_gb ? cores / 2 : ram_gb / floor_gb ))
[ "$slots" -ge 1 ] || slots=1
facts=$(jq -cn --arg n "$name" --argjson c "$cores" --argjson r "$ram_gb" --argjson g "$gpu_fact" \
  '{machines: {($n): ({probed: true, cores: $c, ram_gb: $r} + $g)}}')
proposed=$(jq -cn --arg n "$name" --argjson c "$cores" --argjson s "$slots" --argjson f "$floor_gb" \
  '{machines: {($n): {slots: $s, max_load: $c, gpu: null}}, thread_ram_floor_gb: $f, active_repos: [],
    waivers: [
      {id: "codex-usage-limit", condition: "Codex answers a review request with a usage-limit notice: drive the fallback reviewer and record Codex as not landed; do not hold the merge gate for it."},
      {id: "offline-live-e2e", condition: "A live end-to-end proof needs a real T3 server or other machines: prove it through the scripts over fake CLIs and say so in the PR body."},
      {id: "last-fix-after-cap", condition: "The last fix after the review cap is reached may merge without another review round: record it in the PR body."}]}')

# Linked T3 environments: each is a machine this super agent may launch on. They
# are probed from their own `setup` run, so only their reachability is a fact.
if raw=$(t3 environment list --json 2>/dev/null </dev/null) \
    && envs=$(grep '^\[' <<<"$raw" | tail -1) && jq -e 'type == "array"' <<<"$envs" >/dev/null 2>&1; then
  facts=$(jq -c --argjson e "$envs" '.machines += ([$e[] | {key: .label, value: {environment_id: .environmentId, reachable: (.status == "reachable")}}] | from_entries)' <<<"$facts")
  proposed=$(jq -c --argjson e "$envs" '.machines += ([$e[] | {key: .label, value: {probed: false, slots: 1}}] | from_entries)' <<<"$proposed")
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
# provider: <name> <quota command> <jq test that the output holds a quota>
probe_provider() {
  local p=$1 cmd test=$3 out rc status=available reason=null
  cmd=$(jq -r --arg p "$p" --arg d "$2" '.providers[$p].quota_command // $d' <<<"$existing")
  if ! command -v "$p" >/dev/null; then
    status=unavailable reason=$(jq -cn --arg p "$p" '"\($p) is not installed"')
  else
    out=$(timeout 30 bash -c "$cmd" 2>/dev/null </dev/null); rc=$?
    if [ "$rc" -ne 0 ]; then
      status=unavailable reason=$(jq -cn --argjson r "$rc" '"quota command exited \($r)"')
    elif ! jq -e -n "[inputs | $test] | any" <<<"$out" >/dev/null 2>&1; then
      status=unavailable reason='"quota command printed no quota"'
    fi
  fi
  facts=$(jq -c --arg p "$p" --arg s "$status" --argjson r "$reason" \
    '.providers[$p] = {status: $s, reason: $r}' <<<"$facts")
  proposed=$(jq -c --arg p "$p" --arg c "$cmd" '.providers[$p] = {driver: $p, quota_command: $c}' <<<"$proposed")
}
probe_provider claude 'claude -p "/usage" --output-format json' '(.result | type) == "string"'
probe_provider codex "$codex_cmd" '.id == 2 and (.result.rateLimits | type) == "object"'
probe_provider agy 'agy -p /usage --output-format json' '.status == "SUCCESS"'

# proposal < the file's own values < the probed facts
merged=$(jq -cn --argjson p "$proposed" --argjson e "$existing" --argjson f "$facts" '$p * $e * $f')

if $write; then sa_write "$fleet_file" "$merged"; fi
jq -cn --arg f "$fleet_file" --argjson w "$write" --argjson m "$merged" --argjson warn "$warnings" \
  '{fleet_file: $f, written: $w, fleet: $m, warnings: $warn}'
