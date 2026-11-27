# The `launch record` form, sourced by `launch.sh` after its `record` word: it binds
# the thread to the entry a launch answer (--launch) names, or writes one for a task
# (--task), reads it back and runs the baseline reconcile; a launch answer carrying
# `owner_go` also gets its ruling, once the entry is written. It reads the caller's
# $usage, `sub`, `rec_fields` and `rec_add`, and
# exits.

# shellcheck disable=SC2154  # usage, out, rc and fields come from launch.sh and its sub

launchf='' thread='' ledger='' worktree='' remotes=() rethread='' task='' tbranch='' trepo='' tmachine='' tenv='' ia=()
while [ $# -gt 0 ]; do
  case $1 in --rethread) rethread=1; shift; continue ;; --interactive) ia=(--interactive); shift; continue ;; esac
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
[ -n "$task" ] || [ ${#ia[@]} -eq 0 ] || sa_tooling "record: --interactive marks a --task entry; a launch answer carries its own"
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
    ${tbranch:+--branch "$tbranch"} ${trepo:+--repo "$trepo"} ${tenv:+--environment "$tenv"} ${ia[@]+"${ia[@]}"}
else
  jq -e '.launch == true and (.record | type) == "object"' "$launchf" >/dev/null 2>&1 || sa_tooling "$launchf: not a launch answer that launched"
  rec=$(jq -c .record "$launchf")
  env=$(jq -r '.environment_id // empty' <<<"$rec")
  # a task with no repo runs in a scratch folder and holds no worktree, so its thread is not read
  if [ -z "$worktree" ] && ! jq -e '.kind == "task" and .repo == null' <<<"$rec" >/dev/null; then
    [ -z "$env" ] || sa_tooling "a launch on a linked machine needs --worktree"
    raw=$(t3 thread show "$thread" --json 2>/dev/null </dev/null) || sa_tooling "cannot read thread $thread: pass --worktree"
    worktree=$(grep '^{"' <<<"$raw" | tail -1 | jq -r '.thread.worktreePath // empty' 2>/dev/null)
    [ -n "$worktree" ] || sa_tooling "thread $thread has no worktree path: pass --worktree"
  fi
  key=$(jq -r .key <<<"$rec")
  if [ -n "$rethread" ]; then
    # rethread keeps the entry's machine, so a thread on another machine sets it after.
    rec_fields "$rec"
    sub ledger --ledger "$ledger" rethread "$key" --kind "$(jq -r .kind <<<"$rec")" --thread "$thread" ${worktree:+--worktree "$worktree"} "${fields[@]}"
    if [ "$rc" = 0 ]; then sub ledger --ledger "$ledger" set "$key" machine "$(jq -c .machine <<<"$rec")"; fi
    if [ "$rc" = 0 ]; then
      sub ledger --ledger "$ledger" get "$key"
      [ "$rc" = 0 ] || sa_tooling "cannot read entry $key"
      out=$(jq -c '{entry: .}' <<<"$out") || sa_tooling "cannot read entry $key"
    fi
  else
    rec_add "$rec" --thread "$thread" ${worktree:+--worktree "$worktree"}
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
if [ -n "$launchf" ] && jq -e '.record.owner_go == true' "$launchf" >/dev/null 2>&1; then
  sub ledger --ledger "$ledger" ruling "Owner go: $key launched with --owner-go, past the 5 hour floor and the weekly reserve."
  [ "$rc" = 0 ] || sa_tooling "cannot record the owner-go ruling for $key"
fi
sub reconcile --ledger "$ledger" ${remotes[@]+"${remotes[@]}"}
[ "$rc" = 0 ] && jq -e '.checked != null' >/dev/null <<<"$out" || sa_tooling "reconcile gave no answer"
jq -cn --argjson e "$entry" --argjson r "$out" '{key: $e.key, entry: $e, reconcile: {checked: $r.checked, errors: $r.errors}, status: $r.status}'
exit 0
