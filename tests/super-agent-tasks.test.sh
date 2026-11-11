#!/usr/bin/env bash
# super-agent watches every thread it launches, whatever its kind (#1146): the
# ledger's `task` kind and `adopt` form, `reconcile`'s close rule for a task and
# its `unqueued` list, the record step's refusal, and the status block's rows,
# through the command lines over fake `t3` and `gh` on PATH
# (tests/super-agent-fake.sh). A remote entry's wakes are in super-agent-remote.
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
fleet=$tmp/fleet.json
repo=Gharib89/skills
L() { bash "$s/ledger.sh" --ledger "$led" "$@"; }
R() { bash "$s/reconcile.sh" --ledger "$led" "$@"; }
S() { bash "$s/status.sh" --ledger "$led" "$@"; }
fresh() { rm -rf "$led" "$SA_FAKE"; mkdir -p "$SA_FAKE/threads" "$SA_FAKE/gh"; }

# --- a task entry needs no issue number --------------------------------------------
fresh
out=$(L add --task grill-auth --thread t-g --worktree /wt/g --branch grill/auth); rc=$?
check_rc "add --task exits 0" 0 "$rc"
check "its key is task:<slug>" task:grill-auth "$(jq -r .key <<<"$out")"
check "it is kind task, with no repo and no number, not adopted" "task null null false" \
  "$(jq -r '.entry | [.kind, (.repo | tostring), (.number | tostring), (.adopted | tostring)] | join(" ")' <<<"$out")"
check "get reads it back by its key" t-g "$(L get task:grill-auth | jq -r .thread)"
check "list holds it" task:grill-auth "$(L list --open | jq -r '.entries[].key')"
out=$(L add --task grill-auth --thread t-2 --worktree /wt/g2 --branch b 2>/dev/null); rc=$?
check_rc "a second add of an open task refuses" 1 "$rc"
out=$(L rethread task:grill-auth --thread t-g2 --worktree /wt/g2 --branch grill/auth)
check "rethread takes it to a fresh thread" "t-g2 launched" "$(jq -r '.entry | [.thread, .stage] | join(" ")' <<<"$out")"
L add --task bare --thread t-b >/dev/null; rc=$?
check_rc "a task may hold no worktree and no branch" 0 "$rc"
L add --task a/b --thread t >/dev/null 2>&1; rc=$?
check_rc "add --task a/b is a usage error" 2 "$rc"
L add --task grill --number 4 --thread t >/dev/null 2>&1; rc=$?
check_rc "add --task grill --number 4 is a usage error" 2 "$rc"
L add --task grill --kind ship --thread t >/dev/null 2>&1; rc=$?
check_rc "add --task grill --kind ship is a usage error" 2 "$rc"
L add --repo $repo --number 9 --thread t --worktree w --branch b --kind task >/dev/null 2>&1; rc=$?
check_rc "--kind task without --task is a usage error" 2 "$rc"
out=$(L need task:grill-auth --action "answer the grill"); rc=$?
check_rc "a task can hold a need" 0 "$rc"

# --- adopt records a thread somebody else launched ----------------------------------
fresh
out=$(L adopt --task deploy-x --thread t-d --worktree /wt/d --branch deploy/x --machine alpha)
check "adopt of a task is adopted, kind task" "task true alpha null" \
  "$(jq -r '.entry | [.kind, (.adopted | tostring), .machine, (.environment_id | tostring)] | join(" ")' <<<"$out")"
out=$(L adopt --repo $repo --number 12 --thread t-s --worktree /wt/s --branch feat/s-12)
check "adopt with a ticket records a ship entry, adopted" "ship true $repo#12" \
  "$(jq -r '.entry | [.kind, (.adopted | tostring), .key] | join(" ")' <<<"$out")"
check "a launched entry is not adopted" false "$(L add --repo $repo --number 13 --thread t --worktree w --branch b | jq -r '.entry.adopted | tostring')"
sa_thread t-d running 1 0 /wt/d deploy/x
sa_thread t-s running 1 0 /wt/s feat/s-12
sa_pr $repo feat/s-12 none; sa_issue $repo 12 open
out=$(R)
check "reconcile reads an adopted task and an adopted ticket like launched ones" "running running" \
  "$(jq -r '[.entries[] | select(.key | IN("task:deploy-x", "'"$repo#12"'")) | .stage] | join(" ")' <<<"$out")"
sa_thread t-d idle 1 0 /wt/d deploy/x
out=$(bash "$s/watch.sh" --ledger "$led" --interval 1 --recheck 0 --timeout 5)
check "the watcher wakes on an adopted thread finishing" "task:deploy-x run-finished" "$(jq -r '[.key, .event] | join(" ")' <<<"$out")"

