#!/usr/bin/env bash
# The GitHub adapter's review-thread functions on both of their paths (#254).
# GraphQL answering, they read threads and resolve through it and make no `ccr`
# call. GraphQL refused with the cloud sandbox proxy's 403, the one naming its
# `ccr` routes, they answer through REST and those routes instead, with the same
# row shape, and the refusal is paid once per process rather than once per call.
# A thread's id is its root REST comment id on both paths, which is what the
# reply posts to and the `ccr` routes key on; an id no thread carries answers
# `no such thread`.
#
# A fake `gh` in front of PATH answers per endpoint from raw fixtures and applies
# the call's own `--jq` to them, so the adapter's projections are what is under
# test. The adapter is sourced for the function cases and run under
# `resolve-thread` for the mechanic's own answer. No case reaches a host.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
bin=$work/bin
export FAKE=$work/fake TMPDIR=$work/tmp
mkdir -p "$bin" "$FAKE" "$TMPDIR"

cat > "$FAKE/comments.json" <<'JSON'
[{"id":101,"in_reply_to_id":null,"user":{"login":"claude[bot]"},"body":"finding one\nmore","html_url":"u101"},
 {"id":102,"in_reply_to_id":101,"user":{"login":"me"},"body":"fixed","html_url":"u102"},
 {"id":201,"in_reply_to_id":null,"user":{"login":"copilot"},"body":"finding two","html_url":"u201"}]
JSON
cat > "$FAKE/ccr.json" <<'JSON'
[{"resolved":false,"outdated":false,"path":"a.sh","line":3,"comment_ids":[101,102]},
 {"resolved":true,"outdated":true,"path":"b.sh","line":9,"comment_ids":[201]}]
JSON
cat > "$FAKE/gql-threads.json" <<'JSON'
{"data":{"repository":{"pullRequest":{"reviewThreads":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[
 {"id":"PRRT_a","isResolved":false,"isOutdated":false,"path":"a.sh",
  "comments":{"nodes":[{"databaseId":101,"author":{"login":"claude"},"body":"finding one\nmore","url":"u101"}]},
  "mine":{"nodes":[{"viewerDidAuthor":false},{"viewerDidAuthor":true}]}},
 {"id":"PRRT_b","isResolved":true,"isOutdated":true,"path":"b.sh",
  "comments":{"nodes":[{"databaseId":201,"author":{"login":"copilot"},"body":"finding two","url":"u201"}]},
  "mine":{"nodes":[{"viewerDidAuthor":false}]}}]}}}}}
JSON
printf '%s' '{"message":"GitHub GraphQL is not available from Claude Code sessions; use the REST API (gh api repos/{owner}/{repo}/...). For review threads, auto-merge, and draft/ready-for-review use the CCR routes on api.github.com: GET /repos/{owner}/{repo}/pulls/{n}/ccr/review_threads, POST /repos/{owner}/{repo}/pulls/{n}/ccr/comments/{comment_id}/resolve (or /unresolve)."}' \
  > "$FAKE/refusal.json"

