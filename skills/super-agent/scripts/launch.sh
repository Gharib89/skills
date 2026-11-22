#!/usr/bin/env bash
# One call for a launch, one for its record. The launch form reads the ticket's
# labels (owner skill, Size), claims it, routes it, places it and writes its launch
# message, records the ticket in the ledger at stage `launching` (no thread yet), then
# prints the whole `t3_thread_launch` argument object, or why it did not launch. The
# record form takes that answer and the launched thread, binds the thread id to that
# entry, then runs the baseline reconcile. Neither calls `t3_thread_launch`: the super
# agent makes that call.
#
#   launch <owner/name>#<n> --fleet <file> --ledger <file> --quota <file>
#          --machine <key> --thread <id> [--area <path>]... [--gpu]
#          [--account <login>] [--blocked-by <n>]... [--instance <id>]
#          [--raise <n>] [--wanted yes|no] [--readings <file>] [--exclude <key>]...
#          [--owner-go] [--skill <name>] [--note <text>] [--out <file>]
#   launch record --launch <file> --thread <id> --ledger <file> [--rethread]
#          [--worktree <path>] [--remote <environment id>=<dir>]...
#   launch record --task <slug> --thread <id> --ledger <file> [--worktree <path>]
#          [--branch <name>] [--repo <owner/name>] [--machine <key>] [--environment <id>]
#          [--remote <environment id>=<dir>]... [--interactive]
#
# --machine is this machine's fleet key (the key whose entry's `hostname`, or the
# key itself when it records none, is what `hostname` prints here: any other key
# is a tooling error) and --thread the super agent's own thread, which `claim`
# records; --quota is the saved `quota` read of this wake. --area,
# --gpu, --account, --blocked-by, --readings and --exclude go to `place`,
# --instance and --raise to `route`. --wanted answers a route's `ask`: `yes`
# launches the wanted tier, `no` the default one. --owner-go is the owner's go past
# the 5 hour floor and the weekly reserve when no instance passes them (`route`); a
# launch that used it carries `owner_go` in `record`, and `record` writes a dated
# ruling naming the override and the ticket. --skill <name> is the owner naming the
# skill to run in place of the one the labels pick: installed in the repo
# (`.claude/skills/<name>/SKILL.md` on its default branch), or else on this machine
# (`~/.claude/skills/<name>/SKILL.md`), which then places the thread here alone.
# `ship` and `triage` keep their kinds, and any other skill records a `task` entry
# keyed `task:<name>-<repo name>-<n>`, interactive when the skill waits on the owner
# by design (`sa_interactive_skills`, `_lib.sh`). --note is the owner's note for
# this ticket, one line: a newline in it exits 2. --out also writes the answer to a
# file, only when it launches; `record` reads that file as --launch.
# The ticket's Size label picks the tier (M when it has none, `size_source` says
# so); `ready-for-agent` is a `ship` launch, `needs-triage` a `triage` one.
# The launch message (`args.message`) is the owner-skill invocation (`/ship <n>`,
# `/triage <n>`, or `/<name> <n>` with --skill), plus one `Note: <text>` line with
# --note: every rule a run follows lives in its skill, its repo's profile or the global rules, and the super agent says
# anything more only at a step-in (ADR 0020). One exception: a `/triage` message carries
# the waiting-line contract line (`sa_triage_contract`, `_lib.sh`) between the invocation
# and the note, because the triage skill is upstream and no SKILL.md this repo owns can.
# The fleet file's `merge_gate_ruler` is checked here, `owner` (the default) or
# `super-agent`, so a fleet the super agent cannot rule a hold from launches nothing.
# `record` reads the worktree from `t3 thread show` when --worktree is omitted
# on a launch to this machine; a remote launch names it, and its --remote
# files reach the reconcile. --rethread points the ticket's open entry at the
# new thread (the stall ladder's rung 3) instead of adding one. Every thread the
# super agent launches is recorded, whatever its kind: `record --task <slug>` is for
# one that is no ticket's (a grill, a deploy, a review), from no launch answer, as a
# `task` entry (`ledger`), --interactive when it waits on the owner by design; `--worktree` is read from `t3 thread show` when omitted
# and the thread is on this machine. `record` reads the entry back from the ledger
# before it answers, and fails with `unrecorded launch` (exit 1) when neither
# `--launch` nor `--task` names the entry to bind or the ledger does not hold it.
#
# stdout: launch: {key, launch, ...}. `launch` true: {kind, size, size_source,
#         claim (`taken` or `own`), args, needs, record}: `args` the
#         `t3_thread_launch` arguments (environmentId on a remote machine only,
#         title, workspaceStrategy, modelSelection, message), `needs` the
#         arguments only an MCP read can fill (`projectId`, from `t3_project_list`
#         on the placed machine), `record` the entry `launch` wrote at `launching` and `record` binds (a --skill
#         task's also its `repo` and `interactive`, an --owner-go launch's
#         `owner_go`). `launch` false:
#         {reason, detail}, `reason` one of `no_owner_skill` (detail the labels),
#         `no_skill` (detail {skill}: --skill names a skill installed nowhere; read
#         before the claim, so none is taken),
#         `stale_ship` (installed, minimum: the repo's installed ship is below
#         `sa_min_ship`; read before the claim, so none is taken),
#         `claimed` or `stale` (the claim), `ask` (route's wanted, tier, bucket,
#         reason), `no_instance` (route's reason), `need_reading` (place's
#         machine and environment_id) or `waiting` (place's reason and
#         considered, and the ledger now holds the waiting row).
#         record: {key, entry, reconcile: {checked, errors}, status}, `status`
#         the baseline reconcile's status answer, its block to post; or the
#         ledger's {error} when it refused the entry, or {error: "unrecorded
#         launch: ..."}
# exit: 0 a launch, or a record · 1 no launch, or a record the ledger refused (the
#       key is already open) · 2 usage, an unreadable fleet file, ledger or quota
#       file, a `merge_gate_ruler` other than `owner` or `super-agent`, a
#       --machine that is not this machine's own fleet key (or a `hostname` that
#       cannot be read), a claim, issue or placement the host or a script
#       refused, an installed ship version
#       that cannot be read as X.Y.Z, a launch the ledger would not record at
#       `launching` before it answers, or a record
#       whose reconcile failed after the entry was written (do not record again)
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh" || { printf '{"error":"cannot source _lib.sh"}\n'; exit 2; }

