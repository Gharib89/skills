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
#   host_issue_linked_prs <n>            -> {closing:[{number,state}],
#                                           mentions:[{number,kind,state}]}
#                                           closing: live PRs whose body closes <n>.
#                                           mentions: everything else that names it,
#                                           kind "pr" or "issue"; none where the host
#                                           records no cross-reference of its own.
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

# ship_frontmatter <file> <key>: one `  <key>: <value>` line from a skill's
# YAML frontmatter, value only. Stops at the closing `---`, so a body line that
# looks like the key is never read as it.
ship_frontmatter() {
  awk -v k="  $2:" 'NR>1 && /^---$/{exit} index($0, k) == 1 {sub(/^[^:]*: */, ""); print; exit}' "$1"
}

# ship_missing_skill_reasons <root> <composes>: the skills ship loads through
# the Skill tool, checked against a checkout before the claim. <composes> is
# ship's `metadata.composes` line: space-separated `<source-repo>:<skill>`
# entries, the single place the list lives. Prints one reason per skill whose
# `<root>/.claude/skills/<skill>/SKILL.md` is absent, carrying the line that
# installs it; prints nothing when every one is there.
#
# Only the consumer repo's own `.claude/skills` counts: a global copy under
# ~/.claude/skills is never a derived copy of this repo's, per setup-skills.
ship_missing_skill_reasons() {
  local root=$1 entry source skill
  local -a entries
  # read -ra, not an unquoted expansion: the split on spaces is intentional and
  # explicit, and a glob character in an entry never reaches the filesystem.
  read -ra entries <<<"$2"
  for entry in ${entries[@]+"${entries[@]}"}; do
    source=${entry%%:*}; skill=${entry##*:}
    [ -f "$root/.claude/skills/$skill/SKILL.md" ] && continue
    printf 'skill missing: %s; run npx skills add %s --skill %s --agent claude-code -y\n' \
      "$skill" "$source" "$skill"
  done
}

# The one fence rule every transformation here reads: ship_body_replace_section
# below, ship_body_closes under it, and _gh_add_closes in the GitHub adapter. A `## ` heading inside a fence
# is example text, so the two have to agree on where a fence starts and ends, or
# one rewrites the example and leaves the real section alone.
#
# CommonMark, as far as these two need it: an opening fence is three or more
# backticks or tildes under up to three leading spaces, and only a bare run of
# the same character at least as long closes it. The character rules a tilde
# fence in; the length keeps a ``` line inside a ```` fence from closing it and
# inverting the state for the rest of the body; the bareness keeps a ```js line
# inside a ``` fence from doing the same, since a closing fence carries no info
# string. A backtick opener carrying another backtick after its run is not a
# fence at all but paragraph text, which is the one asymmetry with tildes.
# Indented (four space) code blocks are not a fence form here.
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
    if (!_fenced) {
      if (c == "`" && index(substr(s, n + 1), "`")) return _fenced
      _fenced = 1; _fence_char = c; _fence_len = n
    }
    else if (c == _fence_char && n >= _fence_len && substr(s, n + 1) ~ /^[ \t\r]*$/) _fenced = 0
    return _fenced
  }
'