cat > "$bin/gh" <<'GH'
#!/usr/bin/env bash
# `gh api [graphql] [-i] <path> ... [--jq <expr>]`: log the call, answer from a
# fixture per endpoint, and apply the call's own --jq the way gh does, strings
# raw and everything else as compact JSON.
printf '%s\n' "$*" >> "$FAKE/calls"
jqx="." prev="" include="" path="" method=GET stdin=""
for a in "$@"; do
  case $prev in --jq) jqx=$a ;; -X) method=$a ;; esac
  case $a in
    -i) include=1 ;;
    -) [ "$prev" = --input ] && stdin=1 ;;
    repos/*|user) [ -z "$path" ] && path=$a ;;
  esac
  prev=$a
done
[ -n "$stdin" ] && cat > /dev/null
answer() { # <status> <raw-json>
  [ -n "$include" ] && printf 'HTTP/2.0 %s X\r\nContent-Type: application/json\r\n\r\n' "$1"
  if [ "$1" -ge 400 ]; then printf '%s\n' "$2"; echo "gh: refused (HTTP $1)" >&2; exit 1; fi
  jq -rc "$jqx" <<<"$2"; exit 0
}
if [ "$2" = graphql ] || [ "$1" = graphql ]; then
  # gql-seq: one word per GraphQL call, the last repeating: `flake` is a 401,
  # `refuse` the proxy's 403, anything else an answer.
  if [ -f "$FAKE/gql-seq" ]; then
    n=$(( $(cat "$FAKE/gql.n" 2>/dev/null || echo 0) + 1 )); printf '%s' "$n" > "$FAKE/gql.n"
    i=0; for w in $(cat "$FAKE/gql-seq"); do i=$((i + 1)); word=$w; [ "$i" -ge "$n" ] && break; done
    case $word in
      flake) echo 'gh: Bad credentials (HTTP 401)' >&2; exit 1 ;;
      refuse) : > "$FAKE/gql-refused" ;;
    esac
  fi
  if [ -f "$FAKE/gql-refused" ]; then
    cat "$FAKE/refusal.json"
    printf 'gh: %s (HTTP 403)\n' "$(jq -r .message "$FAKE/refusal.json")" >&2
    exit 1
  fi
  case " $* " in
    *mutation*) answer 200 '{"data":{"resolveReviewThread":{"thread":{"isResolved":true}}}}' ;;
    *) answer 200 "$(cat "$FAKE/gql-threads.json")" ;;
  esac
fi
case $method:$path in
  GET:user) answer 200 '{"login":"me"}' ;;
  GET:*/pulls/7/ccr/review_threads)
    [ -f "$FAKE/ccr-fail" ] && answer 500 '{"message":"Server Error"}'
    answer 200 "$(cat "$FAKE/ccr.json")" ;;
  GET:*/pulls/7/comments*) answer 200 "$(cat "$FAKE/comments.json")" ;;
  POST:*/pulls/7/comments/*/replies) answer 201 '{"id":103,"html_url":"u103"}' ;;
  POST:*/pulls/7/ccr/comments/101/resolve|POST:*/pulls/7/ccr/comments/201/resolve) answer 200 '{}' ;;
  POST:*/pulls/7/ccr/comments/301/resolve) answer 500 '{"message":"Server Error"}' ;;
  POST:*/pulls/7/ccr/comments/*/resolve) answer 404 '{"message":"No review thread on this pull request contains that comment ID"}' ;;
esac
echo "fake gh: unexpected call: $*" >&2; exit 1
GH
printf '#!/bin/sh\nexit 0\n' > "$bin/sleep"
chmod +x "$bin/gh" "$bin/sleep"
export PATH=$bin:$PATH

SHIP_OWNER=owner SHIP_REPO=repo
source skills/ship/scripts/_lib.sh
source skills/ship/scripts/host/github.sh
sleep() { :; }

reset() { # [refused | <gql-seq words>]
  rm -rf "$FAKE/calls" "$FAKE/gql-refused" "$FAKE/gql-seq" "$FAKE/gql.n" "$FAKE/ccr-fail" "${TMPDIR:?}"/*
  : > "$FAKE/calls"
  case ${1:-} in
    '') ;;
    refused) : > "$FAKE/gql-refused" ;;
    *) printf '%s' "$1" > "$FAKE/gql-seq" ;;
  esac
  return 0
}
markers() { find "$TMPDIR" -mindepth 1 -maxdepth 1 -name 'ship-gh-graphql-refused.*' | wc -l | tr -d ' '; }
calls_matching() { grep -c -- "$1" "$FAKE/calls"; }
body=$work/body.md; printf 'fixed in abc\n' > "$body"

# The row both paths owe, less the author, whose spelling is each path's own
# (GraphQL drops a bot's [bot] suffix and REST keeps it).
rows='[{"id":"101","comment_id":101,"resolved":false,"outdated":false,"path":"a.sh","replied":true,"body":"finding one\nmore","url":"u101"},{"id":"201","comment_id":201,"resolved":true,"outdated":true,"path":"b.sh","replied":false,"body":"finding two","url":"u201"}]'
norm() { jq -c 'map(del(.author))'; }

# GraphQL answering: today's reads, keyed by the root comment id, and no ccr call.
reset
out=$(host_pr_threads 7); rc=$?
check_rc "threads read over GraphQL" 0 "$rc"
check "the GraphQL rows carry the root comment id as the thread id" "$rows" "$(norm <<<"$out")"
check "the GraphQL rows keep the row keys in the contract's order" \
  '["id","comment_id","resolved","outdated","path","replied","author","body","url"]' "$(jq -c '.[0] | keys_unsorted' <<<"$out")"
out=$(host_pr_resolve_thread 7 101); rc=$?
check_rc "resolve over GraphQL" 0 "$rc"
check "resolve answers resolved" true "$(jq -r .resolved <<<"$out")"
check "the mutation targets the thread whose root is that comment" 1 "$(calls_matching 'mutation.*id=PRRT_a')"
out=$(host_pr_reply_thread 7 101 "$body"); rc=$?
check_rc "reply by root comment id" 0 "$rc"
check "the reply posts to that comment's replies route" 1 "$(calls_matching 'POST repos/owner/repo/pulls/7/comments/101/replies')"
check "a run GraphQL answers makes no ccr call" 0 "$(calls_matching ccr)"
out=$(host_pr_resolve_thread 7 999); rc=$?
check_rc "an unknown id over GraphQL does not resolve" 1 "$rc"
check "and answers no such thread" 'false no such thread' "$(jq -r '[.resolved, .detail] | @tsv' <<<"$out" | tr '\t' ' ')"

# GraphQL refused by the proxy: the ccr and REST routes answer, same rows.
reset refused
out=$(host_pr_threads 7 2>"$work/err"); rc=$?
check_rc "threads read through the ccr route" 0 "$rc"
check "the switch is said once on stderr" 1 "$(grep -c 'REST routes' "$work/err")"
check "the ccr rows match the GraphQL rows" "$rows" "$(norm <<<"$out")"
check "the ccr row takes its author from the root comment" 'claude[bot]' "$(jq -r '.[0].author' <<<"$out")"
out=$(host_pr_threads 7)
out=$(host_pr_resolve_thread 7 101); rc=$?
check_rc "resolve through the ccr route" 0 "$rc"
check "the ccr resolve answers resolved" true "$(jq -r .resolved <<<"$out")"
check "the ccr resolve is keyed by the root comment id" 1 "$(calls_matching 'POST repos/owner/repo/pulls/7/ccr/comments/101/resolve')"
check "one refused GraphQL call for the whole process" 1 "$(calls_matching graphql)"
out=$(host_pr_reply_thread 7 101 "$body"); rc=$?
check_rc "reply with GraphQL refused" 0 "$rc"
check "the reply answers replied" 'true u103' "$(jq -r '[.replied, .url] | @tsv' <<<"$out" | tr '\t' ' ')"
out=$(host_pr_resolve_thread 7 999 2>/dev/null); rc=$?
check_rc "an unknown id through the ccr route does not resolve" 1 "$rc"
check "the ccr 404 answers no such thread" 'false no such thread' "$(jq -r '[.resolved, .detail] | @tsv' <<<"$out" | tr '\t' ' ')"

# A GraphQL failure that is not the proxy's refusal keeps today's one retry,
# writes no marker and reads as unavailable; the refusal arriving on the retry
# still switches paths.
reset flake
out=$(host_pr_threads 7 2>/dev/null); rc=$?
check_rc "a flaking GraphQL read fails" 1 "$rc"
check "it is retried once" 2 "$(calls_matching graphql)"
check "and remembers nothing" 0 "$(markers)"
check "and makes no ccr call" 0 "$(calls_matching ccr)"
reset "flake refuse"
out=$(host_pr_threads 7 2>/dev/null); rc=$?
check_rc "a refusal on the retry still takes the ccr route" 0 "$rc"
check "with the same rows" "$rows" "$(norm <<<"$out")"
check "and is remembered" 1 "$(markers)"

# Both paths failing is what `threads: "unavailable"` now means.
reset refused; : > "$FAKE/ccr-fail"
out=$(host_pr_threads 7 2>/dev/null); rc=$?
check_rc "a failed ccr read after the refusal fails the read" 1 "$rc"
reset refused
out=$(host_pr_resolve_thread 7 301 2>/dev/null); rc=$?
check_rc "a ccr resolve the host fails does not resolve" 1 "$rc"
check "and names no thread missing" '' "$(jq -r '.detail? // empty' <<<"$out" 2>/dev/null)"

# An id that is no root comment, the old GraphQL node id included, is no thread.
reset
out=$(host_pr_reply_thread 7 999 "$body"); rc=$?
check_rc "a reply to an unknown id is not posted" 1 "$rc"
check "and answers no such thread" 'false no such thread' "$(jq -r '[.replied, .detail] | @tsv' <<<"$out" | tr '\t' ' ')"
out=$(host_pr_reply_thread 7 PRRT_a "$body"); rc=$?
check_rc "a node id is not a thread id" 1 "$rc"
check "and answers no such thread" 'no such thread' "$(jq -r .detail <<<"$out")"
check "neither posts a reply" 0 "$(calls_matching replies)"

# resolve-thread carries the adapter's reason as its error.
repo=$work/repo
git -C "$work" init -q repo
git -C "$repo" remote add origin https://github.com/owner/repo.git
reset refused
out=$( cd "$repo" && bash "$OLDPWD/skills/ship/scripts/resolve-thread.sh" 7 999 2>/dev/null ); rc=$?
check_rc "resolve-thread on an unknown id exits 1" 1 "$rc"
check "resolve-thread names no such thread" 'no such thread' "$(jq -r .error <<<"$out")"

finish
