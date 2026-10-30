#!/usr/bin/env bash
# Local gate over the harness: the gates only Ship needs, with every check of
# the repo's `check.sh full` deferred to CI. Written by setup-skills where the
# repo has a harness profile (docs/agents/harness.md); owned by the repo from
# here.
#
#   scripts/local-gate.sh [--small <node>] [--base <ref>]
#   --help or -h prints that usage line and exits 0, before any check runs.
#
# Contract (ship's local-gate contract, the same in every repo):
#   stdout: one JSON object, {"verdict","base","lane","gates":{<name>:<status>}}
#   stderr: a failing gate's last 40 log lines, and with no scanner on PATH
#           one line naming `scripts/cloud-ship-bootstrap.sh --local`; this
#           repo's gates slot adds
#           scripts/glossary-warn.sh's `glossary:` lines and
#           scripts/context-report.sh's size lines on every run, uncapped,
#           which set no gate status
#   exit:   0 every gate passed · 1 a gate failed · 2 tooling
#   gate status: pass | fail | deferred-to-ci | unavailable
#   verdict: pass | fail | unavailable; fail wins over unavailable
#   `secrets` is required in every lane. Base defaults to origin/HEAD.
#
# This file runs only what CI cannot or must not: `secrets` over base..HEAD, so
# a secret is caught before the push to this public repo, and `version-lines`,
# which needs the base. Every check `check.sh full` would report (its `runner`,
# each TURN_ROWS member's typecheck and tests, each FULL_ROWS row) is CI's
# `check-full` leg's, which runs `check.sh full` on every PR head, so each is a
# gate of the same name here, `deferred-to-ci` and unrun. `--small` runs the
# same two gates: with the rest deferred there is nothing left to trim. This
# repo has no dependencies, so no `deps` gate.
# Bash 3.2 plus jq, so it runs on a stock macOS bash.
set -uo pipefail

small="" base=""
while [ $# -gt 0 ]; do
  case $1 in
    --small) [ $# -ge 2 ] || { printf '{"error":"--small needs a test node"}\n'; exit 2; }; small=$2; shift 2 ;;
    --base)  [ $# -ge 2 ] || { printf '{"error":"--base needs a ref"}\n'; exit 2; }; base=$2; shift 2 ;;
    -h|--help) echo 'usage: scripts/local-gate.sh [--small <node>] [--base <ref>]'; exit 0 ;;
    *) printf '{"error":"unknown flag: %s"}\n' "$1"; exit 2 ;;
  esac
done
command -v jq >/dev/null || { echo '{"error":"jq not installed"}'; exit 2; }
cd "$(git rev-parse --show-toplevel 2>/dev/null)" || { echo '{"error":"not inside a git checkout"}'; exit 2; }
if [ -z "$base" ]; then
  base=$(git symbolic-ref -q refs/remotes/origin/HEAD 2>/dev/null) \
    || { echo '{"error":"cannot resolve origin/HEAD; run git remote set-head origin -a or pass --base"}'; exit 2; }
  base=${base#refs/remotes/}
fi
# gitleaks given a range it cannot resolve scans nothing and exits 0, so an
# unresolvable base would read as a `secrets` pass.
git rev-parse --verify -q "$base^{commit}" >/dev/null \
  || { jq -cn --arg b "$base" '{error: "base \($b) is not a commit; fetch it or pass --base <ref>"}'; exit 2; }
lane=full; [ -z "$small" ] || lane=small

gates='{}' checks='{}'
log=$(mktemp) err=$(mktemp); trap 'rm -f "$log" "$err"' EXIT
# A gate written twice keeps the worse status, so no later write can mask a failure.
# shellcheck disable=SC2016 # jq's own $a and $b
worse='def worse($a; $b): [$a // "pass", $b] | max_by({"pass": 0, "deferred-to-ci": 1, "unavailable": 2, "fail": 3}[.]);'
put()  { gates=$(jq -c --arg k "$1" --arg v "$2" "$worse"' .[$k] = worse(.[$k]; $v)' <<<"$gates"); }
run()  { local name=$1; shift; if "$@" >"$log" 2>&1; then put "$name" pass; else put "$name" fail; tail -n 40 "$log" >&2; fi; }
mark() { put "$1" "$2"; }   # mark <name> deferred-to-ci|unavailable

# --- gates ---------------------------------------------------------------------
# secrets: required in every lane. Wired to the scanner setup-skills detected;
# `unavailable` here stops the first attended run and names what to add.
if command -v gitleaks >/dev/null; then
  run secrets gitleaks detect --no-banner --redact --log-opts="$base..HEAD"
else
  mark secrets unavailable
  echo 'secrets: gitleaks not on PATH; scripts/cloud-ship-bootstrap.sh --local installs it' >&2
fi

# The deferred names are read from check.sh's configuration block and named the
# way its `full` rung names them, so they cannot drift from what CI reports.
eval "$(sed -n '/^# >>> setup-harness configuration/,/^# <<< setup-harness configuration/p' scripts/check.sh)"
if [ -z "${FULL_ROWS:-}" ]; then
  mark check unavailable
  echo "check.sh carries no FULL_ROWS block between its setup-harness configuration markers" >&2
fi
[ -z "${FULL_RUN:-}" ] || mark runner deferred-to-ci
# `full` passes no files, so a member's affected tests never run there.
while IFS='|' read -r _ member _ typecheck tests _; do
  [ -n "$member" ] || continue
  [ -z "$typecheck" ] || mark "typecheck:$member" deferred-to-ci
  [ -z "$tests" ] || mark "tests:$member" deferred-to-ci
done <<<"${TURN_ROWS:-}"
while IFS='|' read -r name _; do
  [ -z "$name" ] || mark "$name" deferred-to-ci
done <<<"${FULL_ROWS:-}"

# version-lines: `metadata.version` is the release run's to write, from the squash
# subject's Conventional-Commit type, so a PR that moves one either loses to that
# run or collides with another PR on the same line. `metadata.profile-schema`
# stays a hand edit and is exempt. scripts/version-line-check.sh is the whole
# rule, and it needs the base, so check.sh cannot run it. Every lane.
run version-lines scripts/version-line-check.sh "$base"

# glossary-warn is a warning, not a gate: its hits go to stderr for the author to
# read, its exit status is ignored, and no gate status is put for it.
scripts/glossary-warn.sh "$base" >&2 || true
# context-report is the same kind: the always-on context's sizes, for the author
# to read, with no cap and no gate status.
scripts/context-report.sh >&2 || true
# --- end gates -----------------------------------------------------------------

# A name both report keeps the worse status, so neither side can mask a failure.
gates=$(jq -c --argjson c "$checks" "$worse"' reduce ($c | to_entries[]) as $e (.; .[$e.key] = worse(.[$e.key]; $e.value))' <<<"$gates")
verdict=$(jq -r 'if any(.[]; . == "fail") then "fail" elif any(.[]; . == "unavailable") then "unavailable" else "pass" end' <<<"$gates")
case $verdict in pass) rc=0 ;; fail) rc=1 ;; *) rc=2 ;; esac
jq -cn --arg v "$verdict" --arg b "$base" --arg l "$lane" --argjson g "$gates" \
  '{verdict: $v, base: $b, lane: $l, gates: $g}'
exit $rc
