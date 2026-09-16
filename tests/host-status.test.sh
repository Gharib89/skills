#!/usr/bin/env bash
# The failure verdict of a PR write carries the HTTP status of the last attempt
# (#173). Two candidate explanations, a payload the host will not take and a
# host that is briefly down, produced the identical verdict, and a run spent
# four minutes bisecting a valid body because of it. Every case here drives the
# adapter against the fake `gh` in tests/gh-fake.sh, so none reaches a host.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
source tests/gh-fake.sh
SHIP_OWNER=owner SHIP_REPO=repo
source skills/ship/scripts/_lib.sh
source skills/ship/scripts/host/github.sh

sleep() { :; }

bin=$(mktemp -d); trap 'rm -rf "$bin"' EXIT
gh_fake_install "$bin"
body=$bin/body; printf 'a body\n' > "$body"

status_of() { jq -r '.status // "null"' <<<"$1" 2>/dev/null; }

# The reported case: an empty 500 body, where gh's own stderr is a JSON parse
# error and not a status line, so the status has to come from the headers.
gh_reset; export GH_STATUS_SEQ="500"
out=$(host_pr_set_body 7 "$body" 2>/dev/null); rc=$?
check_rc "a failed body write fails"                   1 "$rc"
check    "a failed body write carries the status"      500 "$(status_of "$out")"

gh_reset; export GH_STATUS_SEQ="422"
out=$(host_pr_set_body 7 "$body" 2>/dev/null); rc=$?
check    "a refused payload carries its own status"    422 "$(status_of "$out")"

# No HTTP answer at all: there is no status to report, and a guessed one would
# be worse than none.
gh_reset; export GH_STATUS_SEQ="none"
out=$(host_pr_set_body 7 "$body" 2>/dev/null); rc=$?
check_rc "a write with no HTTP answer fails"           1 "$rc"
check    "a write with no HTTP answer carries null"    null "$(status_of "$out")"

gh_reset; export GH_STATUS_SEQ="200"
out=$(host_pr_set_body 7 "$body" 2>/dev/null); rc=$?
check_rc "a successful body write succeeds"            0 "$rc"
check    "a successful body write prints nothing"      "" "$out"

gh_reset; export GH_STATUS_SEQ="503"
out=$(host_pr_set_title 7 "a title" 2>/dev/null); rc=$?
check_rc "a failed title write fails"                  1 "$rc"
check    "a failed title write carries the status"     503 "$(status_of "$out")"

# The creates go through _gh_create_verify: the identity read succeeds, then
# every attempt after it is the outage. The status reported is the failed
# POST's, which is the write, even though the re-read that follows it failed too.
gh_reset; export GH_STATUS_SEQ="200 500"
out=$(host_pr_comment 7 "$body" 2>/dev/null); rc=$?
check_rc "a failed comment fails"                      1 "$rc"
check    "a failed comment carries the write's status" 500 "$(status_of "$out")"

gh_reset; export GH_STATUS_SEQ="200 200 500"
out=$(host_pr_reply_thread 7 THREAD "$body" 2>/dev/null); rc=$?
check_rc "a failed thread reply fails"                 1 "$rc"
check    "a failed thread reply carries the status"    500 "$(status_of "$out")"

# The failed call's own error body must not travel with the status. `-i` prints
# the whole response, error document included, and `_gh_create` prints its JSON
# after it, so a body let through hands the caller two JSON values where
# ship_fail_host expects one.
gh_reset; export GH_STATUS_SEQ="200 404"
export GH_BODY='{"message":"Not Found"}'
out=$(host_pr_comment 7 "$body" 2>/dev/null); rc=$?
check_rc "a refused create fails"                      1 "$rc"
check    "a refused create answers with the status alone" \
  '{"status":404}' "$(jq -c . <<<"$out")"
unset GH_BODY

# The status says the host refused it; gh's own message says why, and `open-pr`
# captures this stderr and prints it with ship_tail40. Dropping it leaves that
# log empty and the run with half an answer.
gh_reset; export GH_STATUS_SEQ="422"
err=$(host_pr_set_body 7 "$body" 2>&1 >/dev/null)
check "a failed write leaves gh's message on stderr, one per attempt" \
  "$(printf 'gh: unexpected end of JSON input\ngh: unexpected end of JSON input')" "$err"

gh_reset; export GH_STATUS_SEQ="200"
err=$(host_pr_set_body 7 "$body" 2>&1 >/dev/null)
check "a successful write says nothing on stderr"      "" "$err"

# The two writes that open with an identity read answer a burst that takes that
# read with the read's status, not with null: `_gh` sets the status inside the
# command substitution the read runs in, so it has to be printed to get out.
gh_reset; export GH_STATUS_SEQ="500"
out=$(host_pr_comment 7 "$body" 2>/dev/null); rc=$?
check_rc "a comment whose identity read fails, fails"  1 "$rc"
check    "it carries the identity read's status"       500 "$(status_of "$out")"

# A call that gives up before it reaches the host, which is what a failed mktemp
# while buffering stdin does, must not report the status in scope from the call
# before it. `api` clears it on the way in, inside the same subshell the write
# prints from.
SHIP_HTTP_STATUS=500
mktemp() { return 1; }
out=$(host_pr_set_body 7 "$body" 2>/dev/null); rc=$?
unset -f mktemp; SHIP_HTTP_STATUS=
check_rc "a write that cannot buffer its payload fails" 1 "$rc"
check    "and reports no status rather than the last one" null "$(status_of "$out")"

# ship_fail_host is what turns that into the mechanic's verdict. It is host
# agnostic: an adapter that reports no status, as `az` does, yields null.
verdict() { bash -c 'source skills/ship/scripts/_lib.sh; ship_fail_host "PR body update failed" "$1"' _ "$1"; }
check "the verdict carries the error and the status" \
  '{"error":"PR body update failed","status":500}' "$(verdict '{"status":500}' | jq -c .)"
check "a verdict with no adapter answer is null" \
  '{"error":"PR body update failed","status":null}' "$(verdict '' | jq -c .)"
check "a verdict whose adapter answer is not JSON is null" \
  '{"error":"PR body update failed","status":null}' "$(verdict 'gh: something' | jq -c .)"
check_rc "a failed write is exit 1" 1 "$(verdict '{"status":500}' >/dev/null; echo $?)"

finish
