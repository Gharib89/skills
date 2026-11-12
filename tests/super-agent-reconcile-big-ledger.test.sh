#!/usr/bin/env bash
# super-agent's `reconcile` over a ledger past Linux's one-argument cap of
# 128 KiB (MAX_ARG_STRLEN): its final report reads the ledger on stdin, so a
# large ledger still reports instead of dying with "Argument list too long".
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
source tests/super-agent-fake.sh

s=skills/super-agent/scripts
tmp=$(mktemp -d) || exit 2
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/fake"
export PATH="$tmp/bin:$PATH" SA_FAKE=$tmp/fake
sa_fake_install "$tmp/bin"
led=$tmp/ledger.json
repo=Gharib89/skills

for n in 5 6; do
  bash "$s/ledger.sh" --ledger "$led" add --repo $repo --number $n --thread "t-$n" --worktree "/wt/$n" --branch "feat/x-$n" >/dev/null
  sa_thread "t-$n" running 1 0 "/wt/$n" "feat/x-$n"
  sa_pr $repo "feat/x-$n" none
  sa_issue $repo "$n" open
done
jq -c '.pad = ("x" * 140000)' "$led" > "$tmp/big.json" && mv "$tmp/big.json" "$led"
check "the test ledger is over 128 KiB" true "$([ "$(wc -c < "$led")" -gt 131072 ] && echo true)"
out=$(bash "$s/reconcile.sh" --ledger "$led" 2>"$tmp/err"); rc=$?
check_rc "a ledger over 128 KiB reconciles" 0 "$rc"
check "and reports its entries" "$repo#5 $repo#6" "$(jq -r '[.entries[].key] | join(" ")' <<<"$out")"
check "with nothing on stderr" "" "$(cat "$tmp/err")"

finish
