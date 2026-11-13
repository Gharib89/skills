#!/usr/bin/env bash
# merge driven end to end over the Host fake (tests/host-fake.sh), against a
# local bare origin whose path names GitHub so host detection still runs (#635).
# The subject is what `merge` binds: it lands only the head the merge gate
# read, so a push after the gate refuses `head-moved` with no merge call, the
# head reaches the Host's merge call for the host to enforce, and the remote
# branch is deleted only while it still holds the PR's head, so a branch
# recreated under that name after the merge keeps its commits. It also refuses,
# with nothing merged, a head whose checks are not settled, a head with no
# admission record in the Run file, and a cloud sandbox whose profile says that
# lane does not merge (#1204).
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

export XDG_STATE_HOME=$work/state
rr=$(cd "$repo" && bash -c 'source "$1"; ship_record_root' _ "$(dirname "$mech")/_lib.sh") || exit 2
runfm=$PWD/skills/ship/scripts/run-file.sh
# admit <slug> <head> [clean]: the record `merge` reads, written by the mechanic that owns it.
admit() { mkdir -p "$rr/ship-$1"; : >> "$rr/ship-$1/run.md"; ( cd "$repo" && bash "$runfm" gate admit human --head "$2" --issue "$1" >/dev/null 2>&1 ); }
admit t "$A"; admit t "$C"

# Every case below merges as run `t`, which holds a record for both heads.
run()    { ( cd "$repo" && bash "$mech" "$@" --run t ); }
runas()  { local s=$1; shift; ( cd "$repo" && bash "$mech" "$@" --run "$s" ); }
profile() { mkdir -p "$repo/docs/agents"; printf '%s\n' "$1" > "$repo/docs/agents/ship.md"; }
no_profile() { rm -rf "$repo/docs"; }
no_merge() { check "$1: no merge call reaches the host" 0 "$(cat "$SHIP_FAKE/calls" 2>/dev/null | grep -c '^host_pr_merge')"; check "$1: the branch stays on origin" "$A" "$(at)"; }
reset()  { rm -rf "$SHIP_FAKE"; mkdir -p "$SHIP_FAKE"; }
pr()     { jq -n --arg s "$2" --arg h "$3" '{number: 7, title: "fix: x", head_sha: $h,
             head_ref: "fix/x", base_ref: "main", state: $s}' > "$SHIP_FAKE/host_pr_get.$1.json"; }
at()     { git -C "$origin" rev-parse -q --verify refs/heads/fix/x; }
push_at() { g push -q -f origin "$1:refs/heads/fix/x"; }

out=$(cd "$repo" && bash "$mech" 7 none 2>&1); rc=$?
check_rc "merge without a head is a usage error" 2 "$rc"
check "and names the head in its usage line" true \
  "$(grep -qF 'usage: merge <pr> <issue|none> <head> [--worktree <path>, the feature checkout to run the main-checkout lookup and the base freshness check from, default the current directory; teardown is cleanup, run after this] [--run <issue|slug>, the run whose Run file holds the admission record, default the issue, required for none]' <<<"$out" && echo true)"

reset; push_at "$A"; pr 1 open "$A"
out=$(run 7 none "$C" 2>/dev/null); rc=$?
check_rc "an open PR whose head moved past the gated head is refused" 1 "$rc"
check "the refusal names the current head and the gated head" "head-moved: $A != $C" "$(jq -r .error <<<"$out")"
check "and no merge call reaches the host" 0 "$(grep -c '^host_pr_merge' "$SHIP_FAKE/calls")"
check "and the branch stays on origin" "$A" "$(at)"

for f in head_sha head_ref base_ref title; do
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

# The issue's reads: 1 finds it closed, 2 and 3 the claim, 4 confirms the
# ready-for-agent removal. Only a read that answered absent confirms it (#636).
closed_issue() {
  printf 'me\n' > "$SHIP_FAKE/host_identity.1.json"
  printf '{"number":9,"state":"closed","assignees":[],"labels":["ready-for-agent"]}\n' > "$SHIP_FAKE/host_issue_get.1.json"
}
reset; pr 1 merged "$A"; closed_issue
: > "$SHIP_FAKE/host_issue_get.4.fail"
out=$(run 7 9 "$A" 2>/dev/null); rc=$?
check_rc "a merge whose label read failed exits 1" 1 "$rc"
check "and does not report ready-for-agent removed" false "$(jq -r .ready_for_agent_removed <<<"$out")"

reset; pr 1 merged "$A"; closed_issue
printf '{"number":9,"state":"closed","assignees":[],"labels":[]}\n' > "$SHIP_FAKE/host_issue_get.4.json"
out=$(run 7 9 "$A" 2>/dev/null); rc=$?
check_rc "a merge whose label read answered absent exits 0" 0 "$rc"
check "and reports ready-for-agent removed" true "$(jq -r .ready_for_agent_removed <<<"$out")"

# --- #1204: the three refusals, each before the host's merge call ----------------

reset; push_at "$A"; pr 1 open "$A"
printf '[{"name":"build","status":"pending"}]\n' > "$SHIP_FAKE/host_pr_checks.1.json"
out=$(run 7 none "$A" 2>/dev/null); rc=$?
check_rc "a head with a check still running is refused" 1 "$rc"
check "the refusal names the check and its state" "checks-unsettled: build: pending" "$(jq -r .error <<<"$out")"
no_merge "a running check"

reset; push_at "$A"; pr 1 open "$A"
printf '[{"name":"build","status":"failure"}]\n' > "$SHIP_FAKE/host_pr_checks.1.json"
out=$(run 7 none "$A" 2>/dev/null); rc=$?
check_rc "a head whose newest run of a check failed or was cancelled is refused" 1 "$rc"
check "the refusal reads checks-unsettled: build: failure" "checks-unsettled: build: failure" "$(jq -r .error <<<"$out")"
no_merge "a failed check"

