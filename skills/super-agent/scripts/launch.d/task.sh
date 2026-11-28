# The `launch task` form, sourced by `launch.sh` after its `task` word: a thread that is
# no ticket's, launched from the owner's ask (research, a test, a deploy, a grill). No
# claim and no issue read; it is routed as an M, placed, recorded at `launching` as a
# `task:<slug>` entry, and answered as `launch.sh --help` says. It reads the caller's
# $usage and the steps of launch.d/steps.sh, and exits.
#
# A one-off task is placed as a ticket is (`place`: pins, slots, a `waiting` answer, which
# records a waiting row carrying the ask, the skill and the place flags, so a later wake
# relaunches it with them); its message is
# the ask (`/<skill> <ask>` with --skill), then the contract line (`sa_task_contract`) as
# its last line. An interactive task (--interactive, or a --skill in
# `sa_interactive_skills`) waits on the owner by design: it takes no slot, runs on this
# machine and carries no contract line, since it leaves only on the owner's `drop`. With
# --repo the thread gets a worktree on `task/<slug>` from the repo's default branch; with
# none it runs in a scratch folder (`args.scratch`) and takes no --area. --raise relaunches
# an open task one tier up (the stall ladder's rung 3), then `record --rethread`.

# shellcheck disable=SC2154,SC2034  # usage, out, rc, route, use, selection and base come from launch.sh and its steps, which read size, raise, wanted, named and go

slug=${1:-}; [ $# -gt 0 ] && shift
sa_task_slug_ok "$slug" || sa_tooling "$usage"
key="task:$slug"
request='' fleet='' ledger='' quota='' machine='' repo='' skill='' interactive=false gpu='' account=''
named='' go='' outf='' raise='' wanted='' areas='[]' pargs=()
while [ $# -gt 0 ]; do
  case $1 in
    --gpu) gpu=--gpu; shift; continue ;; --owner-go) go=--owner-go; shift; continue ;;
    --interactive) interactive=true; shift; continue ;;
  esac
  sa_flag_value "$usage" "${2:-}"
  case $1 in
    --ask) request=$2 ;; --fleet) fleet=$2 ;; --ledger) ledger=$2 ;; --quota) quota=$2 ;; --machine) machine=$2 ;;
    --repo) case $2 in */*) repo=$2 ;; *) sa_tooling "$usage" ;; esac ;;
    --skill) case $2 in .*|*[!A-Za-z0-9._-]*) sa_tooling "$usage" ;; esac; skill=$2 ;;
    --wanted) case $2 in yes|no) wanted=$2 ;; *) sa_tooling "$usage" ;; esac ;;
    --raise) case $2 in *[!0-9]*) sa_tooling "$usage" ;; esac; raise=$2 ;;
    --instance) named=$2 ;; --account) account=$2 ;; --out) outf=$2 ;;
    --area) areas=$(jq -c --arg a "$2" '. + [$a]' <<<"$areas"); pargs+=(--area "$2") ;;
    --exclude) pargs+=(--exclude "$2") ;;
    *) sa_tooling "$usage" ;;
  esac
  shift 2
done
[ -n "$request" ] && [ -n "$fleet" ] && [ -n "$ledger" ] && [ -n "$quota" ] && [ -n "$machine" ] || sa_tooling "$usage"
# an area is a path in the task's repo: a scratch task has none
[ -n "$repo" ] || [ "$areas" = '[]' ] || sa_tooling "$usage"
[ -z "$skill" ] || case $sa_interactive_skills in *" $skill "*) interactive=true ;; esac
fleet_ok
size=M; route_pick

if [ "$interactive" = true ]; then
  placed=$(jq -cn --arg m "$machine" '{machine: $m, environment_id: null}')
else
  sub place --fleet "$fleet" --ledger "$ledger" ${repo:+--repo "$repo"} --key "$key" --own "$machine" ${gpu:+"$gpu"} ${account:+--account "$account"} \
    ${pargs[@]+"${pargs[@]}"}
  jq -e 'has("placed")' <<<"$out" >/dev/null 2>&1 || sa_tooling "place gave no answer"
  placed=$(jq -c .placed <<<"$out")
  if [ "$placed" = null ]; then
    detail=$(jq -c '{reason, considered}' <<<"$out")
    sub ledger --ledger "$ledger" wait "$key" --reason "$(jq -r .reason <<<"$detail")" --ask "$request" ${repo:+--repo "$repo"} ${skill:+--skill "$skill"} \
      ${gpu:+"$gpu"} ${account:+--account "$account"} ${pargs[@]+"${pargs[@]}"}
    [ "$rc" = 0 ] || sa_tooling "cannot record $key as waiting: $(jq -r '.error // empty' <<<"$out")"
    answer waiting "$detail"
  fi
fi
base=''
[ -z "$repo" ] || base_of "$repo"

contract=''
[ "$interactive" = true ] || contract=$sa_task_contract
answer_json=$(jq -cn --arg k "$key" --arg slug "$slug" --arg repo "$repo" --arg base "$base" --arg skill "$skill" --arg ask "$request" \
  --arg contract "$contract" --argjson route "$route" --arg use "$use" --argjson placed "$placed" --argjson sel "$selection" \
  --argjson areas "$areas" --argjson ia "$interactive" '
  ($route[$use]) as $tier
  | {key: $k, launch: true, kind: "task",
     args: ({title: "task \($slug)", modelSelection: $sel,
             message: ([if $skill == "" then $ask else "/\($skill) \($ask)" end, $contract] | map(select(. != "")) | join("\n"))}
            + (if $repo == "" then {scratch: true}
               else {workspaceStrategy: {type: "worktree", baseRef: $base, branch: "task/\($slug)", startFromOrigin: true}} end)
            + (if $placed.environment_id == null then {} else {environmentId: $placed.environment_id} end)),
     needs: (if $repo == "" then [] else ["projectId"] end),
     record: ({key: $k, kind: "task", machine: $placed.machine, environment_id: $placed.environment_id, instance_id: $route.instance_id,
              model: $tier.model, effort: $tier.effort, areas: $areas, repo: (if $repo == "" then null else $repo end), interactive: $ia}
              + (if $repo == "" then {} else {branch: "task/\($slug)"} end)
              + (if $route.owner_go == true then {owner_go: true} else {} end))}') \
  || sa_tooling "cannot build the launch answer"

# Record before launch, as a ticket's launch does. With --raise (the stall ladder's rung 3)
# the task's open entry already records it, and `record --rethread` binds the new thread.
rec_add "$(jq -c .record <<<"$answer_json")" --launching
[ "$rc" = 0 ] || { [ -n "$raise" ] && rec_open; } \
  || sa_tooling "cannot record $key before its launch: $(jq -r '.error // empty' <<<"$out")"
[ -z "$outf" ] || printf '%s\n' "$answer_json" > "$outf" || sa_tooling "cannot write $outf"
printf '%s\n' "$answer_json"
exit 0
