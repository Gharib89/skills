#!/usr/bin/env bash
# retro-run's `retro.sh file`: the model's findings filed as one grouped issue
# labelled `needs-triage` and `retro`, less every class an earlier `retro`
# issue lists, through REST against a fake `gh` answering per endpoint.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
source tests/gh-fake.sh

s=skills/retro-run/scripts/retro.sh
tmp=$(mktemp -d) || exit 2
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"
gh_fake_install "$tmp/bin"
export GH_ROUTES=$tmp/routes
gh_reset

issues='repos/{owner}/{repo}/issues'
gh_route 'repos/{owner}/{repo}' '{"full_name": "o/r"}'
gh_route "$issues" '[
  {"number": 900, "state": "closed", "body": "Class: unpaged-list-read\n"},
  {"number": 901, "state": "open", "body": "Class: brief-path-moved\r\n"}]'
gh_route 'repos/{owner}/{repo}/labels/retro' '{"name": "retro"}'
gh_route "POST $issues" '{"number": 950, "html_url": "https://github.com/o/r/issues/950"}'

findings=$tmp/findings.json
cat > "$findings" <<'EOF'
[{"key": "stale-head", "summary": "poll-pr read a head the push had already moved", "prs": [12, 14], "site": "skill prose"},
 {"key": "unpaged-list-read", "summary": "a list read never paged", "prs": [11, 13], "site": "an automated check"},
 {"key": "missing-retry", "summary": "a REST write was not retried after a 401", "prs": [15, 16, 17], "site": "CLAUDE.md"}]
EOF

# The body of the one issue create, the last POST to the issues endpoint.
created() { gh_body_of "$(gh_args | grep -n "^api -X POST $issues\$\|^api -X POST $issues " | tail -1 | cut -d: -f1)"; }

out=$(bash "$s" file "$findings"); rc=$?
check_rc "file answers" 0 "$rc"
check "names the issue it filed" '{"issue":950,"url":"https://github.com/o/r/issues/950"}' "$(jq -c '{issue, url}' <<<"$out")"
check "the classes it filed and the one it dropped" '{"filed":["stale-head","missing-retry"],"dropped":["unpaged-list-read"]}' \
  "$(jq -c '{filed, dropped}' <<<"$out")"
check "exactly one issue created" 1 "$(gh_args | grep -c "^api -X POST $issues")"
body=$(created)
check "labelled needs-triage and retro" '["needs-triage","retro"]' "$(jq -c '.labels' <<<"$body")"
check "every kept finding's PRs in the body" 'yes' \
  "$(jq -r '.body | if test("#12, #14") and test("#15, #16, #17") then "yes" else . end' <<<"$body")"
check "each kept finding's summary and proposed site" 'yes' \
  "$(jq -r '.body | if test("poll-pr read a head") and test("skill prose") and test("CLAUDE.md") then "yes" else . end' <<<"$body")"
check "a dropped class is not in the body" '' "$(jq -r '.body | select(test("unpaged-list-read"))' <<<"$body")"
check "an existing label is not created again" '' "$(gh_args | grep -F 'labels --input')"
check "no GraphQL call" '' "$(gh_args | grep -F graphql)"

# The body's class keys round-trip: a later `candidates` reads them as filed.
gh_route "$issues" "$(jq -c '[{number: 950, state: "open", body: .body}]' <<<"$body")"
gh_route 'search/issues' '{"total_count": 0, "items": []}'
check "candidates reads the filed keys back" '["stale-head","missing-retry"]' \
  "$(bash "$s" candidates | jq -c '.filed[0].classes')"

gh_reset
rm "$GH_ROUTES/repos_{owner}_{repo}_labels_retro"
gh_route "POST repos/{owner}/{repo}/labels" '{"name": "retro"}'
out=$(bash "$s" file "$findings"); rc=$?
check_rc "a missing label is no failure" 0 "$rc"
check "the retro label is created first" 'retro' \
  "$(gh_body_of "$(gh_args | grep -n 'labels --input' | cut -d: -f1)" | jq -r .name)"
check "and the issue still filed" 950 "$(jq .issue <<<"$out")"

# Nothing left to file creates nothing.
gh_route "$issues" '[{"number": 900, "state": "closed", "body": "Class: stale-head\nClass: unpaged-list-read\nClass: missing-retry\n"}]'
for case in all-dropped empty brackets; do
  case $case in
    all-dropped) cp "$findings" "$tmp/case.json" ;;
    empty) : > "$tmp/case.json" ;;
    brackets) echo '[]' > "$tmp/case.json" ;;
  esac
  gh_reset
  out=$(bash "$s" file "$tmp/case.json"); rc=$?
  check_rc "nothing to file answers: $case" 0 "$rc"
  check "and says no issue: $case" '{"issue":null,"url":null,"filed":[]}' "$(jq -c '{issue, url, filed}' <<<"$out")"
  check "and creates nothing: $case" '' "$(gh_args | grep -F -- '-X POST')"
done
check "the dropped keys are named" '["stale-head","unpaged-list-read","missing-retry"]' \
  "$(bash "$s" file "$findings" | jq -c .dropped)"

for bad in '{"key": "a"}' '[{"key": "Not Kebab", "summary": "s", "prs": [1], "site": "x"}]' \
  '[{"key": "a", "summary": "s", "prs": [], "site": "x"}]' '[{"key": "a", "summary": "s", "prs": [1]}]' 'not json'; do
  printf '%s\n' "$bad" > "$tmp/bad.json"
  out=$(bash "$s" file "$tmp/bad.json" 2>/dev/null); rc=$?
  check_rc "a malformed findings file exits 2: $bad" 2 "$rc"
  check "naming its shape: $bad" 'findings: not a JSON array of {key, summary, prs[], site}' "$(jq -r .error <<<"$out")"
done
out=$(bash "$s" file "$tmp/absent.json" 2>/dev/null); rc=$?
check_rc "a missing findings file exits 2" 2 "$rc"
check "naming the path" "findings: cannot read $tmp/absent.json" "$(jq -r .error <<<"$out")"
for bad in 'file' "file $findings extra"; do
  # shellcheck disable=SC2086 # each case is a word list
  out=$(bash "$s" $bad 2>/dev/null); rc=$?
  check_rc "a malformed call exits 2: $bad" 2 "$rc"
done

gh_route "$issues" '[]'
rm "$GH_ROUTES/POST repos_{owner}_{repo}_issues"
out=$(bash "$s" file "$findings" 2>/dev/null); rc=$?
check_rc "a refused create exits 1" 1 "$rc"
check "naming the write" 'creating the issue: gh: Not Found (HTTP 404)' "$(jq -r .error <<<"$out")"

finish
