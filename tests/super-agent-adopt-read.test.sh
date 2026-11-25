#!/usr/bin/env bash
# "Watch <thread>" (#1381): `ledger adopt --read <file>` fills an entry from one
# `t3_thread_read` of a thread the super agent did not launch: its worktree, branch and
# the ticket from the first message, the repo from the worktree's github.com `origin`
# remote. The adoption starts the clock (`launched_at`,
# `held_since`, pinned here through SA_NOW), posts the claim for a ship thread, and a
# second adoption of the same thread leaves one entry. Fake `gh` is on PATH.
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
repo=acme/widgets
L() { SA_NOW=1795000000 bash "$s/ledger.sh" --ledger "$led" "$@"; }
# the worktree is a real checkout whose `origin` names the repo
git init -q "$tmp/wt" && git -C "$tmp/wt" remote add origin "git@github.com:$repo.git"
read_of() { # <first message> [<worktree>]
  jq -cn --arg w "${2:-$tmp/wt}" --arg f "$1" '
    {thread: {threadId: "th-ext", status: "idle", runCount: 2, worktreePath: $w, branch: "feat/x-7",
       settled: false},
     items: [{position: 3, type: "assistant_message", createdBy: "agent", text: "on it", updatedAt: "2026-11-20T10:05:00.000Z"},
             {position: 1, type: "user_message", createdBy: "user", text: $f, updatedAt: "2026-11-20T10:00:00.000Z"}],
     hasMore: false}' > "$tmp/read.json"
}
sa_route user '{"login":"octo"}'; sa_route "repos/$repo/issues/7/comments" '[]'
L self th-super >/dev/null

read_of '/ship-run 7'
out=$(L adopt --read "$tmp/read.json"); rc=$?
check_rc "adopt --read of a ship thread exits 0" 0 "$rc"
check "the entry is filled from the one read: key, thread, worktree, branch, kind" \
  "$repo#7 th-ext $tmp/wt feat/x-7 ship true" \
  "$(jq -r '.entry | "\(.key) \(.thread) \(.worktree) \(.branch) \(.kind) \(.adopted)"' <<<"$out")"
check "no pull request is read: reconcile finds it by the branch" false "$(jq '.entry | has("adopted_pr")' <<<"$out")"
iso=$(printf '@1795000000' | xargs -I{} date -u -d {} +%Y-%m-%dT%H:%M:%SZ)
check "the clock starts at adoption: launched_at and held_since are the pinned second" "$iso $iso" \
  "$(jq -r '.entry | "\(.launched_at) \(.held_since)"' <<<"$out")"
check "the claim comment is posted for a ship thread" 1 "$(grep -c -- "-X POST.*issues/7/comments" "$SA_FAKE/calls")"
check "and its status is answered" 1 "$(jq '.claim | length > 0 | if . then 1 else 0 end' <<<"$out")"

# --- a second adoption is the same entry --------------------------------------------------
out=$(L adopt --read "$tmp/read.json"); rc=$?
check_rc "adopting a thread the ledger holds exits 0" 0 "$rc"
check "it answers the existing entry" "true $repo#7" "$(jq -r '"\(.existing) \(.key)"' <<<"$out")"
check "the ledger still holds one entry" 1 "$(L list | jq '.entries | length')"
check "and no second claim was posted" 1 "$(grep -c -- "-X POST.*issues/7/comments" "$SA_FAKE/calls")"

