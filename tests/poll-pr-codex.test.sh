#!/usr/bin/env bash
# poll-pr --reviewer on a native Codex block (`Workflow: native codex`): a
# comment transport with no workflow run behind it, whose round status is read
# off the PR itself. The payloads under tests/fixtures/codex/ are the bodies
# Codex posted on the #500 probe PRs (#504 findings, #505 clean) and the reply
# it posted on issue #500; the only synthesized body is the in-progress status
# row, a state the probe saw only as "Completed".
#
# Driven end to end over the Host fake and a throwaway repo whose origin names
# GitHub, as reviewer-run.test.sh drives the workflow transport.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

mech=$PWD/skills/ship/scripts/poll-pr.sh
fx=$PWD/tests/fixtures/codex
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
repo=$work/repo
export SHIP_FAKE=$work/fake SHIP_HOST_ADAPTER=$PWD/tests/host-fake.sh
mkdir -p "$repo/docs/agents" "$SHIP_FAKE"
git -C "$repo" init -q
git -C "$repo" remote add origin https://github.com/owner/repo.git
cat > "$repo/docs/agents/ship.md" <<'EOF'
## Reviewers

### codex

Login: chatgpt-codex-connector[bot]
Trigger: on-request
Request: comment @codex review
Workflow: native codex
Cap: 3
Gating: no

## Coding standards
EOF

