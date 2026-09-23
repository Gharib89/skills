#!/usr/bin/env bash
# comment-issue driven end to end: the mechanic runs inside a throwaway checkout
# whose origin names GitHub, so it loads the real adapter, and the `gh` that
# adapter reaches is the fake in tests/gh-fake.sh, so nothing reaches a host.
# The subject is the verdict: a post that landed, a payload the host refused,
# and a call that got no HTTP answer must read three different ways.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
source tests/gh-fake.sh

m=$PWD/skills/ship/scripts/comment-issue.sh
tmp=$(mktemp -d) || exit 2
trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp/bin" "$tmp/repo"
gh_fake_install "$tmp/bin"
git -C "$tmp/repo" init -q && git -C "$tmp/repo" remote add origin https://github.com/owner/repo.git
printf 'a later finding\n' > "$tmp/body"

run() { (cd "$tmp/repo" && bash "$m" "$@" 2>/dev/null); }
posts() { grep -cF '"body": "a later finding"' "$GH_LOG"; }

out=$(run); rc=$?
check_rc "a bare call is tooling" 2 "$rc"
check "a bare call answers its usage line" \
  'usage: comment-issue <issue> --body-file <path>' "$(jq -r .error <<<"$out")"
check_rc "a missing body file is tooling" 2 "$(run 7 --body-file "$tmp/absent" >/dev/null; echo $?)"
check_rc "an issue that is not a number is tooling" 2 "$(run abc --body-file "$tmp/body" >/dev/null; echo $?)"

gh_reset; export GH_STATUS_SEQ="201"
out=$(run 7 --body-file "$tmp/body"); rc=$?
check_rc "a post that lands exits 0" 0 "$rc"
check "a post that lands answers posted" '{"issue":7,"posted":true}' "$(jq -c . <<<"$out")"
check "a post that lands is posted once, carrying the file's body" \
  1 "$(posts)"

gh_reset; export GH_STATUS_SEQ="422"
out=$(run 7 --body-file "$tmp/body"); rc=$?
check_rc "a refused post exits 1" 1 "$rc"
check "a refused post answers not posted, with the host's status" \
  'false 422' "$(jq -r '"\(.posted) \(.status)"' <<<"$out")"

# A 5xx may have landed the comment anyway, so the POST is not retried blind: a
# create re-reads the comments first, and here the re-read fails too, which
# answers unknown rather than posting a second time. The attempts are the
# identity read, the POST and the re-read.
gh_reset; export GH_STATUS_SEQ="200 500 500"
out=$(run 7 --body-file "$tmp/body"); rc=$?
check_rc "a post the host answered 5xx exits 1" 1 "$rc"
check "a post the host answered 5xx is not posted twice" 1 "$(posts)"
check "a post the host answered 5xx carries the POST's status" \
  'false 500' "$(jq -r '"\(.posted) \(.status)"' <<<"$out")"

gh_reset; export GH_STATUS_SEQ="none"
out=$(run 7 --body-file "$tmp/body"); rc=$?
check_rc "a post with no HTTP answer exits 1" 1 "$rc"
check "a post with no HTTP answer carries a null status" \
  'false null' "$(jq -r '"\(.posted) \(.status)"' <<<"$out")"

finish
