#!/usr/bin/env bash
# `carry-check <file>...` compares each Carry: file in the worktree with the main
# checkout's copy and answers with file names only. Driven over a real linked
# worktree of a temporary repo, the way the isolate-* tests build theirs. The
# secrets in the fixture must never reach stdout or stderr.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

m=$PWD/skills/ship-run/scripts/carry-check.sh
tmp=$(mktemp -d) || exit 2
trap 'rm -rf "$tmp"' EXIT
tmp=$(cd "$tmp" && pwd -P)
g() { git -c user.email=t@t -c user.name=t -c commit.gpgsign=false "$@"; }

{
  git init -q -b main "$tmp/seed"
  g -C "$tmp/seed" commit -q --allow-empty -m one
  git clone -q --bare "$tmp/seed" "$tmp/origin.git"
  git clone -q "$tmp/origin.git" "$tmp/repo"
  g -C "$tmp/repo" worktree add -q -b feat/x-1 "$tmp/wt" origin/main
} >/dev/null 2>&1 || { echo "fixture setup failed" >&2; exit 2; }
main=$tmp/repo wt=$tmp/wt

mkdir -p "$main/cfg" "$wt/cfg"
printf 'SECRET-SAME\n' | tee "$main/.env" "$wt/.env" >/dev/null
printf 'SECRET-MAIN\n' > "$main/.env.local"; printf 'SECRET-WORKTREE\n' > "$wt/.env.local"
printf 'SECRET-NESTED\n' | tee "$main/cfg/key" "$wt/cfg/key" >/dev/null
printf 'SECRET-ONLY-MAIN\n' > "$main/only-main"
printf 'SECRET-ONLY-WT\n' > "$wt/only-wt"

run() { out=$(cd "$wt" && "$m" "$@" 2>"$tmp/err"); rc=$?; }

run .env cfg/key
check "matching files answer ok" '{"ok":true,"match":[".env","cfg/key"],"differs":[],"missing":[]}' "$(jq -c . <<<"$out")"
check_rc "matching files exit 0" 0 "$rc"

run .env .env.local only-main only-wt absent
check "each file lands in its list" \
  '{"ok":false,"match":[".env"],"differs":[".env.local"],"missing":["only-main","only-wt","absent"]}' "$(jq -c . <<<"$out")"
check_rc "a differing or missing file exits 1" 1 "$rc"

run
check "no files answers a passing verdict with empty lists" '{"ok":true,"match":[],"differs":[],"missing":[]}' "$(jq -c . <<<"$out")"
check_rc "no files exits 0" 0 "$rc"

out=$(cd "$wt/cfg" && "$m" cfg/key 2>/dev/null)
check "files are read from the worktree root, whatever the cwd" '{"ok":true,"match":["cfg/key"],"differs":[],"missing":[]}' "$(jq -c . <<<"$out")"

run .env .env.local only-main
all=$out$(cat "$tmp/err")
check "no file content on stdout or stderr" 0 "$(grep -c 'SECRET' <<<"$all")"

out=$(cd "$main" && "$m" .env 2>"$tmp/err"); rc=$?
check_rc "run from the main checkout is a tooling error" 2 "$rc"

out=$(cd "$main" && "$m" 2>/dev/null); rc=$?
check "no files from the main checkout still answers a passing verdict" '{"ok":true,"match":[],"differs":[],"missing":[]}' "$(jq -c . <<<"$out")"
check_rc "no files from the main checkout exits 0" 0 "$rc"

mkdir -p "$main/adir" "$wt/adir"
printf 'SECRET-SPACE\n' | tee "$main/a b" "$wt/a b" >/dev/null
run adir "a b"
check "an unreadable-as-file path is missing, a name with a space matches" '{"ok":false,"match":["a b"],"differs":[],"missing":["adir"]}' "$(jq -c . <<<"$out")"

for bad in /etc/passwd a/../b a/..; do
  run "$bad"
  check_rc "the path $bad is a tooling error" 2 "$rc"
done
run --x
check_rc "a flag typed as a file is a tooling error" 2 "$rc"
run ../escape
check_rc "a path leaving the checkout is a tooling error" 2 "$rc"

finish
