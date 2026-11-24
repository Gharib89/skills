#!/usr/bin/env bash
# super-agent's `handover`, driven through its command line over the fake `gh`
# (tests/super-agent-fake.sh) and a fake `npx`: it writes the successor's bearings
# file from the ledger, and refreshes the global super-agent copy only when the
# loaded copy is older than the source's.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
source tests/super-agent-fake.sh
source tests/super-agent-launch-lib.sh
# The scorecard row each handover counts looks for transcripts under HOME.
export HOME=$tmp/home CLAUDE_CONFIG_DIR=''

loaded=$(sed -n 's/^  version: //p' "$s/../SKILL.md")
src=skills/super-agent/SKILL.md
bear=$tmp/bearings.md
cat > "$tmp/bin/npx" <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$SA_FAKE/npx-calls"
exit "${NPX_RC:-0}"
FAKE
chmod +x "$tmp/bin/npx"
H() { bash "$s/handover.sh" --ledger "$led" --from th-old --out "$bear"; }
npx_calls() { cat "$SA_FAKE/npx-calls" 2>/dev/null; }
seed() {
  reset; rm -f "$bear" "$SA_FAKE/npx-calls"
  sa_skill_file Gharib89/skills "$src" "$loaded"
  bash "$s/ledger.sh" --ledger "$led" add --repo "$repo" --number 7 --thread th-7 --worktree /wt/7 --branch feat/x-7 >/dev/null
  bash "$s/ledger.sh" --ledger "$led" add --task rotate-key --thread th-t >/dev/null
  bash "$s/ledger.sh" --ledger "$led" need "$repo#7" --action "approve the merge" >/dev/null
  bash "$s/ledger.sh" --ledger "$led" wait "$repo#9" --reason "no slot" >/dev/null
}

# --- the contract every script keeps ------------------------------------------
x=handover
out=$(bash "$s/$x.sh" --help); rc=$?
check "$x --help opens with its usage line" "usage: $x" "$(sed -n 1p <<<"$out" | cut -d' ' -f1-2)"
check "$x --help names its stdout fields next" stdout: "$(sed -n 2p <<<"$out" | cut -c1-7)"
check_rc "$x --help exits 0" 0 "$rc"
out=$(bash "$s/$x.sh" --bogus 2>/dev/null); rc=$?
check "$x: a bad flag answers its usage line" "$(sed -n 1p <<<"$(bash "$s/$x.sh" --help)")" "$(jq -r .error <<<"$out")"
check_rc "$x: a bad flag exits 2" 2 "$rc"
sa_skill_file Gharib89/skills "$src" 99.0.0
out=$(bash "$s/$x.sh" --ledger "$led" --from th-old --out /nonexistent/b.md 2>/dev/null); rc=$?
check "$x refuses an unwritable --out by name, exit 2, before any refresh" "2 cannot write /nonexistent/b.md absent" \
  "$rc $(jq -r .error <<<"$out") $([ -e "$SA_FAKE/npx-calls" ] && echo present || echo absent)"
check_rc "$x without --out exits 2" 2 "$(bash "$s/$x.sh" --ledger "$led" --from th-old >/dev/null 2>&1; echo $?)"

# --- the bearings file, from the ledger -----------------------------------------
seed
out=$(H); rc=$?
check_rc "a handover exits 0" 0 "$rc"
check "it answers where the bearings are and that no refresh ran" "$bear false" "$(jq -r '"\(.bearings) \(.refreshed)"' <<<"$out")"
check "it names the predecessor thread and the ledger" 1 "$(grep -F 'th-old' "$bear" | grep -cF "$led")"
check "each open entry is a line with its thread and stage" "2" "$(grep -cE "^- ($repo#7 thread th-7 launched|task:rotate-key thread th-t launched)" "$bear")"
check "each open need is a line with its action" 1 "$(grep -c "^- $repo#7: approve the merge" "$bear")"
check "each waiting row is a line with its reason" 1 "$(grep -c "^- $repo#9: no slot" "$bear")"
check "a settled entry is not in the bearings" 0 "$(bash "$s/ledger.sh" --ledger "$led" add --repo "$repo" --number 3 --thread th-3 --worktree /wt/3 --branch b-3 >/dev/null
  jq '.entries["acme/widgets#3"].stage = "settled"' "$led" > "$tmp/l" && mv "$tmp/l" "$led"; H >/dev/null; grep -c 'acme/widgets#3' "$bear")"
