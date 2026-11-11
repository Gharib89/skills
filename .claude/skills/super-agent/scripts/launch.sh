#!/usr/bin/env bash
# One call for a launch, one for its record. The launch form reads the ticket's
# labels (owner skill, Size), claims it, routes it, places it and writes its brief,
# then prints the whole `t3_thread_launch` argument object, or why it did not
# launch. The record form takes that answer and the launched thread and writes the
# ledger entry, then runs the baseline reconcile. Neither calls `t3_thread_launch`:
# the super agent makes that call.
#
#   launch <owner/name>#<n> --fleet <file> --ledger <file> --quota <file>
#          --machine <key> --thread <id> [--area <path>]... [--gpu]
#          [--account <login>] [--blocked-by <n>]... [--instance <id>]
#          [--raise <n>] [--wanted yes|no] [--readings <file>] [--exclude <key>]...
#          [--note <text>] [--out <file>]
#   launch record --launch <file> --thread <id> --ledger <file> [--rethread]
#          [--worktree <path>] [--remote <environment id>=<dir>]...
#
# --machine is this machine's fleet key and --thread the super agent's own thread,
# which `claim` records (the brief takes the placed machine,
# `record.machine`, not this one); --quota is the saved `quota` read of this wake. --area,
# --gpu, --account, --blocked-by, --readings and --exclude go to `place`,
# --instance and --raise to `route`. --wanted answers a route's `ask`: `yes`
# launches the wanted tier, `no` the default one. --note is a one-ticket brief
# line. --out also writes the answer to a file, only when it launches; `record`
# reads that file as --launch.
# The ticket's Size label picks the tier (M when it has none, `size_source` says
# so); `ready-for-agent` is a `ship` launch, `needs-triage` a `triage` one.
# `record` reads the worktree from `t3 thread show` when --worktree is omitted
# on a launch to this machine; a remote launch names it, and its --remote
# files reach the reconcile. --rethread points the ticket's open entry at the
# new thread (the stall ladder's rung 3) instead of adding one.
#
# stdout: launch: {key, launch, ...}. `launch` true: {kind, size, size_source,
#         claim (`taken` or `own`), args, needs, record}: `args` the
#         `t3_thread_launch` arguments (environmentId on a remote machine only,
#         title, workspaceStrategy, modelSelection, message), `needs` the
#         arguments only an MCP read can fill (`projectId`, from `t3_project_list`
#         on the placed machine), `record` what `record` writes. `launch` false:
#         {reason, detail}, `reason` one of `no_owner_skill` (detail the labels),
#         `claimed` or `stale` (the claim), `ask` (route's wanted, tier, bucket,
#         reason), `no_instance` (route's reason), `need_reading` (place's
#         machine and environment_id) or `waiting` (place's reason and
#         considered, and the ledger now holds the waiting row).
#         record: {key, entry, reconcile: {checked, errors}}, or the ledger's {error}
#         when it refused the entry
# exit: 0 a launch, or a record · 1 no launch, or a record the ledger refused (the
#       key is already open) · 2 usage, an unreadable fleet file, ledger or quota
#       file, a claim, issue or placement the host or a script refused, or a record
#       whose reconcile failed after the entry was written (do not record again)
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh" || { printf '{"error":"cannot source _lib.sh"}\n'; exit 2; }

usage='usage: launch <owner/name>#<n> --fleet <file> --ledger <file> --quota <file> --machine <key> --thread <id> [--area <path>]... [--gpu] [--account <login>] [--blocked-by <n>]... [--instance <id>] [--raise <n>] [--wanted yes|no] [--readings <file>] [--exclude <key>]... [--note <text>] [--out <file>] | launch record --launch <file> --thread <id> --ledger <file> [--rethread] [--worktree <path>] [--remote <environment id>=<dir>]...'
sa_help "$usage" "$@"
here=$(dirname "${BASH_SOURCE[0]}")
# sub <script> <args>...: one script's answer in $out and its exit in $rc. Its exit 2
# is this script's own, carrying its message.
sub() {
  local s=$1; shift
  out=$(bash "$here/$s.sh" "$@" 2>/dev/null </dev/null); rc=$?
  [ "$rc" != 2 ] || sa_tooling "$s: $(jq -r '.error // "failed"' <<<"$out" 2>/dev/null)"
}

