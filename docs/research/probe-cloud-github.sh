#!/usr/bin/env bash
# Probe v2 for issue #28: can a Claude Code on the web sandbox make every GitHub
# call ship's adapter (skills/ship/scripts/host/github.sh) makes?
#
# v1 (probe-gh-proxy.sh) could not answer: `gh` is absent from the sandbox image,
# so all 24 REST rows died at rc=127 without touching the network. v2 splits the
# two questions v1 conflated:
#
#   A. Can `gh` be obtained in the sandbox at all? (section "gh acquisition")
#   B. Does the proxy pass the calls themselves? (asked with curl, which is
#      always present, then again with gh if A succeeded)
#
# Every call goes through one `req` so both clients exercise the same matrix.
# One row per call: name | allowed|blocked|api-error|failed | http | detail | ms.
# Scratch resources only: a scratch issue and a PR from probe/head-* into
# probe/base-* (never main). Ref deletion is 403 in the sandbox (v1 finding), so
# teardown of branches is printed as a command to run locally.
set -u

TS=$(date +%s)
REPO=${PROBE_REPO:-$(git remote get-url origin 2>/dev/null | sed -E 's#\.git$##; s#.*[/:]([^/]+/[^/]+)$#\1#')}
OWNER=${REPO%%/*}
LOG=${PROBE_LOG:-probe-cloud-github-results.md}
API=${GH_API:-https://api.github.com}
TOKEN=${GH_TOKEN:-${GITHUB_TOKEN:-}}
CLIENT=curl
: >"$LOG"

say() { printf '%s\n' "$*" | tee -a "$LOG"; }
row() { printf '| %s | %s | %s | %s | %s |\n' "$1" "$2" "$3" "${4//|/\\|}" "$5" | tee -a "$LOG"; }
hdr() { printf '\n### %s\n\n| call | verdict | http | detail | ms |\n|---|---|---|---|---|\n' "$1" | tee -a "$LOG"; }

# verdict <rc> <http> <stderr>: 2xx allowed; 403/407 blocked (proxy or perms,
# read the detail); any other status means the proxy passed the call through;
# no status at all means the call never reached the network.
verdict() {
  local rc=$1 http=$2
  case "$http" in
    2??) echo allowed ;;
    403|407) echo blocked ;;
    "") [ "$rc" -eq 0 ] && echo allowed || echo failed ;;
    *) echo api-error ;;
  esac
}

OUT=""
# req <name> <METHOD> <path> [json-body] -- sets OUT to the response body.
req() {
  local name=$1 m=$2 p=$3 body=${4:-} t0 t1 rc http err resp
  t0=$(date +%s%3N)
  if [ "$CLIENT" = gh ]; then
    if [ -n "$body" ]; then OUT=$(gh api -X "$m" "$p" --input - <<<"$body" 2>/tmp/probe-err); rc=$?
    else OUT=$(gh api -X "$m" "$p" 2>/tmp/probe-err); rc=$?; fi
    err=$(head -c 300 /tmp/probe-err | tr '\n' ' ')
    http=$(grep -oE 'HTTP [0-9]{3}' <<<"$err" | head -1 | cut -d' ' -f2)
    [ "$rc" -eq 0 ] && http=200
    [ "$rc" -eq 127 ] && err="gh: command not found"
  else
    local -a args=(-sS -m 30 -w $'\n%{http_code}' -X "$m"
      -H "Authorization: Bearer $TOKEN"
      -H 'Accept: application/vnd.github+json'
      -H 'X-GitHub-Api-Version: 2022-11-28')
    [ -n "$body" ] && args+=(-H 'Content-Type: application/json' --data "$body")
    resp=$(curl "${args[@]}" "$API/$p" 2>/tmp/probe-err); rc=$?
    http=$(tail -1 <<<"$resp"); OUT=$(sed '$d' <<<"$resp")
    [ "$http" = 000 ] && http=""
    err=$(head -c 300 /tmp/probe-err | tr '\n' ' ')
    [ -z "$err" ] && [ "${http:0:1}" != 2 ] && err=$(head -c 250 <<<"$OUT" | tr '\n' ' ')
  fi
  t1=$(date +%s%3N)
  row "$name" "$(verdict "$rc" "${http:-}")" "${http:-}" "${err:-}" "$((t1 - t0))"
}

# shell <name> <cmd...> -- for git and installer commands, which have no status code.
shell() {
  local name=$1; shift
  local t0 t1 rc err http
  t0=$(date +%s%3N)
  OUT=$("$@" 2>/tmp/probe-err); rc=$?
  t1=$(date +%s%3N)
  err=$(head -c 300 /tmp/probe-err | tr '\n' ' ')
  http=$(grep -oE '(HTTP|error) [0-9]{3}' <<<"$err" | grep -oE '[0-9]{3}' | head -1)
  row "$name" "$(verdict "$rc" "${http:-}")" "${http:-}" "${err:-}" "$((t1 - t0))"
  return $rc
}

jqr() { jq -r "$1" <<<"$OUT" 2>/dev/null; }

{
  echo "# Cloud sandbox GitHub probe v2: $REPO, $(date -u +%FT%TZ)"
  echo
  echo '## Environment'
  echo
  echo '```'
  echo "gh:    $(command -v gh >/dev/null && gh --version | head -1 || echo MISSING)"
  echo "curl:  $(command -v curl >/dev/null && curl --version | head -1 || echo MISSING)"
  echo "jq:    $(command -v jq >/dev/null && jq --version || echo MISSING)"
  echo "git:   $(git --version)"
  echo "uid:   $(id -u) ($(id -un)); sudo: $(command -v sudo >/dev/null && echo yes || echo no)"
  echo "distro: $(. /etc/os-release 2>/dev/null && echo "$PRETTY_NAME")"
  echo "remote origin: $(git remote get-url origin 2>/dev/null)"
  echo "GH_TOKEN set: $([ -n "${GH_TOKEN:-}" ] && echo yes || echo no); GITHUB_TOKEN set: $([ -n "${GITHUB_TOKEN:-}" ] && echo yes || echo no)"
  echo "proxy set: HTTPS_PROXY=$([ -n "${HTTPS_PROXY:-}" ] && echo yes || echo no) HTTP_PROXY=$([ -n "${HTTP_PROXY:-}" ] && echo yes || echo no) NO_PROXY=$([ -n "${NO_PROXY:-}" ] && echo yes || echo no)"
  echo "NO_PROXY hosts: ${NO_PROXY:-}"
  echo '```'
  echo
  echo "> Redact the proxy address and any token before pasting this into a public issue."
} | tee -a "$LOG"

# ---------------------------------------------------------------- A: gh acquisition
hdr "gh acquisition (question A)"
if command -v gh >/dev/null; then
  row "gh already present" allowed "" "$(gh --version | head -1)" 0
else
  shell "curl https://cli.github.com (apt repo host)" curl -sS -m 20 -o /dev/null -w '%{http_code}' https://cli.github.com/packages/githubcli-archive-keyring.gpg || true
  shell "apt-get install -y gh" bash -c 'apt-get install -y gh </dev/null' || true
  command -v gh >/dev/null || {
    # Latest release via the API: also tells us whether the proxy scopes api.github.com to this repo only.
    req "GET repos/cli/cli/releases/latest (other-repo API read)" GET repos/cli/cli/releases/latest
    GHURL=$(jqr '.assets[]?|select(.name|test("linux_amd64.tar.gz$"))|.browser_download_url' | head -1)
    if [ -n "${GHURL:-}" ]; then
      shell "curl release tarball ($(sed -E 's#https://([^/]+)/.*#\1#' <<<"$GHURL"))" \
        curl -fsSL -m 120 -o /tmp/gh.tgz "$GHURL" &&
        shell "extract + install to /usr/local/bin" bash -c \
          'tar -xzf /tmp/gh.tgz -C /tmp && install -m755 /tmp/gh_*/bin/gh /usr/local/bin/gh 2>/dev/null || install -m755 /tmp/gh_*/bin/gh "$HOME/.local/bin/gh"'
    else
      row "resolve latest gh release asset" failed "" "no linux_amd64 asset in the response" 0
    fi
  }
  command -v gh >/dev/null || export PATH="$HOME/.local/bin:$PATH"
  row "gh after install attempts" "$(command -v gh >/dev/null && echo allowed || echo failed)" "" \
    "$(command -v gh >/dev/null && gh --version | head -1 || echo 'still MISSING')" 0
