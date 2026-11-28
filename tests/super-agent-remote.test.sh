#!/usr/bin/env bash
# super-agent on a linked machine, through the command lines of `ledger`,
# `reconcile` and `watch` over fake `t3`, `gh` and `ssh` on PATH
# (tests/super-agent-fake.sh): a remote entry's thread is read with the `t3` on its
# machine over SSH, one call per machine per look, and a machine that cannot be read
# fails alone, its entries still watched from GitHub.
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
led=$tmp/ledger.json fleet=$tmp/fleet.json
repo=Gharib89/skills
printf '%s\n' '{"machines": {"alpha": {"environment_id": "env-a", "ssh": "alpha", "slots": 3},
  "beta": {"environment_id": "env-b", "ssh": "me@beta", "slots": 3}}}' > "$fleet"
L() { bash "$s/ledger.sh" --ledger "$led" "$@"; }
R() { bash "$s/reconcile.sh" --ledger "$led" --fleet "$fleet" "$@"; }
W() { bash "$s/watch.sh" --ledger "$led" --fleet "$fleet" --interval 1 --recheck 0 "$@"; }
calls() { cat "$SA_FAKE/calls" 2>/dev/null; }
ssh_calls() { cut -f1 "$SA_FAKE/ssh-calls" 2>/dev/null | sort | uniq -c | awk '{print $2 "=" $1}' | paste -sd' '; }
down() { sa_ssh "$1" 255 '' 'ssh: connect to host beta port 22: Connection refused'; }
up() { rm -f "$SA_FAKE/ssh/$1".*; }

# fixture: 5 local; 6, 8 and 9 on machine alpha; 7 on machine beta
fixture() {
  rm -rf "$led" "$led".* "$tmp/remote-watch.jsonl" "$SA_FAKE/calls" "$SA_FAKE/ssh-calls" "$SA_FAKE/machines" "$SA_FAKE/ssh"
  mkdir -p "$SA_FAKE/ssh"
  L add --repo $repo --number 5 --thread t-5 --worktree /wt/5 --branch feat/x-5 >/dev/null
  for n in 6 8 9; do L add --repo $repo --number $n --thread t-$n --worktree /wt/$n --branch feat/x-$n --machine alpha --environment env-a >/dev/null; done
  L add --repo $repo --number 7 --thread t-7 --worktree /wt/7 --branch feat/x-7 --machine beta --environment env-b >/dev/null
  for n in 5 6 7 8 9; do sa_pr $repo "feat/x-$n" none; sa_issue $repo "$n" open; done
  sa_thread t-5 running 1 0 /wt/5 feat/x-5
  for n in 6 8 9; do sa_machine_thread alpha t-$n running 1 0 /wt/$n feat/x-$n; done
  sa_machine_thread me@beta t-7 running 1 0 /wt/7 feat/x-7
}

# --- the ledger records the environment -----------------------------------------
fixture
check "a remote entry holds its environment id" env-a "$(L get "$repo#6" | jq -r .environment_id)"
check "a local entry holds none" null "$(L get "$repo#5" | jq -c .environment_id)"

# --- reconcile reads a remote entry on its machine, one SSH call per machine -------
out=$(R); rc=$?
check_rc "reconcile exits 0" 0 "$rc"
check "all five entries are read, none in error" "5 0" "$(jq -r '[.checked, (.errors | length)] | join(" ")' <<<"$out")"
check "the remote entries took a baseline like the local one" "running running running running running" \
  "$(jq -r '[.entries[].stage] | join(" ")' <<<"$out")"
check "one SSH call per machine, whatever its thread count" "alpha=1 me@beta=1" "$(ssh_calls)"
check "this machine's t3 was asked for the local thread only" "t3 thread show t-5 --json --messages 1" "$(calls | grep '^t3 thread show')"

# --- a thread with another worktree is a mismatch, as locally ----------------------
sa_machine_thread alpha t-6 running 1 0 /wt/other feat/x-6
check "a remote thread with another worktree is thread-mismatch" "$repo#6 thread-mismatch" \
  "$(R | jq -r '.errors[] | "\(.key) \(.kind)"')"

# --- an unreadable machine fails for its entries only, naming why ------------------
reason_of() { jq -r '.errors[] | select(.key == "'"$repo#7"'") | "\(.kind) \(.detail.reason) \(.detail.machine)"' <<<"$1"; }
fixture
down me@beta
out=$(R)
check "a failed SSH call is thread-unreadable with reason ssh, naming the machine" "thread-unreadable ssh beta" "$(reason_of "$out")"
check "its detail carries ssh's reason" "ssh: connect to host beta port 22: Connection refused" "$(jq -r '.errors[0].detail.ssh' <<<"$out")"
check "the other entries still report" "$repo#5 $repo#6 $repo#8 $repo#9" "$(jq -r '[.entries[].key] | join(" ")' <<<"$out")"
up me@beta
jq -c '.machines.beta |= del(.ssh)' "$fleet" > "$fleet.new" && mv "$fleet.new" "$fleet"
check "a machine with no ssh string is reason no-ssh" "thread-unreadable no-ssh beta" "$(reason_of "$(R)")"
jq -c '.machines.beta.ssh = "me@beta"' "$fleet" > "$fleet.new" && mv "$fleet.new" "$fleet"
rm -rf "$SA_FAKE/machines/me@beta/threads"
check "a machine that does not know the thread answers no JSON: shape" "thread-unreadable shape beta" "$(reason_of "$(R)")"