if [ "${1:-}" = record ]; then
  shift
  launchf='' thread='' ledger='' worktree='' remotes=() rethread=''
  while [ $# -gt 0 ]; do
    case $1 in --rethread) rethread=1; shift; continue ;; esac
    sa_flag_value "$usage" "${2:-}"
    case $1 in
      --launch) launchf=$2 ;; --thread) thread=$2 ;; --ledger) ledger=$2 ;; --worktree) worktree=$2 ;;
      --remote) sa_remote_flag "$usage" "$2"; remotes+=(--remote "$2") ;;
      *) sa_tooling "$usage" ;;
    esac
    shift 2
  done
  [ -n "$launchf" ] && [ -n "$thread" ] && [ -n "$ledger" ] || sa_tooling "$usage"
  jq -e '.launch == true and (.record | type) == "object"' "$launchf" >/dev/null 2>&1 || sa_tooling "$launchf: not a launch answer that launched"
  rec=$(jq -c .record "$launchf")
  env=$(jq -r '.environment_id // empty' <<<"$rec")
  if [ -z "$worktree" ]; then
    [ -z "$env" ] || sa_tooling "a launch on a linked machine needs --worktree"
    raw=$(t3 thread show "$thread" --json 2>/dev/null </dev/null) || sa_tooling "cannot read thread $thread: pass --worktree"
    worktree=$(grep '^{"' <<<"$raw" | tail -1 | jq -r '.thread.worktreePath // empty' 2>/dev/null)
    [ -n "$worktree" ] || sa_tooling "thread $thread has no worktree path: pass --worktree"
  fi
  aflags=()
  while IFS= read -r a; do aflags+=(--area "$a"); done < <(jq -r '.areas[]' <<<"$rec")
  key=$(jq -r .key <<<"$rec")
  fields=(--thread "$thread" --worktree "$worktree" --branch "$(jq -r .branch <<<"$rec")" --kind "$(jq -r .kind <<<"$rec")"
    --instance "$(jq -r .instance_id <<<"$rec")" --model "$(jq -r .model <<<"$rec")" --effort "$(jq -r .effort <<<"$rec")"
    ${env:+--environment "$env"} ${aflags[@]+"${aflags[@]}"})
  machine=$(jq -r .machine <<<"$rec")
  if [ -n "$rethread" ]; then
    # rethread keeps the entry's machine, so a thread on another machine sets it after.
    sub ledger --ledger "$ledger" rethread "$key" "${fields[@]}"
    if [ "$rc" = 0 ]; then sub ledger --ledger "$ledger" set "$key" machine "$(jq -cn --arg m "$machine" '$m')"; fi
    if [ "$rc" = 0 ]; then
      sub ledger --ledger "$ledger" get "$key"
      [ "$rc" = 0 ] || sa_tooling "cannot read entry $key"
      out=$(jq -c '{entry: .}' <<<"$out") || sa_tooling "cannot read entry $key"
    fi
  else
    sub ledger --ledger "$ledger" add --repo "${key%#*}" --number "${key##*#}" --machine "$machine" "${fields[@]}"
  fi
  [ "$rc" = 0 ] || { printf '%s\n' "$out"; exit 1; }
  entry=$(jq -c .entry <<<"$out")
  sub reconcile --ledger "$ledger" ${remotes[@]+"${remotes[@]}"}
  [ "$rc" = 0 ] && jq -e '.checked != null' >/dev/null <<<"$out" || sa_tooling "reconcile gave no answer"
  jq -cn --argjson e "$entry" --argjson r "$out" '{key: $e.key, entry: $e, reconcile: {checked: $r.checked, errors: $r.errors}}'
  exit 0
fi