fi

# ---------------------------------------------------------------- B: the call matrix
matrix() {
  CLIENT=$1
  say ""
  say "## Call matrix via \`$CLIENT\`"
  local R="repos/$REPO" ISSUE PR SHA BASE HEAD ME

  hdr "$CLIENT: identity and repo"
  req "GET user" GET user; ME=$(jqr .login)
  req "GET repos/{o}/{r}" GET "$R"
  req "GET rate_limit" GET rate_limit

  hdr "$CLIENT: issues"
  req "POST issues (scratch)" POST "$R/issues" \
    "$(jq -nc --arg t "probe: cloud github $CLIENT $TS (scratch)" '{title:$t,body:"Scratch issue for #28. Safe to close."}')"
  ISSUE=$(jqr .number); [ -n "$ISSUE" ] && [ "$ISSUE" != null ] || ISSUE=28
  req "GET issues/{n}" GET "$R/issues/$ISSUE"
  req "GET issues/{n}/comments" GET "$R/issues/$ISSUE/comments?per_page=100"
  req "POST issues/{n}/comments" POST "$R/issues/$ISSUE/comments" "$(jq -nc --arg b "probe comment $TS" '{body:$b}')"
  req "GET issues/{n}/timeline" GET "$R/issues/$ISSUE/timeline?per_page=100"
  req "GET issues/{n}/dependencies/blocked_by" GET "$R/issues/$ISSUE/dependencies/blocked_by"
  req "POST issues/{n}/assignees" POST "$R/issues/$ISSUE/assignees" "$(jq -nc --arg u "$ME" '{assignees:[$u]}')"
  req "DELETE issues/{n}/assignees" DELETE "$R/issues/$ISSUE/assignees" "$(jq -nc --arg u "$ME" '{assignees:[$u]}')"
  req "GET issues/{n}/labels" GET "$R/issues/$ISSUE/labels"
  req "POST issues/{n}/labels" POST "$R/issues/$ISSUE/labels" '{"labels":["needs-triage"]}'
  req "DELETE issues/{n}/labels/{l}" DELETE "$R/issues/$ISSUE/labels/needs-triage"
  req "GET issues?labels=ready-for-agent" GET "$R/issues?state=open&assignee=none&sort=created&direction=asc&per_page=100&labels=ready-for-agent"

  hdr "$CLIENT: git over the proxy"
  BASE=probe/base-$CLIENT-$TS; HEAD=probe/head-$CLIENT-$TS
  shell "git ls-remote" git ls-remote --heads origin main
  shell "git fetch origin main" git fetch -q origin main
  git branch -f "$BASE" FETCH_HEAD >/dev/null 2>&1
  git branch -f "$HEAD" FETCH_HEAD >/dev/null 2>&1
  shell "git push base branch" git push -q origin "$BASE"
  git checkout -q "$HEAD" 2>/dev/null && {
    echo "probe $TS" >"probe-$TS.txt"; git add "probe-$TS.txt"
    git -c user.name=probe -c user.email=probe@example.invalid commit -qm "probe: scratch commit $TS"
  }
  shell "git push head branch" git push -q origin "$HEAD"
  SHA=$(git rev-parse HEAD)

  hdr "$CLIENT: pull requests"
  req "POST pulls (non-draft)" POST "$R/pulls" \
    "$(jq -nc --arg h "$HEAD" --arg b "$BASE" --arg t "probe: scratch PR $TS" '{head:$h,base:$b,title:$t,body:"Scratch PR for #28.",draft:false}')"
  PR=$(jqr .number)
  if [ -n "$PR" ] && [ "$PR" != null ]; then
    req "GET pulls?head=" GET "$R/pulls?state=all&head=$OWNER:$HEAD&per_page=1"
    req "GET pulls/{n} (mergeable)" GET "$R/pulls/$PR"
    req "PATCH pulls/{n} (body)" PATCH "$R/pulls/$PR" "$(jq -nc --arg b "Body updated $TS." '{body:$b}')"
    req "GET commits/{sha}/check-runs" GET "$R/commits/$SHA/check-runs"
    req "GET commits/{sha}/status" GET "$R/commits/$SHA/status"
    req "GET pulls/{n}/reviews" GET "$R/pulls/$PR/reviews"
    req "GET pulls/{n}/comments" GET "$R/pulls/$PR/comments"
    req "POST pulls/{n}/comments (thread)" POST "$R/pulls/$PR/comments" \
      "$(jq -nc --arg b "probe thread $TS" --arg c "$SHA" --arg p "probe-$TS.txt" '{body:$b,commit_id:$c,path:$p,line:1,side:"RIGHT"}')"
    # Requesting the author on purpose: a GitHub 422 proves the proxy passed the call with no side effect.
    req "POST pulls/{n}/requested_reviewers (self, expect 422)" POST "$R/pulls/$PR/requested_reviewers" "$(jq -nc --arg u "$ME" '{reviewers:[$u]}')"
    req "GET pulls/{n}/requested_reviewers" GET "$R/pulls/$PR/requested_reviewers"
    req "POST issues/{pr}/comments (merge summary)" POST "$R/issues/$PR/comments" "$(jq -nc --arg b "probe merge-summary $TS" '{body:$b}')"

    hdr "$CLIENT: graphql"
    local Q='query($o:String!,$r:String!,$n:Int!){repository(owner:$o,name:$r){pullRequest(number:$n){reviewThreads(first:100){nodes{id isResolved}}}}}'
    req "GraphQL reviewThreads{isResolved}" POST graphql \
      "$(jq -nc --arg q "$Q" --arg o "$OWNER" --arg r "${REPO##*/}" --argjson n "$PR" '{query:$q,variables:{o:$o,r:$r,n:$n}}')"
    local TID; TID=$(jqr '.data.repository.pullRequest.reviewThreads.nodes[0].id // empty')
    if [ -n "$TID" ]; then
      req "GraphQL resolveReviewThread" POST graphql \
        "$(jq -nc --arg id "$TID" '{query:"mutation($id:ID!){resolveReviewThread(input:{threadId:$id}){thread{isResolved}}}",variables:{id:$id}}')"
    else
      row "GraphQL resolveReviewThread" skipped "" "no thread id from the read" 0
    fi

    hdr "$CLIENT: merge and teardown"
    req "PUT pulls/{n}/merge (squash into scratch base)" PUT "$R/pulls/$PR/merge" \
      "$(jq -nc --arg t "probe: scratch squash $TS" '{merge_method:"squash",commit_title:$t}')"
    req "GET pulls/{n} after merge" GET "$R/pulls/$PR"
  else
    hdr "$CLIENT: merge and teardown"
  fi
  req "PATCH issues/{n} (close)" PATCH "$R/issues/$ISSUE" '{"state":"closed","state_reason":"completed"}'
  git checkout -q --detach FETCH_HEAD 2>/dev/null
  shell "git push --delete head" git push -q origin --delete "$HEAD" || true
  shell "git push --delete base" git push -q origin --delete "$BASE" || true
  git branch -D "$HEAD" "$BASE" >/dev/null 2>&1
  say ""
  say "scratch for \`$CLIENT\`: issue #$ISSUE, PR #${PR:-none}, branches $HEAD $BASE"
}

# PROBE_CLIENTS overrides which clients run; default is curl plus gh when present.
for c in ${PROBE_CLIENTS:-curl gh}; do
  if [ "$c" = gh ] && ! command -v gh >/dev/null; then
    say $'\n## Call matrix via `gh`\n\nSkipped: gh could not be obtained (see "gh acquisition").'
    continue
  fi
  matrix "$c"
done

say ""
say "## Local teardown"
say ""
say 'If the `git push --delete` rows are `blocked`, delete the scratch refs from a local clone:'
say ''
say '```'
say "git push origin --delete $(git ls-remote --heads origin 'probe/*' 2>/dev/null | sed -E 's#.*refs/heads/##' | tr '\n' ' ')"
say '```'
say ''
say "results in $LOG"