check "the ledger is only read" "$(cat "$led")" "$(H >/dev/null; cat "$led")"
rm -f "$led"; out=$(H); rc=$?
check "a missing ledger still writes the bearings, with no entries" "0 0" "$rc $(grep -c '^- ' "$bear")"

# --- the refresh, only when the loaded copy is stale ----------------------------
seed
check "a current copy runs no refresh" "false " "$(H | jq -r .refreshed) $(npx_calls)"
sa_skill_file Gharib89/skills "$src" 0.0.1
check "a copy ahead of the source runs no refresh" "false " "$(H | jq -r .refreshed) $(npx_calls)"
sa_skill_file Gharib89/skills "$src" 99.0.0
out=$(H); rc=$?
check "a stale copy is refreshed globally at the pinned CLI" \
  "0 true skills@1.8.1 add Gharib89/skills --skill super-agent --agent claude-code -g -y" "$rc $(jq -r .refreshed <<<"$out") $(npx_calls)"
check "the answer carries the versions it compared" \
  "$(jq -cn --arg l "$loaded" '{loaded: $l, source: "99.0.0", stale: true}')" "$(jq -c .skill <<<"$out")"
check "the bearings record the refresh" 1 "$(grep -c "refreshed to 99.0.0" "$bear")"
rm -f "$SA_FAKE/gh/$(printf '%s' "repos/Gharib89/skills/contents/$src" | sed 's/[^A-Za-z0-9._-]/_/g')" "$SA_FAKE/npx-calls"
check "an unreadable source runs no refresh" "null false " "$(H | jq -r '"\(.skill.stale) \(.refreshed)"') $(npx_calls)"
sa_skill_file Gharib89/skills "$src" 99.0.0
out=$(NPX_RC=1 H); rc=$?
check "a failed refresh exits 1, the bearings still written" "1 false true" "$rc $(jq -r .refreshed <<<"$out") $([ -s "$bear" ] && echo true)"

# --- the scorecard: a row each handover, the weekly review once a week ------------
seed; rm -f "$(dirname "$led")/scorecard.jsonl" "$(dirname "$led")/scorecard-reviewed"
now=$(jq -n '"2026-11-18T08:00:00Z" | fromdateiso8601')
out=$(SA_NOW=$now H); rc=$?
check "a handover counts the previous day's scorecard row for the old thread" "0 2026-11-17 th-old" \
  "$rc $(jq -r .scorecard.row <<<"$out") $(jq -r .thread "$(dirname "$led")/scorecard.jsonl")"
check "the first handover of a week runs the weekly review over the last full week" "[] 2026-11-09" \
  "$(jq -c .scorecard.review <<<"$out") $(cat "$(dirname "$led")/scorecard-reviewed")"
check "a later handover that week runs no review" null "$(SA_NOW=$((now + 86400)) H | jq -c .scorecard.review)"
printf '%s\n' '{"day":"2026-11-11","needs":{"alerted_twice":3}}' >> "$(dirname "$led")/scorecard.jsonl"
rm -f "$(dirname "$led")/scorecard-reviewed"
SA_NOW=$now H >/dev/null
check "a review row joins the bearings' Needs you list" 1 "$(grep -c '^- Scorecard: needs.alerted_twice missed its target' "$bear")"
printf 'not json\n' > "$led.archive.jsonl"
out=$(SA_NOW=$now H 2>/dev/null); rc=$?
check "a scorecard that fails is reported and holds nothing" "0 null true" \
  "$rc $(jq -r .scorecard.row <<<"$out") $(jq -r '.scorecard.error | contains("archive")' <<<"$out")"
rm -f "$led.archive.jsonl"

finish
