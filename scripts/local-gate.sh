#!/usr/bin/env bash
# Local gate: every check this repo runs before a PR opens.
# Written by setup-skills; owned by the repo. Ship never edits it.
#
#   scripts/local-gate.sh [--small <node>] [--base <ref>]
#
# Contract (ship's local-gate contract, the same in every repo):
#   stdout: one JSON object, {"verdict","base","lane","gates":{<name>:<status>}}
#   stderr: a failing gate's last 40 log lines, never the full log
#   exit:   0 every gate passed · 1 a gate failed · 2 tooling
#   gate status: pass | fail | deferred-to-ci | unavailable
#   verdict: pass | fail | unavailable; fail wins over unavailable
#   `secrets` is required in every lane. Base defaults to origin/HEAD.
#
# The repo's one CI leg, `bump-guard`, reads the PR title rather than the diff,
# so no gate here is ever `deferred-to-ci`: this script is the whole automated
# check on a diff. Every gate is repo-wide and takes seconds, so `--small`
# records the lane and narrows nothing.
set -uo pipefail

small="" base=""
while [ $# -gt 0 ]; do
  case $1 in
    --small) [ $# -ge 2 ] || { printf '{"error":"--small needs a test node"}\n'; exit 2; }; small=$2; shift 2 ;;
    --base)  [ $# -ge 2 ] || { printf '{"error":"--base needs a ref"}\n'; exit 2; }; base=$2; shift 2 ;;
    *) printf '{"error":"unknown flag: %s"}\n' "$1"; exit 2 ;;
  esac
done
[ "${BASH_VERSINFO[0]}" -ge 4 ] || { echo '{"error":"bash 4+ required (associative arrays); macOS: brew install bash"}'; exit 2; }
command -v jq >/dev/null || { echo '{"error":"jq not installed"}'; exit 2; }
cd "$(git rev-parse --show-toplevel 2>/dev/null)" || { echo '{"error":"not inside a git checkout"}'; exit 2; }
if [ -z "$base" ]; then
  base=$(git symbolic-ref -q refs/remotes/origin/HEAD 2>/dev/null) \
    || { echo '{"error":"cannot resolve origin/HEAD; run git remote set-head origin -a or pass --base"}'; exit 2; }
  base=${base#refs/remotes/}
fi
lane=full; [ -z "$small" ] || lane=small

declare -A gates
log=$(mktemp); trap 'rm -f "$log"' EXIT
run()  { local name=$1; shift; if "$@" >"$log" 2>&1; then gates[$name]=pass; else gates[$name]=fail; tail -n 40 "$log" >&2; fi; }
mark() { gates[$1]=$2; }
# run_or_unavailable: as run, but the check's exit 2, a tool it could not obtain,
# grades `unavailable` rather than `fail`.
run_or_unavailable() {
  local name=$1 rc; shift
  "$@" >"$log" 2>&1; rc=$?
  case $rc in 0) gates[$name]=pass; return ;; 2) gates[$name]=unavailable ;; *) gates[$name]=fail ;; esac
  tail -n 40 "$log" >&2
}

# --- gates ---------------------------------------------------------------------

# secrets: required in every lane.
if command -v gitleaks >/dev/null; then
  run secrets gitleaks detect --no-banner --redact --log-opts="$base..HEAD"
else
  mark secrets unavailable
fi

