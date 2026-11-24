#!/usr/bin/env bash
# base-fresh while origin cannot be fetched: the base moved one commit on origin,
# the fetch fails, and the verdict is fresh against the last-known ref. With
# origin back, the same checkout is one commit behind. Run from the repo root.
set -uo pipefail
base_fresh=$PWD/skills/ship-run/scripts/base-fresh.sh
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
g() { git -c user.name=t -c user.email=t@t -c init.defaultBranch=main "$@"; }
{
  g init -q --bare "$work/origin.git"
  g clone -q "$work/origin.git" "$work/w"
  g -C "$work/w" commit -q --allow-empty -m init
  g -C "$work/w" push -q origin main
  git -C "$work/w" remote set-head origin main
  g -C "$work/w" checkout -q -b fix/x
  g clone -q "$work/origin.git" "$work/other"
  g -C "$work/other" commit -q --allow-empty -m 'the base moves'
  g -C "$work/other" push -q origin main
} >/dev/null 2>&1 || { echo 'fixture setup failed' >&2; exit 2; }

mv "$work/origin.git" "$work/origin.away"
echo 'Origin unavailable:'
(cd "$work/w" && bash "$base_fresh" 2>/dev/null | jq -c .; echo "rc=${PIPESTATUS[0]}")
mv "$work/origin.away" "$work/origin.git"
echo 'Origin restored, same checkout:'
(cd "$work/w" && bash "$base_fresh" 2>/dev/null | jq -c .; echo "rc=${PIPESTATUS[0]}")
