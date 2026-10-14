#!/usr/bin/env bash
# merge driven end to end over the Host fake (tests/host-fake.sh), against a
# local bare origin whose path names GitHub so host detection still runs (#635).
# The subject is what `merge` binds: it lands only the head the merge gate
# read, so a push after the gate refuses `head-moved` with no merge call, the
# head reaches the Host's merge call for the host to enforce, and the remote
# branch is deleted only while it still holds the PR's head, so a branch
# recreated under that name after the merge keeps its commits.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
T=$'\t'  # the calls log separates arguments with a tab

mech=$PWD/skills/ship/scripts/merge.sh
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
origin=$work/github.com/owner/repo.git; repo=$work/repo; export SHIP_FAKE=$work/fake
export SHIP_HOST_ADAPTER=$PWD/tests/host-fake.sh
mkdir -p "$SHIP_FAKE"
git init -q --bare -b main "$origin"
git init -q -b main "$work/seed"
git -C "$work/seed" -c user.name=t -c user.email=t@t commit -q --allow-empty -m base
git -C "$work/seed" push -q "$origin" main
git clone -q "$origin" "$repo"
g() { git -C "$repo" -c user.name=t -c user.email=t@t "$@"; }
g switch -q -c fix/x
g commit -q --allow-empty -m "the gated head"; A=$(g rev-parse HEAD)
g commit -q --allow-empty -m "a later commit"; C=$(g rev-parse HEAD)

run()    { ( cd "$repo" && bash "$mech" "$@" ); }
reset()  { rm -rf "$SHIP_FAKE"; mkdir -p "$SHIP_FAKE"; }
pr()     { jq -n --arg s "$2" --arg h "$3" '{number: 7, title: "fix: x", head_sha: $h,
             head_ref: "fix/x", base_ref: "main", state: $s}' > "$SHIP_FAKE/host_pr_get.$1.json"; }
at()     { git -C "$origin" rev-parse -q --verify refs/heads/fix/x; }
push_at() { g push -q -f origin "$1:refs/heads/fix/x"; }

out=$(run 7 none 2>&1); rc=$?
check_rc "merge without a head is a usage error" 2 "$rc"
check "and names the head in its usage line" true \
  "$(grep -qF 'usage: merge <pr> <issue|none> <head> [--worktree <path>]' <<<"$out" && echo true)"

reset; push_at "$A"; pr 1 open "$A"
out=$(run 7 none "$C" 2>/dev/null); rc=$?
check_rc "an open PR whose head moved past the gated head is refused" 1 "$rc"
check "the refusal names the current head and the gated head" "head-moved: $A != $C" "$(jq -r .error <<<"$out")"
check "and no merge call reaches the host" 0 "$(grep -c '^host_pr_merge' "$SHIP_FAKE/calls")"
check "and the branch stays on origin" "$A" "$(at)"

for f in head_sha head_ref base_ref; do
  reset; push_at "$A"; pr 1 merged "$A"; jq --arg f "$f" 'del(.[$f])' "$SHIP_FAKE/host_pr_get.1.json" > "$work/pr"
  mv "$work/pr" "$SHIP_FAKE/host_pr_get.1.json"
  out=$(run 7 none "$A" 2>/dev/null); rc=$?
  check_rc "a PR read with no $f is a tooling error, not a verdict" 2 "$rc"
  check "and the branch stays on origin with no $f" "$A" "$(at)"
done

reset; push_at "$A"; pr 1 open "$A"; pr 2 merged "$A"
out=$(run 7 none "$A" 2>/dev/null); rc=$?
check_rc "an open PR at the gated head merges" 0 "$rc"
check "the gated head reaches the host's merge call" "host_pr_merge${T}7${T}fix: x (#7)${T}$A" \
  "$(grep '^host_pr_merge' "$SHIP_FAKE/calls")"
check "the branch at the PR's head is deleted" "" "$(at)"
check "and reported deleted" true "$(jq -r .remote_branch_deleted <<<"$out")"

reset; push_at "$C"; pr 1 merged "$A"
out=$(run 7 none "$A" 2>"$work/err"); rc=$?
check_rc "a re-run whose branch was recreated at another commit is not a false step" 0 "$rc"
check "the recreated branch keeps its commits" "$C" "$(at)"
check "and is reported as no longer the PR's branch" true "$(jq -r .remote_branch_deleted <<<"$out")"
check "with a note on stderr naming both commits" 1 "$(grep -c "$C.*$A\|$A.*$C" "$work/err")"

reset; g push -q origin --delete fix/x 2>/dev/null; pr 1 merged "$A"
out=$(run 7 none "$A" 2>/dev/null); rc=$?
check_rc "a re-run whose branch is already gone exits 0" 0 "$rc"
check "an absent branch reads as deleted" true "$(jq -r .remote_branch_deleted <<<"$out")"

finish
