#!/usr/bin/env bash
# Pick the machine a launch runs on: this machine first, then the other linked
# machines by name, the first that is reachable, has what the ticket needs and
# passes `launch-check`. Only machines the fleet file already holds are
# candidates, and nothing here links, unlinks or reaches a machine except
# through its T3 environment id.
#
#   place --fleet <file> --ledger <file> --repo <owner/name> [--own <key>]
#         [--gpu] [--account <login>] [--area <path>]... [--blocked-by <n>]...
#         [--exclude <key>]... [--readings <file>] [--number <n>]
#
# --own is the fleet key of the machine the ledger is on (`hostname` when
# omitted). --gpu wants a machine with a GPU, --account a machine whose `gh`
# holds that login (a machine never probed holds none that is known). --exclude
# drops a machine the caller found unusable, say one with no T3 project for the
# repo. Reachability is read now from `t3 environment list`; this machine is
# always reachable. Live load and free RAM come from `probe.sh` here, and for a
# linked machine from --readings, a file of `{<key>: {load1, free_gb}}` taken
# from a probe thread run there: when the next candidate has no reading, the
# answer is `need_reading` for it, and the caller probes it and asks again.
# --number records the outcome in the ledger: a ticket nothing fits is `wait`ed
# (the morning report lists it), a placed one is `unwait`ed.
#
# stdout: {placed, waiting, reason, need_reading, considered}: `placed`
#         {machine, environment_id, local} or null; `environment_id` is what a
#         remote launch passes to `t3_thread_launch` (null for this machine);
#         `waiting` true when nothing fits now, `reason` then one line, starting
#         `gpu` when the work wanted a GPU and no machine with one is up;
#         `need_reading` {machine, environment_id} or null; `considered` one
#         {machine, outcome} per candidate looked at, `outcome` skipped:<why>
#         (excluded, no-environment, unreachable, unknown, no-gpu, account, unmeasured)
#         or the refusals of `launch-check` (slots, load, ram, repo, cap); a `repo` or
#         `cap` refusal ends the search with `waiting`, `reason` starting `same repo` or
#         `ship cap`
# exit: 0 an answer, any of the three · 2 usage, an unreadable fleet file or
#       ledger, a launch-check that failed, a failed `t3 environment list` with
#       nothing placed (nothing is recorded), or a ledger write that failed
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh" || { printf '{"error":"cannot source _lib.sh"}\n'; exit 2; }

usage='usage: place --fleet <file> --ledger <file> --repo <owner/name> [--own <key>] [--gpu] [--account <login>] [--area <path>]... [--blocked-by <n>]... [--exclude <key>]... [--readings <file>] [--number <n>]'
sa_help "$usage" "$@"
here=$(dirname "${BASH_SOURCE[0]}")
fleet='' ledger='' repo='' own='' gpu=false account='' readings='' number='' excluded='[]'
check_args=()
while [ $# -gt 0 ]; do
  case $1 in
    --gpu) gpu=true; shift; continue ;;
    --fleet|--ledger|--repo|--own|--account|--readings|--number|--area|--blocked-by|--exclude) sa_flag_value "$usage" "${2:-}" ;;
    *) sa_tooling "$usage" ;;
  esac
  case $1 in
    --fleet) fleet=$2 ;; --ledger) ledger=$2 ;; --repo) repo=$2 ;; --own) own=$2 ;;
    --account) account=$2 ;; --readings) readings=$2 ;; --exclude) excluded=$(jq -c --arg e "$2" '. + [$e]' <<<"$excluded") ;;
    --number) case $2 in *[!0-9]*) sa_tooling "$usage" ;; esac; number=$2 ;;
    --area|--blocked-by) check_args+=("$1" "$2") ;;
  esac
  shift 2
done
[ -n "$fleet" ] && [ -n "$ledger" ] && [ -n "$repo" ] || sa_tooling "$usage"
[ -f "$fleet" ] || sa_tooling "$fleet: no such file"
jq -e '(.machines | type) == "object"' "$fleet" >/dev/null 2>&1 || sa_tooling "$fleet: not a fleet file (machines must be an object)"
[ -z "$readings" ] || jq -e 'type == "object"' "$readings" >/dev/null 2>&1 || sa_tooling "$readings: not a JSON object"
[ -n "$own" ] || own=$(hostname 2>/dev/null) || sa_tooling "cannot read this machine's name: pass --own"
sa_read "$ledger"

# Reachability now. A failed read leaves it unknown, never down: a linked
# machine is then skipped:unknown and no ticket waits on that answer.
reach='{}' reach_known=false
if raw=$(t3 environment list --json 2>/dev/null </dev/null) && envs=$(grep '^\[' <<<"$raw" | tail -1) \
    && jq -e 'type == "array"' <<<"$envs" >/dev/null 2>&1; then
  reach=$(jq -c '[.[] | {key: .environmentId, value: (.status == "reachable")}] | from_entries' <<<"$envs") && reach_known=true
fi