# --- a task closes on its thread's rest, never on an issue ---------------------------
fresh
L add --task review-x --thread t-r --worktree /wt/r --branch review/x --repo $repo >/dev/null
sa_pr $repo review/x merged
sa_thread t-r running 1 0 /wt/r review/x
out=$(R)
check "a running task thread stays open with its branch's PR merged" "running" "$(jq -r '.entries[0].stage' <<<"$out")"
check "and nothing settled" "0" "$(jq '.settled | length' <<<"$out")"
sa_thread t-r idle 1 0 /wt/r review/x
out=$(R)
check "a task whose thread has run and rests is settled" "task:review-x task" "$(jq -r '.settled[] | "\(.key) \(.kind)"' <<<"$out")"
check "the ledger holds it settled" settled "$(L get task:review-x | jq -r .stage)"
check "no issue was read for it" 0 "$(grep -c 'repos/.*/issues/' "$SA_FAKE/calls")"
fresh
L add --task fresh-t --thread t-f --worktree /wt/f --branch f/x >/dev/null
sa_thread t-f idle 0 0 /wt/f f/x
check "a thread that has not run yet is at rest, not settled" at-rest "$(R | jq -r '.entries[0].stage')"
sa_thread t-f idle 1 1 /wt/f f/x
check "a rest holding a permission request is not settled" at-rest "$(R | jq -r '.entries[0].stage')"
sa_thread t-f idle 1 0 /wt/f f/x
fresh
L add --task nowt --thread t-n >/dev/null
sa_thread t-n running 1 0 /anywhere x
check "a task with no worktree is matched by its thread id alone" running "$(R | jq -r '.entries[0].stage')"
L adopt --repo $repo --number 20 --thread t-20 --worktree /wt/20 --branch feat/x-20 >/dev/null
sa_thread t-20 running 1 0 /wt/20 feat/x-20; sa_pr $repo feat/x-20 none; sa_issue $repo 20 closed
check "a ticket entry still closes on its issue" "issue-closed" "$(R | jq -r '.closed[0].reason')"

# --- the record step refuses a launch with no entry ---------------------------------
fresh
out=$(bash "$s/launch.sh" record --thread t-x --ledger "$led" 2>/dev/null); rc=$?
check_rc "record with neither --launch nor --task exits 1" 1 "$rc"
check "and names the unrecorded launch" "unrecorded launch" "$(jq -r .error <<<"$out" | cut -d: -f1)"
check "the ledger was not written" no "$([ -f "$led" ] && echo yes || echo no)"
sa_thread t-t running 1 0 /wt/t grill/t
out=$(bash "$s/launch.sh" record --task grill-t --thread t-t --ledger "$led" --branch grill/t 2>/dev/null); rc=$?
check_rc "record --task exits 0" 0 "$rc"
check "it wrote the task entry, its worktree read from the thread" "task:grill-t /wt/t" \
  "$(jq -r '[.key, .entry.worktree] | join(" ")' <<<"$out")"
check "the baseline reconcile ran on it" "1 0" "$(jq -r '[.reconcile.checked, (.reconcile.errors | length)] | join(" ")' <<<"$out")"
check "the entry is in the ledger" t-t "$(L get task:grill-t | jq -r .thread)"
out=$(bash "$s/launch.sh" record --task grill-t --thread t-t2 --ledger "$led" --worktree /wt/t 2>/dev/null); rc=$?
check_rc "recording an open task twice refuses" 1 "$rc"
sa_thread t-e running 1 0 /wt/e x
out=$(bash "$s/launch.sh" record --task remote-t --thread t-e --ledger "$led" --environment env-a 2>/dev/null); rc=$?
check_rc "a remote task record with no machine is a usage error" 2 "$rc"
out=$(bash "$s/launch.sh" record --task remote-t --thread t-e --ledger "$led" --environment env-a --machine m2 2>/dev/null); rc=$?
check_rc "a remote task record needs no worktree" 0 "$rc"
check "and carries its machine" m2 "$(L get task:remote-t | jq -r .machine)"
check "and carries its environment" env-a "$(L get task:remote-t | jq -r .environment_id)"

# --- unqueued: issues filed while a batch runs ----------------------------------------
fresh
printf '{"active_repos":["%s"]}\n' $repo > "$fleet"
issues="repos/$repo/issues?state=open&sort=created&direction=desc&per_page=100"
L add --repo $repo --number 5 --thread t-5 --worktree /wt/5 --branch feat/x-5 >/dev/null
sa_thread t-5 running 1 0 /wt/5 feat/x-5; sa_pr $repo feat/x-5 none; sa_issue $repo 5 open
launched=$(L get "$repo#5" | jq -r .launched_at)
early=$(date -u -d "$launched - 1 day" +%Y-%m-%dT%H:%M:%SZ)
late=$(date -u -d "$launched + 1 hour" +%Y-%m-%dT%H:%M:%SZ)
sa_route "$issues" "$(jq -cn --arg e "$early" --arg l "$late" '[
  {number: 5, title: "held by an entry", created_at: $l},
  {number: 30, title: "filed during the batch", created_at: $l},
  {number: 31, title: "older than the batch", created_at: $e},
  {number: 32, title: "a pull request", created_at: $l, pull_request: {}},
  {number: 33, title: "claimed by a super agent", created_at: $l},
  {number: 34, title: "waiting for a machine", created_at: $l},
  {number: 35, title: "a task of a repo no entry names", created_at: $l}]')"
