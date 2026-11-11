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

# --- the detail says why, so a missing --remote reads apart from a bad save ---------
reason_of() { jq -r '.errors[] | select(.key == "'"$repo#7"'") | .detail.reason' <<<"$1"; }
fixture
check "no --remote for the environment is no-remote" no-remote "$(reason_of "$(R --remote "env-a=$rem/env-a")")"
rm -f "$rem/env-b/t-7.json"
check "no file is missing, and the detail names it" "missing $rem/env-b/t-7.json" \
  "$(out=$(R "${remote_args[@]}"); echo "$(reason_of "$out") $(jq -r '.errors[0].detail.file' <<<"$out")")"
printf 'not json\n' > "$rem/env-b/t-7.json"
check "a file that is not JSON is not-json" not-json "$(reason_of "$(R "${remote_args[@]}")")"
echo '{"messages":[]}' > "$rem/env-b/t-7.json"
check "JSON of the wrong shape is shape" shape "$(reason_of "$(R "${remote_args[@]}")")"

# --- rethread names the new thread's environment, or clears it ---------------------
fixture
L rethread "$repo#6" --thread t-6b --worktree /wt/6b --branch feat/x-6 --environment env-c >/dev/null
check "rethread --environment records the new environment" env-c "$(L get "$repo#6" | jq -r .environment_id)"
L rethread "$repo#6" --thread t-6c --worktree /wt/6c --branch feat/x-6 >/dev/null
check "rethread without it puts the entry back on this machine" null "$(L get "$repo#6" | jq -c .environment_id)"

# --- watch wakes a remote entry from GitHub alone ----------------------------------
# The thread is read from its reply file on a wake (reconcile) only: watch never
# asks the t3 CLI, and a refreshed file mid-watch changes nothing until reconcile.
fixture
for n in 6 7; do sa_pr_head $repo "feat/x-$n" none sha$n; done
R "${remote_args[@]}" >/dev/null
check "a remote entry's baseline carries its PR's checks" none "$(L get "$repo#6" | jq -r .observed.pr.checks)"
check "a local entry's baseline carries none" null "$(L get "$repo#5" | jq -c .observed.pr.checks)"
sa_remote_thread env-a t-6 idle 1 0 /wt/6 feat/x-6
rm -f "$SA_FAKE/calls"
out=$(W --timeout 3)
check "a remote thread that finished in its file wakes nothing, with no --remote" "timeout 3" \
  "$(jq -r '[.event, (.watching | length)] | join(" ")' <<<"$out")"
check "a refreshed reply file is not read by watch either" "timeout" "$(W "${remote_args[@]}" --timeout 2 | jq -r .event)"
check "watch asked the t3 CLI for the local thread only" "t3 thread show t-5 --json --messages 1" \
  "$(calls | grep '^t3 thread show' | sort -u)"
sa_pr_head $repo feat/x-6 open sha6; sa_checks $repo sha6 pending
out=$(W --timeout 5)
check "a PR opening on the remote branch wakes watch" "$repo#6 pr-opened" "$(jq -r '[.key, .event] | join(" ")' <<<"$out")"
check "its snapshot says what the checks are" "open pending" "$(jq -r '[.observed.pr.state, .observed.pr.checks] | join(" ")' <<<"$out")"
R "${remote_args[@]}" >/dev/null
check "once reconcile took it as the baseline, it is quiet" timeout "$(W --timeout 2 | jq -r .event)"
sa_checks $repo sha6 "done"
out=$(W --timeout 5)
check "the checks on its head finishing wake watch" "$repo#6 checks-finished" "$(jq -r '[.key, .event] | join(" ")' <<<"$out")"
R "${remote_args[@]}" >/dev/null
sa_pr_head $repo feat/x-6 merged sha6
out=$(W --timeout 5)
check "a merge wakes watch" "$repo#6 pr-merged" "$(jq -r '[.key, .event] | join(" ")' <<<"$out")"
R "${remote_args[@]}" >/dev/null
sa_pr_head $repo feat/x-7 closed sha7
out=$(W --timeout 5)
check "a close wakes watch" "$repo#7 pr-closed" "$(jq -r '[.key, .event] | join(" ")' <<<"$out")"
fixture
sa_pr_head $repo feat/x-6 open sha6; sa_checks $repo sha6 "done"
R "${remote_args[@]}" >/dev/null
sa_pr_head $repo feat/x-7 none sha7
sa_gh_fail check-runs 2
out=$(W --timeout 5)
check "a check read that fails is pr-unreadable, not silence" "$repo#6 pr-unreadable" "$(jq -r '[.key, .event] | join(" ")' <<<"$out")"
rm -f "$SA_FAKE/gh-fail"
fixture
sa_pr_head $repo feat/x-6 open sha6; sa_checks $repo sha6 pending
sa_pr_head $repo feat/x-7 none sha7
R "${remote_args[@]}" >/dev/null
rm -rf "$rem/env-b"
out=$(W --timeout 2)
check "a remote entry whose reply file is gone is still watched, from GitHub" "timeout 3" \
  "$(jq -r '[.event, (.watching | length)] | join(" ")' <<<"$out")"
sa_thread t-5 idle 1 0 /wt/5 feat/x-5
out=$(W --timeout 5)
check "a local entry still wakes on its own thread" "$repo#5 run-finished" "$(jq -r '[.key, .event] | join(" ")' <<<"$out")"

# --- usage -----------------------------------------------------------------------
usage_r=$(bash "$s/reconcile.sh" --help | sed -n 1p)
for bad in env-a =dir env-a= ; do
  out=$(R --remote "$bad" 2>/dev/null); rc=$?
  check_rc "--remote $bad is a usage error" 2 "$rc"
  check "and it answers the usage line" "$usage_r" "$(jq -r .error <<<"$out")"
done
out=$(L add --repo $repo --number 9 --thread t --worktree w --branch b --environment 2>/dev/null); rc=$?
check_rc "--environment on add needs a value" 2 "$rc"
check "and it answers the usage line" "usage: ledger" "$(jq -r .error <<<"$out" | cut -d' ' -f1-2)"

# a thread id with a slash never names a file outside the reply directory
fixture
L set "$repo#6" thread '"../env-b/t-7"' >/dev/null
out=$(R "${remote_args[@]}")
check "a thread id holding a slash is thread-unreadable" "$repo#6 thread-unreadable" \
  "$(jq -r '.errors[] | select(.key == "'"$repo#6"'") | "\(.key) \(.kind)"' <<<"$out")"

finish