# A body edit after a green ci-wait re-fires a workflow: the merge call's own read sees it.
reset; push_at "$A"; pr 1 open "$A"; pr 2 merged "$A"
printf '[{"name":"build","status":"pending"}]\n' > "$SHIP_FAKE/host_pr_checks.1.json"
printf '[{"name":"build","status":"success"}]\n' > "$SHIP_FAKE/host_pr_checks.2.json"
run 7 none "$A" >/dev/null 2>&1; rc1=$?
rm -f "$SHIP_FAKE/host_pr_get.2.json"; pr 1 open "$A"; pr 2 merged "$A"
run 7 none "$A" >/dev/null 2>&1; rc2=$?
check "an edit-fired check refuses the first call, and the settled re-read merges" "1 0" "$rc1 $rc2"

profile $'## CI\n\nLegs: build: the build\nNo-checks legal: no'
reset; push_at "$A"; pr 1 open "$A"
printf '[{"name":"other","status":"success"}]\n' > "$SHIP_FAKE/host_pr_checks.1.json"
out=$(run 7 none "$A" 2>/dev/null); rc=$?
check_rc "a profile leg with no check on the head is refused" 1 "$rc"
check "and reads missing" "checks-unsettled: build: missing" "$(jq -r .error <<<"$out")"
no_merge "a missing leg"

profile $'## CI\n\nLegs: build: the build\nNo-checks legal: yes'
reset; push_at "$A"; pr 1 open "$A"; pr 2 merged "$A"
printf '[]\n' > "$SHIP_FAKE/host_pr_checks.1.json"
run 7 none "$A" >/dev/null 2>&1; rc=$?
check_rc "a missing leg the profile calls legal merges" 0 "$rc"

profile $'## CI\n\nLegs: build: the build\nNo-checks legal: no'
reset; push_at "$A"; pr 1 open "$A"; pr 2 merged "$A"
printf '[{"name":"build (linux)","status":"success"},{"name":"unlisted","status":"failure"}]\n' > "$SHIP_FAKE/host_pr_checks.1.json"
run 7 none "$A" >/dev/null 2>&1; rc=$?
check_rc "a matrix job counts for its leg and a check no leg names is left alone, as ci-wait reads it" 0 "$rc"
no_profile

reset; push_at "$A"; pr 1 open "$A"
mkdir -p "$rr/ship-u"; : > "$rr/ship-u/run.md"
out=$(runas u 7 none "$A" 2>/dev/null); rc=$?
check_rc "a Run file with no admission record is refused" 1 "$rc"
check "the refusal names the head and the missing record" true "$(err=$(jq -r .error <<<"$out"); grep -qF "no-gate-record: no clean gate verdict or merge word recorded for $A in " <<<"$err" && echo true)"
no_merge "no record"

reset; push_at "$A"; pr 1 open "$A"
out=$(runas nope 7 none "$A" 2>/dev/null); rc=$?
check_rc "a run with no Run file at all is refused" 1 "$rc"
no_merge "no Run file"

reset; push_at "$C"; pr 1 open "$C"
admit v "$A"
out=$(runas v 7 none "$C" 2>/dev/null); rc=$?
check_rc "a record for an older head does not admit a newer one" 1 "$rc"
check "and the refusal names the newer head" true "$(err=$(jq -r .error <<<"$out"); grep -qF "$C" <<<"$err" && echo true)"
check "and no merge call reaches the host" 0 "$(cat "$SHIP_FAKE/calls" 2>/dev/null | grep -c '^host_pr_merge')"

reset; push_at "$A"; pr 1 open "$A"
out=$(cd "$repo" && bash "$mech" 7 none "$A" 2>/dev/null); rc=$?
check_rc "merge none with no --run has no Run file to read and is a usage error" 2 "$rc"
no_merge "no --run"

# The sandbox marker plus a profile that does not say the lane merges.
sandbox() { ( cd "$repo" && CLAUDE_CODE_REMOTE=true bash "$mech" "$@" --run t ); }
profile $'## Cloud lane\n\nPR cap: 3\nBootstrap: None.'
reset; push_at "$A"; pr 1 open "$A"
out=$(sandbox 7 none "$A" 2>/dev/null); rc=$?
check_rc "a cloud sandbox whose profile has no Sandbox merge: line is refused" 1 "$rc"
check "the refusal names the lane" "cloud-sandbox: " "$(jq -r .error <<<"$out" | cut -c1-15)"
no_merge "a sandbox with no line"
profile $'## Cloud lane\n\nPR cap: 3\nSandbox merge: no\nBootstrap: None.'
reset; push_at "$A"; pr 1 open "$A"
sandbox 7 none "$A" >/dev/null 2>&1; rc=$?
check_rc "a cloud sandbox whose profile says no is refused" 1 "$rc"
no_merge "a sandbox that says no"
reset; push_at "$A"; pr 1 open "$A"; pr 2 merged "$A"
run 7 none "$A" >/dev/null 2>&1; rc=$?
check_rc "the same profile outside a sandbox merges on a clean gate as before" 0 "$rc"
profile $'## Cloud lane\n\nPR cap: 3\nSandbox merge: yes\nBootstrap: None.'
reset; push_at "$A"; pr 1 open "$A"; pr 2 merged "$A"
sandbox 7 none "$A" >/dev/null 2>&1; rc=$?
check_rc "a cloud sandbox whose profile says yes merges" 0 "$rc"
no_profile

finish
