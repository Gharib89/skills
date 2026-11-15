#!/usr/bin/env bash
# open-pr's two create-side forms (#1239). The default form pushes and prints
# the host's PR-create command for the agent to run as its own Bash call,
# creating nothing, because Claude Code's `claude_code.pull_request.count`
# counts a PR only when the create command is the Bash command text itself;
# where an open PR is already on the branch it answers with that PR instead.
# `--verify` reads back the PR the agent's command opened. Driven over the Host
# fake (tests/host-fake.sh) in a throwaway repo whose origin names GitHub and
# whose pushes land in a local bare repo, so "no create" is read off the fake's
# calls log: the fake has no create function at all.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

open=$PWD/skills/ship/scripts/open-pr.sh
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
repo=$work/repo; bare=$work/origin.git; export SHIP_FAKE=$work/fake
g() { git -c user.name=t -c user.email=t@t -c init.defaultBranch=main "$@"; }
{
  g init -q --bare "$bare"
  g init -q "$repo"
  git -C "$repo" remote add origin https://github.com/owner/repo.git
  git -C "$repo" config "url.$bare.pushInsteadOf" https://github.com/owner/repo.git
  g -C "$repo" commit -q --allow-empty -m init
  git -C "$repo" update-ref refs/remotes/origin/main HEAD
  git -C "$repo" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
  g -C "$repo" checkout -q -b fix/thing-7
  g -C "$repo" commit -q --allow-empty -m work
} >/dev/null 2>&1 || { echo "fixture setup failed" >&2; exit 2; }
export SHIP_HOST_ADAPTER=$PWD/tests/host-fake.sh XDG_STATE_HOME=$work/state
reset()  { rm -rf "$SHIP_FAKE"; mkdir -p "$SHIP_FAKE"; git -C "$bare" update-ref -d refs/heads/fix/thing-7 2>/dev/null; }
pushed() { git -C "$bare" rev-parse -q --verify refs/heads/fix/thing-7 >/dev/null && echo pushed || echo none; }
calls()  { cut -f1 "$SHIP_FAKE/calls" 2>/dev/null | paste -sd' '; }
fx()     { printf '%s\n' "$2" > "$SHIP_FAKE/$1.1.json"; }
printf '## Summary\n\nx\n' > "$work/body.md"
pre()    { ( cd "$repo" && bash "$open" 7 --title "fix: a thing" --body-file "$work/body.md" 2>"$work/err" ); }
verify() { ( cd "$repo" && bash "$open" 7 --verify 2>"$work/err" ); }

# --- the pre-create call ---------------------------------------------------
reset
fx host_pr_for_branch null
fx host_pr_create_body '{"body": "Closes #7\n\n## Summary\n\nx"}'
fx host_pr_create_cmd '{"command": "gh api -X POST repos/owner/repo/pulls --input body.create.json"}'
out=$(pre); rc=$?
check_rc "a green pre-create call exits 0" 0 "$rc"
check "its stderr is empty" "" "$(cat "$work/err")"
check "it pushes the branch" pushed "$(pushed)"
check "it creates nothing: a branch lookup, the body and the command" \
  'host_pr_for_branch host_pr_create_body host_pr_create_cmd' "$(calls)"
check "it prints the host's create command" 'gh api -X POST repos/owner/repo/pulls --input body.create.json' "$(jq -r .create <<<"$out")"
check "it names the branch and base" 'fix/thing-7 main' "$(jq -r '"\(.branch) \(.base)"' <<<"$out")"
bf=$(jq -r .body_file <<<"$out")
check "the prepared body file carries the host's body" "$(printf 'Closes #7\n\n## Summary\n\nx')" "$(cat "$bf" 2>/dev/null)"
check "the body file sits beside the given one, which is left as written" \
  "$work/body.create.md $(printf '## Summary\n\nx')" "$bf $(cat "$work/body.md")"
