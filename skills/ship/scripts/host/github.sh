#!/usr/bin/env bash
# GitHub adapter: the host_* interface from _lib.sh over REST via `gh api`.
# REST throughout, one retry after 2 s: gh's GraphQL paths (gh pr view --json,
# gh pr checks --watch) flake 401 mid-session. GraphQL is used only for the
# three things REST lacks, review-thread resolution state, resolveReviewThread,
# and a thread id's reply target (REST offers no route from a thread to its
# first comment), behind the same retry. Sourced by _lib.sh's ship_load_host; needs SHIP_OWNER
# and SHIP_REPO set.

R="repos/$SHIP_OWNER/$SHIP_REPO"

# Reads retry once on any failure. Creates go through `_gh_create_verify`,
# which re-reads before retrying so a slow success is never double-posted.
# A retry has to be the request it retries. `gh api "$@"` carries the argument
# list but not stdin, so a `--input -` payload the failed attempt already drained
# reaches the retry empty and GitHub rejects it as "Body should be a JSON
# object" (#108); buffering it once is what keeps the two byte-identical.
api() {
  local a prev="" buf=""
  local -a args=()
  for a in "$@"; do
    # `gh` spells a stdin payload either `--input -` or `--input=-`.
    if { [ "$prev" = --input ] && [ "$a" = - ]; } || [ "$a" = --input=- ]; then
      buf=$(mktemp) || return 2
      trap 'rm -f "$buf"' RETURN
      cat > "$buf"
      case $a in --input=-) a=--input=$buf ;; *) a=$buf ;; esac
    fi
    args+=("$a"); prev=$a
  done
  gh api "${args[@]}" 2>/dev/null || { sleep 2; gh api "${args[@]}"; }
}
gql() { gh api graphql "$@" 2>/dev/null || { sleep 2; gh api graphql "$@"; }; }

host_tooling_reasons() {
  command -v gh  >/dev/null || echo "gh not installed"
  command -v jq  >/dev/null || echo "jq not installed"
  command -v git >/dev/null || echo "git not installed"
}
# The Ubuntu archive is the one route the cloud sandbox proxy passes (the
# release tarball host 404s through it); apt installs 2.45.0 in about 12 s.
host_tooling_install() {
  command -v gh >/dev/null && return 0
  local sudo=""; [ "$(id -u)" -eq 0 ] || sudo="sudo -n"
  $sudo apt-get install -y gh
}
host_identity() { api user --jq .login; }
host_can_push() { api "$R" --jq '.permissions.push // false'; }

_norm_issue='{number, title, body: (.body // ""),
  state: (if .state == "open" then "open" else "closed" end),
  is_pr: (.pull_request != null),
  labels: [.labels[].name], assignees: [.assignees[].login],
  created_at, url: .html_url}'

