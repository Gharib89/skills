#!/usr/bin/env bash
# Local gate over the harness: the repo's `check.sh full`, plus the gates only
# Ship needs. Written by setup-skills where the repo has a harness profile
# (docs/agents/harness.md); owned by the repo from here.
#
#   scripts/local-gate.sh [--small <node>] [--base <ref>]
#   --help or -h prints that usage line and exits 0, before any check runs.
#
# Contract (ship's local-gate contract, the same in every repo):
#   stdout: one JSON object, {"verdict","base","lane","gates":{<name>:<status>}}
#   stderr: a failing gate's last 40 log lines, and the last 40 lines of
#           check.sh's own stderr unless check.sh answered a clean pass
#   exit:   0 every gate passed · 1 a gate failed · 2 tooling
#   gate status: pass | fail | deferred-to-ci | unavailable
#   verdict: pass | fail | unavailable; fail wins over unavailable
#   `secrets` is required in every lane. Base defaults to origin/HEAD.
#
# check.sh owns every check it runs, each one a gate of the same name here. This
# file owns only what check.sh cannot know: `secrets` over base..HEAD and
# `version-lines`, both relative to the base. The one CI leg, `bump-guard`, reads
# the PR title and body, so no gate is ever `deferred-to-ci`; this repo has no
# dependencies, so no `deps` gate. `--small` runs check.sh's own `FULL_ROWS`
# checks in place of `check.sh full`, which leaves out only its `runner`, the
# linters, that the edit and commit hooks run on every change.
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
put()  { gates=$(jq -c --arg k "$1" --arg v "$2" '. + {($k): $v}' <<<"$gates"); }
run()  { local name=$1; shift; if "$@" >"$log" 2>&1; then put "$name" pass; else put "$name" fail; tail -n 40 "$log" >&2; fi; }
mark() { put "$1" "$2"; }   # mark <name> deferred-to-ci|unavailable

# --- gates ---------------------------------------------------------------------
# secrets: required in every lane. Wired to the scanner setup-skills detected;
# `unavailable` here stops the first attended run and names what to add.
if command -v gitleaks >/dev/null; then
  run secrets gitleaks detect --no-banner --redact --log-opts="$base..HEAD"
else
  mark secrets unavailable
fi

if [ "$lane" = small ]; then
  # FULL_ROWS is read from check.sh's configuration block, so the two lanes
  # cannot drift; each row is `<name>|<command>`, the command may hold a `|`.
  # The row data is check.sh's; the runner is not, and covers the parts of
  # check.sh's own that a row's result rests on: exit 127 is `unavailable`, a
  # LOCAL_ONLY row is skipped (read as `pass`) in a cloud session, a command
  # gets no stdin, which would otherwise drain the rows still to come, and it
  # runs under `-u` and `pipefail` as check.sh does. No deadline here.
  eval "$(sed -n '/^# >>> setup-harness configuration/,/^# <<< setup-harness configuration/p' scripts/check.sh)"
  if [ -z "${FULL_ROWS:-}" ]; then
    mark check unavailable
    echo "check.sh carries no FULL_ROWS block between its setup-harness configuration markers" >&2
  fi
  while IFS='|' read -r name cmd; do
    [ -n "$name" ] || continue
    if [ "${CLAUDE_CODE_REMOTE:-}" = true ]; then
      case " ${LOCAL_ONLY:-} " in *" $name "*) put "$name" pass; continue ;; esac
    fi
    bash -uo pipefail -c "$cmd" </dev/null >"$log" 2>&1; rc=$?
    case $rc in
      0) put "$name" pass ;;
      127) put "$name" unavailable; tail -n 40 "$log" >&2 ;;
      *) put "$name" fail; tail -n 40 "$log" >&2 ;;
    esac
  done <<<"${FULL_ROWS:-}"
else
  # No CHECK_DEADLINE: `full` is measured only, and a deadline would have
  # check.sh skip whatever it had not reached.
  (unset CHECK_DEADLINE; exec scripts/check.sh full) >"$log" 2>"$err"; rc=$?
  # 0 to 3 all carry the one JSON line (2 is a check unavailable, 3 over
  # budget), so an unavailable tool still names its own check; a stdout outside
  # the contract (the usage path, not a git repo) leaves nothing to map, which
  # the jq guard catches. A status outside the gate vocabulary reads as
  # unavailable.
  if [ "$rc" -le 3 ] && parsed=$(jq -sce 'select(length == 1) | .[0].checks | objects
      | map_values(if . == "skipped" then "pass" elif . == "pass" or . == "fail" or . == "unavailable" then . else "unavailable" end)' \
      "$log" 2>/dev/null); then
    checks=$parsed
    [ "$rc" -eq 0 ] || tail -n 40 "$err" >&2
  else
    mark check unavailable
    tail -n 40 "$err" >&2
  fi
fi

# version-lines: `metadata.version` is the release run's to write, from the squash
# subject's Conventional-Commit type, so a PR that moves one either loses to that
# run or collides with another PR on the same line. `metadata.profile-schema`
# stays a hand edit and is exempt. scripts/version-line-check.sh is the whole
# rule, and it needs the base, so check.sh cannot run it. Every lane.
run version-lines scripts/version-line-check.sh "$base"
# --- end gates -----------------------------------------------------------------

# A name both report keeps the worse status, so neither side can mask a failure.
gates=$(jq -c --argjson c "$checks" '
  def rank: {"pass": 0, "deferred-to-ci": 1, "unavailable": 2, "fail": 3}[.];
  reduce ($c | to_entries[]) as $e (.; .[$e.key] = ([.[$e.key] // "pass", $e.value] | max_by(rank)))' <<<"$gates")
verdict=$(jq -r 'if any(.[]; . == "fail") then "fail" elif any(.[]; . == "unavailable") then "unavailable" else "pass" end' <<<"$gates")
case $verdict in pass) rc=0 ;; fail) rc=1 ;; *) rc=2 ;; esac
jq -cn --arg v "$verdict" --arg b "$base" --arg l "$lane" --argjson g "$gates" \
  '{verdict: $v, base: $b, lane: $l, gates: $g}'
exit $rc