usage='usage: launch <owner/name>#<n> --fleet <file> --ledger <file> --quota <file> --machine <key> --thread <id> [--area <path>]... [--gpu] [--account <login>] [--blocked-by <n>]... [--instance <id>] [--raise <n>] [--wanted yes|no] [--readings <file>] [--exclude <key>]... [--owner-go] [--skill <name>] [--note <text>] [--out <file>] | launch record (--launch <file> [--rethread] | --task <slug> [--branch <name>] [--repo <owner/name>] [--machine <key>] [--environment <id>] [--interactive]) --thread <id> --ledger <file> [--worktree <path>] [--remote <environment id>=<dir>]...'
sa_help "$usage" "$@"
here=$(dirname "${BASH_SOURCE[0]}")
# sub <script> <args>...: one script's answer in $out and its exit in $rc. Its exit 2
# is this script's own, carrying its message.
sub() {
  local s=$1; shift
  out=$(bash "$here/$s.sh" "$@" 2>/dev/null </dev/null); rc=$?
  [ "$rc" != 2 ] || sa_tooling "$s: $(jq -r '.error // "failed"' <<<"$out" 2>/dev/null)"
}
# rec_fields <record>: a launch answer's `record` as the ledger flags in $fields.
rec_fields() {
  local a env; env=$(jq -r '.environment_id // empty' <<<"$1")
  fields=(--branch "$(jq -r .branch <<<"$1")" --instance "$(jq -r .instance_id <<<"$1")"
    --model "$(jq -r .model <<<"$1")" --effort "$(jq -r .effort <<<"$1")" ${env:+--environment "$env"})
  while IFS= read -r a; do fields+=(--area "$a"); done < <(jq -r '.areas[]' <<<"$1")
}
# rec_add <record> <flag>...: `ledger add` its entry to $ledger, a --skill task keyed
# by the skill and the ticket (its repo kept) or the ticket, with the flags given.
rec_add() {
  local r=$1 k; k=$(jq -r .key <<<"$r"); shift; rec_fields "$r"
  fields+=(--machine "$(jq -r .machine <<<"$r")" "$@")
  if [ "$(jq -r .kind <<<"$r")" = task ]; then
    [ "$(jq -r .interactive <<<"$r")" != true ] || fields+=(--interactive)
    sub ledger --ledger "$ledger" add --task "${k#task:}" --repo "$(jq -r .repo <<<"$r")" "${fields[@]}"
  else
    sub ledger --ledger "$ledger" add --repo "${k%#*}" --number "${k##*#}" --kind "$(jq -r .kind <<<"$r")" "${fields[@]}"
  fi
}

if [ "${1:-}" = record ]; then
  shift
  source "$here/launch.d/record.sh" || sa_tooling "cannot source launch.d/record.sh"
fi

