#!/usr/bin/env bash
# update-skills names the preflight reasons a refresh expects from its own run.
# Preflight reads `existing branch` from the remote, and `isolate` creates the
# branch locally, so before step 8 pushes it the run's own reasons are
# `worktree exists` alone. A reading of prose: every sentence of the skill that
# names `existing branch` must admit it only once or after a push, so a
# negated sentence (before the push, until it pushes) fails. Reads files only;
# no call here reaches a host.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

# Prints each sentence naming `existing branch` that does not wait for a push.
unpushed_branch_claims() {
  tr '\n' ' ' <"$1" | sed 's/\. /.\n/g' | grep -F '`existing branch`' | grep -vE '(once|after) [^.]*push'
}

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
printf 'Expected:\nthis run'"'"'s `existing branch` and `worktree exists`.\n' >"$tmp/old.md"
printf 'Expected: `worktree exists`, and `existing branch` once\nthe branch is pushed.\n' >"$tmp/new.md"
printf 'Expected: `worktree exists`, and `existing branch` before\nthe branch is pushed.\n' >"$tmp/negated.md"

check "fixture: the unpushed pair is caught" 1 "$(unpushed_branch_claims "$tmp/old.md" | wc -l)"
check "fixture: a branch tied to a push passes" "" "$(unpushed_branch_claims "$tmp/new.md")"
check "fixture: a branch expected before the push is caught" 1 "$(unpushed_branch_claims "$tmp/negated.md" | wc -l)"
check "update-skills expects no unpushed branch" "" "$(unpushed_branch_claims skills/update-skills/SKILL.md)"

finish
