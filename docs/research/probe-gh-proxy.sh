#!/usr/bin/env bash
# Probe: does the Claude Code on the web GitHub proxy pass every call ship's
# GitHub adapter (skills/ship/scripts/host/github.sh) makes? One row per call:
# name | allowed|blocked|api-error|failed | http status | stderr head | ms.
# Any HTTP 403 is `blocked`: GitHub itself never 403s the repo owner on these
# calls, so a 403 here is the proxy's. Scratch resources only: a scratch issue
# and a PR from probe/head-* into probe/base-* (never main), torn down at the
# end. If scratch creation fails, the write rows are skipped: nothing on the
# real ticket is ever modified.
# Run 1 (2026-09-08) found no `gh` in the sandbox, so this version first tries
# to install it (apt, then the release tarball) and otherwise shims `gh api`
# over curl with GH_TOKEN, so the REST rows are measured either way.
set -u
TS=$(date +%s)
REPO=${PROBE_REPO:-$(git remote get-url origin 2>/dev/null | sed -E 's#\.git$##; s#.*[/:]([^/]+/[^/]+)$#\1#')}
OWNER=${REPO%%/*}; NAME=${REPO##*/}
R="repos/$REPO"
LOG=${PROBE_LOG:-probe-gh-proxy-results.md}
GH_PIN=${GH_PIN:-2.46.0}
: >"$LOG"
row() { printf '| %s | %s | %s | %s | %s |\n' "$@" | tee -a "$LOG"; }
hdr() { printf '\n### %s\n\n| call | verdict | http | detail | ms |\n|---|---|---|---|---|\n' "$1" | tee -a "$LOG"; }
note() { printf '\n%s\n' "$*" | tee -a "$LOG"; }
OUT=""
probe() {
  local name=$1; shift
  local err t0 t1 rc http detail verdict
  t0=$(date +%s%3N)
  OUT=$("$@" 2>/tmp/probe-err); rc=$?
  t1=$(date +%s%3N)
  err=$(head -c 400 /tmp/probe-err | tr '\n' ' ')
  http=$(grep -oE 'HTTP[ /][0-9.]* ?[0-9]{3}|error: [0-9]{3}' <<<"$err" | grep -oE '[0-9]{3}$' | head -1)
  if [ $rc -eq 0 ]; then verdict=allowed; detail="";
  elif [ "${http:-}" = 403 ]; then verdict=blocked; detail=$err;
  elif [ -n "$http" ]; then verdict=api-error; detail=$err;
  else verdict=failed; detail="rc=$rc $err"; fi
  row "$name" "$verdict" "${http:-}" "${detail//|/\\|}" "$((t1-t0))"
}

# ---- gh presence, install attempts, curl shim ------------------------------
GH_MODE=binary
if ! command -v gh >/dev/null; then
  hdr "gh install attempts"
  if command -v apt-get >/dev/null; then
    probe "apt-get install gh" bash -c 'SUDO=""; [ "$(id -u)" = 0 ] || SUDO=sudo; $SUDO apt-get update -qq >/dev/null && $SUDO apt-get install -y -qq gh >/dev/null && command -v gh'
  else row "apt-get install gh" skipped "" "no apt-get" 0; fi
  if ! command -v gh >/dev/null; then
    probe "download gh $GH_PIN tarball from github.com releases" bash -c "curl -fsSL -o /tmp/gh.tgz https://github.com/cli/cli/releases/download/v$GH_PIN/gh_${GH_PIN}_linux_amd64.tar.gz && tar -xzf /tmp/gh.tgz -C /tmp && install -m755 /tmp/gh_${GH_PIN}_linux_amd64/bin/gh /usr/local/bin/gh 2>/dev/null || { mkdir -p \$HOME/.local/bin && install -m755 /tmp/gh_${GH_PIN}_linux_amd64/bin/gh \$HOME/.local/bin/gh; }"
    export PATH="$HOME/.local/bin:/usr/local/bin:$PATH"
  fi
  if command -v gh >/dev/null; then GH_MODE=installed; else GH_MODE=curl-shim; fi
