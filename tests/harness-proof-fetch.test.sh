#!/usr/bin/env bash
# skills/setup-harness/reference/cloud.md `## Recording the proof`: a re-run
# fetches a `Proof: <sha>` the clone does not hold before calling it unproven.
# A squash merge leaves the proven setup-branch head off the default branch,
# reachable on GitHub only from `refs/pull/<n>/head`, which a clone never
# fetches (#579). The origin here is a bare repo serving reachable shas, as
# GitHub does; the fetch is the command cloud.md gives, as written there.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

fixture=$(mktemp -d); trap 'rm -rf "$fixture"' EXIT
g() { git -C "$1" -c user.name=t -c user.email=t@t "${@:2}"; }

fetch=$(sed -n 's/.*`\(git fetch -q origin <sha>\)`.*/\1/p' skills/setup-harness/reference/cloud.md)
check "cloud.md gives the fetch of a missing proof sha" 1 "$(printf '%s\n' "$fetch" | grep -c .)"

# The setup branch: the proven commit, the proof commit on top, then squashed
# onto main and deleted, so only refs/pull/1/head reaches the proven sha.
w=$fixture/work
git init -q -b main "$w"
g "$w" commit -q --allow-empty -m base
g "$w" checkout -q -b setup
echo hook > "$w/check.sh"; g "$w" add check.sh; g "$w" commit -q -m setup
sha=$(g "$w" rev-parse HEAD)
g "$w" commit -q --allow-empty -m proof
g "$w" checkout -q main
git clone -q --bare "$w" "$fixture/origin.git"
git -C "$fixture/origin.git" config uploadpack.allowReachableSHA1InWant true
git -C "$fixture/origin.git" update-ref refs/pull/1/head setup
git -C "$fixture/origin.git" branch -q -D setup
# file:// so the clone goes through upload-pack rather than copying objects.
git clone -q "file://$fixture/origin.git" "$fixture/clone"
c=$fixture/clone

check_rc "a fresh clone lacks the proof sha" 1 "$(git -C "$c" cat-file -e "$sha" 2>/dev/null; echo $?)"
(cd "$c" && eval "${fetch//<sha>/$sha}") 2>/dev/null
check_rc "the fetch brings it from refs/pull" 0 "$(git -C "$c" cat-file -e "$sha^{commit}" 2>/dev/null; echo $?)"
(cd "$c" && eval "${fetch//<sha>/0000000000000000000000000000000000000001}") 2>/dev/null
check_rc "a sha no ref reaches fails the fetch" 128 "$?"

finish
