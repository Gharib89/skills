#!/usr/bin/env bash
# super-agent on a linked machine, through the command lines of `ledger`,
# `reconcile` and `watch` over fake `t3` and `gh` on PATH
# (tests/super-agent-fake.sh): `t3 thread show` has no environment flag, so a
# remote entry's thread is read from a reply file the super agent saved, one
# directory per environment, and an environment with no reply fails alone.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
source tests/super-agent-fake.sh

s=skills/super-agent/scripts
tmp=$(mktemp -d) || exit 2
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/fake"
export PATH="$tmp/bin:$PATH" SA_FAKE=$tmp/fake
sa_fake_install "$tmp/bin"
led=$tmp/ledger.json
repo=Gharib89/skills
L() { bash "$s/ledger.sh" --ledger "$led" "$@"; }
R() { bash "$s/reconcile.sh" --ledger "$led" "$@"; }
W() { bash "$s/watch.sh" --ledger "$led" --interval 1 --recheck 0 "$@"; }
rem=$SA_FAKE/remote
calls() { cat "$SA_FAKE/calls" 2>/dev/null; }

# fixture: 5 local, 6 on environment env-a, 7 on environment env-b
fixture() {
  rm -rf "$led" "$SA_FAKE/calls" "$rem"
  L add --repo $repo --number 5 --thread t-5 --worktree /wt/5 --branch feat/x-5 >/dev/null
  L add --repo $repo --number 6 --thread t-6 --worktree /wt/6 --branch feat/x-6 --machine alpha --environment env-a >/dev/null
  L add --repo $repo --number 7 --thread t-7 --worktree /wt/7 --branch feat/x-7 --machine beta --environment env-b >/dev/null
  for n in 5 6 7; do sa_pr $repo "feat/x-$n" none; sa_issue $repo "$n" open; done
  sa_thread t-5 running 1 0 /wt/5 feat/x-5
  sa_remote_thread env-a t-6 running 1 0 /wt/6 feat/x-6
  sa_remote_thread env-b t-7 running 1 0 /wt/7 feat/x-7
}
remote_args=(--remote "env-a=$rem/env-a" --remote "env-b=$rem/env-b")

# --- the ledger records the environment -----------------------------------------
fixture
check "a remote entry holds its environment id" env-a "$(L get "$repo#6" | jq -r .environment_id)"
check "a local entry holds none" null "$(L get "$repo#5" | jq -c .environment_id)"

# --- reconcile reads a remote entry from its reply file ---------------------------
out=$(R "${remote_args[@]}"); rc=$?
check_rc "reconcile exits 0" 0 "$rc"
check "all three entries are read, none in error" "3 0" "$(jq -r '[.checked, (.errors | length)] | join(" ")' <<<"$out")"
check "the remote entries took a baseline like the local one" "running running running" \
  "$(jq -r '[.entries[].stage] | join(" ")' <<<"$out")"
check "the remote thread was never asked of the t3 CLI" "t3 thread show t-5 --json --messages 1" "$(calls | grep '^t3 thread show')"

# --- a reply for another thread or worktree is a mismatch, as locally -------------
sa_remote_thread env-a t-6 running 1 0 /wt/other feat/x-6
out=$(R "${remote_args[@]}")
check "a remote reply with another worktree is thread-mismatch" "$repo#6 thread-mismatch" \
  "$(jq -r '.errors[] | "\(.key) \(.kind)"' <<<"$out")"

# --- an unreachable environment fails for its entries only ------------------------
fixture
rm -rf "$rem/env-b"
out=$(R "${remote_args[@]}")
check "an environment with no reply is thread-unreadable, for its entry only" "$repo#7 thread-unreadable" \
  "$(jq -r '.errors[] | "\(.key) \(.kind)"' <<<"$out")"
check "its detail names the environment" env-b "$(jq -r '.errors[0].detail.environment_id' <<<"$out")"
check "the local and the other remote entry still report" "$repo#5 $repo#6" \
  "$(jq -r '[.entries[].key] | join(" ")' <<<"$out")"
out=$(R)
check "no --remote at all leaves each remote entry unreadable and the local one read" "1 2" \
  "$(jq -r '[(.entries | length), (.errors | length)] | join(" ")' <<<"$out")"
fixture
printf 'not json\n' > "$rem/env-b/t-7.json"
out=$(R "${remote_args[@]}")
check "a reply that is not JSON is thread-unreadable" "$repo#7 thread-unreadable" \
  "$(jq -r '.errors[] | "\(.key) \(.kind)"' <<<"$out")"

# --- watch reads the same files ---------------------------------------------------
fixture
R "${remote_args[@]}" >/dev/null
sa_remote_thread env-a t-6 idle 1 0 /wt/6 feat/x-6
out=$(W "${remote_args[@]}" --timeout 5)
check "a remote thread that finished wakes watch" "$repo#6 run-finished" "$(jq -r '[.key, .event] | join(" ")' <<<"$out")"
sa_remote_thread env-a t-6 running 1 0 /wt/6 feat/x-6
rm -rf "$rem/env-b"
out=$(W "${remote_args[@]}" --timeout 5)
check "an unreachable environment wakes watch with thread-unreadable" "$repo#7 thread-unreadable" \
  "$(jq -r '[.key, .event] | join(" ")' <<<"$out")"
R "${remote_args[@]}" >/dev/null
out=$(W "${remote_args[@]}" --timeout 2)
check "once reconcile recorded it, the fault is quiet and local entries are still watched" "timeout 3" \
  "$(jq -r '[.event, (.watching | length)] | join(" ")' <<<"$out")"
sa_thread t-5 idle 1 0 /wt/5 feat/x-5
out=$(W "${remote_args[@]}" --timeout 5)
check "a local entry still wakes past the unreachable environment" "$repo#5 run-finished" "$(jq -r '[.key, .event] | join(" ")' <<<"$out")"

# --- usage -----------------------------------------------------------------------
check_rc "--remote without =<dir> is a usage error" 2 "$(R --remote env-a >/dev/null 2>&1; echo $?)"
check_rc "--environment on add needs a value" 2 "$(L add --repo $repo --number 9 --thread t --worktree w --branch b --environment >/dev/null 2>&1; echo $?)"

finish
