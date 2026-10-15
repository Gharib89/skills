#!/usr/bin/env bash
# `open-pr <n> --rework` pushes a Rework run's commits to the PR's branch and
# answers with the PR already open on it, never creating one: the Rework run's
# phase 6 rewrites that PR's title and body through update-pr-title and
# update-pr-body. Driven over the Host fake (tests/host-fake.sh) in a throwaway
# repo whose origin names GitHub and whose pushes land in a local bare repo.
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
  g -C "$repo" checkout -q -b feat/thing-7
  g -C "$repo" commit -q --allow-empty -m rework
} >/dev/null 2>&1 || { echo "fixture setup failed" >&2; exit 2; }
export SHIP_HOST_ADAPTER=$PWD/tests/host-fake.sh XDG_STATE_HOME=$work/state
reset() { rm -rf "$SHIP_FAKE"; mkdir -p "$SHIP_FAKE"; git -C "$bare" update-ref -d refs/heads/feat/thing-7 2>/dev/null; }
pushed() { git -C "$bare" rev-parse -q --verify refs/heads/feat/thing-7 || echo none; }

reset
jq -n '{number: 9, state: "open", head_sha: "x"}' > "$SHIP_FAKE/host_pr_for_branch.1.json"
jq -n '{number: 9, url: "https://example.invalid/pull/9", head_ref: "feat/thing-7"}' > "$SHIP_FAKE/host_pr_get.1.json"
out=$( cd "$repo" && bash "$open" 7 --rework 2>/dev/null ); rc=$?
check_rc "open-pr --rework exits ok" 0 "$rc"
check "it answers with the open PR" '{"number":9,"url":"https://example.invalid/pull/9","created_at":null,"branch":"feat/thing-7","base":"main"}' \
  "$(jq -c . <<<"$out")"
check "it pushes the branch" "$(git -C "$repo" rev-parse HEAD)" "$(pushed)"
check "it finds the PR and creates none" 'host_pr_for_branch host_pr_get' "$(cut -f1 "$SHIP_FAKE/calls" | paste -sd' ')"

# --rework takes no body file, so the template-heading check (#647) does not
# run: a profile naming a template that cannot be read still reworks.
reset
mkdir -p "$repo/docs/agents"
printf '## PR\n\nTemplate: .github/absent.md\n' > "$repo/docs/agents/ship.md"
jq -n '{number: 9, state: "open", head_sha: "x"}' > "$SHIP_FAKE/host_pr_for_branch.1.json"
jq -n '{number: 9, url: "https://example.invalid/pull/9", head_ref: "feat/thing-7"}' > "$SHIP_FAKE/host_pr_get.1.json"
( cd "$repo" && bash "$open" 7 --rework >/dev/null 2>&1 ); rc=$?
check_rc "open-pr --rework runs no template-heading check" 0 "$rc"
rm -rf "$repo/docs"

reset
printf 'null\n' > "$SHIP_FAKE/host_pr_for_branch.1.json"
out=$( cd "$repo" && bash "$open" 7 --rework 2>/dev/null ); rc=$?
check_rc "no PR on the branch exits 1" 1 "$rc"
check "and says so" 'no open PR on feat/thing-7 to rework' "$(jq -r .error <<<"$out")"
check "and pushes nothing" none "$(pushed)"

reset
jq -n '{number: 9, state: "merged", head_sha: "x"}' > "$SHIP_FAKE/host_pr_for_branch.1.json"
( cd "$repo" && bash "$open" 7 --rework >/dev/null 2>&1 ); rc=$?
check_rc "a merged PR on the branch exits 1" 1 "$rc"

reset
touch "$SHIP_FAKE/host_pr_for_branch.1.fail"
( cd "$repo" && bash "$open" 7 --rework >/dev/null 2>&1 ); rc=$?
check_rc "an unreadable branch lookup exits 2" 2 "$rc"
check "and pushes nothing" none "$(pushed)"

reset
jq -n '{number: 9, state: "open", head_sha: "x"}' > "$SHIP_FAKE/host_pr_for_branch.1.json"
touch "$SHIP_FAKE/host_pr_get.1.fail"
out=$( cd "$repo" && bash "$open" 7 --rework 2>/dev/null ); rc=$?
check_rc "an unreadable PR exits 2" 2 "$rc"
check "and names it" 'cannot read PR #9' "$(jq -r .error <<<"$out")"
check "and pushes nothing" none "$(pushed)"

# An answer that does not parse is a failed read, caught before the push.
for fn in host_pr_for_branch host_pr_get; do
  reset
  jq -n '{number: 9, state: "open", head_sha: "x"}' > "$SHIP_FAKE/host_pr_for_branch.1.json"
  printf 'not json\n' > "$SHIP_FAKE/$fn.1.json"
  ( cd "$repo" && bash "$open" 7 --rework >/dev/null 2>&1 ); rc=$?
  check_rc "an unparseable $fn exits 2" 2 "$rc"
  check "and pushes nothing" none "$(pushed)"
done

check_rc "--rework takes no title" 2 "$( cd "$repo" && bash "$open" 7 --rework --title x >/dev/null 2>&1; echo $? )"
check_rc "--rework has no free-text form" 2 "$( cd "$repo" && bash "$open" none --rework >/dev/null 2>&1; echo $? )"

finish
