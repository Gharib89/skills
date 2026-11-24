#!/usr/bin/env bash
# super-agent's version gates, driven through the command lines over the fake `t3`
# and `gh` (tests/super-agent-fake.sh): every wake (reconcile, and pulse, which runs
# it) compares the loaded super-agent copy's version with the source copy's on
# Gharib89/skills and flags an older loaded one stale; launch answers `stale_ship`
# for a ship ticket whose repo's installed ship is below the minimum, taking no claim.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
source tests/super-agent-fake.sh
source tests/super-agent-launch-lib.sh

loaded=$(sed -n 's/^  version: //p' "$s/../SKILL.md")
src=skills/super-agent/SKILL.md
pulse() { bash "$s/pulse.sh" --ledger "$led"; }

# --- each wake: the loaded copy against the source copy ---------------------------
reset
sa_skill_file Gharib89/skills "$src" 99.0.0
check "a wake whose loaded copy is older than the source flags it stale" \
  "$(jq -cn --arg l "$loaded" '{loaded: $l, source: "99.0.0", stale: true}')" "$(pulse | jq -c .skill)"
check "reconcile, the watcher wake, carries the same flag" true "$(bash "$s/reconcile.sh" --ledger "$led" | jq .skill.stale)"
check "a stale copy alone is no change for the backstop" false "$(pulse | jq .changed)"
sa_skill_file Gharib89/skills "$src" "${loaded%%.*}.100.0"
check "versions compare by number, not as text" true "$(pulse | jq .skill.stale)"
sa_skill_file Gharib89/skills "$src" "$loaded"
check "a loaded copy at the source's version is not stale" false "$(pulse | jq .skill.stale)"
sa_skill_file Gharib89/skills "$src" 0.0.1
check "a loaded copy ahead of the source (a worktree run) is not stale" false "$(pulse | jq .skill.stale)"
sa_skill_file Gharib89/skills "$src" v99.0.0
check "a source version that is not X.Y.Z is unread, never a verdict" null "$(pulse | jq .skill.stale)"
rm -f "$SA_FAKE/gh/$(printf '%s' "repos/Gharib89/skills/contents/$src" | sed 's/[^A-Za-z0-9._-]/_/g')"
out=$(pulse); rc=$?
check "an unreadable source copy leaves the flag unknown, and the wake still answers" \
  "0 $(jq -cn --arg l "$loaded" '{loaded: $l, source: null, stale: null}')" "$rc $(jq -c .skill <<<"$out")"

# --- launch: the target repo's installed ship -------------------------------------
ship=.claude/skills/ship-run/SKILL.md
reset; issue 7 "widgets: add a frobnicator" ready-for-agent S
sa_skill_file "$repo" "$ship" 0.66.3
out=$(L 7 --area x --out "$out_f"); rc=$?
check "a ship below the minimum answers stale_ship with the installed and minimum versions, exit 1" \
  '1 {"launch":false,"reason":"stale_ship","installed":"0.66.3"}' "$rc $(jq -c '{launch, reason, installed: .detail.installed}' <<<"$out")"
check "the minimum is a version" 1 "$(jq -r .detail.minimum <<<"$out" | grep -cE '^[0-9]+\.[0-9]+\.[0-9]+$')"
check "a stale_ship launch takes no claim and writes no --out file" "0 absent" \
  "$(grep -c 'issues/7/comments.*POST\|POST.*issues/7/comments' "$SA_FAKE/calls") $([ -e "$out_f" ] && echo present || echo absent)"