# Closing-keyword test, the same on both hosts: does <body> claim to close
# <issue>? Fenced blocks and inline code come out first (a PR quoting
# "Closes #n" while discussing another PR mentions the issue, it does not claim
# it). The "(#n, and #m)" run lets a multi-issue "Closes #75, #81" count for #81.
#
# The fenced blocks come out by SHIP_AWK_FENCE, so this agrees with the two
# heading transformations on what a fence is: a tilde-fenced example carrying
# "Closes #n" reads as a mention here too, and host_pr_create, which asks this
# before it places a closing line, does not skip a body that never claimed one.
#
# Code spans come out after, and stay in jq, because a span opens mid-line where
# a line-oriented pass cannot see it. One rule for every run length: a span
# closes on a backtick run as long as the one that opened it, which the
# backreference says directly, and a multi-line ```md span is that rule at
# length three rather than a fence form of its own.
ship_body_closes() { # ship_body_closes <body> <issue> -> exit 0 when it does
  local unfenced
  unfenced=$(awk "$SHIP_AWK_FENCE"'
    { was = fenced; fenced = ship_fence($0); if (!was && !fenced) print }' <<<"$1")
  jq -e -n --arg body "$unfenced" --arg n "$2" '
    $body
    | gsub("(?s)(`+).*?\\1"; "")
    | test("\\b(clos(e[sd]?|ing)|fix(e[sd]|ing)?|resolv(e[sd]?|ing))"
           + "\\s+(#[0-9]+[\\s,]+(and[\\s,]+)?)*#" + $n + "\\b"; "i")' >/dev/null
}

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

# The vocabulary a reviewer refuses a round in, shared by the two readers: the
# blocked lookup, which returns the notice line, and the reviews projection,
# which refuses to call such a body a round.
#
# The refusal VERB carries the match, not the bare noun. A round that merely
# mentions a quota or a rate limit ("back off rather than burn the API quota")
# is a finding, and a draft of this that matched the noun alone dropped such a
# round as a notice, which costs the run its whole poll window.
#   notice_body:  the body on one line, HTML comments and quote or bold marks
#                 gone, so a wrapped notice and one carrying a generated footer
#                 classify the same as the one-line form. PR #154's notice
#                 arrived all three ways.
#   notice_lines: the matching lines of a body, de-quoted and unbolded: what the
#                 blocked lookup reports, so the summary quotes the reviewer.
#   is_notice:    the body is ONLY a refusal, every sentence of it one. Known
#                 limit: a one-sentence round whose whole content is a refusal
#                 phrase reads as a notice. The run then waits the window out
#                 and reports the reviewer blocked, with the body still in
#                 `rounds[]` to read, rather than losing it.
# shellcheck disable=SC2034  # read by the host adapters that source this library
readonly SHIP_BLOCKED_NOTICE='def notice_re:
  "(unable|not able|cannot|could not|failed)( to)? [a-z ]{0,24}review"
  + "|(reached|exceeded|hit|out of|ran out of) [a-z ]{0,24}(quota|rate limit)"
  + "|next included review";
def notice_body:
  gsub("<!--[\\s\\S]*?-->"; "") | gsub("[*>]"; "") | gsub("\\s+"; " ")
  | sub("^ +"; "") | sub(" +$"; "");
def notice_lines:
  splits("\n") | select(test(notice_re; "i")) | sub("^>\\s*"; "") | gsub("\\*"; "");
def is_notice:
  [notice_body | splits("(?<=[.!?]) +") | select(test("\\S"))] as $sentences
  | ($sentences | length) > 0 and all($sentences[]; test(notice_re; "i"));'

# poll-pr's two landing rules over a `host_pr_reviews` projection, invoked with
# `--arg l <normalised login>` and `--arg s <since|"">`. `$l` arrives already
# lowercased and stripped of a `[bot]` suffix, the row side normalised here to
# match. Only a SUBSTANTIVE row lands, which is what keeps a quota notice from
# answering for a round that never arrived (#155).
# shellcheck disable=SC2034  # read by poll-pr
readonly SHIP_LANDED_BY='
  def mine: [.[] | select(.substantive and ((.login | ascii_downcase | sub("\\[bot\\]$"; "")) == $l))];
  if $s == "" then (if (.on_head | mine) != [] then "head" else null end)
  else (if (.all | mine | map(select(.submitted_at != null and .submitted_at >= $s))) != [] then "since" else null end)
  end'

# ship_fence_unclosed <text>: does the text end inside a fenced block? Prints
# `line <n>: <run>` naming the opener that never closed, or nothing when the
# fence state is balanced. `update-pr-body` asks before it rewrites a section:
# an open fence inverts the in-fence state for the rest of the body, so every
# `## ` heading after it reads as example text and the rewrite swallows the
# sections between them (run #121 lost four that way).
ship_fence_unclosed() {
  awk "$SHIP_AWK_FENCE"'
    { was = fenced; fenced = ship_fence($0)
      if (!was && fenced) {
        open_line = NR; open_run = $0
        sub(/^ ? ? ?/, "", open_run); sub(/[^`~].*$/, "", open_run)
      } }
    END { if (fenced) printf "line %d: %s\n", open_line, open_run }' <<<"$1"
}

# ship_body_headings <body>: the body's `## ` section headings, heading text
# only, one per line, in order. The same fence rule as every transformation
# above, so a `## ` inside a fence is example text here too. `update-pr-body`
# reports this after the write, where a swallowed section is visible in the JSON
# rather than eight minutes later in a review.
ship_body_headings() {
  awk "$SHIP_AWK_FENCE"'
    { fenced = ship_fence($0) }
    !fenced && /^## / { sub(/^## /, ""); sub(/[ \t\r]+$/, ""); print }' <<<"$1"
}

# ship_stale_base_reason <base-fresh-json>: the refusal `merge` answers with when
# the branch has not seen every commit on its base, or nothing when it has. The
# base can move between phase 5's `base-fresh` and the human's "merge" (PR #131
# merged 46 seconds after its base moved, landing a body that no longer matched
# the template), so the merge asks the same question again and reads the answer
# here.
#
# Anything that is not a `fresh: true` verdict refuses, an unparseable one
# included: a check that could not ask its question must not answer "fresh".
ship_stale_base_reason() {
  jq -rn --arg v "$1" '
    (try ($v | fromjson) catch null) as $j
    | if ($j | type) != "object" then "stale-base: base freshness unreadable"
      elif $j.fresh == true then empty
      elif ($j.behind | type) == "number" then "stale-base: behind \($j.behind) on \($j.base)"
      else "stale-base: base freshness unreadable" end'
}

# ship_brief <poll-json> <identity> <on_head|all> [<full-ids-json>]: the projection `poll-pr
# --brief` prints, from the JSON the poll already built. One host fetch, two
# output shapes; the full shape stays the default so nothing existing changes
# meaning.
#
# <identity> is the login the run posts as: its own thread replies land as review
# rows of their own, and a convergence test that counts them reads its own voice
# as the reviewer's. An empty <identity> drops nothing: a host that could not
# name the run must not cost it the rounds it came for. <on_head|all> is `all`
# under the --since rule and `on_head` under the head rule, matching the list
# that rule lands from.
#
# A round's body comes down to its lead line and its finding items, which is what
# a triage acts on: the lead line carries the round's verdict and the items carry
# what to fix. A round with no items is clipped instead, so it is short without
# being empty. A row named by <full-ids-json> keeps its whole body: `--full` says
# "this round, verbatim" and outranks the cut, the way it outranks the adapter's.
#
# A body the adapter already clipped ends in the truncation marker, and the cut
# carries that marker through: a round nobody has read whole must not come back
# looking complete, or the loop never re-polls it with --full.
# Threads come down to the open ones, the only ones still owed a disposition,
# and the string "unavailable" passes through as itself.
ship_brief() {
  jq -c --arg me "$2" --arg key "$3" --argjson full "${4:-[]}" '
    def norm: ascii_downcase | sub("\\[bot\\]$"; "");
    def mine: $me != "" and (((.login // "") | norm) == ($me | norm));
    def finding_items:
      (if endswith("\n...[truncated]") then "\n...[truncated]" else "" end) as $mark
      | [splits("\n") | select(test("^[ \t]*$") | not)] as $lines
      | [$lines[] | select(test("^[ \t]*([-*+]|[0-9]+[.)])[ \t]"))] as $items
      | if ($items | length) == 0 then (if length > 200 then .[0:200] + "\n...[truncated]" else . end)
        elif $lines[0] == $items[0] then (($items | join("\n")) + $mark)
        else ((([$lines[0]] + $items) | join("\n")) + $mark) end;
    {head_sha, mergeable, landed_by,
     rounds: [.reviews[$key][] | select(mine | not) | . as $r
              | {id, submitted_at, substantive,
                 body: (if ($full | index($r.id | tostring)) then $r.body
                        else ($r.body | finding_items) end)}],
     threads: (if (.threads | type) == "array"
               then [.threads[] | select(.resolved | not) | {id, resolved, replied}]
               else .threads end)}' <<<"$1"
}
