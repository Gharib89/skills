#!/usr/bin/env bash
# Shared by tests/merge*.test.sh: a local bare origin whose path names GitHub,
# the Host fake, a feature branch with two heads A and C, run `t` admitted at
# both, and the helpers each case uses. Sourced from the repo root, never run.
# shellcheck disable=SC2034 # the sourcing test reads these
source tests/lib.sh
T=$'\t'  # the calls log separates arguments with a tab

mech=$PWD/skills/ship-run/scripts/merge.sh
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
origin=$work/github.com/owner/repo.git; repo=$work/repo; export SHIP_FAKE=$work/fake
export SHIP_HOST_ADAPTER=$PWD/tests/host-fake.sh SHIP_MERGE_CHECKS_GRACE=0
mkdir -p "$SHIP_FAKE"
git init -q --bare -b main "$origin"
git init -q -b main "$work/seed"
git -C "$work/seed" -c user.name=t -c user.email=t@t commit -q --allow-empty -m base
git -C "$work/seed" push -q "$origin" main
# A PR may target `release`: merge fetches its base, so that branch exists on origin, level with main.
git -C "$work/seed" push -q "$origin" main:release
git clone -q "$origin" "$repo"
g() { git -C "$repo" -c user.name=t -c user.email=t@t "$@"; }
g switch -q -c fix/x
g commit -q --allow-empty -m "the gated head"; A=$(g rev-parse HEAD)
g commit -q --allow-empty -m "a later commit"; C=$(g rev-parse HEAD)

export XDG_STATE_HOME=$work/state
rr=$(cd "$repo" && bash -c 'source "$1"; ship_record_root' _ "$(dirname "$mech")/_lib.sh") || exit 2
runfm=$PWD/skills/ship-run/scripts/run-file.sh
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
pr()     { jq -n --arg s "$2" --arg h "$3" --arg b "${4:-main}" '{number: 7, title: "fix: x", head_sha: $h,
             head_ref: "fix/x", base_ref: $b, state: $s}' > "$SHIP_FAKE/host_pr_get.$1.json"; }
at()     { git -C "$origin" rev-parse -q --verify refs/heads/fix/x; }
push_at() { g push -q -f origin "$1:refs/heads/fix/x"; }