sa_route "repos/$repo/issues/30/comments?per_page=100" '[{"body":"a human comment"}]'
sa_route "repos/$repo/issues/33/comments?per_page=100" '[{"body":"<!-- super-agent-claim machine=ribo thread=x -->\nClaimed."}]'
sa_route "repos/$repo/issues/34/comments?per_page=100" '[]'
sa_route "repos/$repo/issues/35/comments?per_page=100" '[]'
L wait "$repo#34" --reason "no machine fits" >/dev/null
L adopt --task other --thread t-o --worktree /wt/o --branch o/x >/dev/null
sa_thread t-o running 1 0 /wt/o o/x
out=$(R --fleet "$fleet")
check "reconcile prints the issues nothing holds, once" "$repo#30 $repo#35" "$(jq -r '[.unqueued[].key] | join(" ")' <<<"$out")"
check "each carries its title" "filed during the batch" "$(jq -r '.unqueued[0].title' <<<"$out")"
check "the ledger remembers what it offered" "$repo#30 $repo#35" "$(jq -r '.unqueued_offered | join(" ")' "$led")"
out=$(R --fleet "$fleet")
check "a later run leaves the offered ones out" "0" "$(jq '.unqueued | length' <<<"$out")"
sa_route "$issues" "$(jq -cn --arg l "$late" '[{number: 36, title: "filed later", created_at: $l}]')"
sa_route "repos/$repo/issues/36/comments?per_page=100" '[]'
check "a new issue is offered on its own" "$repo#36" "$(R --fleet "$fleet" | jq -r '[.unqueued[].key] | join(" ")')"
check "without --fleet it lists none" "0" "$(R | jq '.unqueued | length')"
sa_route "repos/$repo/issues/37/comments?per_page=100" 'x'
sa_route "$issues" "$(jq -cn --arg l "$late" '[{number: 37, title: "claim unreadable", created_at: $l}]')"
out=$(R --fleet "$fleet")
check "a claim read that fails is an error, and the issue is not offered" "0 $repo#37 claim-unreadable" \
  "$(jq -r '[(.unqueued | length), .errors[0].key, .errors[0].kind] | join(" ")' <<<"$out")"
sa_route "repos/$repo/issues/38/comments?per_page=100" "$(jq -cn '[range(100) | {body: "c"}]')"
sa_route "$issues" "$(jq -cn --arg l "$late" '[{number: 38, title: "full page", created_at: $l}]')"
out=$(R --fleet "$fleet")
check "a full page of comments is an error, not an unclaimed issue" "0 $repo#38 claim-unreadable" \
  "$(jq -r '[(.unqueued | length), .errors[0].key, .errors[0].kind] | join(" ")' <<<"$out")"
rm -f "$SA_FAKE/gh/$(printf '%s' "$issues" | sed 's/[^A-Za-z0-9._-]/_/g')"
out=$(R --fleet "$fleet")
check "a repo whose issues cannot be read is an error" "$repo repo-unreadable" "$(jq -r '.errors[0] | "\(.key) \(.kind)"' <<<"$out")"
# no batch running: nothing open, so nothing is unqueued
fresh
sa_route "$issues" '[{"number": 40, "title": "x", "created_at": "2099-01-01T00:00:00Z"}]'
check "with no entry open there is no batch to file against" "0" "$(R --fleet "$fleet" | jq '.unqueued | length')"
out=$(R --fleet "$tmp/none.json" 2>/dev/null); rc=$?
check_rc "an unreadable fleet file is a usage error" 2 "$rc"

# --- the status block shows task and adopted entries ----------------------------------
fresh
L add --task grill-auth --thread t-g --worktree /wt/g --branch grill/auth >/dev/null
L adopt --task deploy-x --thread t-d --worktree /wt/d --branch deploy/x >/dev/null
L adopt --repo $repo --number 12 --thread t-s --worktree /wt/s --branch feat/s-12 >/dev/null
L add --repo $repo --number 13 --thread t-13 --worktree /wt/13 --branch feat/x-13 >/dev/null
L need task:grill-auth --action "answer the grill" >/dev/null
block=$(S | jq -r .block)
check "a task reads task:<slug> (task) in Running" "yes" "$(grep -q 'task:grill-auth (task) launched' <<<"$block" && echo yes || echo no)"
check "an adopted task says so" "yes" "$(grep -q 'task:deploy-x (task) (adopted) launched' <<<"$block" && echo yes || echo no)"
check "an adopted ticket is a link with its mark" "yes" "$(grep -q '\[skills#12\](https://github.com/Gharib89/skills/issues/12) (adopted) launched' <<<"$block" && echo yes || echo no)"
check "a launched ticket carries no mark" "yes" "$(grep -q '\[skills#13\](https://github.com/Gharib89/skills/issues/13) launched' <<<"$block" && echo yes || echo no)"
check "a task's need names its key, not a link" "yes" "$(grep -q '^Needs you (1): task:grill-auth answer the grill' <<<"$block" && echo yes || echo no)"
L set task:grill-auth stage '"settled"' >/dev/null
check "a settled task is no Merged row" "no" "$(S --digest | jq -r .block | grep -q '^Merged' && echo yes || echo no)"

finish
