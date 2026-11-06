#!/usr/bin/env bash
# Pick a supervised thread's starting model tier from the issue's Size label, or
# the driver for a bounded text job, from `quota`'s answer.
#
#   route --size <XS|S|M|L|XL> [--raise <n>] --quota <file>
#   route --job text [--claude] --quota <file>
#
# --quota is a file holding `quota`'s output. The tier ladder is Sonnet low,
# Sonnet medium, Sonnet high, Opus high; XS and S start on the first rung, M on
# the second, L on the third, XL on the fourth. --raise (default 0) climbs one
# rung per stall or hard finding, and stops at the top. A tier above the
# default is a question for the owner only when Claude Code's weekly bucket
# (`week` of `claude`) has under 50% remaining; the tier to launch meanwhile is
# the default. A quota that is unknown never asks: the tier is the default.
# A text job goes to agy on its Gemini group. With --claude the job wants a
# Claude model: it stays on Claude Code, and overflows to agy's Claude group
# only when Claude Code's weekly bucket is under 50% and agy's Claude weekly
# bucket is not, both known.
#
# stdout: with --size: {size, raise, default, wanted, tier, ask, reason, bucket},
#         each tier a {model, effort}; `tier` is what to launch now and `ask`
#         true when `wanted` needs the owner's yes first; `bucket` the weekly
#         bucket read, {provider, id, remaining}, null when unknown; `reason`
#         one line. With --job: {job, driver, group, model, reason}, `driver`
#         `agy` or `claude`, `group` and `model` null for `claude`
# exit: 0 a route, an unknown quota included · 2 usage, or a --quota file that
#       is missing or not JSON
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh" || { printf '{"error":"cannot source _lib.sh"}\n'; exit 2; }

usage='usage: route --size <XS|S|M|L|XL> [--raise <n>] --quota <file> | --job text [--claude] --quota <file>'
sa_help "$usage" "$@"
size='' raise=0 job='' claude=false quota=''
while [ $# -gt 0 ]; do
  case $1 in
    --size) sa_flag_value "$usage" "${2:-}"; size=$2; shift 2 ;;
    --raise) sa_flag_value "$usage" "${2:-}"; case $2 in *[!0-9]*) sa_tooling "$usage" ;; esac; raise=$2; shift 2 ;;
    --job) sa_flag_value "$usage" "${2:-}"; job=$2; shift 2 ;;
    --claude) claude=true; shift ;;
    --quota) sa_flag_value "$usage" "${2:-}"; quota=$2; shift 2 ;;
    *) sa_tooling "$usage" ;;
  esac
done
[ -n "$quota" ] || sa_tooling "$usage"
if [ -n "$job" ]; then
  [ "$job" = text ] && [ -z "$size" ] && [ "$raise" = 0 ] || sa_tooling "$usage"
else
  case $size in XS|S|M|L|XL) ;; *) sa_tooling "$usage" ;; esac
  ! $claude || sa_tooling "$usage"
fi
[ -f "$quota" ] || sa_tooling "$quota: no such file"
jq -e . "$quota" >/dev/null 2>&1 || sa_tooling "$quota: not JSON"

# threshold: the weekly remaining below which a bucket counts as low
if [ -n "$job" ]; then
  jq -c --argjson claude "$claude" '
    def weekly($p; pred): [.providers[$p].buckets[]? | select(.window == "weekly" and pred)] | first | .remaining;
    (weekly("claude"; .id == "week")) as $cc
    | (weekly("agy"; (.group // "") | startswith("Claude"))) as $agyc
    | if ($claude | not) then {job: "text", driver: "agy", group: "gemini", model: "gemini-3.8-flash-medium", reason: "text jobs run on agy'"'"'s own quota"}
      elif $cc != null and $cc < 0.5 and $agyc != null and $agyc >= 0.5
        then {job: "text", driver: "agy", group: "claude", model: "claude-sonnet-4-6", reason: "Claude Code weekly under 50%: overflow to agy'"'"'s Claude group"}
      else {job: "text", driver: "claude", group: null, model: null, reason: "stays on Claude Code"} end' "$quota"
  exit 0
fi
jq -c --arg size "$size" --argjson raise "$raise" '
  [{model: "sonnet", effort: "low"}, {model: "sonnet", effort: "medium"}, {model: "sonnet", effort: "high"}, {model: "opus", effort: "high"}] as $ladder
  | ({XS: 0, S: 0, M: 1, L: 2, XL: 3}[$size]) as $d
  | ([$d + $raise, 3] | min) as $w
  | ([.providers.claude.buckets[]? | select(.window == "weekly" and .id == "week")] | first) as $b
  | (if $b == null then null else {provider: "claude", id: $b.id, remaining: $b.remaining} end) as $bucket
  | ($w > $d and $bucket != null and $bucket.remaining < 0.5) as $ask
  | {size: $size, raise: $raise, default: $ladder[$d], wanted: $ladder[$w],
     tier: (if $w > $d and ($bucket == null or $ask) then $ladder[$d] else $ladder[$w] end),
     ask: $ask,
     reason: (if $w == $d then "the default tier"
       elif $bucket == null then "quota unknown: default tier"
       elif $ask then "weekly under 50%: the owner decides the raise"
       else "weekly at or above 50%: raised" end),
     bucket: $bucket}' "$quota"
