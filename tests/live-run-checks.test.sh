#!/usr/bin/env bash
# scripts/live-run-checks.sh: the happy-path verdict of Ship's live run, read
# from records alone. The seam is its CLI: a Run file, the host state the driver
# fetched (issue assignees, open PRs with their bodies) and the issue number in,
# with the PR template in PR_TEMPLATE; one failed check per stdout line and an
# exit code out.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

# check-pr-body.sh reads `Closes #N` titles through `gh`, as evidence only; a
# `gh` that fails quietly keeps this file off the host.
mkdir "$T/nogh"
printf '#!/bin/sh\nexit 127\n' > "$T/nogh/gh"
chmod +x "$T/nogh/gh"
export PATH="$T/nogh:$PATH"

export PR_TEMPLATE=$T/template.md
printf 'Closes #\n\n## Why\n\n## Attribution\n' > "$PR_TEMPLATE"

# A Run file at the merge gate: every phase before it closed or skipped.
good_run() {
  cat <<'RUN'
# ship run · 7

- [x] 0 · Isolate: preflight (10:00→10:01)
- [x] 1 · Understand: claim (10:01→10:02)
- [x] 2 · Implement: classify (10:02→10:05)
- [x] 3 · Verify: none skipped (no verification applies)
- [x] 4 · Docs-sync + self-review: review (10:05→10:09)
- [x] 5 · Local gate: gate (10:09→10:10)
- [x] 6 · Open PR: open (10:10→10:11)
- [x] 7 · Reviewers: none skipped (no reviewer)
- [x] 8 · CI: ci (10:11→10:11)
- [ ] 9 · Merge gate: summary in_progress (10:11→)
RUN
}
good_body='Closes #7\n\n## Why\n\nBecause.\n\n## Attribution\n\nfooter\n'
# <assignees json> <bodies...>: a host-state file, one open PR per body.
host_of() {
  local a=$1 f; shift
  f=$(mktemp "$T/host.XXXXXX")
  printf '%s\n' "$@" | jq -Rn --argjson a "$a" \
    '{assignees: $a, open_prs: [inputs | {number: 1, body: (. | gsub("\\\\n"; "\n"))}]}' > "$f"
  printf '%s' "$f"
}
# <run text> <host file>: the script's stdout, then its exit code on the last line.
verdict() {
  printf '%s\n' "$1" > "$T/run.md"
  bash scripts/live-run-checks.sh "$T/run.md" "$2" 7 2>/dev/null
  printf 'rc=%s\n' "$?"
}

host_ok=$(host_of '["agent"]' "$good_body")

check "a run at the merge gate passes" "rc=0" "$(verdict "$(good_run)" "$host_ok")"
check "a closed merge gate passes" "rc=0" \
  "$(verdict "$(good_run | sed 's/^- \[ \] 9 · Merge gate: summary in_progress (10:11→)/- [x] 9 · Merge gate: summary (10:11→10:12)/')" "$host_ok")"

check "a phase left open is named" "phase 5: not closed
rc=1" "$(verdict "$(good_run | sed 's/^- \[x\] 5 · Local gate: gate (10:09→10:10)/- [ ] 5 · Local gate: gate/')" "$host_ok")"

check "a phase opened before its predecessor is named" "phase 6: closed out of order
rc=1" "$(verdict "$(good_run | sed 's/(10:10→10:11)/(10:04→10:11)/')" "$host_ok")"

check "a run that never reached the merge gate is named" "merge gate: not reached
rc=1" "$(verdict "$(good_run | sed 's/ in_progress (10:11→)//')" "$host_ok")"

check "an unassigned issue is named" "issue: not claimed
rc=1" "$(verdict "$(good_run)" "$(host_of '[]' "$good_body")")"

check "no PR closing the issue is named" "pr: 0 open PRs close #7, want 1
rc=1" "$(verdict "$(good_run)" "$(host_of '["agent"]' 'Closes #8\n')")"