# --- rethread names the new thread's environment, or clears it ---------------------
fixture
L rethread "$repo#6" --thread t-6b --worktree /wt/6b --branch feat/x-6 --environment env-c >/dev/null
check "rethread --environment records the new environment" env-c "$(L get "$repo#6" | jq -r .environment_id)"
L rethread "$repo#6" --thread t-6c --worktree /wt/6c --branch feat/x-6 >/dev/null
check "rethread without it puts the entry back on this machine" null "$(L get "$repo#6" | jq -c .environment_id)"

# --- watch reads a remote thread every poll, like a local one -----------------------
fixture
R >/dev/null
rm -f "$SA_FAKE/ssh-calls"
check "a quiet poll times out" timeout "$(W --timeout 0 | jq -r .event)"
check "one poll is one SSH call per machine" "alpha=1 me@beta=1" "$(ssh_calls)"
sa_machine_thread alpha t-8 idle 2 0 /wt/8 feat/x-8 "done for now" 2020-01-01T00:00:00Z
out=$(W --timeout 5)
check "a remote thread that finished wakes watch" "$repo#8 run-finished" "$(jq -r '[.key, .event] | join(" ")' <<<"$out")"
check "the rest and the wake that reported it are logged" "rest wake $repo#8 alpha 2020-01-01T00:00:00Z run-finished" \
  "$(jq -sr '[.[] | select(.event == "rest" or .event == "wake")] | [(map(.event) | join(" ")), .[-1].key, .[-1].machine, .[-1].rest_at, .[-1].reported] | join(" ")' "$tmp/remote-watch.jsonl")"
R >/dev/null
sa_machine_thread alpha t-9 running 1 1 /wt/9 feat/x-9
check "a permission hold on a remote thread wakes watch" "$repo#9 pending-approval" "$(W --timeout 5 | jq -r '[.key, .event] | join(" ")')"

# --- a machine that cannot be read: GitHub still wakes its entries ------------------
fixture
for n in 6 8 9; do sa_pr_head $repo "feat/x-$n" none sha$n; done
sa_pr_head $repo feat/x-7 none sha7
R >/dev/null
check "a remote entry's baseline carries its PR's checks" none "$(L get "$repo#7" | jq -r .observed.pr.checks)"
down me@beta
check "an unreadable machine raises no thread-unreadable, its entries quiet" timeout "$(W --timeout 0 | jq -r .event)"
sa_pr_head $repo feat/x-7 open sha7; sa_checks $repo sha7 pending
out=$(W --timeout 5)
check "a PR opening on its branch still wakes watch" "$repo#7 pr-opened true" "$(jq -r '[.key, .event, .observed.stale] | join(" ")' <<<"$out")"
R >/dev/null 2>&1; L set "$repo#7" observed "$(jq -c '.observed.pr = {number: 7, state: "open", checks: "pending", head: "sha7"}' <<<"$(L get "$repo#7")" | jq -c .observed)" >/dev/null
sa_checks $repo sha7 "done"
check "the checks on its head finishing wake watch" "$repo#7 checks-finished" "$(W --timeout 5 | jq -r '[.key, .event] | join(" ")')"
sa_pr_head $repo feat/x-7 merged sha7
check "a merge wakes watch, not held for a stale status" "$repo#7 pr-merged" "$(W --timeout 5 | jq -r '[.key, .event] | join(" ")')"

# --- 300 s unreadable: one offer naming the machine, cleared by a good read --------
fixture
R >/dev/null
down me@beta
t0=2000000000
check "a first failed read starts the clock and offers nothing" timeout "$(SA_NOW=$t0 W --timeout 0 | jq -r .event)"
check "each failed read is logged with its reason" "beta ssh" "$(jq -sr '[.[] | select(.event == "unreadable")][0] | "\(.machine) \(.reason)"' "$tmp/remote-watch.jsonl")"
check "inside 300 s it still offers nothing" timeout "$(SA_NOW=$((t0 + 299)) W --timeout 0 | jq -r .event)"
out=$(SA_NOW=$((t0 + 300)) W --timeout 0); rc=$?
check_rc "at 300 s the watcher exits" 0 "$rc"
check "with one offer naming the machine" "machine-unreadable beta ssh" "$(jq -r '"\(.event) \(.machine) \(.reason)"' <<<"$out")"
check "a restarted watcher does not offer it again" timeout "$(SA_NOW=$((t0 + 900)) W --timeout 0 | jq -r .event)"
up me@beta
check "the next good read clears it silently" "timeout false" "$(SA_NOW=$((t0 + 960)) W --timeout 0 | jq -r .event) $([ -e "$led.ssh-down" ] && echo true || echo false)"
down me@beta
SA_NOW=$((t0 + 1000)) W --timeout 0 >/dev/null
check "a later outage is timed afresh" timeout "$(SA_NOW=$((t0 + 1200)) W --timeout 0 | jq -r .event)"
check "and offered once more past 300 s" machine-unreadable "$(SA_NOW=$((t0 + 1300)) W --timeout 0 | jq -r .event)"

# --- usage -----------------------------------------------------------------------
out=$(R --remote env-a=dir 2>/dev/null); rc=$?
check_rc "--remote is gone: a usage error" 2 "$rc"
out=$(L add --repo $repo --number 10 --thread t --worktree w --branch b --environment 2>/dev/null); rc=$?
check_rc "--environment on add needs a value" 2 "$rc"
check "and it answers the usage line" "usage: ledger" "$(jq -r .error <<<"$out" | cut -d' ' -f1-2)"

finish
