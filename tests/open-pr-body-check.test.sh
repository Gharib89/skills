#!/usr/bin/env bash
# open-pr runs the repo's body checker, the `Body-check:` line under the
# profile's `## PR`, on the body file before the push, with the exit contract
# update-pr-body follows (#986): a body the checker refuses is posted by no
# mechanic, so the run fixes its Change outline in phase 6 rather than at the
# first phase-7 body write. Driven over the Host fake (tests/host-fake.sh) in a
# throwaway repo whose pushes land in a local bare repository, so "no push" is
# read off that bare repo and "no create" off the fake's calls log, with a
# fixture checker that fails a Shape fence over three lines.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

open=$PWD/skills/ship/scripts/open-pr.sh
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
repo=$work/repo; bare=$work/origin.git; export SHIP_FAKE=$work/fake
mkdir -p "$SHIP_FAKE"
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
} >/dev/null 2>&1 || { echo "fixture setup failed" >&2; exit 2; }
export SHIP_HOST_ADAPTER=$PWD/tests/host-fake.sh
export XDG_STATE_HOME=$work/state

mkdir -p "$repo/docs/agents" "$repo/scripts"
checker() { printf '#!/bin/sh\n%s\n' "$1" > "$repo/scripts/check-outline.sh"; chmod +x "$repo/scripts/check-outline.sh"; }
checker 'n=$(awk '\''/^```diff/ { f = 1; next } /^```/ { f = 0 } f'\'' "$1" | wc -l)
[ "$n" -le 3 ] || { echo "pr-body: change outline: the Shape fence is $n lines, over 3"; exit 1; }'
profile() { { printf '## PR\n\nTemplate: None.\n'; printf '%s\n' "$@"; printf '\n## Public surface\n\nDefault.\n'; } > "$repo/docs/agents/ship.md"; }
reset()   { rm -f "$SHIP_FAKE"/*; git -C "$bare" update-ref -d refs/heads/feat/thing-7 2>/dev/null; }
opn()     { printf '%s' "$1" > "$work/body.md"; ( cd "$repo" && bash "$open" 7 --title "fix: a thing" --body-file "$work/body.md" 2>/dev/null ); }
pushed()  { git -C "$bare" rev-parse -q --verify refs/heads/feat/thing-7 >/dev/null && echo pushed || echo none; }
created() { cut -f1 "$SHIP_FAKE/calls" 2>/dev/null | paste -sd' '; }

short=$'## Change outline\n\n```diff\na\nb\n```\n'
long=$'## Change outline\n\n```diff\na\nb\nc\nd\n```\n'

reset; profile 'Body-check: scripts/check-outline.sh'
out=$(opn "$long"); rc=$?
check_rc "a body the checker refuses exits 1" 1 "$rc"
check "the refusal names the checker and quotes it" "PR body fails the repo's body check (scripts/check-outline.sh): pr-body: change outline: the Shape fence is 4 lines, over 3" "$(jq -r .error <<<"$out")"
check "nothing is pushed" none "$(pushed)"
check "no PR is created" "" "$(created)"

reset
opn "$short" >/dev/null; rc=$?
check_rc "a body the checker accepts opens" 0 "$rc"
check "it pushes and creates" "pushed host_pr_create" "$(pushed) $(created)"

checker 'echo oops >&2
exit 2'
reset
out=$(opn "$short"); rc=$?
check_rc "a checker that exits 2 is tooling" 2 "$rc"
check "its stderr is the reason" "body check scripts/check-outline.sh failed (exit 2): oops" "$(jq -r .error <<<"$out")"
check "nothing is pushed" none "$(pushed)"
check "no PR is created" "" "$(created)"

checker 'echo refused
exit 1'
reset; rm -f "$repo/docs/agents/ship.md"
opn "$long" >/dev/null; rc=$?
check_rc "no profile opens unchecked" 0 "$rc"

reset; profile 'Merge: Default.'
opn "$long" >/dev/null; rc=$?
check_rc "no Body-check line opens unchecked" 0 "$rc"

reset; profile 'Body-check: None.'
opn "$long" >/dev/null; rc=$?
check_rc "Body-check: None. opens unchecked" 0 "$rc"

# A profile that is there but cannot be read is no answer: read as "no
# checker", it would open the PR unchecked.
if [ "$(id -u)" -ne 0 ]; then
  reset; profile 'Body-check: scripts/check-outline.sh'
  chmod 000 "$repo/docs/agents/ship.md"
  out=$(opn "$short"); rc=$?
  chmod 644 "$repo/docs/agents/ship.md"
  check_rc "an unreadable profile is tooling" 2 "$rc"
  check "nothing is pushed" none "$(pushed)"
  check "no PR is created" "" "$(created)"
else
  skipped "unreadable profile is tooling: running as root"
fi

finish
