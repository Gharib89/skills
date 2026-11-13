#!/usr/bin/env bash
# Pick a supervised thread's launch instance and starting model tier from the
# issue's Size label, or the driver for a bounded text job, from `quota`'s
# answer.
#
#   route --size <XS|S|M|L|XL> [--raise <n>] [--instance <id>] --quota <file>
#   route --job text [--claude] --quota <file>
#
# --quota is a file holding `quota`'s output. The tier ladder is Sonnet medium,
# Opus medium, Opus high (medium is the lowest effort a ship launch gets, owner
# ruling 2026-11-11); XS and S start on the first rung, M on the second, L and XL
# on the third (owner ruling 2026-11-13). --raise (default 0) climbs one rung per stall or hard finding, and
# stops at the top. Each provider is a T3
# provider instance, its key the instance id. A launch's candidates are the
# `claude` instances plus the `pi`, `cursor` and `grok` instances the owner
# allowed (`route: true`); a `pi` one also needs a `models` map giving the tier's
# `sonnet` and `opus` a model id. One whose
# `auth` is `failed`, whose weekly bucket is at 0 or under the weekly reserve, or
# (a `claude` instance) whose 5 hour bucket is under the 5 hour floor, is skipped.
# The floor and the reserve are fractions the quota read carries from the fleet
# file (`floors.five_hour`, default 0.1; `floors.weekly_reserve`, default 0.05).
# Of the rest the one with the most weekly headroom wins, its weekly remaining
# times its `weekly_weight` (default 1, the quota read carries it from the fleet
# entry: 40% of a seat three times the size is more work than 60% of one), an
# instance with no measured weekly bucket after every measured one, and a tie goes
# to a `claude` instance, then to the first id. A Claude instance's weekly bucket is its `week`, a Pi
# instance's the weekly bucket of agy's Claude group. A tier above the default
# is a question for the owner only when the chosen instance's weekly bucket has
# under 50% remaining; the tier to launch meanwhile is the default. A quota that
# is unknown never asks: the tier is the default. A `cursor` or `grok` instance has
# no non-interactive usage read (measured 2026-11-09), so its quota is always
# unknown: it is a last resort, and one only the owner allowed (`route: true`, off
# by default: they are for side tasks, not a full ship run), a candidate only when
# no `claude` or allowed `pi` instance can launch, on the model the entry's
# `models` map gives the tier or else its own default (`model` and `options` null).
# --instance <id> is the owner naming an instance: only it is considered, an
# unallowed `pi`, `cursor` or `grok` one included, and its auth and weekly bucket
# still disqualify it. With no candidate left,
# `instance_id` is null with the reason, for the caller to escalate. Each instance
# skipped on a floor or the reserve is named in `reason`, also when another wins. An old
# quota file keyed `claude` routes as before, on the instance `claude`.
# A text job goes to agy on its Gemini group. With --claude the job wants a
# Claude model: it stays on Claude Code, and overflows to agy's Claude group
# only when the best weekly bucket among the `claude` instances not signed out
# is under 50% and agy's Claude weekly bucket is not, both known.
#
# stdout: with --size: {size, raise, default, wanted, tier, ask, reason, bucket,
#         instance_id, model, options, wanted_model, wanted_options}, each tier a {model, effort}; `tier` is
#         what to launch now and `ask` true when `wanted` needs the owner's yes
#         first; `bucket` the weekly bucket read, {provider (the instance id),
#         id, remaining}, null when unknown; `instance_id` the T3 instance to
#         launch on, `model` the model id to send there (the exact id the
#         instance's `models` map gives the tier, the tier's alias on a Claude
#         instance whose map names none) and `options` the
#         `modelSelection` options for it, `wanted_model` and `wanted_options` the
#         same for `wanted` (what to send on the owner's yes); a Pi instance
#         always thinks `high`; `reason` one line, naming each instance skipped
#         on the 5 hour floor or the weekly reserve. With --job: {job,
#         driver, group, model, reason}, `driver` `agy` or `claude`, `group` and
#         `model` null for `claude`
# exit: 0 a route, an unknown quota included · 2 usage, or a --quota file that
#       is missing, not JSON, or of the wrong shape (providers an object, every
#       bucket's remaining a number)
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh" || { printf '{"error":"cannot source _lib.sh"}\n'; exit 2; }