key=${1:-}; [ $# -gt 0 ] && shift
case $key in */*#[0-9]*) ;; *) sa_tooling "$usage" ;; esac
repo=${key%#*} number=${key##*#}
case $number in *[!0-9]*) sa_tooling "$usage" ;; esac
fleet='' ledger='' quota='' machine='' thread='' raise='' named='' wanted='' readings='' note='' outf='' gpu=''
account='' go='' skill=''
pargs=()
areas='[]'
while [ $# -gt 0 ]; do
  case $1 in --gpu) gpu=--gpu; shift; continue ;; --owner-go) go=--owner-go; shift; continue ;; esac
  sa_flag_value "$usage" "${2:-}"
  case $1 in
    --fleet) fleet=$2 ;; --ledger) ledger=$2 ;; --quota) quota=$2 ;; --machine) machine=$2 ;; --thread) thread=$2 ;;
    --raise) case $2 in *[!0-9]*) sa_tooling "$usage" ;; esac; raise=$2 ;;
    --instance) named=$2 ;; --readings) readings=$2 ;; --note) case $2 in *$'\n'*) sa_tooling "--note holds a newline: the launch message takes one Note: line" ;; esac; note=$2 ;; --out) outf=$2 ;; --account) account=$2 ;;
    --wanted) case $2 in yes|no) wanted=$2 ;; *) sa_tooling "$usage" ;; esac ;;
    --area) areas=$(jq -c --arg a "$2" '. + [$a]' <<<"$areas"); pargs+=(--area "$2") ;;
    --blocked-by) case $2 in *[!0-9]*) sa_tooling "$usage" ;; esac; pargs+=(--blocked-by "$2") ;;
    --exclude) pargs+=(--exclude "$2") ;;
    --skill) case $2 in .*|*[!A-Za-z0-9._-]*) sa_tooling "$usage" ;; esac; skill=$2 ;;
    *) sa_tooling "$usage" ;;
  esac
  shift 2
done
[ -n "$fleet" ] && [ -n "$ledger" ] && [ -n "$quota" ] && [ -n "$machine" ] && [ -n "$thread" ] || sa_tooling "$usage"
[ -f "$fleet" ] || sa_tooling "$fleet: no such file, run setup"
jq -e '(.merge_gate_ruler // "owner") | IN("owner", "super-agent")' "$fleet" >/dev/null 2>&1 \
  || sa_tooling "$fleet: merge_gate_ruler must be \"owner\" or \"super-agent\""
# --machine must be this machine: a key carried in the agent's notes would otherwise
# pick where the thread runs and what the claim and the ledger say (#1332).
host=$(hostname 2>/dev/null) || sa_tooling "cannot read this machine's name"
jq -e --arg m "$machine" --arg h "$host" '.machines[$m] | type == "object" and (.hostname // $m) == $h' "$fleet" >/dev/null 2>&1 \
  || sa_tooling "--machine $machine is not this machine ($host) in $fleet: pass this machine's own fleet key, or run setup here"
# An answer that does not launch leaves no file, so a stale one is never recorded.
[ -z "$outf" ] || rm -f "$outf"

# answer <reason> <detail json>: no launch, exit 1
answer() { jq -cn --arg k "$key" --arg r "$1" --argjson d "$2" '{key: $k, launch: false, reason: $r, detail: $d}'; exit 1; }

# 1. The owner skill and the Size, from one read of the issue.
issue=$(gh api "repos/$repo/issues/$number" 2>/dev/null </dev/null) && jq -e '.labels | type == "array"' <<<"$issue" >/dev/null 2>&1 \
  || sa_tooling "cannot read $repo#$number"
labels=$(jq -c '[.labels[].name]' <<<"$issue")
if [ -n "$skill" ]; then
  # the owner named the skill: it must be installed where the thread can load it, and a
  # copy only this machine holds keeps the thread here (a 404 is the one "not in the repo")
  if ! err=$(gh api "repos/$repo/contents/.claude/skills/$skill/SKILL.md" 2>&1 >/dev/null </dev/null); then
    case $err in *"HTTP 404"*) ;; *) sa_tooling "cannot read $repo's .claude/skills/$skill" ;; esac
    [ -f "$HOME/.claude/skills/$skill/SKILL.md" ] || answer no_skill "$(jq -cn --arg s "$skill" '{skill: $s}')"
    while IFS= read -r m; do pargs+=(--exclude "$m"); done < <(jq -r --arg o "$machine" '.machines | keys[] | select(. != $o)' "$fleet")
  fi
  case $skill in ship|triage) kind=$skill ;; *) kind=task ;; esac
else
  kind=$(jq -r 'if index("ready-for-agent") then "ship" elif index("needs-triage") then "triage" else "" end' <<<"$labels")
  [ -n "$kind" ] || answer no_owner_skill "$labels"
  skill=$kind
fi
interactive=false
case $sa_interactive_skills in *" $skill "*) [ "$kind" != task ] || interactive=true ;; esac
size=$(jq -r '[.[] | select(IN("XS", "S", "M", "L", "XL"))] | first // ""' <<<"$labels")
size_source=label; [ -n "$size" ] || { size=M size_source=default; }

# 1b. A ship launch needs the repo's installed ship at `sa_min_ship` or above, read before
# the claim so a refused launch leaves none.
if [ "$kind" = ship ]; then
  installed=$(sa_skill_version "$repo" .claude/skills/ship/SKILL.md)
  [ -n "$installed" ] || sa_tooling "cannot read the installed ship version of $repo"
  jq -en --arg i "$installed" --arg m "$sa_min_ship" "$sa_jq_ver"'($i | ver) >= ($m | ver)' >/dev/null \
    || answer stale_ship "$(jq -cn --arg i "$installed" --arg m "$sa_min_ship" '{installed: $i, minimum: $m}')"
fi

# 2. The claim: a comment, never an assignment.
rc=0; sub claim --repo "$repo" --number "$number" --machine "$machine" --thread "$thread"
[ "$rc" = 0 ] || answer "$(jq -r .status <<<"$out")" "$(jq -c .claim <<<"$out")"
claim=$(jq -r .status <<<"$out")

# 3. The route.
sub route --size "$size" --quota "$quota" ${raise:+--raise "$raise"} ${named:+--instance "$named"} ${go:+"$go"}
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

# 5. The names, the base and the launch message. The branch is named the way `/ship` names
# its own: <type>/<slug>-<n>, the slug the title past its `area: ` prefix.
raw=$(gh api "repos/$repo" 2>/dev/null </dev/null) && base=$(jq -r '.default_branch // empty' <<<"$raw") && [ -n "$base" ] \
  || sa_tooling "cannot read the default branch of $repo"
slug=$(jq -r '.title // ""' <<<"$issue" | sed 's/^[^:]*: *//' | tr 'A-Z' 'a-z' | sed 's/[^a-z0-9][^a-z0-9]*/-/g; s/^-//; s/-$//')
if [ "${#slug}" -gt 32 ]; then slug=${slug:0:32}; slug=${slug%-*}; fi
[ -n "$slug" ] || slug=ticket
type=$(jq -r 'if index("bug") then "fix" elif index("documentation") then "docs" elif index("refactor") then "refactor" elif index("chore") then "chore" else "feat" end' <<<"$labels")
case $kind in ship) ;; triage) type=triage ;; *) type=$skill ;; esac
branch="$type/$slug-$number"

