#!/usr/bin/env bash
# update-skills' drift-body mechanic over fixture plans: the `## Drift` table
# step 7 and the upstream-drift workflow write, and whether it differs from an
# issue body's current one. No call in this file reaches a host or the network.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

body=skills/update-skills/scripts/drift-body.sh
usage='usage: drift-body <plan-file> [--current <body-file>]'
A=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa; B=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
C=cccccccccccccccccccccccccccccccccccccccc

tmp=$(mktemp -d) || exit 2
trap 'rm -rf "$tmp"' EXIT

# --help and the malformed calls: the usage line, exit 0 and exit 2.
out=$(bash "$body" --help 2>"$tmp/err"); rc=$?
check "--help opens with its usage" "$usage" "$(sed -n 1p <<<"$out")"
check "--help names its stdout fields next" stdout: "$(sed -n 2p <<<"$out" | cut -c1-7)"
check_rc "--help exits 0" 0 "$rc"
check "--help writes nothing on stderr" "" "$(cat "$tmp/err")"
out=$(bash "$body" 2>/dev/null); rc=$?
check "a bare call answers its usage line" "$usage" "$(jq -r .error <<<"$out")"
check_rc "a bare call exits 2" 2 "$rc"
out=$(bash "$body" -x 2>/dev/null); rc=$?
check "a leading-dash plan answers its usage line" "$usage" "$(jq -r .error <<<"$out")"
check_rc "a leading-dash plan exits 2" 2 "$rc"
out=$(bash "$body" p --current 2>/dev/null); rc=$?
check_rc "--current with no value exits 2" 2 "$rc"
out=$(bash "$body" p --x 2>/dev/null); rc=$?
check_rc "an unknown flag exits 2" 2 "$rc"

# A source-repo plan: one composed drift row and two others rows, one of them
# installed unpinned, given out of skill order.
cat > "$tmp/source.json" <<EOF
{"mode": "source",
 "drift": [{"skill": "tdd", "pin": "$A", "head": "$B"}],
 "others": [{"skill": "wayfinder", "source": "o/r", "old_ref": "$A", "head": "$C", "install": "x"},
            {"skill": "grilling", "source": "o/r", "old_ref": null, "head": "$C", "install": "x"}]}
EOF
table="| Skill | Pinned | Upstream head |
|---|---|---|
| grilling | unpinned | \`$C\` |
| tdd | \`$A\` | \`$B\` |
| wayfinder | \`$A\` | \`$C\` |"
out=$(bash "$body" "$tmp/source.json"); rc=$?
check_rc "a source plan exits 0" 0 "$rc"
check "a source plan tables drift and others rows, by skill" "$table" "$(jq -r .table <<<"$out")"
check "a source plan counts every row" 3 "$(jq -r .rows <<<"$out")"
check "with no --current the table is changed" true "$(jq -r .changed <<<"$out")"

# A consumer plan: its others rows are the consumer's own installs, which the
# public source repo's issue never carries.
jq '.mode = "consumer"' "$tmp/source.json" > "$tmp/consumer.json"
out=$(bash "$body" "$tmp/consumer.json")
check "a consumer plan tables only its drift rows" 1 "$(jq -r .rows <<<"$out")"
check "a consumer plan leaves the others rows out" "| tdd | \`$A\` | \`$B\` |" "$(jq -r .table <<<"$out" | sed -n 3p)"

# Nothing moved: no rows and no table.
echo '{"mode": "source", "drift": [], "others": []}' > "$tmp/none.json"
out=$(bash "$body" "$tmp/none.json")
check "a plan with nothing moved has no rows" 0 "$(jq -r .rows <<<"$out")"
check "a plan with nothing moved has no table" "" "$(jq -r .table <<<"$out")"

# --current: the issue body as the workflow wrote it, then the same with
# trailing spaces and a CRLF a web edit leaves, with decoys outside the Drift
# section and inside a <details> record in it.
printf '## Drift\n\n%s\n\n## Moving the pins\n\nA Ship run moves these pins.\n' "$table" > "$tmp/same.md"
out=$(bash "$body" "$tmp/source.json" --current "$tmp/same.md"); rc=$?
check_rc "a --current read exits 0" 0 "$rc"
check "the same table is unchanged" false "$(jq -r .changed <<<"$out")"
{ echo '## Drifted'; echo; echo '| decoy | x | y |'; echo
  printf '## Drift\r\n\r\n'; sed 's/$/  /' <<<"$table"; echo
  echo '<details><summary>Original</summary>'; echo; echo '| old | x | y |'; echo '</details>'; echo
  echo '## Moving the pins'; echo; echo '| another | x | y |'; } > "$tmp/decoys.md"
out=$(bash "$body" "$tmp/source.json" --current "$tmp/decoys.md")
check "trailing blanks, CRLF and rows outside the section leave it unchanged" false "$(jq -r .changed <<<"$out")"

# One row moved: changed.
sed "s/| tdd | \`$A\` | \`$B\` |/| tdd | \`$A\` | \`$C\` |/" "$tmp/same.md" > "$tmp/moved.md"
out=$(bash "$body" "$tmp/source.json" --current "$tmp/moved.md")
check "a moved row is changed" true "$(jq -r .changed <<<"$out")"
# A row gone: changed.
grep -v '^| wayfinder' "$tmp/same.md" > "$tmp/fewer.md"
out=$(bash "$body" "$tmp/source.json" --current "$tmp/fewer.md")
check "a missing row is changed" true "$(jq -r .changed <<<"$out")"
# No Drift section, only a heading that contains the word: changed.
printf '## Drifted\n\n%s\n' "$table" > "$tmp/nosection.md"
out=$(bash "$body" "$tmp/source.json" --current "$tmp/nosection.md")
check "a body with no Drift section is changed" true "$(jq -r .changed <<<"$out")"
# An indented heading is no heading.
printf '  ## Drift\n\n%s\n' "$table" > "$tmp/indented.md"
out=$(bash "$body" "$tmp/source.json" --current "$tmp/indented.md")
check "an indented Drift heading is no section" true "$(jq -r .changed <<<"$out")"

# Unreadable inputs answer exit 1, never a table.
out=$(bash "$body" "$tmp/nope.json" 2>/dev/null); rc=$?
check_rc "an unreadable plan exits 1" 1 "$rc"
check "an unreadable plan names it" "cannot read plan: $tmp/nope.json" "$(jq -r .error <<<"$out")"
echo '{"mode": "source"}' > "$tmp/partial.json"
out=$(bash "$body" "$tmp/partial.json" 2>/dev/null); rc=$?
check_rc "a plan with no drift array exits 1" 1 "$rc"
out=$(bash "$body" "$tmp/source.json" --current "$tmp/nope.md" 2>/dev/null); rc=$?
check_rc "an unreadable --current exits 1" 1 "$rc"
check "an unreadable --current names it" "cannot read body: $tmp/nope.md" "$(jq -r .error <<<"$out")"

finish
