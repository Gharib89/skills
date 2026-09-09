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
# This repo has no CI, so no gate is ever `deferred-to-ci`: the gate is the
# whole check. All three gates are repo-wide and take seconds, so `--small`
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
  done
  jq -e '.skills | has("ship") and has("cloud-ship") and has("setup-skills")' skills-lock.json >/dev/null \
    || { echo "skills-lock.json does not record all three self-installed skills"; rc=1; }
  return $rc
}
run derived-copies derived_copies

# shellcheck: the source tree's scripts plus this gate. The derived copies are
# covered by `derived-copies` proving them identical. -P SCRIPTDIR resolves the
# `source "$(dirname ...)/_lib.sh"` idiom the mechanics use.
lint() {
  local files
  mapfile -t files < <(git ls-files 'skills/*.sh' 'skills/**/*.sh' 'scripts/*.sh')
  [ ${#files[@]} -gt 0 ] || { echo "no shell scripts tracked"; return 1; }
  npx -y shellcheck -x -s bash -P SCRIPTDIR -S warning "${files[@]}"
}
if command -v npx >/dev/null; then
  run shellcheck lint
else
  mark shellcheck unavailable
fi

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
