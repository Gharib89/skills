#!/usr/bin/env bash
# Shared helpers for ship's generic mechanics. Sourced, never executed.
# Serves ship's own scripts only: a repo's local gate never sources this.
#
# Every mechanic prints one JSON object on stdout (built with jq -n), a failing
# step's last 40 log lines on stderr, and exits 0 ok / 1 real failure / 2 tooling.
#
# Host adapter interface. Each mechanic sources exactly one of host/github.sh or
# host/ado.sh, chosen from the origin remote, never from a flag. An adapter
# defines every function below; reads come back in one vocabulary on both hosts:
# checks pending|success|failure, mergeable clean|conflict|unknown, review
# approved|changes|comment, and threads as `resolved: true|false` per thread, or
# the whole `threads` field as the string "unavailable" when the state could not
# be read.
#
#   host_tooling_reasons                 -> one missing-tool reason per line
#   host_tooling_install                 -> install the host CLI where absent; non-zero = could not
#   host_identity                        -> the login the claim is written as
#   host_can_push                        -> true | false | unknown
#   host_issue_get <n>                   -> {number,title,body,state,is_pr,labels[],assignees[],created_at,url}
#   host_issue_comments <n>              -> [{author,body,created_at}]
#   host_issue_blockers_open <n>         -> [n, ...] open blockers; non-zero exit = query unavailable
#   host_issue_linked_prs <n>            -> {closing:[{number,state}], mentions:[{number,state}]} (live PRs)
#   host_issue_assign <n> <identity>
#   host_issue_unassign <n> <identity>
#   host_issue_has_label <n> <label>     -> exit 0 when present
#   host_issue_add_label <n> <label>
#   host_issue_remove_label <n> <label>  (no-op success when absent)
#   host_issue_comment <n> <body>
#   host_issue_close <n>
#   host_issue_create <title> <body-file> <label> -> {number,url}
#   host_issues_open                     -> [{number,title,url}] every open issue, newest first,
#                                           never a PR. Narrows only where the host refuses the
#                                           whole set, and says so on stderr when it does.
#   host_pr_create <head> <base> <title> <body-file> <issue> -> {number,url,created_at}
#   host_pr_get <pr>                     -> {number,url,title,body,head_sha,head_ref,base_ref,state,mergeable}
#   host_pr_for_branch <branch>          -> {number,state} of the newest PR with that head, or null
#   host_pr_checks <pr> <head_sha>       -> [{name,status}]
#   host_pr_reviews <pr> <head_sha> [<full-ids-json>]
#                                        -> {on_head:[REVIEW],all:[REVIEW],total}
#                                           REVIEW = {id,login,state,substantive,submitted_at,body}
#                                           id: what the host knows the round by (a GitHub review,
#                                           an Azure DevOps thread), null where it records a state
#                                           rather than a round. poll-pr --full names ids from here.
#                                           body: the round's text. Phase 7 triages from it.
#                                           Past 2000 chars it is clipped and marked
#                                           "...[truncated]", unless <full-ids-json> names its id;
#                                           "" where the host records a state rather than a
#                                           written round.
#                                           all: every round across heads, for poll-pr --since.
#                                           submitted_at: one UTC spelling, or null where the host
#                                           records state rather than a timed event (an ADO vote),
#                                           which the --since rule then cannot admit.
#   host_pr_threads <pr>                 -> [{id,resolved,replied,author,path,body}]; non-zero exit =
#                                           unavailable. replied: this identity has a comment in the
#                                           thread, which is how phase 7 skips a thread it already
#                                           dispositioned in an earlier round.
#                                           GitHub rows also carry comment_id, the thread's first
#                                           review comment: the REST reply target that host's
#                                           reply is keyed to. On Azure DevOps the thread id is
#                                           that target already.
#   host_pr_reviewer_blocked <pr> <login>-> JSON string | null
#   host_pr_request_review <pr> <login>  -> {requested,readback[],requested_at}
#                                           requested_at: ISO-8601 time of the request event,
#                                           or the wall clock where the host records none.
#   host_pr_comment <pr> <body-file>     -> {id,url}
#   host_pr_set_body <pr> <body-file>
#   host_pr_set_title <pr> <title>
#   host_pr_reply_thread <pr> <thread> <body-file> -> {replied,url}
#                                           A reply inside the thread, leaving its status alone.
#   host_pr_resolve_thread <pr> <thread> -> {resolved}
#   host_pr_merge <pr> <subject>         -> exit 0 once the host reports merged
#   host_prs_open                        -> [{number,title,head_ref,author,url,created_at}]
#   host_issues_ready <label>            -> [{number,title,created_at}] oldest first, unassigned, not PRs

