#!/usr/bin/env bash
# update-skills names the preflight reasons a refresh expects from its own run.
# Preflight reads `existing branch` from the remote, and `isolate` creates the
# branch locally; no preflight runs after step 8 pushes it, so the run's own
# reasons are `worktree exists` alone. A reading of prose: no line of the skill
# names `existing branch`, and its Verification item names the expected
# `worktree exists` reason. Reads files only; no call here reaches a host.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

skill=skills/update-skills/SKILL.md
check "update-skills expects no \`existing branch\`" "" "$(grep -nF '`existing branch`' "$skill")"
check "update-skills' Verification item names the expected worktree exists reason" 1 \
  "$(tr '\n' ' ' <"$skill" | grep -oF 'the expected `worktree exists` reason' | wc -l | tr -d ' ')"

finish