# derived-copies: this repo is both the source of the shared skills and a
# consumer of them, so `.claude/skills/<n>` must be the bytes of `skills/<n>`.
# A change to a skill that was not followed by the refresh line fails here.
derived_copies() {
  local s rc=0
  for s in ship cloud-ship setup-skills; do
    [ -d ".claude/skills/$s" ] || { echo "missing derived copy: .claude/skills/$s"; rc=1; continue; }
    diff -rq "skills/$s" ".claude/skills/$s" || rc=1
    # diff -rq compares content only. A mechanic that loses its executable bit
    # on one side passes that check and then fails at run time, so compare the
    # set of executable files too.
    diff <(cd "skills/$s" && find . -type f -perm -u+x | sort) \
         <(cd ".claude/skills/$s" && find . -type f -perm -u+x | sort) \
      || { echo "executable bits differ between skills/$s and .claude/skills/$s"; rc=1; }
  done
  jq -e '.skills | has("ship") and has("cloud-ship") and has("setup-skills")' skills-lock.json >/dev/null \
    || { echo "skills-lock.json does not record all three self-installed skills"; rc=1; }
  # The profile schema number across its three files: scripts/profile-schema-check.sh.
  scripts/profile-schema-check.sh || rc=1
  return $rc
}

run derived-copies derived_copies

# version-lines: `metadata.version` is the release run's to write, from the squash
# subject's Conventional-Commit type, so a PR that moves one either loses to that
# run or collides with another PR on the same line. `metadata.profile-schema`
# stays a hand edit and is exempt. scripts/version-line-check.sh is the whole rule.
run version-lines scripts/version-line-check.sh "$base"

# The `shellcheck` gate: the source tree's scripts plus this gate itself,
# through a system `shellcheck` when one is on PATH and `npx` otherwise.
# A missing shellcheck is `unavailable`, not a lint finding;
# scripts/shellcheck-check.sh is the whole rule, and exits 2 for that case.
run_or_unavailable shellcheck scripts/shellcheck-check.sh

# house-style: the standards doc bans em dashes in files this repo authors.
# A written standard nothing enforces drifts, so enforce it, under any locale.
# The same files carry no trailing space or tab and end in a newline, which a
# derived repo's stock whitespace hooks demand of the copies it installs;
# scripts/house-style-check.sh is the whole rule.
run house-style scripts/house-style-check.sh

# prose-budget: ship's own documents, whose shape decides what a run reads
# before it acts. `skills/*/SKILL.md` at most 400 lines, and every
# `skills/*/reference/*.md` over 100 lines opening with a `## Contents` heading
# inside its first 15 lines whose list matches the file's `## ` headings;
# scripts/prose-budget-check.sh is the whole rule.
run prose-budget scripts/prose-budget-check.sh

# stray-files: a tracked path outside the top-level entries this repo owns, which
# is what a `git add -A` sweeps in and what a diff-shaped review misses.
# scripts/stray-file-check.sh carries the allowlist.
run stray-files scripts/stray-file-check.sh

# contract: the mechanics' malformed-invocation contract, their --help contract,
# and the Bash 3.2 target over the whole skills tree. Every mechanic answers a
# malformed invocation with one JSON error object and exit 2 and `--help` with its
# usage line and exit 0, and nothing a consumer installs uses a Bash 4
# builtin outside the setup-skills local-gate template, which carries its own
# version guard; nothing else in the tree holds a new mechanic to either. Reaches no
# host: each guard fires before the adapter loads.
run contract scripts/contract-check.sh skills/ship/scripts skills

# tests: the pure transformations the mechanics were refactored around, run
# with no host call. A regression is caught here rather than by a reviewer.
run tests tests/run.sh

# --- end gates -----------------------------------------------------------------

verdict=pass
for s in "${gates[@]}"; do
  case $s in
    fail) verdict=fail ;;
    unavailable) [ "$verdict" = fail ] || verdict=unavailable ;;
  esac
done
case $verdict in pass) rc=0 ;; fail) rc=1 ;; *) rc=2 ;; esac

for k in "${!gates[@]}"; do printf '%s\t%s\n' "$k" "${gates[$k]}"; done \
  | jq -Rs --arg v "$verdict" --arg b "$base" --arg l "$lane" \
      '{verdict: $v, base: $b, lane: $l,
        gates: (split("\n") | map(select(. != "") | split("\t") | {(.[0]): .[1]}) | add // {})}'
exit $rc
