#!/usr/bin/env bash
set -eu -o pipefail
src=$PWD/skills/ship/scripts
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
origin=$work/github.com/owner/repo.git
repo="$work/repo"
export XDG_STATE_HOME="$work/state" SHIP_FAKE="$work/fake" SHIP_HOST_ADAPTER="$PWD/tests/host-fake.sh" SHIP_MERGE_CHECKS_GRACE=0
mkdir -p "$SHIP_FAKE"
git init -q --bare -b main "$origin"
git clone -q "$origin" "$repo" 2>/dev/null
g() { git -C "$repo" -c user.name=t -c user.email=t@t "$@"; }
g commit -q --allow-empty -m base
g push -q origin main
g remote set-head origin main
g switch -q -c fix/x
g commit -q --allow-empty -m 'published head A'
A=$(g rev-parse HEAD)
g push -q origin fix/x
g switch -q main
g commit -q --allow-empty -m 'new main'
g push -q origin main
g switch -q fix/x
g merge -q --no-edit main
B=$(g rev-parse HEAD)
record=$(cd "$repo" && bash -c 'source "$1"; ship_record_root' _ "$src/_lib.sh")
mkdir -p "$record/ship-case"
touch "$record/ship-case/run.md"
(cd "$repo" && bash "$src/run-file.sh" gate admit human --head "$A" --issue case)
pr() { jq -n --arg s "$2" --arg a "$A" '{number:7,title:"fix: x",head_ref:"fix/x",base_ref:"main",head_sha:$a,state:$s}' > "$SHIP_FAKE/host_pr_get.$1.json"; }
pr 1 open; pr 2 merged
echo "Published head $A behind actual base by $(g rev-list --count "$A..origin/main"); checkout head $B behind by $(g rev-list --count HEAD..origin/main)"
(cd "$repo" && bash "$src/merge.sh" 7 none "$A" --run case)
rg '^host_pr_merge' "$SHIP_FAKE/calls"