# Which PR closes the issue is read the way Ship reads it (ship_body_closes):
# a keyword form, the list form; not a longer number, a bare mention or a span.
closes() { verdict "$(good_run)" "$(host_of '["agent"]' "$1\n\n## Why\n\nx\n\n## Attribution\n")" | head -n 1; }
check "Fixes closes the issue" "rc=0" "$(closes 'Fixes #7')"
check "the list form closes the issue" "rc=0" "$(closes 'Closes #3, #7')"
check "a longer number does not close it" "pr: 0 open PRs close #7, want 1" "$(closes 'Closes #70')"
check "a bare mention does not close it" "pr: 0 open PRs close #7, want 1" "$(closes 'See #7')"
check "a code span does not close it" "pr: 0 open PRs close #7, want 1" "$(closes '`Closes #7`')"

# The clock wraps at midnight: a later phase may start at a smaller HH:MM.
check "a run across midnight passes" "rc=0" "$(verdict "$(good_run \
  | sed -e 's/(10:00→10:01)/(23:50→23:51)/' -e 's/(10:01→10:02)/(23:51→23:52)/' \
        -e 's/(10:02→10:05)/(23:52→00:05+1d)/')" "$host_ok")"

# A re-opened phase carries a second range; its first start is what orders it.
check "a re-opened phase passes" "rc=0" "$(verdict "$(good_run \
  | sed -e 's/(10:02→10:05)/(10:02→10:05) (10:20→10:22)/' -e 's/(10:10→10:11)/(10:22→10:23)/' -e 's/(10:11→10:11)/(10:23→10:24)/')" "$host_ok")"

# Only the trailing run of ranges is time, as run-file reads it: a range inside
# a skip reason is wording and orders nothing.
check "a range inside a skip reason passes" "rc=0" "$(verdict "$(good_run \
  | sed 's/none skipped (no verification applies)/none skipped (covered by the phase 2 run (10:30→10:31) above)/')" "$host_ok")"

check "two PRs closing the issue are named" "pr: 2 open PRs close #7, want 1
rc=1" "$(verdict "$(good_run)" "$(host_of '["agent"]' "$good_body" "$good_body")")"

check "a body the PR check refuses is named" "pr body: pr-body: missing heading: ## Why
rc=1" "$(verdict "$(good_run)" "$(host_of '["agent"]' 'Closes #7\n\n## Attribution\n')")"

check "every failed check is named, not only the first" "phase 1: not closed
phase 5: not closed
issue: not claimed
rc=1" "$(verdict "$(good_run | sed 's/^- \[x\] \([15]\) · \([^:]*\): \([a-z]*\) ([0-9:→]*)/- [ ] \1 · \2: \3/')" "$(host_of '[]' "$good_body")")"

check_rc "a missing Run file is a failed check, not tooling" 1 \
  "$(bash scripts/live-run-checks.sh "$T/nope.md" "$host_ok" 7 >/dev/null 2>&1; printf '%s' "$?")"
check "a missing Run file is named" "run file: missing" \
  "$(bash scripts/live-run-checks.sh "$T/nope.md" "$host_ok" 7 2>/dev/null)"

# Host state of the wrong shape is a failed read, not a verdict.
printf '%s' '{"assignees": ["agent"], "open_prs": null}' > "$T/host-null.json"
check_rc "a null open_prs is tooling" 2 \
  "$(verdict "$(good_run)" "$T/host-null.json" | tail -n 1 | sed 's/^rc=//')"
printf '%s' '{"assignees": true, "open_prs": []}' > "$T/host-bool.json"
check_rc "a non-array assignees is tooling" 2 \
  "$(verdict "$(good_run)" "$T/host-bool.json" | tail -n 1 | sed 's/^rc=//')"

# --ambiguous: the early stop on a vague issue. The reply names the stop, the
# host shows no claim, no PR closing the issue and no branch of the run, and a
# Run file, where there is one, shows no work past phase 1.
stop_run() {
  cat <<'RUN'
# ship run · 7

- [ ] 0 · Isolate: preflight in_progress (10:00→)
- [ ] 1 · Understand: claim
- [ ] 2 · Implement: classify
- [ ] 3 · Verify: none
- [ ] 4 · Docs-sync + self-review: review
- [ ] 5 · Local gate: gate
- [ ] 6 · Open PR: open
- [ ] 7 · Reviewers: none
- [ ] 8 · CI: ci
- [ ] 9 · Merge gate: summary
RUN
}
stopped='Stopped `ambiguous` on issue 7, with no claim taken.'
# <assignees json> <branches json> [<body> [<reply>]]: no body, no open PR.
amb_host() {
  local f
  f=$(mktemp "$T/host.XXXXXX")
  jq -n --argjson a "$1" --argjson b "$2" --arg body "${3:-}" --arg r "${4-$stopped}" '{assignees: $a,
    branches: $b, reply: $r,
    open_prs: (if $body == "" then [] else [{number: 1, body: ($body | gsub("\\\\n"; "\n"))}] end)}' > "$f"
  printf '%s' "$f"
}
amb() {
  printf '%s\n' "$1" > "$T/run.md"
  bash scripts/live-run-checks.sh --ambiguous "$T/run.md" "$2" 7 2>/dev/null
  printf 'rc=%s\n' "$?"
}
amb_ok=$(amb_host '[]' '[]' '')

