#!/usr/bin/env bash
# The two reads a Rework run's preflight takes its PR-comment feedback from, on
# both real adapters: host_pr_comments, the PR's own conversation comments with
# the issue comments' `writer` grade, and host_pr_pushed_at, the time of the
# push that put the head where it is; and, on Azure DevOps, host_pr_threads'
# `ship_last`, which drops a thread ship declined from the threads' feedback
# (tests/gh-threads-proxy.test.sh has GitHub's). Each adapter runs with its transport
# (`api` on GitHub, `invoke` on Azure DevOps) redefined to answer from a
# fixture, GitHub's applying the call's own `--jq` the way `gh` does, so the
# projection is the subject and no call reaches a host.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
source skills/ship/scripts/_lib.sh

head=84c7f25fccd0b31fdb95bc19bdd262c9994006d2

# GitHub. The activity rows are the shape the API returned for PR #622's branch.
( SHIP_OWNER=o SHIP_REPO=r
  source skills/ship/scripts/host/github.sh
  log=$(mktemp); trap 'rm -f "$log"' EXIT
  ACTIVITY=''
  api() {
    printf '%s\n' "$*" >> "$log"
    local a prev='' q='.' kind=''
    for a; do
      [ "$prev" = --jq ] && q=$a
      [ "$prev" = -f ] && case $a in activity_type=*) kind=${a#*=} ;; esac
      prev=$a
    done
    case $1 in
      # The API's own activity_type filter, so a call that passes one is held to it.
      repos/o/r/activity) [ -n "$ACTIVITY" ] || return 1
        jq -c --arg k "$kind" 'map(select($k == "" or .activity_type == $k))' <<<"$ACTIVITY" | jq -r "$q" ;;
      repos/o/r/issues/9/comments) jq -c "$q" <<<'[{"user": {"login": "w"}, "body": "b", "created_at": "2026-01-02T00:00:01Z"}]' ;;
      repos/o/r/collaborators/w/permission) jq -r "$q" <<<'{"user": {"permissions": {"push": true}}}' ;;
      *) echo "unexpected api call: $*" >&2; return 1 ;;
    esac
  }
  ACTIVITY='[{"activity_type": "push", "after": "'$head'", "timestamp": "2026-10-12T21:47:48Z"},
             {"activity_type": "push", "after": "5d62928f", "timestamp": "2026-10-12T21:43:54Z"},
             {"activity_type": "push", "after": "'$head'", "timestamp": "2026-10-12T21:40:00Z"}]'
  check "github: the newest push of the head sha" 2026-10-12T21:47:48Z "$(host_pr_pushed_at 9 feat/y-9 "$head")"
  check "github: asks for the branch's activity on an explicit GET" yes \
    "$(grep -Fq -- "repos/o/r/activity -X GET -f ref=refs/heads/feat/y-9 -f per_page=100" "$log" && echo yes)"
  # A branch's first push is logged as its creation, as PR #623's was.
  for kind in branch_creation force_push; do
    ACTIVITY='[{"activity_type": "'$kind'", "after": "'$head'", "timestamp": "2026-10-12T22:17:40Z"}]'
    check "github: a $kind of the head sha is its push" 2026-10-12T22:17:40Z "$(host_pr_pushed_at 9 feat/y-9 "$head")"
  done
  host_pr_pushed_at 9 feat/y-9 0000000 >/dev/null
  check_rc "github: no push of that sha is non-zero" 1 $?
  ACTIVITY=''
  host_pr_pushed_at 9 feat/y-9 "$head" >/dev/null
  check_rc "github: an unreadable activity log is non-zero" 1 $?
  check "github: comments are the PR's issue comments, writer graded" \
    '[{"author":"w","body":"b","created_at":"2026-01-02T00:00:01Z","writer":true}]' "$(host_pr_comments 9 | jq -c .)"
  finish
) || _failed=1