host_issue_get()      { api "$R/issues/$1" --jq "$_norm_issue"; }
host_issue_comments() {
  api "$R/issues/$1/comments" --paginate --jq '.[] | {author: .user.login, body, created_at}' | jq -s .
}
# GitHub has native issue dependencies, so a failed query is "unavailable", never vacuous.
host_issue_blockers_open() {
  api "$R/issues/$1/dependencies/blocked_by" --paginate --jq '.[] | select(.state == "open") | .number' | jq -s .
}
# Cross-referenced timeline events hydrate each source PR in full, so the split
# between "claims to close this issue" and "merely mentions it" costs no extra call.
host_issue_linked_prs() {
  local n=$1 raw
  raw=$(api "$R/issues/$n/timeline" --paginate --jq '
      .[] | select(.event == "cross-referenced") | .source.issue
      | select(if .pull_request != null then (.state == "open" or .pull_request.merged_at != null)
               else .state == "open" end)
      | {number,
         kind: (if .pull_request != null then "pr" else "issue" end),
         state: (if .pull_request != null and .pull_request.merged_at != null then "merged" else .state end),
         body: (.body // "")}' \
    | jq -s 'unique_by(.number)') || return 1
  local out='{"closing":[],"mentions":[]}' row
  while IFS= read -r row; do
    [ -z "$row" ] && continue
    # Only a PR can close an issue: an issue whose body says "closes #n" is a
    # mention, and reading it as a closing link would stop every run on this
    # issue with `existing PR`.
    if [ "$(jq -r .kind <<<"$row")" = pr ] && ship_body_closes "$(jq -r .body <<<"$row")" "$n"; then
      out=$(jq --argjson r "$row" '.closing += [$r | {number, state}]' <<<"$out")
    else
      out=$(jq --argjson r "$row" '.mentions += [$r | {number, kind, state}]' <<<"$out")
    fi
  done < <(jq -c '.[]' <<<"$raw")
  printf '%s\n' "$out"
}
host_issue_assign()   { api -X POST   "$R/issues/$1/assignees" -f "assignees[]=$2" >/dev/null; }
host_issue_unassign() { api -X DELETE "$R/issues/$1/assignees" -f "assignees[]=$2" >/dev/null; }
host_issue_has_label(){ api "$R/issues/$1/labels" --jq '.[].name' | grep -qxF -- "$2"; }
host_issue_add_label(){ api -X POST "$R/issues/$1/labels" -f "labels[]=$2" >/dev/null; }
# Check first: a DELETE 404s the same way whether the label was already gone or
# the call itself failed, and a reported removal that never happened is exactly
# the residue this exists to stop.
host_issue_remove_label() {
  host_issue_has_label "$1" "$2" || return 0
  api -X DELETE "$R/issues/$1/labels/$(jq -rn --arg l "$2" '$l | @uri')" >/dev/null
}
host_issue_comment()  { jq -n --arg b "$2" '{body: $b}' | api -X POST "$R/issues/$1/comments" --input - >/dev/null; }
host_issue_close()    { api -X PATCH "$R/issues/$1" -f state=closed -f state_reason=completed >/dev/null; }

# Create-then-verify, the shape every create in this adapter has: attempt the
# POST once, and on failure look for the row a slow success would have left
# before posting again, so a flake never double-posts. <post> performs the one
# POST and prints the row; <find> prints that row, or nothing when there is
# none. A <find> that fails is not an absent row: it answers unknown, so the
# caller gets the failure rather than a second POST. A <find> that ends in a
# pipe answers that way only under the `pipefail` every mechanic sets, which is
# where a failed `api` upstream of a `jq` becomes the pipeline's exit status.
#
# A <post> calls `gh api` directly, not `api`: `api` retries on its own, and a
# create is retried only after the re-read.
_gh_create_verify() { # <post-fn> <find-fn>
  local out
  if out=$("$1"); then printf '%s\n' "$out"; return 0; fi
  sleep 2
  out=$("$2") || return 1
  if [ -n "$out" ]; then printf '%s\n' "$out"; return 0; fi
  "$1"
}

host_issue_create() { # <title> <body-file> <label>
  local title=$1 file=$2 label=$3 me
  me=$(host_identity) || return 1
  _issue_post() {
    jq -n --arg t "$title" --rawfile b "$file" --arg l "$label" \
      '{title: $t, body: $b, labels: (if $l == "" then [] else [$l] end)}' \
      | gh api -X POST "$R/issues" --input - --jq '{number, url: .html_url}' 2>/dev/null
  }
  _issue_find() {
    api "$R/issues?state=open&creator=$me&sort=created&direction=desc&per_page=20" --jq '.[]' \
      | jq -s --arg t "$title" '[.[] | select(.pull_request == null and .title == $t)] | first | select(. != null) | {number, url: .html_url}'
  }
  _gh_create_verify _issue_post _issue_find
}

# Put `Closes #<issue>` above the first `## ` heading, where no section rewrite
# reaches it: `update-pr-body` replaces a section wholesale, so a closing line
# appended to the end of the body sits inside the last section and the next
# rewrite of that section drops it. A body with no heading has no section to
# fall inside, so it keeps the append.
#
# Fenced blocks are skipped by `SHIP_AWK_FENCE`, matching the model
# `ship_body_closes` uses: a `## ` inside a fence is example text, and a closing
# line printed into a fence renders as code, so the host registers no link and
# the keyword test that gates a re-run reads false.
# The heading match stays anchored at column 0 on purpose: it has to agree
# with `update-pr-body`, whose `^## ` is what decides a section boundary.
_gh_add_closes() { # <body> <issue>
  awk -v n="$2" "$SHIP_AWK_FENCE"'
    { fenced = ship_fence($0) }
    !placed && !fenced && /^## / { print "Closes #" n; print ""; placed = 1 }
    { print }
    END { if (!placed) printf "\nCloses #%s\n", n }' <<<"$1"
}

host_pr_create() { # <head> <base> <title> <body-file> <issue>
  local head=$1 base=$2 title=$3 file=$4 issue=$5 body
  body=$(cat "$file")
  # The mechanic translates the closing link for the host: add the keyword when
  # the body does not already carry one aimed at this issue.
  if [ -n "$issue" ] && ! ship_body_closes "$body" "$issue"; then
    body=$(_gh_add_closes "$body" "$issue")
  fi
  _pr_post() {
    jq -n --arg h "$head" --arg b "$base" --arg t "$title" --arg body "$body" \
      '{head: $h, base: $b, title: $t, body: $body, draft: false}' \
      | gh api -X POST "$R/pulls" --input - --jq '{number, url: .html_url, created_at}' 2>/dev/null
  }
  _pr_find() {
    api "$R/pulls?state=open&head=$SHIP_OWNER:$head" --jq 'first | select(. != null) | {number, url: .html_url, created_at}'
  }
  _gh_create_verify _pr_post _pr_find
}

host_pr_get() {
  api "$R/pulls/$1" --jq '{number, url: .html_url, title, body: (.body // ""),
    head_sha: .head.sha, head_ref: .head.ref, base_ref: .base.ref,
    state: (if .merged then "merged" elif .state == "open" then "open" else "closed" end),
    mergeable: (if .mergeable_state == "dirty" then "conflict"
                elif .mergeable == true then "clean" else "unknown" end)}'
}

host_pr_for_branch() { # <branch>
  api "$R/pulls?state=all&head=$SHIP_OWNER:$1&sort=created&direction=desc&per_page=1" \
    --jq 'first | if . == null then null else {number, state: (if .merged_at != null then "merged" elif .state == "open" then "open" else "closed" end)} end'
}

# Check runs plus classic commit statuses, one row per name, latest wins.
host_pr_checks() { # <pr> <head_sha>
  local sha=$2 runs statuses
  runs=$(api "$R/commits/$sha/check-runs" --paginate --jq '.check_runs[] | {name,
      status: (if .status != "completed" then "pending"
               elif (.conclusion | IN("success","neutral","skipped")) then "success"
               else "failure" end), at: (.completed_at // .started_at // "")}' | jq -s .) || return 1
  statuses=$(api "$R/commits/$sha/status" --jq '.statuses[] | {name: .context,
      status: (if .state == "success" then "success" elif .state == "pending" then "pending" else "failure" end),
      at: .updated_at}' | jq -s .) || return 1
  jq -n --argjson a "$runs" --argjson b "$statuses" \
    '$a + $b | group_by(.name) | map(max_by(.at) | {name, status})'
}

# `on_head` is keyed to the current head (a review on an older commit does not
# count), which poll-pr's default head rule reads; `all` carries every round
# across heads, for its --since rule. `substantive` is the landing signal, and
# two kinds of row fail it: a reviewer's reply to one thread, which posts as a
# review row of its own (current head, empty body), and a quota or rate-limit
# notice, which posts as a review with a non-empty body (PR #154, three times)
# and refuses the round rather than delivering it. Counting either lands round 2
# off round 1. Both stay in the two lists with their bodies, so the run can see
# what it is waiting on.
_gh_reviews_projection="$SHIP_REVIEW_CLIP$SHIP_BLOCKED_NOTICE"'
    def row: . as $r | {id: (.id | tostring), login: .user.login,
      state: (if .state == "APPROVED" then "approved" elif .state == "CHANGES_REQUESTED" then "changes" else "comment" end),
      substantive: ((.body // "") != "" and ((.body // "") | is_notice | not)),
      submitted_at, body: ((.body // "") | clip($r.id))};
    {on_head: [.[] | select(.commit_id == $sha) | row], all: [.[] | row], total: length}'
host_pr_reviews() { # <pr> <head_sha> [<full-ids-json>]
  api "$R/pulls/$1/reviews" --paginate --jq '.[]' \
    | jq -s --arg sha "$2" --argjson full "${3:-[]}" "$_gh_reviews_projection"
}

_threads_query='query($o:String!,$r:String!,$n:Int!,$after:String){
  repository(owner:$o,name:$r){ pullRequest(number:$n){
    reviewThreads(first:100, after:$after){
      pageInfo{hasNextPage endCursor}
      nodes{ id isResolved isOutdated path
        comments(first:1){ nodes{ databaseId author{login} body url } }
        mine: comments(last:100){ nodes{ viewerDidAuthor } } } } } } }'
# GraphQL only: REST has no thread-resolution state. A refused GraphQL path
# (a proxy that pins it) fails this call; the mechanic reports "unavailable".
host_pr_threads() {
  local after=null page out='[]'
  while :; do
    # shellcheck disable=SC2046  # deliberate: the optional `-F after=<cursor>` pair must split
    page=$(gql -f query="$_threads_query" -F o="$SHIP_OWNER" -F r="$SHIP_REPO" -F n="$1" \
      $([ "$after" != null ] && printf -- '-F after=%s' "$after") \
      --jq '.data.repository.pullRequest.reviewThreads') || return 1
    out=$(jq --argjson p "$page" '. + [$p.nodes[] | {id, comment_id: .comments.nodes[0].databaseId,
      resolved: .isResolved, outdated: .isOutdated, path,
      replied: ([.mine.nodes[] | select(.viewerDidAuthor)] | length > 0),
      author: .comments.nodes[0].author.login, body: .comments.nodes[0].body, url: .comments.nodes[0].url}]' <<<"$out")
    [ "$(jq -r .pageInfo.hasNextPage <<<"$page")" = true ] || break
    after=$(jq -r .pageInfo.endCursor <<<"$page")
  done
  printf '%s\n' "$out"
}

# The awaited login's own account of a round it has not delivered. A reviewer
# states it either as a review of its own or as a PR comment (Copilot did the
# former on PR #154, three times), so both surfaces merge into one time-sorted
# list and the latest notice wins whichever way it arrived.
# The login is compared the way `SHIP_LANDED_BY` compares it, so a `Login:` typed
# in another case cannot land rounds here and report blocked nowhere.
_gh_blocked_select="$SHIP_BLOCKED_NOTICE"'
  def norm: ascii_downcase | sub("\\[bot\\]$"; "");
  [sort_by(.at)[] | select((.login | norm) == ($l | norm)) | (.body // "") | notice_lines]
  | last // null'
host_pr_reviewer_blocked() { # <pr> <login>
  { api "$R/issues/$1/comments" --paginate --jq '.[] | {login: .user.login, body, at: .created_at}'
    api "$R/pulls/$1/reviews"   --paginate --jq '.[] | {login: .user.login, body, at: .submitted_at}'
  } | jq -s --arg l "$2" "$_gh_blocked_select"
}

# Request, then read the request back off the host's own record: the login you
# request and the login you read back can differ (Copilot is requested as
# copilot-pull-request-reviewer[bot] and recorded on the timeline as `Copilot`),
# and an empty requested_reviewers list proves nothing once the bot has posted.
host_pr_request_review() { # <pr> <login>
  local pr=$1 login=$2 ok=false before after readback now
  _requested_events() {
    api "$R/issues/$pr/timeline" --paginate \
      --jq '.[] | select(.event == "review_requested") | select(.requested_reviewer.login) | {login: .requested_reviewer.login, created_at}' \
      | jq -s .
  }
  before=$(_requested_events) || before='[]'
  # Stamped before the POST, so a review submitted the instant the request lands
  # is still at-or-after the fallback requested_at.
  now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  api -X POST "$R/pulls/$pr/requested_reviewers" -f "reviewers[]=$login" >/dev/null && ok=true
  sleep 2
  after=$(_requested_events) || after='[]'
  readback=$( { api "$R/pulls/$pr" --jq '.requested_reviewers[].login'; jq -r '.[].login' <<<"$after"; } | jq -R . | jq -s 'unique')
  # Read back by delta: the request landed iff the timeline gained a
  # review_requested event during this call. Comparing logins does not work for
  # an app reviewer, which is requested under one login and recorded under another.
  # The timeline is chronological, so that new event is the last one.
  jq -n --argjson ok "$ok" --argjson b "$before" --argjson a "$after" --argjson rb "$readback" --arg l "$login" --arg now "$now" \
    '{requested: ($ok and (($a | length) > ($b | length)
                          or ([$rb[] | ascii_downcase | sub("\\[bot\\]$"; "")] | index($l | ascii_downcase | sub("\\[bot\\]$"; "")) != null))),
      readback: $rb,
      requested_at: (if ($a | length) > ($b | length) then ($a[-1].created_at // $now) else $now end)}'
}

host_pr_comment() { # <pr> <body-file>
  local pr=$1 file=$2 me
  me=$(host_identity) || return 1
  _comment_post() { jq -n --rawfile b "$file" '{body: $b}' | gh api -X POST "$R/issues/$pr/comments" --input - --jq '{id, url: .html_url, created_at}' 2>/dev/null; }
  _comment_find() {
    api "$R/issues/$pr/comments?per_page=100" --paginate --jq '.[]' \
      | jq -s --arg me "$me" --rawfile b "$file" '[.[] | select(.user.login == $me and .body == $b)] | last | select(. != null) | {id, url: .html_url, created_at}'
  }
  _gh_create_verify _comment_post _comment_find
}
host_pr_set_body() { jq -n --rawfile b "$2" '{body: $b}' | api -X PATCH "$R/pulls/$1" --input - >/dev/null; }
host_pr_set_title() { jq -n --arg t "$2" '{title: $t}' | api -X PATCH "$R/pulls/$1" --input - >/dev/null; }

_thread_reply_target_query='query($id:ID!){ node(id:$id){
  ... on PullRequestReviewThread { comments(first:1){ nodes{ databaseId } } } } }'
# REST, per this adapter's rule: a reply is `POST .../comments/{id}/replies`
# keyed by the thread's first comment, which the thread row carries as
# `comment_id`, so nothing here needs a GraphQL mutation. The thread ids
# themselves come from GraphQL, so where the proxy blocks it there are no ids
# to reply to and `poll-pr` already reports `threads: "unavailable"`.
#
# The caller passes the thread id, the one id both reply-thread and
# resolve-thread take on either host, and this resolves that thread's
# comment_id for it: one targeted node read, not a walk of every thread on the
# PR, because phase 7 replies once per thread.
#
# Create-then-verify like every other create here, with a find that returns
# non-zero when the comment read fails, so a lost response never becomes a
# duplicate disposition in the thread.
host_pr_reply_thread() { # <pr> <thread-node-id> <body-file>
  local pr=$1 file=$3 cid me
  cid=$(gql -f query="$_thread_reply_target_query" -F id="$2" \
    --jq '.data.node.comments.nodes[0].databaseId') \
    || { printf '{"replied": false, "url": null, "detail": "unavailable"}\n'; return 1; }
  [ -n "$cid" ] && [ "$cid" != null ] || { printf '{"replied": false, "url": null, "detail": "no such thread"}\n'; return 1; }
  me=$(host_identity) || return 1
  _reply_post() { jq -n --rawfile b "$file" '{body: $b}' \
    | gh api -X POST "$R/pulls/$pr/comments/$cid/replies" --input - --jq '{replied: true, url: .html_url}' 2>/dev/null; }
  _reply_find() {
    local raw
    raw=$(api "$R/pulls/$pr/comments?per_page=100" --paginate --jq '.[]') || return 1
    jq -s --argjson c "$cid" --arg me "$me" --rawfile b "$file" \
      '[.[] | select(.in_reply_to_id == $c and .user.login == $me and .body == $b)] | last | select(. != null) | {replied: true, url: .html_url}' <<<"$raw"
  }
  _gh_create_verify _reply_post _reply_find
}

host_pr_resolve_thread() { # <pr> <thread-node-id>
  gql -f query='mutation($id:ID!){ resolveReviewThread(input:{threadId:$id}){ thread{ isResolved } } }' \
    -F id="$2" --jq '{resolved: .data.resolveReviewThread.thread.isResolved}'
}

# Squash with the PR title as the subject; release tooling reads it. Verified by
# the caller re-reading host_pr_get, never assumed from this call's exit code.
host_pr_merge() { # <pr> <subject>
  api -X PUT "$R/pulls/$1/merge" -f merge_method=squash -f commit_title="$2" >/dev/null
}

host_prs_open() {
  api "$R/pulls?state=open&per_page=100" --paginate \
    --jq '.[] | {number, title, head_ref: .head.ref, author: .user.login, url: .html_url, created_at}' | jq -s .
}
# Every open issue, for file-issue's candidate check. No label filter: an
# adjacent find may already sit under any label, or none. Paginated, because a
# candidate the check cannot see is the bug it exists to stop, and a repo's
# open issues are a bounded read.
host_issues_open() {
  api "$R/issues?state=open&sort=created&direction=desc&per_page=100" --paginate \
    --jq '.[] | select(.pull_request == null) | {number, title, url: .html_url}' | jq -s .
}

# Oldest first, unassigned, issues only (the issues endpoint also lists PRs).
host_issues_ready() { # <label>
  api "$R/issues?state=open&assignee=none&sort=created&direction=asc&per_page=100&labels=$(jq -rn --arg l "$1" '$l | @uri')" \
    --paginate --jq '.[] | select(.pull_request == null) | {number, title, created_at}' | jq -s .
}