SHIP_SCRIPTS=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
readonly SHIP_SCRIPTS
# shellcheck disable=SC2034  # read by the mechanics that source this library
readonly SHIP_CLAIM_COMMENT='🤖 Claimed by a ship run: implementation in progress.'

# ship_tooling <msg>: the exit-2 shape. Also used when the host adapter itself
# cannot load, so a broken install still emits the contract, not "command not found".
ship_tooling() { jq -n --arg e "$1" '{error: $e}'; exit 2; }
ship_fail()    { jq -n --arg e "$1" '{error: $e}'; exit 1; }

# ship_tail40 <file>: a failing step's evidence, never the whole log.
ship_tail40() { tail -n 40 "$1" >&2; }

# Branch convention: <type>/<slug>-<issue>. The "-<issue>" suffix is what
# preflight greps for on the remote.
ship_branch()           { printf '%s/%s-%s' "$1" "$2" "$3"; }
ship_branch_suffix_re() { printf -- '-%s$' "$1"; }

# The main checkout, even when run from inside a worktree: --git-common-dir
# points at the primary .git, so a run started in a worktree never nests another.
ship_main_checkout() {
  local common
  common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || return 1
  dirname "$common"
}

# Sibling container beside the checkout: <parent>/<repo>.worktrees
ship_worktree_container() {
  local root; root=$(ship_main_checkout) || return 1
  printf '%s/%s.worktrees' "$(dirname "$root")" "$(basename "$root")"
}

# The base ref, resolved from origin/HEAD, never a hardcoded branch (ADO
# defaults vary). Refreshes the symbolic ref when the clone never recorded it.
ship_base_ref() {
  local ref
  ref=$(git symbolic-ref -q refs/remotes/origin/HEAD 2>/dev/null) \
    || { git remote set-head origin -a >/dev/null 2>&1 \
         && ref=$(git symbolic-ref -q refs/remotes/origin/HEAD 2>/dev/null); } \
    || return 1
  printf '%s' "${ref#refs/remotes/}"
}
ship_base_branch() { local b; b=$(ship_base_ref) || return 1; printf '%s' "${b#origin/}"; }

# Host detection from the origin remote. Sets SHIP_HOST and the host's
# identifiers; no --host flag and no env var, because every Bash call is a fresh
# shell and a per-call flag is one more thing prose can get wrong.
ship_detect_host() {
  local url
  url=$(git remote get-url origin 2>/dev/null) || return 1
  case $url in
    *github.com[:/]*)
      SHIP_HOST=github
      local p=${url#*github.com}; p=${p#[:/]}; p=${p%.git}; p=${p%/}
      SHIP_OWNER=${p%%/*}; SHIP_REPO=${p#*/}
      SHIP_REPO_SLUG="$SHIP_OWNER/$SHIP_REPO" ;;
    *dev.azure.com/*)
      # https://[user@]dev.azure.com/<org>/<project>/_git/<repo>
      SHIP_HOST=ado
      local p=${url#*dev.azure.com/}; p=${p%.git}
      SHIP_ORG=${p%%/*}; p=${p#*/}
      SHIP_PROJECT=${p%%/_git/*}; SHIP_REPO=${p##*/_git/}
      SHIP_ORG_URL="https://dev.azure.com/$SHIP_ORG"
      SHIP_REPO_SLUG="$SHIP_ORG/$SHIP_PROJECT/$SHIP_REPO" ;;
    *@vs-ssh.visualstudio.com:v3/*)
      # git@ssh.dev.azure.com:v3/<org>/<project>/<repo> and the visualstudio.com twin
      SHIP_HOST=ado
      local p=${url#*:v3/}
      SHIP_ORG=${p%%/*}; p=${p#*/}
      SHIP_PROJECT=${p%%/*}; SHIP_REPO=${p#*/}
      SHIP_ORG_URL="https://dev.azure.com/$SHIP_ORG"
      SHIP_REPO_SLUG="$SHIP_ORG/$SHIP_PROJECT/$SHIP_REPO" ;;
    *ssh.dev.azure.com:v3/*)
      SHIP_HOST=ado
      local p=${url#*:v3/}
      SHIP_ORG=${p%%/*}; p=${p#*/}
      SHIP_PROJECT=${p%%/*}; SHIP_REPO=${p#*/}
      SHIP_ORG_URL="https://dev.azure.com/$SHIP_ORG"
      SHIP_REPO_SLUG="$SHIP_ORG/$SHIP_PROJECT/$SHIP_REPO" ;;
    *.visualstudio.com/*)
      # https://<org>.visualstudio.com/<project>/_git/<repo> (or DefaultCollection/)
      SHIP_HOST=ado
      local hostpart=${url#*://}; hostpart=${hostpart#*@}
      SHIP_ORG=${hostpart%%.visualstudio.com*}
      local p=${url#*.visualstudio.com/}; p=${p#DefaultCollection/}; p=${p%.git}
      SHIP_PROJECT=${p%%/_git/*}; SHIP_REPO=${p##*/_git/}
      SHIP_ORG_URL="https://dev.azure.com/$SHIP_ORG"
      SHIP_REPO_SLUG="$SHIP_ORG/$SHIP_PROJECT/$SHIP_REPO" ;;
    *) return 1 ;;
  esac
  SHIP_PROJECT=$(printf '%s' "${SHIP_PROJECT:-}" | sed 's/%20/ /g')
  export SHIP_HOST SHIP_OWNER SHIP_REPO SHIP_REPO_SLUG SHIP_ORG SHIP_PROJECT SHIP_ORG_URL
}

