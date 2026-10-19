#!/usr/bin/env bash
# drive-session's at-rest rows: `read --rest` marks one and `watch` stops waking
# on it, over the same fake `herdr` as tests/drive-session.test.sh.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
source tests/herdr-fake.sh

s=skills/drive-session/scripts
tmp=$(mktemp -d) || exit 2
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/fake" "$tmp/cwd"
herdr_fake_install "$tmp/bin"
export PATH="$tmp/bin:$PATH" HERDR_FAKE=$tmp/fake HERDR_ENV=1 HERDR_WORKSPACE_ID=w1

# -------------------------------------------------------------------
# A merged run's tab fires `done` on idle compaction with nothing to answer: a
# row read with --rest is not watched, but a timeout still lists it, and a roster
# with only gone or at-rest rows has no live session.
for w in r1 r2; do
  printf 'idle 69\n' > "$HERDR_FAKE/$w.states"
  bash "$s/spawn.sh" "$w" --roster "$tmp/rest.json" --cwd "$tmp/cwd" --prompt x >/dev/null
done
printf 'done 70\n' > "$HERDR_FAKE/r1.states"
out=$(bash "$s/read.sh" r1 --roster "$tmp/rest.json" --rest)
check "read --rest answers rest" true "$(jq -r .rest <<<"$out")"
check "and marks the row at rest" true "$(jq -r '.sessions[0].at_rest' "$tmp/rest.json")"
check "read without --rest leaves the row unmarked" null "$(bash "$s/read.sh" r2 --roster "$tmp/rest.json" | jq -c '.rest // null')"
printf 'done 90\n' > "$HERDR_FAKE/r1.states"
printf 'working 71\n' > "$HERDR_FAKE/r2.states"
out=$(bash "$s/watch.sh" --roster "$tmp/rest.json" --timeout 3000)
check "watch ignores a done past seen_seq on an at-rest row" null "$(jq -c .name <<<"$out")"
check "its timeout lists the at-rest row beside the live one" '[["r2","working"],["r1","at-rest"]]' \
  "$(jq -c '[.sessions[] | [.name, .status]]' <<<"$out")"
rm "$HERDR_FAKE/r2.states"
bash "$s/read.sh" r2 --roster "$tmp/rest.json" >/dev/null
out=$(bash "$s/watch.sh" --roster "$tmp/rest.json" 2>/dev/null); rc=$?
check_rc "watch with every row gone or at rest exits 1" 1 "$rc"
check "and says there is nothing to watch" "no live session in the roster $tmp/rest.json" "$(jq -r .error <<<"$out")"

finish