min=$(jq -r .detail.minimum <<<"$out")
sa_skill_file "$repo" "$ship" "$min"
check "a ship at the minimum launches" true "$(L 7 --area x | jq .launch)"
reset; issue 7 "widgets: add a frobnicator" ready-for-agent S
sa_skill_file "$repo" "$ship" "${min%%.*}.$(( $(cut -d. -f2 <<<"$min") + 1 )).0"
check "a ship above the minimum launches" true "$(L 7 --area x | jq .launch)"
reset; issue 8 "widgets: a question" needs-triage S
sa_skill_file "$repo" "$ship" 0.0.1
check "a triage launch reads no ship version" true "$(L 8 --area x | jq .launch)"
reset; issue 7 "widgets: add a frobnicator" ready-for-agent S
sa_route "repos/$repo/contents/$ship" "$(jq -cn '{content: ("---\nmetadata:\n  version: 0.66.3\n---\nExample:\n  version: 9.9.9\n" | @base64)}')"
check "only the frontmatter's version is read, never a body line" stale_ship "$(L 7 --area x | jq -r .reason)"
for body in 'metadata:\n  version: 0.67.0\n' '---\nmetadata:\n  version: 0.67.0\n'; do
  reset; issue 7 "widgets: add a frobnicator" ready-for-agent S
  sa_route "repos/$repo/contents/$ship" "$(jq -cn --arg b "$body" '{content: ($b | gsub("\\\\n"; "\n") | @base64)}')"
  check "a SKILL.md with no opening or no closing --- is unread: exit 2 ($body)" 2 "$(L 7 --area x >/dev/null 2>&1; echo $?)"
done
for v in 0.67 0.67.0-rc1 abc; do
  reset; issue 7 "widgets: add a frobnicator" ready-for-agent S
  sa_skill_file "$repo" "$ship" "$v"
  check "an installed ship version of $v is unread: exit 2, never a launch or stale_ship" 2 "$(L 7 --area x >/dev/null 2>&1; echo $?)"
done
reset; issue 7 "widgets: add a frobnicator" ready-for-agent S
rm -f "$SA_FAKE/gh/$(printf '%s' "repos/$repo/contents/$ship" | sed 's/[^A-Za-z0-9._-]/_/g')"
out=$(L 7 --area x 2>/dev/null); rc=$?
check "an unreadable ship copy exits 2 naming it, never launching" "2 false 1" \
  "$rc $(jq -r 'has("args")' <<<"$out") $(jq -r .error <<<"$out" | grep -c 'ship version')"

# A repo still holding only the pre-rename `.claude/skills/ship/` copy cannot answer
# `/ship-run`: stale_ship with that copy's version, so the owner refreshes it first.
reset; issue 7 "widgets: add a frobnicator" ready-for-agent S
rm -f "$SA_FAKE/gh/$(printf '%s' "repos/$repo/contents/$ship" | sed 's/[^A-Za-z0-9._-]/_/g')"
sa_skill_file "$repo" .claude/skills/ship/SKILL.md 0.71.3
check "a repo with only the pre-rename ship copy answers stale_ship with its version" \
  '1 stale_ship 0.71.3' "$(L 7 --area x >/dev/null; echo $?) $(L 7 --area x | jq -r '"\(.reason) \(.detail.installed)"')"

# The fallback reads the old copy only on a 404 for `ship-run`: a failed or malformed read
# of a copy that is there is no verdict, whatever the old copy beside it says.
reset; issue 7 "widgets: add a frobnicator" ready-for-agent S
sa_skill_file "$repo" .claude/skills/ship/SKILL.md 0.71.3
sa_gh_fail "contents/.claude/skills/ship-run/SKILL.md" 5
check "a failed read of the ship-run copy exits 2, never stale_ship off the old copy beside it" \
  2 "$(L 7 --area x >/dev/null 2>&1; echo $?)"
reset; issue 7 "widgets: add a frobnicator" ready-for-agent S
sa_skill_file "$repo" .claude/skills/ship/SKILL.md 0.71.3
sa_route "repos/$repo/contents/$ship" "$(jq -cn '{content: ("no frontmatter\n" | @base64)}')"
check "a malformed ship-run copy exits 2, never stale_ship off the old copy beside it" \
  2 "$(L 7 --area x >/dev/null 2>&1; echo $?)"

finish
