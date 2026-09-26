#!/usr/bin/env bash
# update-issue-body's guards, then the mechanic driven end to end over the Host
# fake (tests/host-fake.sh) in a throwaway repo whose origin names GitHub. The
# guard cases are malformed, so they answer before `ship_load_host`; the rest
# hold the envelope: a section replaced or created, `sections[]` read off the
# body written, a body the adapter refuses to edit, and a write the host refuses.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
T=$'\t'  # the calls log separates arguments with a tab

mech=$PWD/skills/ship/scripts/update-issue-body.sh
usage='usage: update-issue-body <issue> [--repo <owner>/<repo>] --section <name> --body-file <path>'

err() { bash "$mech" "$@" 2>/dev/null | jq -r '.error'; }
rc()  { bash "$mech" "$@" >/dev/null 2>&1; echo $?; }

check "a bare invocation prints the usage line" "$usage" "$(err)"
check "a flag in the issue slot is the usage error" "$usage" "$(err --section X --body-file /dev/null)"
check "no --section is the usage error" "$usage" "$(err 7 --body-file /dev/null)"
check_rc "no --section is tooling" 2 "$(rc 7 --body-file /dev/null)"
# Section-only by design: a whole-body or preamble write is not a mode here.
check "--preamble is an unknown flag" 'unknown flag: --preamble' "$(err 7 --preamble --body-file /dev/null)"
check_rc "--preamble is tooling" 2 "$(rc 7 --preamble --body-file /dev/null)"
check "a flag in the section slot is the usage error" "$usage" \
  "$(err 7 --section --body-file /dev/null)"

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
printf '```diff\n- before\n' > "$work/open-fence.md"
check "a body file whose fence ends open is refused, naming the fence" \
  'body file ends inside an unclosed fence (line 1: ```)' \
  "$(err 7 --section X --body-file "$work/open-fence.md")"

repo=$work/repo; export SHIP_FAKE=$work/fake
mkdir -p "$repo" "$SHIP_FAKE"
git -C "$repo" init -q
git -C "$repo" remote add origin https://github.com/owner/repo.git
export SHIP_HOST_ADAPTER=$PWD/tests/host-fake.sh
file=$work/section.md
printf 'new decision\n' > "$file"

run()   { ( cd "$repo" && bash "$mech" "$@" ); }
reset() { rm -f "$SHIP_FAKE"/*; }

reset
jq -n '{body: "lede\n\n## Decisions\n\nold\n\n## Fog\n\nopen\n"}' > "$SHIP_FAKE/host_issue_body.1.json"
out=$(run 7 --section Decisions --body-file "$file"); rc=$?
check_rc "a section replaced exits 0" 0 "$rc"
check "and says so" '7 Decisions true false' \
  "$(jq -r '[.issue, .section, .replaced, .created] | @tsv' <<<"$out" | tr '\t' ' ')"
check "sections[] reads the body written" '["Decisions","Fog"]' "$(jq -c .sections <<<"$out")"
check "the sequence is read, then write" "host_issue_body${T}7" "$(head -1 "$SHIP_FAKE/calls")"
check "the write is the issue's" "host_issue_set_body${T}7" "$(sed -n 2p "$SHIP_FAKE/calls" | cut -f1,2)"

reset
jq -n '{body: "lede\n\n## Fog\n\nopen\n"}' > "$SHIP_FAKE/host_issue_body.1.json"
out=$(run 7 --section Decisions --body-file "$file"); rc=$?
check_rc "a section created exits 0" 0 "$rc"
check "and reports created" 'false true' "$(jq -r '[.replaced, .created] | @tsv' <<<"$out" | tr '\t' ' ')"
check "at the end of the body" '["Fog","Decisions"]' "$(jq -c .sections <<<"$out")"

# The adapter's refusal carries its reason (an Azure DevOps description ship
# did not write), and nothing is written.
reset
jq -n '{reason: "the description is HTML ship did not write"}' > "$SHIP_FAKE/host_issue_body.1.json"
: > "$SHIP_FAKE/host_issue_body.1.fail"
out=$(run 7 --section Decisions --body-file "$file"); rc=$?
check_rc "a body the adapter will not edit exits 1" 1 "$rc"
check "with the adapter's reason" 'issue 7: the description is HTML ship did not write' "$(jq -r .error <<<"$out")"
check "and no write" "host_issue_body${T}7" "$(cat "$SHIP_FAKE/calls")"

reset
: > "$SHIP_FAKE/host_issue_body.1.fail"
check_rc "a read that fails with no reason is tooling" 2 "$(run 7 --section Decisions --body-file "$file" >/dev/null 2>&1; echo $?)"

reset
jq -n '{body: "## Decisions\n\nold\n"}' > "$SHIP_FAKE/host_issue_body.1.json"
: > "$SHIP_FAKE/host_issue_set_body.1.fail"
printf '502' > "$SHIP_FAKE/host_issue_set_body.1.status"
out=$(run 7 --section Decisions --body-file "$file"); rc=$?
check_rc "a write the host refuses exits 1" 1 "$rc"
check "and carries the host's status" '502' "$(jq -r .status <<<"$out")"

# `az` reports no status, so a failed write there prints nothing.
reset
jq -n '{body: "## Decisions\n\nold\n"}' > "$SHIP_FAKE/host_issue_body.1.json"
: > "$SHIP_FAKE/host_issue_set_body.1.fail"
out=$(run 7 --section Decisions --body-file "$file"); rc=$?
check_rc "a silent write failure exits 1" 1 "$rc"
check "with status null" '{"error":"issue body update failed","status":null}' "$(jq -c . <<<"$out")"

# --repo: the source repo's issue, reached from a consumer whose origin is
# another host entirely (ADR 0004).
check "a --repo that is not owner/repo is the usage error" "$usage" \
  "$(err 7 --repo nope --section X --body-file "$file")"
git -C "$repo" remote set-url origin https://dev.azure.com/org/proj/_git/repo
reset
jq -n '{body: "## Decisions\n\nold\n"}' > "$SHIP_FAKE/host_issue_body.1.json"
out=$(run 7 --repo Gharib89/skills --section Decisions --body-file "$file"); rc=$?
check_rc "a --repo write exits 0" 0 "$rc"
check "on GitHub, at the named repo" 'github Gharib89/skills' "$(cat "$SHIP_FAKE/loaded")"
check "after proving the host answers" "host_identity" "$(head -1 "$SHIP_FAKE/calls")"

reset
: > "$SHIP_FAKE/host_identity.1.fail"
out=$(run 7 --repo Gharib89/skills --section Decisions --body-file "$file"); rc=$?
check_rc "an unreachable --repo host exits 1" 1 "$rc"
check "with the command to run by hand" \
  "$mech 7 --repo Gharib89/skills --section Decisions --body-file $file" "$(jq -r .command <<<"$out")"
check "and no read or write" "host_identity" "$(cat "$SHIP_FAKE/calls")"

finish