usage='usage: route --size <XS|S|M|L|XL> [--raise <n>] [--instance <id>] --quota <file> | --job text [--claude] --quota <file>'
sa_help "$usage" "$@"
size='' raise=0 job='' claude=false quota='' named=''
while [ $# -gt 0 ]; do
  case $1 in
    --size) sa_flag_value "$usage" "${2:-}"; size=$2; shift 2 ;;
    --raise) sa_flag_value "$usage" "${2:-}"; case $2 in *[!0-9]*) sa_tooling "$usage" ;; esac; raise=$2; shift 2 ;;
    --instance) sa_flag_value "$usage" "${2:-}"; named=$2; shift 2 ;;
    --job) sa_flag_value "$usage" "${2:-}"; job=$2; shift 2 ;;
    --claude) claude=true; shift ;;
    --quota) sa_flag_value "$usage" "${2:-}"; quota=$2; shift 2 ;;
    *) sa_tooling "$usage" ;;
  esac
done
[ -n "$quota" ] || sa_tooling "$usage"
if [ -n "$job" ]; then
  [ "$job" = text ] && [ -z "$size" ] && [ "$raise" = 0 ] && [ -z "$named" ] || sa_tooling "$usage"
else
  case $size in XS|S|M|L|XL) ;; *) sa_tooling "$usage" ;; esac
  ! $claude || sa_tooling "$usage"
fi
[ -f "$quota" ] || sa_tooling "$quota: no such file"
jq -e . "$quota" >/dev/null 2>&1 || sa_tooling "$quota: not JSON"
# A wrong shape would route silently (a string sorts above any number in jq, so a
# low bucket would read as full and a raise would go out unasked), so refuse by name.
jq -e '(.providers | type) == "object"' "$quota" >/dev/null || sa_tooling "$quota: providers must be an object"
jq -e '[.providers[]? | .buckets[]? | .remaining | type] | all(. == "number")' "$quota" >/dev/null \
  || sa_tooling "$quota: every bucket's remaining must be a number"
jq -e '[.providers[]? | .weekly_weight // 1 | type == "number" and . > 0] | all' "$quota" >/dev/null \
  || sa_tooling "$quota: every weekly_weight must be a number above 0"
jq -e '[.floors[]?] | all(type == "number" and . >= 0 and . <= 1)' "$quota" >/dev/null \
  || sa_tooling "$quota: every floor must be a fraction 0 to 1"