fi
if [ "$GH_MODE" = curl-shim ]; then
  # Minimal `gh api` over curl: -X, -f k=v (string), -F k=v (typed), --input FILE|-,
  # --jq, --paginate (single page), `graphql` with -f query= and -F vars.
  # Non-2xx prints "HTTP <code> <body head>" to stderr and exits 1, like gh.
  gh() {
    [ "$1" = api ] || { echo "shim: only 'gh api' supported" >&2; return 1; }
    shift
    local method="" apipath="" jqf="" body="" input="" gql=0 k v
    local -a fields=()
    while [ $# -gt 0 ]; do
      case $1 in
        -X) method=$2; shift 2;;
        -f) fields+=("$(jq -cn --arg k "${2%%=*}" --arg v "${2#*=}" '{($k): $v}')"); shift 2;;
        -F) k=${2%%=*}; v=${2#*=}; fields+=("$(jq -cn --arg k "$k" --arg v "$v" '{($k): ($v | (tonumber? // (if . == "true" then true elif . == "false" then false else . end)))}')"); shift 2;;
        --input) input=$2; shift 2;;
        --jq) jqf=$2; shift 2;;
        --paginate) shift;;
        graphql) gql=1; shift;;
        *) apipath=$1; shift;;
      esac
    done
    if [ -n "$input" ]; then body=$(cat "$input");
    elif [ ${#fields[@]} -gt 0 ]; then
      body=$(printf '%s\n' "${fields[@]}" | jq -cs 'reduce .[] as $o ({}; . as $acc | reduce ($o | to_entries[]) as $e ($acc; if ($e.key | endswith("[]")) then .[$e.key[:-2]] += [$e.value] else .[$e.key] = $e.value end))')
    fi
    local url
    if [ $gql = 1 ]; then
      url=https://api.github.com/graphql; method=POST
      body=$(jq -cn --argjson f "$body" '{query: $f.query, variables: ($f | del(.query))}')
    else
      url="https://api.github.com/${apipath#/}"
      [ -z "$method" ] && { [ -n "$body" ] && method=POST || method=GET; }
    fi
    local resp code
    resp=$(curl -sS -X "$method" -H "Authorization: Bearer ${GH_TOKEN:-${GITHUB_TOKEN:-}}" -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28" \
      ${body:+-H "Content-Type: application/json" --data-binary "$body"} -w '\n%{http_code}' "$url") || return 1
    code=${resp##*$'\n'}; resp=${resp%$'\n'*}
    case $code in
      2*) if [ -n "$jqf" ]; then jq -r "$jqf" <<<"${resp:-null}"; else printf '%s\n' "$resp"; fi;;
      *) echo "HTTP $code $(head -c 200 <<<"$resp" | tr '\n' ' ')" >&2; return 1;;
    esac
  }
fi

{
echo "# GitHub proxy probe: $REPO, $(date -u +%FT%TZ)"
echo
echo '## Environment'
echo
echo '```'
echo "gh mode: $GH_MODE"
echo "gh:  $(command -v gh >/dev/null && gh --version 2>/dev/null | head -1 || echo MISSING)"
echo "jq:  $(command -v jq >/dev/null && jq --version || echo MISSING)"
echo "curl: $(curl --version | head -1)"
echo "git: $(git --version)"
echo "user: $(id -un) uid=$(id -u); HOME=$HOME; pwd=$(pwd)"
echo "remote origin: $(git remote get-url origin 2>/dev/null)"
echo "GH_TOKEN set: $([ -n "${GH_TOKEN:-}" ] && echo yes || echo no) (prefix $(printf '%s' "${GH_TOKEN:-}" | head -c 4)...); GITHUB_TOKEN set: $([ -n "${GITHUB_TOKEN:-}" ] && echo yes || echo no); same value: $([ "${GH_TOKEN:-a}" = "${GITHUB_TOKEN:-b}" ] && echo yes || echo no); GH_HOST=${GH_HOST:-}"
echo "proxy env: HTTPS_PROXY=$([ -n "${HTTPS_PROXY:-}" ] && echo set || echo empty) HTTP_PROXY=$([ -n "${HTTP_PROXY:-}" ] && echo set || echo empty) NO_PROXY=$([ -n "${NO_PROXY:-}" ] && echo set || echo empty)"
echo "gh auth status:"; gh auth status 2>&1 | sed 's/^/  /' | head -8
echo "git config http:"; git config --show-origin --get-regexp 'http\.|url\.|credential' 2>/dev/null | sed 's/^/  /'
echo '```'
} | tee -a "$LOG"

hdr "Network controls (curl, independent of gh)"
probe "curl api.github.com/zen (no auth)"   curl -fsS https://api.github.com/zen
probe "curl api.github.com/user (GH_TOKEN)" curl -fsS -H "Authorization: Bearer ${GH_TOKEN:-}" https://api.github.com/user
probe "curl github.com/ (html)"             curl -fsS -o /dev/null https://github.com/
probe "curl objects.githubusercontent.com"  curl -fsS -o /dev/null -I https://objects.githubusercontent.com/

hdr "Identity and repo"
probe "GET user"                    gh api user --jq .login;  ME=$OUT
probe "GET repos/{o}/{r}"           gh api "$R" --jq .permissions
probe "GET rate_limit"              gh api rate_limit --jq .rate.remaining

hdr "Issues"
probe "POST issues (scratch)"       gh api -X POST "$R/issues" -f title="probe: gh proxy $TS (scratch, auto-closed)" -f body="Scratch issue for #28. Safe to delete." --jq .number; ISSUE=$OUT
if [ -n "$ISSUE" ]; then SCRATCH=1; else SCRATCH=0; ISSUE=28; note "Scratch issue creation failed: reads below hit #28, every write row is skipped."; fi
probe "GET issues/{n}"              gh api "$R/issues/$ISSUE" --jq .state
probe "GET issues/{n}/comments"     gh api "$R/issues/$ISSUE/comments" --paginate --jq length
probe "GET issues/{n}/timeline"     gh api "$R/issues/$ISSUE/timeline" --paginate --jq length
probe "GET issues/{n}/dependencies/blocked_by" gh api "$R/issues/$ISSUE/dependencies/blocked_by" --paginate --jq length
probe "GET issues/{n}/labels"       gh api "$R/issues/$ISSUE/labels" --jq length
probe "GET issues?labels=ready-for-agent" gh api "$R/issues?state=open&assignee=none&sort=created&direction=asc&per_page=100&labels=ready-for-agent" --paginate --jq length
if [ $SCRATCH = 1 ]; then
probe "POST issues/{n}/comments"    gh api -X POST "$R/issues/$ISSUE/comments" -f body="probe comment $TS" --jq .id
probe "POST issues/{n}/assignees"   gh api -X POST "$R/issues/$ISSUE/assignees" -f "assignees[]=$ME" --jq '.assignees|length'
probe "DELETE issues/{n}/assignees" gh api -X DELETE "$R/issues/$ISSUE/assignees" -f "assignees[]=$ME" --jq '.assignees|length'
probe "POST issues/{n}/labels"      gh api -X POST "$R/issues/$ISSUE/labels" -f "labels[]=needs-triage" --jq length
probe "DELETE issues/{n}/labels/{l}" gh api -X DELETE "$R/issues/$ISSUE/labels/needs-triage" --jq length
fi

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
probe "GET pulls?head="             gh api "$R/pulls?state=all&head=$OWNER:$HEAD&per_page=1" --jq '.[0].number'
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
probe "GraphQL reviewThreads{isResolved}" gh api graphql -f query="$Q" -F o="$OWNER" -F r="$NAME" -F n="$PR" --jq '.data.repository.pullRequest.reviewThreads.nodes'
TID=$(jq -r '.[0].id // empty' <<<"$OUT" 2>/dev/null)
if [ -n "$TID" ]; then
probe "GraphQL resolveReviewThread"  gh api graphql -f query='mutation($id:ID!){resolveReviewThread(input:{threadId:$id}){thread{isResolved}}}' -F id="$TID" --jq .data.resolveReviewThread.thread.isResolved
else row "GraphQL resolveReviewThread" skipped "" "no thread id from the read" 0; fi
probe "GraphQL viewer (control)"     gh api graphql -f query='{viewer{login}}' --jq .data.viewer.login

hdr "Merge"
probe "PUT pulls/{n}/merge (squash into scratch base)" gh api -X PUT "$R/pulls/$PR/merge" -f merge_method=squash -f commit_title="probe: scratch squash $TS" --jq .merged
probe "GET pulls/{n} after merge"   gh api "$R/pulls/$PR" --jq .merged
else note "No scratch PR: pulls, GraphQL and merge rows skipped."; fi

hdr "Teardown: ref deletion both ways"
[ $SCRATCH = 1 ] && probe "PATCH issues/{n} (close)" gh api -X PATCH "$R/issues/$ISSUE" -f state=closed -f state_reason=completed --jq .state
git checkout -q --detach FETCH_HEAD 2>/dev/null
# Run 1: `git push --delete` got 403 from the proxy. Try the REST ref delete on one
# branch and git on the other, then sweep whatever survived with the other method.
probe "DELETE git/refs/heads/{head} (REST)" gh api -X DELETE "$R/git/refs/heads/$HEAD"
probe "git push --delete base"      git push -q origin --delete "$BASE"
for b in "$HEAD" "$BASE"; do
  if git ls-remote --exit-code --heads origin "$b" >/dev/null 2>&1; then
    [ "$b" = "$HEAD" ] && probe "git push --delete head (sweep)" git push -q origin --delete "$b" \
                       || probe "DELETE git/refs/heads/{base} (REST sweep)" gh api -X DELETE "$R/git/refs/heads/$b"
  fi
done
git branch -D "$HEAD" "$BASE" >/dev/null 2>&1
LEFT=$(git ls-remote --heads origin "probe/*" 2>/dev/null | awk '{print $2}' | tr '\n' ' ')
note "scratch: issue #$ISSUE (scratch=$SCRATCH), PR #${PR:-none}, branches $HEAD $BASE; still on remote: ${LEFT:-none}"
echo "results in $LOG"