key=${1:-}; [ $# -gt 0 ] && shift
case $key in */*#[0-9]*) ;; *) sa_tooling "$usage" ;; esac
repo=${key%#*} number=${key##*#}
case $number in *[!0-9]*) sa_tooling "$usage" ;; esac
fleet='' ledger='' quota='' machine='' thread='' raise='' named='' wanted='' readings='' note='' outf='' gpu=''
account=''
pargs=()
areas='[]'
while [ $# -gt 0 ]; do
  case $1 in --gpu) gpu=--gpu; shift; continue ;; esac
  sa_flag_value "$usage" "${2:-}"
  case $1 in
    --fleet) fleet=$2 ;; --ledger) ledger=$2 ;; --quota) quota=$2 ;; --machine) machine=$2 ;; --thread) thread=$2 ;;
    --raise) case $2 in *[!0-9]*) sa_tooling "$usage" ;; esac; raise=$2 ;;
    --instance) named=$2 ;; --readings) readings=$2 ;; --note) note=$2 ;; --out) outf=$2 ;; --account) account=$2 ;;
    --wanted) case $2 in yes|no) wanted=$2 ;; *) sa_tooling "$usage" ;; esac ;;
    --area) areas=$(jq -c --arg a "$2" '. + [$a]' <<<"$areas"); pargs+=(--area "$2") ;;
    --blocked-by) case $2 in *[!0-9]*) sa_tooling "$usage" ;; esac; pargs+=(--blocked-by "$2") ;;
    --exclude) pargs+=(--exclude "$2") ;;
    *) sa_tooling "$usage" ;;
  esac
  shift 2
done
[ -n "$fleet" ] && [ -n "$ledger" ] && [ -n "$quota" ] && [ -n "$machine" ] && [ -n "$thread" ] || sa_tooling "$usage"
# An answer that does not launch leaves no file, so a stale one is never recorded.
[ -z "$outf" ] || rm -f "$outf"

# answer <reason> <detail json>: no launch, exit 1
answer() { jq -cn --arg k "$key" --arg r "$1" --argjson d "$2" '{key: $k, launch: false, reason: $r, detail: $d}'; exit 1; }

# 1. The owner skill and the Size, from one read of the issue.
issue=$(gh api "repos/$repo/issues/$number" 2>/dev/null </dev/null) && jq -e '.labels | type == "array"' <<<"$issue" >/dev/null 2>&1 \
  || sa_tooling "cannot read $repo#$number"
labels=$(jq -c '[.labels[].name]' <<<"$issue")
kind=$(jq -r 'if index("ready-for-agent") then "ship" elif index("needs-triage") then "triage" else "" end' <<<"$labels")
[ -n "$kind" ] || answer no_owner_skill "$labels"
size=$(jq -r '[.[] | select(IN("XS", "S", "M", "L", "XL"))] | first // ""' <<<"$labels")
size_source=label; [ -n "$size" ] || { size=M size_source=default; }

# 2. The claim: a comment, never an assignment.
rc=0; sub claim --repo "$repo" --number "$number" --machine "$machine" --thread "$thread"
[ "$rc" = 0 ] || answer "$(jq -r .status <<<"$out")" "$(jq -c .claim <<<"$out")"
claim=$(jq -r .status <<<"$out")

# 3. The route.
sub route --size "$size" --quota "$quota" ${raise:+--raise "$raise"} ${named:+--instance "$named"}
[ "$rc" = 0 ] && jq -e 'type == "object"' <<<"$out" >/dev/null 2>&1 || sa_tooling "route gave no answer"
route=$out
jq -e '.instance_id != null' <<<"$route" >/dev/null || answer no_instance "$(jq -c '{reason}' <<<"$route")"
ask=$(jq -r .ask <<<"$route")
if [ "$ask" = true ] && [ -z "$wanted" ]; then answer ask "$(jq -c '{wanted, tier, bucket, reason}' <<<"$route")"; fi
use=tier; if [ "$ask" = true ] && [ "$wanted" = yes ]; then use=wanted; fi
selection=$(jq -c --arg u "$use" '{instanceId: .instance_id}
  + (if $u == "wanted" then {model: .wanted_model, options: .wanted_options} else {model, options} end
     | with_entries(select(.value != null)))' <<<"$route")

# 4. The placement.
sub place --fleet "$fleet" --ledger "$ledger" --repo "$repo" --number "$number" --own "$machine" ${gpu:+"$gpu"} ${account:+--account "$account"} \
  ${readings:+--readings "$readings"} ${pargs[@]+"${pargs[@]}"}
jq -e 'has("placed")' <<<"$out" >/dev/null 2>&1 || sa_tooling "place gave no answer"
placed=$(jq -c .placed <<<"$out")
if [ "$placed" = null ]; then
  jq -e '.need_reading != null' <<<"$out" >/dev/null && answer need_reading "$(jq -c .need_reading <<<"$out")"
  answer waiting "$(jq -c '{reason, considered}' <<<"$out")"
fi
pm=$(jq -r .machine <<<"$placed")

# 5. The names, the base and the brief. The branch is named the way `/ship` names
# its own: <type>/<slug>-<n>, the slug the title past its `area: ` prefix.
raw=$(gh api "repos/$repo" 2>/dev/null </dev/null) && base=$(jq -r '.default_branch // empty' <<<"$raw") && [ -n "$base" ] \
  || sa_tooling "cannot read the default branch of $repo"
slug=$(jq -r '.title // ""' <<<"$issue" | sed 's/^[^:]*: *//' | tr 'A-Z' 'a-z' | sed 's/[^a-z0-9][^a-z0-9]*/-/g; s/^-//; s/-$//')
if [ "${#slug}" -gt 32 ]; then slug=${slug:0:32}; slug=${slug%-*}; fi
[ -n "$slug" ] || slug=ticket
type=$(jq -r 'if index("bug") then "fix" elif index("documentation") then "docs" elif index("refactor") then "refactor" elif index("chore") then "chore" else "feat" end' <<<"$labels")
[ "$kind" = ship ] || type=triage
branch="$type/$slug-$number"
sub brief --fleet "$fleet" --ledger "$ledger" --repo "$repo" --machine "$pm" ${note:+--note "$note"}
[ "$rc" = 0 ] && brief=$(jq -er '.brief | select(type == "string" and length > 0)' <<<"$out" 2>/dev/null) || sa_tooling "brief gave no answer"

# `record` is what the ledger entry carries: the fleet's machine key and the
# routed tier's model and effort, one spelling each.
answer_json=$(jq -cn --arg k "$key" --arg kind "$kind" --arg size "$size" --arg ss "$size_source" --arg claim "$claim" \
  --argjson route "$route" --argjson use "\"$use\"" --argjson placed "$placed" --argjson sel "$selection" --argjson areas "$areas" \
  --arg base "$base" --arg branch "$branch" --arg slug "$slug" --arg msg "/$kind $number" \
  --arg brief "$brief" --arg n "$number" --arg short "${repo#*/}" '
  ($route[$use]) as $tier
  | {key: $k, launch: true, kind: $kind, size: $size, size_source: $ss, claim: $claim,
     args: ({title: "\($short)#\($n) \($slug)",
             workspaceStrategy: {type: "worktree", baseRef: $base, branch: $branch, startFromOrigin: true},
             modelSelection: $sel, message: "\($msg)\n\n\($brief)"}
            + (if $placed.environment_id == null then {} else {environmentId: $placed.environment_id} end)),
     needs: ["projectId"],
     record: {key: $k, kind: $kind, machine: $placed.machine, environment_id: $placed.environment_id, instance_id: $route.instance_id,
              model: $tier.model, effort: $tier.effort, areas: $areas, branch: $branch}}') \
  || sa_tooling "cannot build the launch answer"
[ -z "$outf" ] || printf '%s\n' "$answer_json" > "$outf" || sa_tooling "cannot write $outf"
printf '%s\n' "$answer_json"
