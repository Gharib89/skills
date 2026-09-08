#!/usr/bin/env bash
# Probe: does the Claude Code on the web GitHub proxy pass every call ship's
# GitHub adapter (skills/ship/scripts/host/github.sh) makes? One row per call:
# name | allowed|blocked|api-error | http status | first stderr line | ms.
# Scratch resources only: a scratch issue and a PR from probe/head-* into
# probe/base-* (never main); everything is torn down at the end.
set -u
TS=$(date +%s)
REPO=${PROBE_REPO:-$(git remote get-url origin 2>/dev/null | sed -E 's#\.git$##; s#.*[/:]([^/]+/[^/]+)$#\1#')}
R="repos/$REPO"
LOG=${PROBE_LOG:-probe-gh-proxy-results.md}
: >"$LOG"
row() { printf '| %s | %s | %s | %s | %s |\n' "$@" | tee -a "$LOG"; }
hdr() { printf '\n### %s\n\n| call | verdict | http | detail | ms |\n|---|---|---|---|---|\n' "$1" | tee -a "$LOG"; }
OUT=""
# probe <name> <cmd...>: runs, classifies. 403 with proxy wording = blocked; other 4xx = api-error (proxy passed it).
probe() {
  local name=$1; shift
  local err t0 t1 rc http detail verdict
  t0=$(date +%s%3N)
  OUT=$("$@" 2>/tmp/probe-err); rc=$?
  t1=$(date +%s%3N)
  err=$(head -c 300 /tmp/probe-err | tr '\n' ' ')
  http=$(grep -oE 'HTTP [0-9]{3}' <<<"$err" | head -1 | cut -d' ' -f2)
  if [ $rc -eq 0 ]; then verdict=allowed; detail="";
  elif grep -qiE 'proxy|not allowed|forbidden by|blocked|policy' <<<"$err" && [ "${http:-403}" = 403 ]; then verdict=blocked; detail=$err;
  elif [ -n "$http" ]; then verdict=api-error; detail=$err;
  else verdict=failed; detail="rc=$rc $err"; fi
  row "$name" "$verdict" "${http:-}" "${detail//|/\\|}" "$((t1-t0))"
}

{
echo "# GitHub proxy probe: $REPO, $(date -u +%FT%TZ)"
echo
echo '## Environment'
echo
echo '```'
echo "gh:  $(command -v gh >/dev/null && gh --version | head -1 || echo MISSING)"
echo "jq:  $(command -v jq >/dev/null && jq --version || echo MISSING)"
echo "git: $(git --version)"
echo "remote origin: $(git remote get-url origin 2>/dev/null)"
echo "GH_TOKEN set: $([ -n "${GH_TOKEN:-}" ] && echo yes || echo no); GITHUB_TOKEN set: $([ -n "${GITHUB_TOKEN:-}" ] && echo yes || echo no); GH_HOST=${GH_HOST:-}"
echo "proxy env: HTTPS_PROXY=${HTTPS_PROXY:-} HTTP_PROXY=${HTTP_PROXY:-} NO_PROXY=${NO_PROXY:-}"
env | grep -iE 'proxy|claude|sandbox' | grep -viE 'token|key|secret' | sed 's/=.*//' | tr '\n' ' '; echo
echo "gh auth status:"; gh auth status 2>&1 | sed 's/^/  /'
echo "git config http:"; git config --show-origin --get-regexp 'http\.|url\.|credential' 2>/dev/null | sed 's/^/  /'
echo '```'
} | tee -a "$LOG"

hdr "Identity and repo"
probe "GET user"                    gh api user --jq .login;  ME=$OUT
probe "GET repos/{o}/{r}"           gh api "$R" --jq .permissions
probe "GET rate_limit"              gh api rate_limit --jq .rate.remaining

hdr "Issues"
probe "POST issues (scratch)"       gh api -X POST "$R/issues" -f title="probe: gh proxy $TS (scratch, auto-closed)" -f body="Scratch issue for #28. Safe to delete." --jq .number; ISSUE=$OUT
[ -z "$ISSUE" ] && { echo "no scratch issue, falling back to 28"; ISSUE=28; }
probe "GET issues/{n}"              gh api "$R/issues/$ISSUE" --jq .state
probe "GET issues/{n}/comments"     gh api "$R/issues/$ISSUE/comments" --paginate --jq length
probe "POST issues/{n}/comments"    gh api -X POST "$R/issues/$ISSUE/comments" -f body="probe comment $TS" --jq .id
probe "GET issues/{n}/timeline"     gh api "$R/issues/$ISSUE/timeline" --paginate --jq length
probe "GET issues/{n}/dependencies/blocked_by" gh api "$R/issues/$ISSUE/dependencies/blocked_by" --paginate --jq length
probe "POST issues/{n}/assignees"   gh api -X POST "$R/issues/$ISSUE/assignees" -f "assignees[]=$ME" --jq '.assignees|length'
probe "DELETE issues/{n}/assignees" gh api -X DELETE "$R/issues/$ISSUE/assignees" -f "assignees[]=$ME" --jq '.assignees|length'
probe "GET issues/{n}/labels"       gh api "$R/issues/$ISSUE/labels" --jq length
probe "POST issues/{n}/labels"      gh api -X POST "$R/issues/$ISSUE/labels" -f "labels[]=needs-triage" --jq length
probe "DELETE issues/{n}/labels/{l}" gh api -X DELETE "$R/issues/$ISSUE/labels/needs-triage" --jq length
probe "GET issues?labels=ready-for-agent" gh api "$R/issues?state=open&assignee=none&sort=created&direction=asc&per_page=100&labels=ready-for-agent" --paginate --jq length