considered='[]' placed=null need=null wait_reason='' eligible=0
note() { considered=$(jq -c --arg m "$1" --arg o "$2" '. + [{machine: $m, outcome: $o}]' <<<"$considered"); }
while IFS= read -r m; do
  mj=$(jq -c --arg m "$m" '.machines[$m]' "$fleet")
  id=$(jq -r '.environment_id // empty' <<<"$mj")
  if jq -e --arg m "$m" 'index($m)' <<<"$excluded" >/dev/null; then note "$m" skipped:excluded; continue; fi
  if [ "$m" != "$own" ]; then
    [ -n "$id" ] || { note "$m" skipped:no-environment; continue; }
    $reach_known || { note "$m" skipped:unknown; continue; }
    [ "$(jq -r --arg i "$id" '.[$i] // false' <<<"$reach")" = true ] || { note "$m" skipped:unreachable; continue; }
  fi
  if $gpu && ! jq -e '.gpu | type == "string"' <<<"$mj" >/dev/null; then note "$m" skipped:no-gpu; continue; fi
  if [ -n "$account" ] && ! jq -e --arg a "$account" '(.gh_logins // []) | index($a)' <<<"$mj" >/dev/null; then note "$m" skipped:account; continue; fi
  eligible=$((eligible + 1))
  if [ "$m" = "$own" ]; then
    reading=$(bash "$here/probe.sh" --json 2>/dev/null </dev/null) && jq -e '(.load1 | type) == "number"' <<<"$reading" >/dev/null 2>&1 \
      || { note "$m" skipped:unmeasured; continue; }
  else
    reading=$(jq -c --arg m "$m" '.[$m] // empty' "${readings:-/dev/null}" 2>/dev/null)
    if ! jq -e '(.load1 | type) == "number" and (.free_gb | type) == "number"' <<<"$reading" >/dev/null 2>&1; then
      need=$(jq -cn --arg m "$m" --arg i "$id" '{machine: $m, environment_id: $i}'); break
    fi
  fi
  rc=0; res=$(bash "$here/launch-check.sh" --fleet "$fleet" --ledger "$ledger" --machine "$m" --own "$own" ${number:+--key "$repo#$number"} \
    --load "$(jq -r .load1 <<<"$reading")" --free-gb "$(jq -r .free_gb <<<"$reading")" --repo "$repo" ${check_args[@]+"${check_args[@]}"} 2>/dev/null) || rc=$?
  case $rc in 0|1) ;; *) sa_tooling "launch-check failed for $m: $res" ;; esac
  if [ "$rc" = 0 ]; then
    placed=$(jq -cn --arg m "$m" --arg i "$id" --argjson l "$([ "$m" = "$own" ] && echo true || echo false)" \
      '{machine: $m, environment_id: (if $l or $i == "" then null else $i end), local: $l}'); break
  fi
  note "$m" "refused:$(jq -r '.refused | join(",")' <<<"$res")"
  # A conflict with the ticket's own repo follows it to every machine.
  if jq -e '.refused | index("repo")' >/dev/null <<<"$res"; then
    wait_reason="same repo: $(jq -r '.repo.conflicts | join(", ")' <<<"$res") is open and blocks or overlaps this ticket"; break
  fi
  # So does the repo's ship cap: the count is repo-wide, not the machine's.
  if jq -e '.refused | index("cap")' >/dev/null <<<"$res"; then
    wait_reason="ship cap: $(jq -r '.cap | "\(.open) of \(.max)"' <<<"$res") open tickets of $repo"; break
  fi
done < <(jq -r --arg own "$own" '.machines | keys as $k | ($k | map(select(. != $own))) as $rest | (if $k | index($own) then [$own] else [] end) + $rest | .[]' "$fleet")

waiting=false
if [ "$placed" = null ] && [ "$need" = null ]; then
  ! jq -e 'any(.[]; .outcome == "skipped:unknown")' >/dev/null <<<"$considered" \
    || sa_tooling "t3 environment list failed: reachability unknown, nothing placed and nothing recorded"
  waiting=true
  if [ -z "$wait_reason" ]; then
    if $gpu && [ "$eligible" = 0 ]; then wait_reason="gpu: no reachable machine with a GPU${account:+ and the $account login}"
    else wait_reason="no machine fits now: $(jq -r '[.[] | "\(.machine) \(.outcome)"] | join("; ")' <<<"$considered")"; fi
  fi
fi
if [ -n "$number" ]; then
  if [ "$waiting" = true ]; then
    out=$(bash "$here/ledger.sh" --ledger "$ledger" wait "$repo#$number" --reason "$wait_reason") || sa_tooling "ledger wait failed: $out"
  elif [ "$placed" != null ]; then
    out=$(bash "$here/ledger.sh" --ledger "$ledger" unwait "$repo#$number") || sa_tooling "ledger unwait failed: $out"
  fi
fi
jq -cn --argjson p "$placed" --argjson w "$waiting" --arg r "$wait_reason" --argjson n "$need" --argjson c "$considered" \
  '{placed: $p, waiting: $w, reason: (if $r == "" then null else $r end), need_reading: $n, considered: $c}'