# `record` is what the ledger entry carries: the fleet's machine key and the
# routed tier's model and effort, one spelling each.
answer_json=$(jq -cn --arg k "$key" --arg kind "$kind" --arg size "$size" --arg ss "$size_source" --arg claim "$claim" \
  --argjson route "$route" --argjson use "\"$use\"" --argjson placed "$placed" --argjson sel "$selection" --argjson areas "$areas" \
  --arg base "$base" --arg branch "$branch" --arg slug "$slug" --arg msg "/$skill $number" --arg skill "$skill" --argjson ia "$interactive" \
  --arg note "$note" --arg n "$number" --arg short "${repo#*/}" --arg contract "$([ "$kind" = triage ] && printf %s "$sa_triage_contract")" '
  ($route[$use]) as $tier
  | {key: $k, launch: true, kind: $kind, size: $size, size_source: $ss, claim: $claim,
     args: ({title: "\($short)#\($n) \($slug)",
             workspaceStrategy: {type: "worktree", baseRef: $base, branch: $branch, startFromOrigin: true},
             modelSelection: $sel, message: ([$msg, $contract, (if $note == "" then "" else "Note: \($note)" end)] | map(select(. != "")) | join("\n"))}
            + (if $placed.environment_id == null then {} else {environmentId: $placed.environment_id} end)),
     needs: ["projectId"],
     record: ({key: (if $kind == "task" then "task:\($skill)-\($short)-\($n)" else $k end), kind: $kind, machine: $placed.machine, environment_id: $placed.environment_id, instance_id: $route.instance_id,
              model: $tier.model, effort: $tier.effort, areas: $areas, branch: $branch}
              + (if $kind == "task" then {repo: ($k | sub("#.*$"; "")), interactive: $ia} else {} end)
              + (if $route.owner_go == true then {owner_go: true} else {} end))}') \
  || sa_tooling "cannot build the launch answer"

# 6. Record before launch: the entry goes in at stage `launching` before the arguments
# come out, so a turn cut between `t3_thread_launch` and `record` loses no launch. An
# open entry for the ticket (a rethread) already records it, and `add` refuses that one.
rec_add "$(jq -c .record <<<"$answer_json")" --launching
[ "$rc" = 0 ] || jq -e '.error | endswith("is already in the ledger")' <<<"$out" >/dev/null 2>&1 \
  || sa_tooling "cannot record $key before its launch"

[ -z "$outf" ] || printf '%s\n' "$answer_json" > "$outf" || sa_tooling "cannot write $outf"
printf '%s\n' "$answer_json"