check "an ambiguous stop in phase 0 passes" "rc=0" "$(amb "$(stop_run)" "$amb_ok")"
check "an ambiguous stop in phase 1 passes" "rc=0" "$(amb "$(stop_run | sed \
  -e 's/^- \[ \] 0 · Isolate: preflight in_progress (10:00→)/- [x] 0 · Isolate: preflight (10:00→10:01)/' \
  -e 's/^- \[ \] 1 · Understand: claim/- [ ] 1 · Understand: claim in_progress (10:01→)/')" "$amb_ok")"
check "an early stop with no Run file passes" "rc=0" \
  "$(bash scripts/live-run-checks.sh --ambiguous "$T/nope.md" "$amb_ok" 7 2>/dev/null; printf 'rc=%s\n' "$?")"
check "a PR that only mentions the issue still passes" "rc=0" \
  "$(amb "$(stop_run)" "$(amb_host '[]' '[]' 'See #7\n')")"
check "a reply naming another stop is named" "stop: the reply does not name ambiguous
rc=1" "$(amb "$(stop_run)" "$(amb_host '[]' '[]' '' 'Stopped `nothing-ready`.')")"
check "an empty reply is named" "stop: the reply does not name ambiguous
rc=1" "$(amb "$(stop_run)" "$(amb_host '[]' '[]' '' '')")"
check "a longer word is not the stop name" "stop: the reply does not name ambiguous
rc=1" "$(amb "$(stop_run)" "$(amb_host '[]' '[]' '' 'The issue is unambiguous.')")"
check "a claim is named" "issue: claimed
rc=1" "$(amb "$(stop_run)" "$(amb_host '["agent"]' '[]' '')")"
check "a PR closing the issue is named" "pr: 1 open PRs close #7, want 0
rc=1" "$(amb "$(stop_run)" "$(amb_host '[]' '[]' "$good_body")")"
check "a pushed branch is named" "branch: feat/x-7 pushed
rc=1" "$(amb "$(stop_run)" "$(amb_host '[]' '["feat/x-7"]' '')")"
check "a run that went past phase 1 is named" "phase 1: closed
phase 2: opened
rc=1" "$(amb "$(stop_run | sed -e 's/^- \[ \] 1 · Understand: claim/- [x] 1 · Understand: claim (10:01→10:02)/' \
  -e 's/^- \[ \] 2 · Implement: classify/- [ ] 2 · Implement: classify in_progress (10:02→)/')" "$amb_ok")"
check "a skipped later phase is named" "phase 3: opened
rc=1" "$(amb "$(stop_run | sed 's/^- \[ \] 3 · Verify: none/- [x] 3 · Verify: none skipped (docs)/')" "$amb_ok")"
check_rc "ambiguous host state without branches or reply is tooling" 2 \
  "$(amb "$(stop_run)" "$host_ok" | tail -n 1 | sed 's/^rc=//')"

finish