# low: the weekly remaining below which a bucket counts as low
low=0.5
if [ -n "$job" ]; then
  jq -c --argjson claude "$claude" --argjson low "$low" '
    def weekly($p; pred): [.providers[$p].buckets[]? | select(.window == "weekly" and pred)] | first | .remaining;
    ([.providers | to_entries[] | select((.value.driver // .key) == "claude" and .value.auth != "failed")
      | [.value.buckets[]? | select(.window == "weekly" and .id == "week")] | first | .remaining] | max) as $cc
    | (weekly("agy"; (.group // "") | startswith("Claude"))) as $agyc
    | if ($claude | not) then {job: "text", driver: "agy", group: "gemini", model: "gemini-3.8-flash-medium", reason: "text jobs run on the agy quota"}
      elif $cc != null and $cc < $low and $agyc != null and $agyc >= $low
        then {job: "text", driver: "agy", group: "claude", model: "claude-sonnet-4-6", reason: "Claude Code weekly under 50%: overflow to the agy Claude group"}
      else {job: "text", driver: "claude", group: null, model: null, reason: "stays on Claude Code"} end' "$quota" || sa_tooling "$quota: cannot be read"
  exit 0
fi
jq -c --arg size "$size" --argjson raise "$raise" --argjson low "$low" --arg named "$named" '
  [{model: "sonnet", effort: "medium"}, {model: "opus", effort: "medium"}, {model: "opus", effort: "high"}] as $ladder
  | ({XS: 0, S: 0, M: 1, L: 2, XL: 2}[$size]) as $d
  | ([$d + $raise, 2] | min) as $w
  | (.floors.five_hour // 0.1) as $f5
  | (.floors.weekly_reserve // 0.05) as $res
  | ([$ladder[$d].model, $ladder[$w].model] | unique) as $models
  | def weekly($e): [$e.value.buckets[]? | select(.window == "weekly"
      and (if $e.driver == "pi" then ((.group // "") | startswith("Claude")) else .id == "week" end))] | first;
    [.providers | to_entries[] | (.value.driver // .key) as $drv | . + {driver: $drv}
      | ($drv == "cursor" or $drv == "grok") as $lr
      | select(if $named != "" then .key == $named and ($drv == "claude" or $drv == "pi" or $lr)
               else $drv == "claude" or (($drv == "pi" or $lr) and .value.route == true) end)
      | . + {lr: $lr, bucket: weekly(.), fivehour: ([.value.buckets[]? | select(.window == "5h")] | first)}
      | . + {skip: (if .value.auth == "failed" then "auth failed"
                    elif .bucket != null and .bucket.remaining == 0 then "weekly at 0"
                    elif .bucket != null and .bucket.remaining < $res then "weekly under the weekly reserve \($res)"
                    elif $drv == "claude" and .fivehour != null and .fivehour.remaining < $f5 then "5 hour bucket under the 5 hour floor \($f5)"
                    elif $drv == "pi" and ([$models[] as $m | (.value.models[$m] // null)] | any(. == null)) then "no model for the tier"
                    else null end)}] as $cands
  | ([$cands[] | select(.skip == null)] as $ok
      | (if ($ok | any(.lr | not)) then [$ok[] | select(.lr | not)] else $ok end)
      | sort_by([(if .bucket == null then 1 else 0 end), -((.bucket.remaining // 0) * (.value.weekly_weight // 1)), (if .driver == "claude" then 0 else 1 end), .key]) | first) as $pick
  | (if $pick == null or $pick.bucket == null then null else {provider: $pick.key, id: $pick.bucket.id, remaining: $pick.bucket.remaining} end) as $bucket
  | ([$cands[] | select(.skip != null and (.skip | test("floor|reserve"))) | "\(.key) \(.skip)"] | join(", ")) as $floored
  | ($w > $d and $bucket != null and $bucket.remaining < $low) as $ask
  | (if $w > $d and ($bucket == null or $ask) then $ladder[$d] else $ladder[$w] end) as $tier
  | def model($t): if $pick == null then null elif $pick.lr then ($pick.value.models[$t.model] // null) else ($pick.value.models[$t.model] // $t.model) end;
    def options($t): if $pick == null or $pick.lr then null elif $pick.driver == "pi" then [{id: "thinking", value: "high"}] else [{id: "effort", value: $t.effort}] end;
    {size: $size, raise: $raise, default: $ladder[$d], wanted: $ladder[$w],
     tier: $tier,
     ask: $ask,
     reason: ((if $pick == null then
         "no instance can launch: " + (if $named != "" and ($cands | length) == 0 then "\($named) is not a routable instance in the quota read"
           elif ($cands | length) == 0 then "no claude instance, and no pi, cursor or grok instance the owner allowed, in the quota read"
           else ([$cands[] | "\(.key) \(.skip)"] | join(", ")) end)
       elif $pick.lr then (if $named != "" then "owner named the instance" else "no routable instance has a measured quota: last resort" end)
       elif $w == $d then "the default tier"
       elif $bucket == null then "quota unknown: default tier"
       elif $ask then "weekly under 50%: the owner decides the raise"
       else "weekly at or above 50%: raised" end)
       + (if $pick != null and $floored != "" then " (skipped: \($floored))" else "" end)),
     bucket: $bucket,
     instance_id: ($pick.key // null),
     model: model($tier),
     options: options($tier),
     wanted_model: model($ladder[$w]),
     wanted_options: options($ladder[$w])}' "$quota" || sa_tooling "$quota: cannot be read"