bot='chatgpt-codex-connector[bot]'
since=2026-10-07T12:28:13Z
head=9ffa460496e3250311111218d4350b0f666d1372
empty='{"on_head":[],"all":[],"total":0}'
findings=$(jq -cn --arg b "$(cat "$fx/findings-review.md")" --arg l "$bot" \
  '{id: "5442290679", login: $l, state: "comment", submitted_at: "2026-10-07T12:31:04Z", body: $b}
   | {on_head: [.], all: [.], total: 1}')

reset() { # [<head>]
  rm -f "$SHIP_FAKE"/*
  jq -cn --arg h "${1:-$head}" '{number: 7, url: "https://example.invalid/7", title: "t", body: "",
    head_sha: $h, head_ref: "feat/x-7", base_ref: "main", state: "open", mergeable: "clean"}' \
    > "$SHIP_FAKE/host_pr_get.1.json"
  echo null > "$SHIP_FAKE/host_pr_reviewer_blocked.1.json"
  echo '[]' > "$SHIP_FAKE/host_pr_threads.1.json"
  printf '%s\n' "$empty" > "$SHIP_FAKE/host_pr_reviews.1.json"
}
# activity <n> [comment|reaction]...: the n-th native-activity answer. A comment
# is `c|<file>|<created_at>[|<updated_at>]` by the bot, the file read from the
# scratch dir before the fixtures; `eyes` is the bot's 👀 on the request
# comment; `thumbs|<at>` its 👍 on the PR.
activity() {
  local n=$1 cs='[]' pr='[]' rq='[]' a f c u; shift
  for a in "$@"; do
    case $a in
      eyes) rq='[{"content":"eyes","login":"chatgpt-codex-connector[bot]","created_at":"2026-10-07T12:28:24Z"}]' ;;
      thumbs\|*) pr=$(jq -cn --arg t "${a#thumbs|}" --arg l "$bot" '[{content: "+1", login: $l, created_at: $t}]') ;;
      c\|*) IFS='|' read -r _ f c u <<<"$a"
           cs=$(jq -c --arg b "$(cat "$work/$f" 2>/dev/null || cat "$fx/$f")" --arg c "$c" --arg u "${u:-$c}" --arg l "$bot" \
             '. + [{id: (length + 100), login: $l, created_at: $c, updated_at: $u, body: $b, url: "https://example.invalid/c"}]' <<<"$cs") ;;
    esac
  done
  jq -cn --argjson c "$cs" --argjson p "$pr" --argjson r "$rq" \
    '{comments: ([{id: 1, login: "me", created_at: "2026-10-07T12:28:13Z", updated_at: "2026-10-07T12:28:13Z",
                   body: "@codex review", url: "https://example.invalid/r"}] + $c),
      pr_reactions: $p, request_reactions: $r}' > "$SHIP_FAKE/host_pr_native_activity.$n.json"
}
poll() { ( cd "$repo" && bash "$mech" 7 --reviewer codex --since "$since" --timeout 0 --interval 1 "$@" ); }
calls() { cat "$SHIP_FAKE/host_$1.n" 2>/dev/null || echo 0; }
# An in-progress row: the probe's Completed row with its status cell replaced.
sed 's/✅ \*\*Completed\*\*/⏳ **In progress**/' "$fx/summary-completed.md" > "$work/summary-progress.md"
# The same Completed row naming a commit that is not the head.
sed 's/`9ffa460`/`1111111`/' "$fx/summary-completed.md" > "$work/summary-stale.md"

# The findings round, as #504 delivered it: 👀 and an in-progress row first,
# then the formal review on the head. The 👀 holds the window past --timeout 0.
reset
activity 1 eyes "c|summary-progress.md|2026-10-07T12:28:29Z"
activity 2 "c|summary-completed.md|2026-10-07T12:28:29Z|2026-10-07T12:31:08Z"
printf '%s\n' "$findings" > "$SHIP_FAKE/host_pr_reviews.2.json"
out=$(poll --brief); rc=$?
check "a findings round lands after the in-progress pass" '0 since null' \
  "$rc $(jq -r '.landed_by, .not_reviewed' <<<"$out" | xargs)"
check "the in-progress pass held the window for a second read" 2 "$(calls pr_reviews)"
check "the round is the formal review" 5442290679 "$(jq -r '.rounds[0].id' <<<"$out")"
check "the status is reported on reviewer_run" '"completed success"' \
  "$(jq -c '.reviewer_run | "\(.status) \(.conclusion)"' <<<"$out")"

# An in-progress row with no 👀 holds the window the same way.
reset
activity 1 "c|summary-progress.md|2026-10-07T12:28:29Z"
activity 2 "c|summary-completed.md|2026-10-07T12:28:29Z|2026-10-07T12:31:08Z"
printf '%s\n' "$findings" > "$SHIP_FAKE/host_pr_reviews.2.json"
out=$(poll); rc=$?
check "an in-progress status row holds the window until the round" '0 since' \
  "$rc $(jq -r .landed_by <<<"$out")"

# The clean round, as #505 delivered it: no formal review, an issue comment
# naming the reviewed commit, then 👍 on the PR. It is a landed round.
clean_head=7e1ab20b3c610e03bb4d968237f5a567815917d6
since=2026-10-07T12:36:17Z
reset "$clean_head"
sed 's/`9ffa460`/`7e1ab20`/' "$fx/summary-completed.md" > "$work/summary-clean.md"
activity 1 "c|summary-clean.md|2026-10-07T12:36:32Z|2026-10-07T12:38:05Z" \
  "c|clean.md|2026-10-07T12:38:02Z" "thumbs|2026-10-07T12:38:07Z"
out=$(poll --brief); rc=$?
check "a clean comment with no review is a landed round" '0 since null' \
  "$rc $(jq -r '.landed_by, .not_reviewed' <<<"$out" | xargs)"
check "the clean round reads as Codex's own words" "Codex Review: Didn't find any major issues. Hooray!" \
  "$(jq -r '.rounds[0].body' <<<"$out" | head -1)"

# 👍 on the PR alone is Codex's other clean signal.
reset "$clean_head"
activity 1 "c|summary-clean.md|2026-10-07T12:36:32Z|2026-10-07T12:38:05Z" "thumbs|2026-10-07T12:38:07Z"
out=$(poll); rc=$?
check "a 👍 on the PR with no comment is a landed round" '0 since null' \
  "$rc $(jq -r '.landed_by, .not_reviewed' <<<"$out" | xargs)"
# A 👍 from before the request is an older round's.
reset "$clean_head"
activity 1 "thumbs|2026-10-07T12:00:00Z"
out=$(poll); rc=$?
check "a 👍 older than the request lands nothing" '1 null never-queued' \
  "$rc $(jq -r '.landed_by, .not_reviewed' <<<"$out" | xargs)"

# Silence: no 👀, no status row, no comment. An unconnected repo is this.
since=2026-10-07T12:28:13Z
reset
activity 1
out=$(poll); rc=$?
check "silence past the window is never-queued" '1 never-queued none' \
  "$rc $(jq -r '.not_reviewed, .reviewer_run.status' <<<"$out" | xargs)"
# A Completed row from an older request (untouched since this one) is not this
# request's status.
reset
activity 1 "c|summary-completed.md|2026-10-07T12:00:00Z|2026-10-07T12:05:00Z"
out=$(poll); rc=$?
check "an older request's status row is no status for this one" '1 never-queued' \
  "$rc $(jq -r .not_reviewed <<<"$out")"

# A bot reply that is neither a review nor the clean marker: the reply Codex
# posted on issue #500 for want of an environment. Its text is the reason.
reset
activity 1 "c|env-reply.md|2026-10-07T12:28:20Z"
out=$(poll); rc=$?
check "an unrecognised bot reply is blocked" '1 blocked since' \
  "$rc $(jq -r '.not_reviewed, .refused_by' <<<"$out" | xargs)"
check "the reply's text is kept as the notice" \
  "To use Codex here, [create an environment for this repo](https://chatgpt.com/codex/cloud/settings/environments)." \
  "$(jq -r .reviewer_blocked <<<"$out")"

# A Completed row on a commit that is not the head, with nothing delivered.
reset
activity 1 "c|summary-stale.md|2026-10-07T12:28:29Z|2026-10-07T12:31:08Z"
out=$(poll); rc=$?
check "a Completed row on a stale head is not reviewed" '1 stale-head' \
  "$rc $(jq -r .not_reviewed <<<"$out")"

# The read failing is no evidence about the reviewer.
reset
touch "$SHIP_FAKE/host_pr_native_activity.1.fail"
out=$(poll); rc=$?
check "an unreadable native status is unreachable" '1 unreachable unavailable' \
  "$rc $(jq -r '.not_reviewed, .reviewer_run' <<<"$out" | xargs)"
check "the native read names the request it follows" "host_pr_native_activity	7	$since	@codex review" \
  "$(grep '^host_pr_native_activity' "$SHIP_FAKE/calls" | head -1)"
