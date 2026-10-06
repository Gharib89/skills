#!/usr/bin/env bash
# read-pr driven end to end over the Host fake (tests/host-fake.sh): a
# throwaway repo whose origin names GitHub so host detection still runs, and
# SHIP_HOST_ADAPTER points ship_load_host at the fake instead of host/github.sh.
# The subject is the mechanic's own envelope: the PR object unchanged, and a
# host that cannot answer at all reading as tooling (exit 2), not a verdict.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

mech=$PWD/skills/ship/scripts/read-pr.sh
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
repo=$work/repo; export SHIP_FAKE=$work/fake
mkdir -p "$repo" "$SHIP_FAKE"
git -C "$repo" init -q
git -C "$repo" remote add origin https://github.com/owner/repo.git
export SHIP_HOST_ADAPTER=$PWD/tests/host-fake.sh

run()   { ( cd "$repo" && bash "$mech" "$@" ); }
reset() { rm -f "$SHIP_FAKE"/*; }

reset
out=$(run 7); rc=$?
check_rc "a read that lands exits 0" 0 "$rc"
check "the PR object comes back unchanged" 'fix: a fake PR' "$(jq -r .title <<<"$out")"
check "the call the mechanic hands the host" $'host_pr_get\t7' "$(cat "$SHIP_FAKE/calls")"

reset
: > "$SHIP_FAKE/host_pr_get.1.fail"
out=$(run 7 2>/dev/null); rc=$?
check_rc "a read the host cannot answer is tooling, not a verdict" 2 "$rc"
check "and it names the PR it could not read" 'cannot read PR 7' "$(jq -r .error <<<"$out")"

# headings and missing: the body's own `## ` headings, and the headings of the
# profile's `## PR` Template: the body lacks. Fenced and <details> headings are
# not sections (ship_body_headings), and the template path is relative to the
# checkout root. With no profile, `Template: None.` or no such file, missing is [].
mkdir -p "$repo/docs/agents" "$repo/.github"
printf '## Summary\n\n## Evidence\n\n## Merge Danger\n' > "$repo/.github/pull_request_template.md"
profile() { printf '## Host\n\nHost: github\n\n## PR\n\n%s\n\n## Public surface\n' "$1" > "$repo/docs/agents/ship.md"; }
pr_body() { # <body>
  jq -n --arg b "$1" '{number:7,url:"u",title:"t",body:$b,head_sha:"d",head_ref:"h",base_ref:"main",draft:false,state:"open",mergeable:"clean"}' \
    > "$SHIP_FAKE/host_pr_get.1.json"
}
body=$'intro\n\n## Summary\nx\n\n```\n## Merge Danger\n```\n\n## Evidence\ny\n'

reset; rm -f "$repo/docs/agents/ship.md"; pr_body "$body"
out=$(run 7)
check "the body's headings are listed in order" '["Summary","Evidence"]' "$(jq -c .headings <<<"$out")"
check "no profile means nothing is missing" '[]' "$(jq -c .missing <<<"$out")"
check "the PR object's own fields are still there" 'fix: a fake PR' "$(jq -r .title <<<"$(reset; run 7)")"

reset; profile 'Template: .github/pull_request_template.md'; pr_body "$body"
check "a template heading the body lacks is missing; a fenced one is not a section" '["Merge Danger"]' \
  "$(run 7 | jq -c .missing)"

reset; profile 'Template: .github/pull_request_template.md'; pr_body $'## Summary\n## Evidence\n## Merge Danger\n'
check "a body with every heading misses none" '[]' "$(run 7 | jq -c .missing)"

reset; profile 'Template: None.'; pr_body "$body"
check "Template: None. means nothing is missing" '[]' "$(run 7 | jq -c .missing)"

reset; profile 'Template: .github/absent.md'; pr_body "$body"
check "a template file that is not there is null, not a complete body's []" 'null' "$(run 7 | jq -c .missing)"
check "and the rest of the answer still stands" '["Summary","Evidence"]' "$(run 7 | jq -c .headings)"

if [ "$(id -u)" -ne 0 ]; then
  reset; profile 'Template: .github/pull_request_template.md'; pr_body "$body"
  chmod 000 "$repo/.github/pull_request_template.md"
  check "a template file that cannot be read is null" 'null' "$(run 7 | jq -c .missing)"
  chmod 644 "$repo/.github/pull_request_template.md"
else
  echo "skip: an unreadable template (root reads past chmod 000)"
fi

finish
