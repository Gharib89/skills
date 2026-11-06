#!/usr/bin/env bash
# Probe this machine, the linked T3 environments, GitHub and each provider's
# quota command, and propose the fleet file: the owner's machines, providers,
# accounts, active repos and standing waivers, which the launch reads instead of
# the skill text. --propose prints the proposal and writes nothing, so the owner
# reads it and confirms first; --write then writes it.
#
#   setup (--propose | --write) [--fleet <file>] [--name <machine>]
#         [--probe <environment id>=<reply file>]...
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
# stdout: {fleet_file, written, fleet, warnings, to_probe}: `fleet` the merged
#         file as it is or would be written, `warnings` one string per probe
#         that failed (T3 environments, GitHub accounts, a reply that is no
#         probe); `to_probe` one {machine, environment_id} per reachable linked
#         machine no `--probe` covered; a provider whose quota command
#         fails is `unavailable` with a `reason` in `fleet.providers`, not a
#         warning
# exit: 0 a proposal or a write, failed probes included · 2 usage, a fleet file
#       that is not JSON or has a field of the wrong shape, a machine probe
#       (hostname, nproc, free, uptime) that failed, or a write that failed
#
# Linux only: the machine probes are GNU `nproc`, `free` and `timeout`.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh" || { printf '{"error":"cannot source _lib.sh"}\n'; exit 2; }

usage='usage: setup (--propose | --write) [--fleet <file>] [--name <machine>] [--probe <environment id>=<reply file>]...'
sa_help "$usage" "$@"
fleet_file="${XDG_CONFIG_HOME:-$HOME/.config}/super-agent/fleet.json"
name='' write=false mode='' replies='{}'
while [ $# -gt 0 ]; do
  case $1 in
    --fleet) sa_flag_value "$usage" "${2:-}"; fleet_file=$2; shift 2 ;;
    --name) sa_flag_value "$usage" "${2:-}"; name=$2; shift 2 ;;
    --probe) sa_flag_value "$usage" "${2:-}"; case $2 in *=?*) ;; *) sa_tooling "$usage" ;; esac
      replies=$(jq -c --arg k "${2%%=*}" --arg v "${2#*=}" '.[$k] = $v' <<<"$replies"); shift 2 ;;
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
jq -cn --arg f "$fleet_file" --argjson w "$write" --argjson m "$merged" --argjson warn "$warnings" --argjson p "$to_probe" \
  '{fleet_file: $f, written: $w, fleet: $m, warnings: $warn, to_probe: $p}'