hdr "Git over the proxy"
BASE=probe/base-$TS; HEAD=probe/head-$TS
probe "git ls-remote"               git ls-remote --heads origin main
probe "git fetch origin main"       git fetch -q origin main
git branch -f "$BASE" FETCH_HEAD >/dev/null 2>&1
git branch -f "$HEAD" FETCH_HEAD >/dev/null 2>&1
probe "git push base branch"        git push -q origin "$BASE"
git checkout -q "$HEAD" 2>/dev/null && { echo "probe $TS" >"probe-$TS.txt"; git add "probe-$TS.txt"; git -c user.name=probe -c user.email=probe@example.invalid commit -qm "probe: scratch commit $TS"; }
probe "git push head branch"        git push -q origin "$HEAD"
SHA=$(git rev-parse HEAD)

hdr "Pull requests"
probe "POST pulls (non-draft)"      gh api -X POST "$R/pulls" -f head="$HEAD" -f base="$BASE" -f title="probe: scratch PR $TS" -f body="Scratch PR for #28. Closes nothing." -F draft=false --jq .number; PR=$OUT
if [ -n "$PR" ]; then
probe "GET pulls?head="             gh api "$R/pulls?state=all&head=${REPO%%/*}:$HEAD&per_page=1" --jq '.[0].number'
probe "GET pulls/{n} (mergeable)"   gh api "$R/pulls/$PR" --jq '{mergeable, mergeable_state}'
probe "PATCH pulls/{n} (body)"      gh api -X PATCH "$R/pulls/$PR" -f body="Scratch PR for #28. Body updated $TS." --jq .number
probe "GET commits/{sha}/check-runs" gh api "$R/commits/$SHA/check-runs" --paginate --jq .total_count
probe "GET commits/{sha}/status"    gh api "$R/commits/$SHA/status" --jq .state
probe "GET pulls/{n}/reviews"       gh api "$R/pulls/$PR/reviews" --paginate --jq length
probe "GET pulls/{n}/comments"      gh api "$R/pulls/$PR/comments" --paginate --jq length
probe "POST pulls/{n}/comments (thread)" gh api -X POST "$R/pulls/$PR/comments" -f body="probe thread $TS" -f commit_id="$SHA" -f path="probe-$TS.txt" -F line=1 -f side=RIGHT --jq .id
probe "POST pulls/{n}/requested_reviewers (self, expect 422)" gh api -X POST "$R/pulls/$PR/requested_reviewers" -f "reviewers[]=$ME" --jq .number
probe "GET pulls/{n}/requested_reviewers" gh api "$R/pulls/$PR/requested_reviewers" --jq '.users|length'
probe "GET issues/{pr}/comments (PR comments)" gh api "$R/issues/$PR/comments" --paginate --jq length
probe "POST issues/{pr}/comments (merge summary)" gh api -X POST "$R/issues/$PR/comments" -f body="probe merge-summary comment $TS" --jq .id

hdr "GraphQL"
Q='query($o:String!,$r:String!,$n:Int!){repository(owner:$o,name:$r){pullRequest(number:$n){reviewThreads(first:100){nodes{id isResolved}}}}}'
probe "GraphQL reviewThreads{isResolved}" gh api graphql -f query="$Q" -F o="${REPO%%/*}" -F r="${REPO##*/}" -F n="$PR" --jq '.data.repository.pullRequest.reviewThreads.nodes'
TID=$(jq -r '.[0].id // empty' <<<"$OUT" 2>/dev/null)
if [ -n "$TID" ]; then
probe "GraphQL resolveReviewThread"  gh api graphql -f query='mutation($id:ID!){resolveReviewThread(input:{threadId:$id}){thread{isResolved}}}' -F id="$TID" --jq .data.resolveReviewThread.thread.isResolved
else row "GraphQL resolveReviewThread" skipped "" "no thread id from the read" 0; fi
probe "GraphQL viewer (control)"     gh api graphql -f query='{viewer{login}}' --jq .data.viewer.login

hdr "Merge and teardown"
probe "PUT pulls/{n}/merge (squash into scratch base)" gh api -X PUT "$R/pulls/$PR/merge" -f merge_method=squash -f commit_title="probe: scratch squash $TS" --jq .merged
probe "GET pulls/{n} after merge"   gh api "$R/pulls/$PR" --jq .merged
fi
probe "PATCH issues/{n} (close)"    gh api -X PATCH "$R/issues/$ISSUE" -f state=closed -f state_reason=completed --jq .state
git checkout -q --detach FETCH_HEAD 2>/dev/null
probe "git push --delete head"      git push -q origin --delete "$HEAD"
probe "git push --delete base"      git push -q origin --delete "$BASE"
git branch -D "$HEAD" "$BASE" >/dev/null 2>&1
printf '\nscratch: issue #%s, PR #%s, branches %s %s (deleted)\n' "$ISSUE" "${PR:-none}" "$HEAD" "$BASE" | tee -a "$LOG"
echo "results in $LOG"
