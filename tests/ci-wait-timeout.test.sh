#!/usr/bin/env bash
# ci-wait's --timeout floor. The mechanic waits out a fixed no-checks grace
# before it will believe a PR has no checks, so a window shorter than that grace
# can only report `timeout` where the mechanic itself would have answered
# `no-checks` a minute later (#203). Every case here is malformed or runs where
# no origin resolves, so the guard answers before `ship_load_host` and nothing
# reaches a host.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

m=$PWD/skills/ship/scripts/ci-wait.sh
nogit=$(mktemp -d); trap 'rm -rf "$nogit"' EXIT

err() { ( cd "$nogit" && bash "$m" "$@" 2>/dev/null | jq -r '.error' ); }
rc()  { ( cd "$nogit" && bash "$m" "$@" >/dev/null 2>&1 ); echo $?; }

floor='--timeout below the 120s no-checks grace: a shorter window reports timeout where this mechanic answers no-checks'

check "a timeout under the grace names the grace" "$floor" "$(err 1 --timeout 30)"
check_rc "a timeout under the grace is tooling" 2 "$(rc 1 --timeout 30)"
check "the grace itself is accepted" "cannot derive the host from the origin remote" "$(err 1 --timeout 120)"
check "a non-numeric timeout is the usage line" \
  'usage: ci-wait <pr> [--timeout <s>, at least the 120s no-checks grace] [--interval <s>]' \
  "$(err 1 --timeout later)"

finish