# --- a triage thread, and a thread that is neither -----------------------------------------
read_of '/triage 9'; jq '.thread.threadId = "th-tri" | .thread.branch = "triage-9"' "$tmp/read.json" > "$tmp/r2" && mv "$tmp/r2" "$tmp/read.json"
out=$(L adopt --read "$tmp/read.json")
check "a /triage thread is a triage entry on the same repo, with no claim" "$repo#9 triage null" "$(jq -r '"\(.entry.key) \(.entry.kind) \(.claim // "null")"' <<<"$out")"
read_of 'help me with the build'; jq '.thread.threadId = "th-free"' "$tmp/read.json" > "$tmp/r2" && mv "$tmp/r2" "$tmp/read.json"
out=$(L adopt --read "$tmp/read.json" 2>/dev/null); rc=$?
check_rc "a thread whose first message is no ticket call is refused" 2 "$rc"
out=$(L adopt --read "$tmp/read.json" --task build-help); rc=$?
check "with --task it is a task entry" "0 task:build-help task" "$rc $(jq -r '"\(.key) \(.entry.kind)"' <<<"$out")"
check "a read that is no t3_thread_read result is refused" 2 "$(echo '{}' > "$tmp/bad.json"; L adopt --read "$tmp/bad.json" >/dev/null 2>&1; echo $?)"

# --- a thread an entry holds is not adopted as another ticket ---------------------------------------------
read_of '/ship-run 8'
out=$(L adopt --read "$tmp/read.json" 2>&1); rc=$?
check "a read naming another ticket than the holder's is refused, naming the holder" "1 1" "$rc $(grep -q "held by $repo#7" <<<"$out" && echo 1)"
read_of '/ship-run 7'
check "so is a --number that is not the holder's" 1 "$(L adopt --read "$tmp/read.json" --repo $repo --number 8 >/dev/null 2>&1; echo $?)"
check "and a --task for a ticket's thread" 1 "$(L adopt --read "$tmp/read.json" --task other >/dev/null 2>&1; echo $?)"
check "the holder's own ticket is adopted again" 0 "$(L adopt --read "$tmp/read.json" --repo $repo --number 7 >/dev/null 2>&1; echo $?)"

# --- the repo comes from a github.com origin only ----------------------------------------------------------
for url in 'https://x-access-token:abc@github.com/o/r.git' 'https://dev.azure.com/org/proj/_git/repo'; do
  git init -q "$tmp/wt2" 2>/dev/null; git -C "$tmp/wt2" remote remove origin 2>/dev/null; git -C "$tmp/wt2" remote add origin "$url"
  read_of '/ship-run 11' "$tmp/wt2"; jq '.thread.threadId = "th-url"' "$tmp/read.json" > "$tmp/r2" && mv "$tmp/r2" "$tmp/read.json"
  out=$(L adopt --read "$tmp/read.json" 2>&1); rc=$?
  check "an origin of $url is refused, naming --repo" "2 1" "$rc $(grep -q -- '--repo' <<<"$out" && echo 1)"
done
git -C "$tmp/wt2" remote remove origin; git -C "$tmp/wt2" remote add origin https://github.com/acme/widgets/
sa_route "repos/$repo/issues/11/comments" '[]'
check "a plain https github.com origin, with a trailing slash, names the repo" "$repo#11" "$(L adopt --read "$tmp/read.json" | jq -r .key)"

# --- the read must be the thread's first page ----------------------------------------------------------------
read_of '/ship-run 12'; jq '.thread.threadId = "th-later" | .earlierPosition = 4' "$tmp/read.json" > "$tmp/r2" && mv "$tmp/r2" "$tmp/read.json"
check "a read with an earlier page is refused" 2 "$(L adopt --read "$tmp/read.json" >/dev/null 2>&1; echo $?)"

# --- a ticket's thread started without a /ship-run call: --number stands in for the first message ---------------
sa_route "repos/$repo/issues/5/comments" '[]'
read_of 'please fix the bug'; jq '.thread.threadId = "th-hand"' "$tmp/read.json" > "$tmp/r2" && mv "$tmp/r2" "$tmp/read.json"
out=$(L adopt --read "$tmp/read.json" --repo $repo --number 5 --kind ship); rc=$?
check "--repo, --number and --kind adopt it, as the refusal's advice says" "0 $repo#5 ship" "$rc $(jq -r '"\(.key) \(.entry.kind)"' <<<"$out")"

finish