# ship_load_host: detect and source the adapter, or exit 2 with the contract.
ship_load_host() {
  ship_detect_host || ship_tooling "cannot derive the host from the origin remote"
  # shellcheck source=/dev/null
  source "$SHIP_SCRIPTS/host/$SHIP_HOST.sh" || ship_tooling "cannot load host adapter $SHIP_HOST"
}

# Triage roles are canonical names; the label strings a repo actually uses live
# in docs/agents/triage-labels.md (a fixed two-column table the setup skill
# writes). Falls back to the canonical name when the file or row is missing.
ship_triage_label() {
  local role=$1 root file label
  root=$(ship_main_checkout) || { printf '%s' "$role"; return; }
  file="$root/docs/agents/triage-labels.md"
  label=$(grep -E "^\| *\`$role\` *\|" "$file" 2>/dev/null | head -1 \
    | awk -F'|' '{print $3}' | tr -d '` ')
  printf '%s' "${label:-$role}"
}

# Closing-keyword test, the same on both hosts: does <body> claim to close
# <issue>? Fenced blocks and inline code come out first (a PR quoting
# "Closes #n" while discussing another PR mentions the issue, it does not claim
# it). The "(#n, and #m)" run lets a multi-issue "Closes #75, #81" count for #81.
ship_body_closes() { # ship_body_closes <body> <issue> -> exit 0 when it does
  jq -e -n --arg body "$1" --arg n "$2" '
    $body
    | gsub("(?s)```.*?```"; "") | gsub("`[^`]*`"; "")
    | test("\\b(clos(e[sd]?|ing)|fix(e[sd]|ing)?|resolv(e[sd]?|ing))"
           + "\\s+(#[0-9]+[\\s,]+(and[\\s,]+)?)*#" + $n + "\\b"; "i")' >/dev/null
}

# The one fence rule both heading transformations read: ship_body_replace_section
# below and _gh_add_closes in the GitHub adapter. A `## ` heading inside a fence
# is example text, so the two have to agree on where a fence starts and ends, or
# one rewrites the example and leaves the real section alone.
#
# CommonMark, as far as these two need it: an opening fence is three or more
# backticks or tildes under up to three leading spaces, and only a bare run of
# the same character at least as long closes it. The character rules a tilde
# fence in; the length keeps a ``` line inside a ```` fence from closing it and
# inverting the state for the rest of the body; the bareness keeps a ```js line
# inside a ``` fence from doing the same, since a closing fence carries no info
# string. Indented (four space) code blocks are not a fence form here.
#
# `ship_fence(line)` returns the in-fence state after the line: a fence line
# reads as fenced when it opens one and unfenced when it closes one. Prepend it
# to an awk program and call it once per line, before any heading test. It
# holds its state for the length of the input in the globals `_fenced`,
# `_fence_char` and `_fence_len`, so a host program leaves those three names to
# it.
readonly SHIP_AWK_FENCE='function ship_fence(line,   s, c, n) {
    s = line; sub(/^ ? ? ?/, "", s); c = substr(s, 1, 1)
    if (c != "`" && c != "~") return _fenced
    n = 0; while (substr(s, n + 1, 1) == c) n++
    if (n < 3) return _fenced
    if (!_fenced) { _fenced = 1; _fence_char = c; _fence_len = n }
    else if (c == _fence_char && n >= _fence_len && substr(s, n + 1) ~ /^[ \t]*$/) _fenced = 0
    return _fenced
  }
