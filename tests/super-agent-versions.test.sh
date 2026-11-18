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
sa_skill_version Gharib89/skills "$src" 99.0.0
check "a wake whose loaded copy is older than the source flags it stale" \
  "$(jq -cn --arg l "$loaded" '{loaded: $l, source: "99.0.0", stale: true}')" "$(pulse | jq -c .skill)"
check "reconcile, the watcher wake, carries the same flag" true "$(bash "$s/reconcile.sh" --ledger "$led" | jq .skill.stale)"
check "a stale copy alone is no change for the backstop" false "$(pulse | jq .changed)"
sa_skill_version Gharib89/skills "$src" "${loaded%%.*}.100.0"
check "versions compare by number, not as text" true "$(pulse | jq .skill.stale)"
sa_skill_version Gharib89/skills "$src" "$loaded"
check "a loaded copy at the source's version is not stale" false "$(pulse | jq .skill.stale)"
sa_skill_version Gharib89/skills "$src" 0.0.1
check "a loaded copy ahead of the source (a worktree run) is not stale" false "$(pulse | jq .skill.stale)"
rm -f "$SA_FAKE/gh/$(printf '%s' "repos/Gharib89/skills/contents/$src" | sed 's/[^A-Za-z0-9._-]/_/g')"
out=$(pulse); rc=$?
check "an unreadable source copy leaves the flag unknown, and the wake still answers" \
  "0 $(jq -cn --arg l "$loaded" '{loaded: $l, source: null, stale: null}')" "$rc $(jq -c .skill <<<"$out")"

# --- launch: the target repo's installed ship -------------------------------------
ship=.claude/skills/ship/SKILL.md
reset; issue 7 "widgets: add a frobnicator" ready-for-agent S
sa_skill_version "$repo" "$ship" 0.66.3
out=$(L 7 --area x --out "$out_f"); rc=$?
check "a ship below the minimum answers stale_ship with the installed and minimum versions, exit 1" \
  '1 {"launch":false,"reason":"stale_ship","installed":"0.66.3"}' "$rc $(jq -c '{launch, reason, installed: .detail.installed}' <<<"$out")"
check "the minimum is a version" 1 "$(jq -r .detail.minimum <<<"$out" | grep -cE '^[0-9]+\.[0-9]+\.[0-9]+$')"
check "a stale_ship launch takes no claim and writes no --out file" "0 absent" \
  "$(grep -c 'issues/7/comments.*POST\|POST.*issues/7/comments' "$SA_FAKE/calls") $([ -e "$out_f" ] && echo present || echo absent)"
min=$(jq -r .detail.minimum <<<"$out")
sa_skill_version "$repo" "$ship" "$min"
check "a ship at the minimum launches" true "$(L 7 --area x | jq .launch)"
reset; issue 7 "widgets: add a frobnicator" ready-for-agent S
sa_skill_version "$repo" "$ship" "${min%%.*}.$(( $(cut -d. -f2 <<<"$min") + 1 )).0"
check "a ship above the minimum launches" true "$(L 7 --area x | jq .launch)"
reset; issue 8 "widgets: a question" needs-triage S
sa_skill_version "$repo" "$ship" 0.0.1
check "a triage launch reads no ship version" true "$(L 8 --area x | jq .launch)"
reset; issue 7 "widgets: add a frobnicator" ready-for-agent S
rm -f "$SA_FAKE/gh/$(printf '%s' "repos/$repo/contents/$ship" | sed 's/[^A-Za-z0-9._-]/_/g')"
out=$(L 7 --area x 2>/dev/null); rc=$?
check "an unreadable ship copy exits 2 naming it, never launching" "2 false 1" \
  "$rc $(jq -r 'has("args")' <<<"$out") $(jq -r .error <<<"$out" | grep -c 'ship version')"

finish