check "the body adapter gets the given file and the issue" "$(printf 'host_pr_create_body\t%s\t7' "$work/body.md")" \
  "$(grep '^host_pr_create_body' "$SHIP_FAKE/calls")"
check "the command adapter gets head, base, title, the prepared file and the issue" \
  "$(printf 'host_pr_create_cmd\tfix/thing-7\tmain\tfix: a thing\t%s\t7' "$bf")" \
  "$(grep '^host_pr_create_cmd' "$SHIP_FAKE/calls")"

# The agent runs the command from wherever its shell stands, so a relative body
# file still yields an absolute prepared path.
reset
fx host_pr_for_branch null
fx host_pr_create_body '{"body": "b"}'
fx host_pr_create_cmd '{"command": "c"}'
out=$( cd "$repo" && bash "$open" 7 --title "fix: a thing" --body-file ../body.md 2>/dev/null )
check "a relative body file gives an absolute prepared path" "$(cd "$work" && pwd)/body.create.md" "$(jq -r .body_file <<<"$out")"

# A re-run after the create step landed (or a flake that opened the PR anyway)
# finds the PR and answers with it, so no second PR is ever opened.
reset
fx host_pr_for_branch '{"number": 12, "state": "open", "head_sha": "x"}'
fx host_pr_get '{"number": 12, "url": "https://example.invalid/pull/12", "title": "t", "body": "", "head_sha": "x", "head_ref": "fix/thing-7", "base_ref": "main", "draft": false, "state": "open", "mergeable": "clean", "created_at": "2026-11-15T10:00:00Z"}'
out=$(pre); rc=$?
check_rc "a pre-create call with an open PR on the branch exits 0" 0 "$rc"
check "it answers with that PR" \
  '{"number":12,"url":"https://example.invalid/pull/12","created_at":"2026-11-15T10:00:00Z","branch":"fix/thing-7","base":"main"}' \
  "$(jq -c . <<<"$out")"
check "it prints no create command and builds none" 'host_pr_for_branch host_pr_get' "$(calls)"
check "it still pushes" pushed "$(pushed)"

# The newest PR on the branch closed or merged is no PR to reuse.
reset
fx host_pr_for_branch '{"number": 12, "state": "closed", "head_sha": "x"}'
fx host_pr_create_body '{"body": "b"}'
fx host_pr_create_cmd '{"command": "gh api -X POST repos/owner/repo/pulls"}'
out=$(pre); rc=$?
check_rc "a closed PR on the branch is ignored" 0 "$rc"
check "and a create command is printed" 'gh api -X POST repos/owner/repo/pulls' "$(jq -r .create <<<"$out")"

reset
touch "$SHIP_FAKE/host_pr_for_branch.1.fail"
pre >/dev/null; rc=$?
check_rc "an unreadable branch lookup exits 2" 2 "$rc"
check "and pushes nothing" none "$(pushed)"

reset
fx host_pr_for_branch null
fx host_pr_create_body '{"body": "b"}'
fx host_pr_create_cmd '{"command": ""}'
pre >/dev/null; rc=$?
check_rc "a host that builds no create command exits 2" 2 "$rc"

# --- the verify call -------------------------------------------------------
pr_get() { # <draft> <base> <body>
  jq -n --argjson d "$1" --arg b "$2" --arg body "$3" '{number: 12, url: "https://example.invalid/pull/12", title: "t",
    body: $body, head_sha: "x", head_ref: "fix/thing-7", base_ref: $b, draft: $d, state: "open",
    mergeable: "clean", created_at: "2026-11-15T10:00:00Z"}' > "$SHIP_FAKE/host_pr_get.1.json"
}
closes='Closes #7

## Summary'

reset
fx host_pr_for_branch '{"number": 12, "state": "open", "head_sha": "x"}'
pr_get false main "$closes"
fx host_pr_create_body "$(jq -n --arg b "$closes" '{body: $b}')"
out=$(verify); rc=$?
check_rc "verify on an open non-draft PR exits 0" 0 "$rc"
check "its stderr is empty" "" "$(cat "$work/err")"
check "it answers with the PR" \
  '{"number":12,"url":"https://example.invalid/pull/12","created_at":"2026-11-15T10:00:00Z","branch":"fix/thing-7","base":"main"}' \
  "$(jq -c . <<<"$out")"