'

# Replace one `## <section>` of <body> with <body-file>'s content, appending the
# section when the body has none. Every other line is untouched, including a
# `Closes` line above the first heading. Prints the new body; exit 0 replaced,
# 1 created, the way ship_body_closes answers with its exit code.
#
# The heading match is anchored at column 0 and skips fenced blocks by
# SHIP_AWK_FENCE, the rule _gh_add_closes reads too, so the two agree on what a
# section boundary is.
ship_body_replace_section() { # ship_body_replace_section <body> <section> <body-file>
  awk -v sec="$2" -v file="$3" "$SHIP_AWK_FENCE"'
    function dump() { while ((getline line < file) > 0) print line; close(file) }
    { fenced = ship_fence($0) }
    !fenced && $0 ~ "^## " sec "[ \t]*$" {
      print; print ""; dump(); print ""; skip=1; placed=1; next }
    skip && !fenced && /^## / { skip=0 }
    !skip { print }
    END { if (!placed) { printf "\n## %s\n\n", sec; dump(); exit 1 } }' <<<"$1"
}

# Generic English function words of four or more characters; shorter ones the
# length rule already drops. No repo-specific word belongs here: the candidate
# check is generic, and an over-eager candidate costs one `--distinct-from`
# while a missed one costs a second issue for a find already filed.
readonly SHIP_TITLE_STOPWORDS='about also been both does each else from have here into just like made make more most much must only over same some such than that their them then there these they this those very were what when where which while will with would your'

# Titles that look like <title> among <open-issues>, for file-issue's candidate
# check. Compares lowercased tokens with punctuation as a separator, dropping
# tokens under four characters and the stopwords above; three or more shared
# tokens is a candidate. <exclude> is the JSON array of numbers the caller has
# read and judged different. Prints the candidates as compact JSON.
ship_title_candidates() { # ship_title_candidates <title> <open-issues-json> <exclude-json>
  jq -c --arg t "$1" --argjson x "$3" --arg s "$SHIP_TITLE_STOPWORDS" '
    def tokens: ascii_downcase | [splits("[^a-z0-9]+")]
      | map(select(length >= 4)) | unique | . - ($s | split(" "));
    ($t | tokens) as $new
    | [ .[]
        | select(([.number] - $x) != [])
        | select((($new - ($new - (.title | tokens))) | length) >= 3)
        | {number, title, url} ]' <<<"$2"
}

# ship_id_list <comma-list>: the ids `poll-pr --full` takes, trimmed, blanks
# dropped, as a JSON array. Prints nothing and answers non-zero when the list
# holds no id or one that reads as an option, so `--full --timeout` is the
# caller's usage error rather than a poll that quietly matches no row.
ship_id_list() {
  jq -cne --arg n "$1" '
    ($n | split(",") | map(gsub("^\\s+|\\s+$"; "")) | map(select(. != ""))) as $ids
    | if ($ids | length) == 0 or any($ids[]; startswith("-")) then empty else $ids end'
}

# The review-body clip both adapters run, so they clip in one vocabulary: a jq
# `clip($id)` filter over a body string, invoked with `--argjson full <ids>`.
# The cut leaves a marker, so a clipped round never reads as a whole one.
# `$id | tostring` so a row the host gives no id (an Azure DevOps vote) compares
# without erroring; such a row carries no body to unclip.
# shellcheck disable=SC2034  # read by the host adapters that source this library
readonly SHIP_REVIEW_CLIP='def clip($id):
  if ($full | index($id | tostring)) then .
  elif length > 2000 then .[0:2000] + "\n...[truncated]"
  else . end;'
