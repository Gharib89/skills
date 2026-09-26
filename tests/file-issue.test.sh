#!/usr/bin/env bash
# file-issue driven end to end over the Host fake (tests/host-fake.sh), for
# --repo: a Ship defect filed at the source repo from a consumer repo whose
# origin may name another host (ADR 0004). The candidate matcher itself is
# tests/file-issue-candidates.test.sh's subject.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

mech=$PWD/skills/ship/scripts/file-issue.sh
usage='usage: file-issue [--repo <owner>/<repo>] --title "<title>" --body-file <path> --label <marker> [--distinct-from <n>[,<n>]]'
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
repo=$work/repo; export SHIP_FAKE=$work/fake
mkdir -p "$repo" "$SHIP_FAKE"
git -C "$repo" init -q
git -C "$repo" remote add origin https://dev.azure.com/org/proj/_git/repo
export SHIP_HOST_ADAPTER=$PWD/tests/host-fake.sh
file=$work/body.md
printf 'the defect\n' > "$file"

run()   { ( cd "$repo" && bash "$mech" "$@" 2>/dev/null ); }
reset() { rm -f "$SHIP_FAKE"/*; }

check "a --repo that is not owner/repo is the usage error" "$usage" \
  "$(run --repo nope --title t --body-file "$file" --label needs-triage | jq -r .error)"
check "a bare --repo is the usage error" "$usage" \
  "$(run --title t --body-file "$file" --label needs-triage --repo | jq -r .error)"

reset
printf '[]\n' > "$SHIP_FAKE/host_issues_open.1.json"
jq -n '{number: 9, url: "https://github.com/Gharib89/skills/issues/9"}' > "$SHIP_FAKE/host_issue_create.1.json"
out=$(run --repo Gharib89/skills --title "poll-pr misses a round" --body-file "$file" --label needs-triage); rc=$?
check_rc "a --repo file exits 0" 0 "$rc"
check "and files" 'true 9' "$(jq -r '"\(.filed) \(.number)"' <<<"$out")"
check "on GitHub, at the named repo, from an Azure DevOps origin" \
  'github Gharib89/skills' "$(cat "$SHIP_FAKE/loaded")"
check "proving the host answers, then the candidate check, then the create" \
  'host_identity host_issues_open host_issue_create' "$(cut -f1 "$SHIP_FAKE/calls" | paste -sd' ')"

reset
: > "$SHIP_FAKE/host_identity.1.fail"
out=$(run --repo Gharib89/skills --title "poll-pr misses a round" --body-file "$file" --label needs-triage); rc=$?
check_rc "an unreachable --repo host exits 1" 1 "$rc"
check "with the command to run by hand, quoted as a shell reads it" \
  "$mech --repo Gharib89/skills --title poll-pr\\ misses\\ a\\ round --body-file $file --label needs-triage" \
  "$(jq -r .command <<<"$out")"
check "and nothing listed or filed" 'host_identity' "$(cut -f1 "$SHIP_FAKE/calls")"

# Without --repo the run's own origin is the host, and no reachability probe
# stands in front of the list: an unreachable host there is the run's own stop.
git -C "$repo" remote set-url origin https://github.com/owner/repo.git
reset
printf '[]\n' > "$SHIP_FAKE/host_issues_open.1.json"
out=$(run --title "poll-pr misses a round" --body-file "$file" --label needs-triage); rc=$?
check_rc "an origin file exits 0" 0 "$rc"
check "at the origin's repo" 'github owner/repo' "$(cat "$SHIP_FAKE/loaded")"
check "with no reachability probe" 'host_issues_open host_issue_create' "$(cut -f1 "$SHIP_FAKE/calls" | paste -sd' ')"

finish