check "it pushes nothing" none "$(pushed)"

reset
fx host_pr_for_branch null
out=$(verify); rc=$?
check_rc "verify with no PR on the branch exits 1" 1 "$rc"
check "and says so" 'no open PR on fix/thing-7' "$(jq -r .error <<<"$out")"

reset
fx host_pr_for_branch '{"number": 12, "state": "merged", "head_sha": "x"}'
verify >/dev/null; rc=$?
check_rc "verify with only a merged PR on the branch exits 1" 1 "$rc"

reset
fx host_pr_for_branch '{"number": 12, "state": "open", "head_sha": "x"}'
pr_get true main "$closes"
fx host_pr_create_body "$(jq -n --arg b "$closes" '{body: $b}')"
out=$(verify); rc=$?
check_rc "verify on a draft exits 1" 1 "$rc"
check "and says so" 'PR #12 is a draft' "$(jq -r .error <<<"$out")"

reset
fx host_pr_for_branch '{"number": 12, "state": "open", "head_sha": "x"}'
pr_get false develop "$closes"
fx host_pr_create_body "$(jq -n --arg b "$closes" '{body: $b}')"
out=$(verify); rc=$?
check_rc "verify on a PR against another base exits 1" 1 "$rc"
check "and names both" 'PR #12 targets develop, not main' "$(jq -r .error <<<"$out")"

# The closing link is held by the host's own body rule: a body the host would
# still add its closing link to does not carry it.
reset
fx host_pr_for_branch '{"number": 12, "state": "open", "head_sha": "x"}'
pr_get false main '## Summary'
fx host_pr_create_body "$(jq -n --arg b "$closes" '{body: $b}')"
out=$(verify); rc=$?
check_rc "verify on a body lacking the closing link exits 1" 1 "$rc"
check "and says so" 'PR #12 body does not close #7' "$(jq -r .error <<<"$out")"

reset
touch "$SHIP_FAKE/host_pr_for_branch.1.fail"
verify >/dev/null; rc=$?
check_rc "verify on an unreadable branch lookup exits 2" 2 "$rc"

reset
fx host_pr_for_branch '{"number": 12, "state": "open", "head_sha": "x"}'
pr_get false main '## Summary'
out=$( cd "$repo" && bash "$open" none --verify 2>/dev/null ); rc=$?
check_rc "verify for a free-text run checks no closing link" 0 "$rc"
check "and makes no body call" 'host_pr_for_branch host_pr_get' "$(calls)"

# On Azure DevOps the work item links the PR, so the host's create body is the
# body unchanged and the verify reads it as carrying the link.
reset
git -C "$repo" remote set-url origin https://dev.azure.com/org/proj/_git/repo
fx host_pr_for_branch '{"number": 12, "state": "open", "head_sha": "x"}'
pr_get false main '## Summary'
fx host_pr_create_body "$(jq -n '{body: "## Summary"}')"
out=$(verify); rc=$?
check_rc "verify on an Azure DevOps checkout exits 0" 0 "$rc"
check "it loaded the Azure DevOps host" 'ado' "$(cut -d' ' -f1 "$SHIP_FAKE/loaded")"
check "it answers with the PR" 12 "$(jq -r .number <<<"$out")"
git -C "$repo" remote set-url origin https://github.com/owner/repo.git

check_rc "--verify takes no title" 2 "$( cd "$repo" && bash "$open" 7 --verify --title x >/dev/null 2>&1; echo $? )"
check_rc "--verify and --rework are separate forms" 2 "$( cd "$repo" && bash "$open" 7 --verify --rework >/dev/null 2>&1; echo $? )"

finish
