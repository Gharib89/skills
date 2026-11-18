# The `launch record` form, sourced by `launch.sh` after its `record` word: it writes
# the ledger entry from a launch answer (--launch) or for a task (--task), reads it
# back and runs the baseline reconcile. It reads the caller's $usage and `sub`, and
# exits.

# shellcheck disable=SC2154  # usage, out and rc come from launch.sh and its sub

launchf='' thread='' ledger='' worktree='' remotes=() rethread='' task='' tbranch='' trepo='' tmachine='' tenv=''
while [ $# -gt 0 ]; do
  case $1 in --rethread) rethread=1; shift; continue ;; esac
  sa_flag_value "$usage" "${2:-}"
  case $1 in
    --launch) launchf=$2 ;; --thread) thread=$2 ;; --ledger) ledger=$2 ;; --worktree) worktree=$2 ;;
    --task) task=$2 ;; --branch) tbranch=$2 ;; --repo) trepo=$2 ;; --machine) tmachine=$2 ;; --environment) tenv=$2 ;;
    --remote) sa_remote_flag "$usage" "$2"; remotes+=(--remote "$2") ;;
    *) sa_tooling "$usage" ;;
  esac
  shift 2
done
[ -n "$thread" ] && [ -n "$ledger" ] || sa_tooling "$usage"
if [ -z "$launchf" ] && [ -z "$task" ]; then
  jq -cn '{error: "unrecorded launch: name the entry to write, --launch <file> or --task <slug>"}'
  printf '%s\n' "unrecorded launch: name the entry to write, --launch <file> or --task <slug>" >&2; exit 1
fi
[ -z "$launchf" ] || [ -z "$task" ] || sa_tooling "record: --launch and --task are two ways to name the entry, give one"
if [ -n "$task" ]; then
  # a thread that is no ticket's: no launch answer, so the entry comes from the flags
  key="task:$task"
  [ -z "$tenv" ] || [ -n "$tmachine" ] || sa_tooling "record --task: --environment needs --machine, or the slot lands on this machine"
  tmachine=${tmachine:-local}
  if [ -z "$worktree" ] && [ -z "$tenv" ]; then
    raw=$(t3 thread show "$thread" --json 2>/dev/null </dev/null) \
      && worktree=$(grep '^{"' <<<"$raw" | tail -1 | jq -r '.thread.worktreePath // empty' 2>/dev/null) || worktree=''
  fi
  sub ledger --ledger "$ledger" add --task "$task" --thread "$thread" --machine "$tmachine" ${worktree:+--worktree "$worktree"} \
    ${tbranch:+--branch "$tbranch"} ${trepo:+--repo "$trepo"} ${tenv:+--environment "$tenv"}
else
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
  kind=$(jq -r .kind <<<"$rec")
  fields=(--thread "$thread" --worktree "$worktree" --branch "$(jq -r .branch <<<"$rec")"
    --instance "$(jq -r .instance_id <<<"$rec")" --model "$(jq -r .model <<<"$rec")" --effort "$(jq -r .effort <<<"$rec")"
    ${env:+--environment "$env"} ${aflags[@]+"${aflags[@]}"})
  machine=$(jq -r .machine <<<"$rec")
  if [ "$kind" = task ] && [ -z "$rethread" ]; then
    # a --skill launch's entry: a task keyed by the skill and the ticket, its repo kept
    ia=(); [ "$(jq -r .interactive <<<"$rec")" != true ] || ia=(--interactive)
    sub ledger --ledger "$ledger" add --task "${key#task:}" --repo "$(jq -r .repo <<<"$rec")" --machine "$machine" \
      "${fields[@]}" ${ia[@]+"${ia[@]}"}
  elif [ -n "$rethread" ]; then
    # rethread keeps the entry's machine, so a thread on another machine sets it after.
    sub ledger --ledger "$ledger" rethread "$key" --kind "$kind" "${fields[@]}"
    if [ "$rc" = 0 ]; then sub ledger --ledger "$ledger" set "$key" machine "$(jq -cn --arg m "$machine" '$m')"; fi
    if [ "$rc" = 0 ]; then
      sub ledger --ledger "$ledger" get "$key"
      [ "$rc" = 0 ] || sa_tooling "cannot read entry $key"
      out=$(jq -c '{entry: .}' <<<"$out") || sa_tooling "cannot read entry $key"
    fi
  else
    sub ledger --ledger "$ledger" add --repo "${key%#*}" --number "${key##*#}" --kind "$kind" --machine "$machine" "${fields[@]}"
  fi
fi
[ "$rc" = 0 ] || { printf '%s\n' "$out"; exit 1; }
entry=$(jq -c .entry <<<"$out")
# The entry is read back: a launch is finished only once the ledger holds its thread.
sub ledger --ledger "$ledger" get "$key"
if [ "$rc" != 0 ] || [ "$(jq -r '.thread // empty' <<<"$out")" != "$thread" ]; then
  jq -cn --arg k "$key" --arg t "$thread" '{error: "unrecorded launch: \($k) has no ledger entry for thread \($t)"}'
  printf 'unrecorded launch: %s has no ledger entry for thread %s\n' "$key" "$thread" >&2; exit 1
fi
sub reconcile --ledger "$ledger" ${remotes[@]+"${remotes[@]}"}
[ "$rc" = 0 ] && jq -e '.checked != null' >/dev/null <<<"$out" || sa_tooling "reconcile gave no answer"
jq -cn --argjson e "$entry" --argjson r "$out" '{key: $e.key, entry: $e, reconcile: {checked: $r.checked, errors: $r.errors}}'
exit 0