# Azure DevOps.
( SHIP_ORG_URL=https://dev.azure.com/org SHIP_PROJECT=proj SHIP_REPO=repo
  source skills/ship/scripts/host/ado.sh
  ANSWER=''
  invoke() { [ -n "$ANSWER" ] || return 1; printf '%s' "$ANSWER"; }
  ANSWER='{"value": [
    {"id": 1, "createdDate": "2026-10-01T10:00:00.123Z", "sourceRefCommit": {"commitId": "'$head'"}},
    {"id": 2, "createdDate": "2026-10-01T11:00:00Z", "sourceRefCommit": {"commitId": "aaaa"}},
    {"id": 3, "createdDate": "2026-10-01T12:00:00.977591+00:00", "sourceRefCommit": {"commitId": "'$head'"}}]}'
  check "ado: the newest iteration of the head sha, in the one UTC spelling" 2026-10-01T12:00:00Z \
    "$(host_pr_pushed_at 9 feat/y-9 "$head")"
  host_pr_pushed_at 9 feat/y-9 0000000 >/dev/null
  check_rc "ado: no iteration of that sha is non-zero" 1 $?
  ANSWER=''
  host_pr_pushed_at 9 feat/y-9 "$head" >/dev/null
  check_rc "ado: unreadable iterations are non-zero" 1 $?
  ANSWER='{"value": [
    {"id": 1, "threadContext": null, "comments": [{"author": {"uniqueName": "h@x"}, "content": "rename x",
      "publishedDate": "2026-10-01T13:00:00.5Z", "commentType": "text"}]},
    {"id": 2, "threadContext": {"filePath": "/a"}, "comments": [{"author": {"uniqueName": "h@x"}, "content": "on a line",
      "publishedDate": "2026-10-01T13:00:00Z", "commentType": "text"}]},
    {"id": 3, "threadContext": null, "comments": [{"author": {"uniqueName": "s"}, "content": "voted",
      "publishedDate": "2026-10-01T13:00:00Z", "commentType": "system"}]},
    {"id": 4, "isDeleted": true, "threadContext": null, "comments": [{"author": {"uniqueName": "h@x"}, "content": "gone",
      "publishedDate": "2026-10-01T13:00:00Z", "commentType": "text"}]}]}'
  check "ado: comments are the live PR-level threads, writer null" \
    '[{"author":"h@x","body":"rename x","created_at":"2026-10-01T13:00:00Z","writer":null}]' "$(host_pr_comments 9 | jq -c .)"
  # ship_last: the thread's latest comment, system and deleted ones aside, is ship's.
  host_identity() { echo me@x; }
  ANSWER='{"value": [
    {"id": 1, "status": "active", "threadContext": {"filePath": "/a"}, "comments": [
      {"author": {"uniqueName": "r@x"}, "content": "finding", "commentType": "text"},
      {"author": {"uniqueName": "me@x"}, "content": "declined: x\n<span data-ship=1></span>\n", "commentType": "text"}]},
    {"id": 2, "status": "active", "threadContext": {"filePath": "/a"}, "comments": [
      {"author": {"uniqueName": "r@x"}, "content": "finding", "commentType": "text"},
      {"author": {"uniqueName": "me@x"}, "content": "declined: x\n<span data-ship=1></span>\n", "commentType": "text"},
      {"author": {"uniqueName": "r@x"}, "content": "still wrong", "commentType": "text"}]},
    {"id": 3, "status": "active", "threadContext": {"filePath": "/a"}, "comments": [
      {"author": {"uniqueName": "r@x"}, "content": "finding", "commentType": "text"},
      {"author": {"uniqueName": "me@x"}, "content": "declined: x\n<span data-ship=1></span>\n", "commentType": "text"},
      {"author": {"uniqueName": "s"}, "content": "status changed", "commentType": "system"},
      {"author": {"uniqueName": "r@x"}, "content": "", "commentType": "text", "isDeleted": true}]},
    {"id": 4, "status": "active", "threadContext": {"filePath": "/a"}, "comments": [
      {"author": {"uniqueName": "r@x"}, "content": "finding", "commentType": "text"}]}]}'
  check "ado: threads say whether ship's comment is last" '[true,false,true,false]' \
    "$(host_pr_threads 9 | jq -c 'map(.ship_last)')"
  check "ado: replied is unchanged" '[true,true,true,false]' "$(host_pr_threads 9 | jq -c 'map(.replied)')"
  finish
) || _failed=1

finish
