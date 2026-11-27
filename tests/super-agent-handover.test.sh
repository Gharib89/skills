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
export HOME=$tmp/home CLAUDE_CONFIG_DIR='' XDG_STATE_HOME=$tmp/state
folder=$XDG_STATE_HOME/super-agent/home hc=$XDG_STATE_HOME/super-agent/home/.claude/settings.local.json
proj=$tmp/projects.json
jq -n --arg f "$folder" '{projects: [{id: "p-other", workspaceRoot: "/repo"}, {id: "p-home", workspaceRoot: $f}]}' > "$proj"
mkdir -p "$HOME/.claude/projects/p"
jq -cn '{type: "user", timestamp: "2026-11-17T09:00:00Z", message: {role: "user",
  content: "Base directory for this skill: /x/.claude/skills/super-agent\nthread th-old"}}' > "$HOME/.claude/projects/p/s.jsonl"

loaded=$(sed -n 's/^  version: //p' "$s/../SKILL.md")
src=skills/super-agent/SKILL.md
bear=$tmp/bearings.md
cat > "$tmp/bin/npx" <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$SA_FAKE/npx-calls"
exit "${NPX_RC:-0}"
FAKE
chmod +x "$tmp/bin/npx"
H() { bash "$s/handover.sh" --ledger "$led" --from th-old --out "$bear" --projects "$proj"; }
npx_calls() { cat "$SA_FAKE/npx-calls" 2>/dev/null; }
seed() {
  reset; rm -f "$bear" "$SA_FAKE/npx-calls"
  sa_skill_file Gharib89/skills "$src" "$loaded"
  bash "$s/ledger.sh" --ledger "$led" add --repo "$repo" --number 7 --thread th-7 --worktree /wt/7 --branch feat/x-7 >/dev/null
  bash "$s/ledger.sh" --ledger "$led" add --task rotate-key --thread th-t >/dev/null
  bash "$s/ledger.sh" --ledger "$led" need "$repo#7" --action "Approve ${repo#*/}#7 merge" --reason merge-gate --why w --option a --option b >/dev/null
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
out=$(bash "$s/$x.sh" --ledger "$led" --from th-old --out /nonexistent/b.md --projects "$proj" 2>/dev/null); rc=$?
check "$x refuses an unwritable --out by name, exit 2, before any refresh" "2 cannot write /nonexistent/b.md absent" \
  "$rc $(jq -r .error <<<"$out") $([ -e "$SA_FAKE/npx-calls" ] && echo present || echo absent)"
check_rc "$x without --out exits 2" 2 "$(bash "$s/$x.sh" --ledger "$led" --from th-old --projects "$proj" >/dev/null 2>&1; echo $?)"
check_rc "$x without --projects exits 2" 2 "$(bash "$s/$x.sh" --ledger "$led" --from th-old --out "$bear" >/dev/null 2>&1; echo $?)"
printf 'not json\n' > "$tmp/bad.json"
out=$(bash "$s/$x.sh" --ledger "$led" --from th-old --out "$bear" --projects "$tmp/bad.json" 2>/dev/null); rc=$?
check_rc "$x with a --projects file that is no project list exits 2" 2 "$rc"
check "$x says the file is no project list" "$tmp/bad.json: not a t3_project_list answer" "$(jq -r .error <<<"$out")"
jq -n '{projects: [], nextCursor: "c2"}' > "$tmp/page1.json"
out=$(bash "$s/$x.sh" --ledger "$led" --from th-old --out "$bear" --projects "$tmp/page1.json" 2>/dev/null); rc=$?
check_rc "$x with one page of several exits 2" 2 "$rc"
check "$x says a nextCursor is set" "$tmp/page1.json: a nextCursor is set: save all pages' rows as one array" "$(jq -r .error <<<"$out")"
jq -n '{projects: [{id: "p5", workspaceRoot: 5}]}' > "$tmp/badrow.json"
out=$(bash "$s/$x.sh" --ledger "$led" --from th-old --out "$bear" --projects "$tmp/badrow.json" 2>/dev/null); rc=$?
check_rc "$x with a project row whose workspaceRoot is no string exits 2" 2 "$rc"
check "$x names the projects file and the field for a bad row" "$tmp/badrow.json: a project row is no object, or its workspaceRoot is no string" "$(jq -r .error <<<"$out")"

# --- the bearings file, from the ledger -----------------------------------------
seed
out=$(H); rc=$?
check_rc "a handover exits 0" 0 "$rc"
check "it answers where the bearings are and that no refresh ran" "$bear false" "$(jq -r '"\(.bearings) \(.refreshed)"' <<<"$out")"
check "it names the predecessor thread and the ledger" 1 "$(grep -F 'th-old' "$bear" | grep -cF "$led")"
check "each open entry is a line with its thread and stage" "2" "$(grep -cE "^- ($repo#7 thread th-7 launched|task:rotate-key thread th-t launched)" "$bear")"
check "each open need is a line with its action" 1 "$(grep -c "^- $repo#7: Approve ${repo#*/}#7 merge" "$bear")"
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
seed; rm -f "$(dirname "$led")/scorecard-reviewed"
for d in 09 10 11 12 13 14 15; do printf '{"day":"2026-11-%s"}\n' "$d"; done > "$(dirname "$led")/scorecard.jsonl"
now=$(jq -n '"2026-11-18T08:00:00Z" | fromdateiso8601')
out=$(SA_NOW=$now H); rc=$?
check "a handover counts the previous day's scorecard row for the old thread" "0 2026-11-17 th-old" \
  "$rc $(jq -r .scorecard.row <<<"$out") $(jq -r 'select(.day == "2026-11-17") | .thread' "$(dirname "$led")/scorecard.jsonl")"
check "the first handover of a week runs the weekly review over the last full week" "[] 2026-11-09" \
  "$(jq -c .scorecard.review <<<"$out") $(cat "$(dirname "$led")/scorecard-reviewed")"
check "a later handover that week runs no review" null "$(SA_NOW=$((now + 86400)) H | jq -c .scorecard.review)"
for d in 10-19 10-26 11-02 11-09; do printf '{"day":"2026-%s","guards":{"watch":{"blocks":0,"passes":0}}}\n' "$d"; done >> "$(dirname "$led")/scorecard.jsonl"
rm -f "$(dirname "$led")/scorecard-reviewed"
SA_NOW=$now H >/dev/null
check "a review row joins the bearings' Needs you list" 1 "$(grep -c '^- Scorecard: the watch guard blocked nothing' "$bear")"
rm -f "$(dirname "$led")/scorecard-reviewed"
printf 'not json\n' >> "$(dirname "$led")/scorecard.jsonl"
err=$(SA_NOW=$now H 2>&1 >/dev/null); rc=$?
check "a review that fails is reported, holds nothing and marks no week" "0 1 absent" \
  "$rc $(grep -c 'the scorecard review failed' <<<"$err") $([ -f "$(dirname "$led")/scorecard-reviewed" ] && echo present || echo absent)"
for d in 09 10 11 12 13 14; do printf '{"day":"2026-11-%s"}\n' "$d"; done > "$(dirname "$led")/scorecard.jsonl"
out=$(SA_NOW=$now H 2>/dev/null)
check "a week missing a row: the review error is in the JSON and a Needs you line" "true 1" \
  "$(jq -r '.scorecard.review_error | contains("no row for 2026-11-15")' <<<"$out") $(grep -c '^- Scorecard: the weekly review failed: .*no row for 2026-11-15' "$bear")"
cp -r "$s/.." "$tmp/sa" && printf '#!/usr/bin/env bash\n[ "$1" = review ] && exit 1\nexec bash %q "$@"\n' "$s/scorecard.sh" > "$tmp/sa/scripts/scorecard.sh"
out=$(SA_NOW=$now bash "$tmp/sa/scripts/handover.sh" --ledger "$led" --from th-old --out "$bear" --projects "$proj" 2>/dev/null); rc=$?
check "a review that dies with no output is still reported and holds nothing" '0 "the review failed" null absent' \
  "$rc $(jq -c .scorecard.review_error <<<"$out") $(jq -c .scorecard.review <<<"$out") $([ -f "$(dirname "$led")/scorecard-reviewed" ] && echo present || echo absent)"
rm -f "$(dirname "$led")/scorecard.jsonl"
printf 'not json\n' > "$led.archive.jsonl"
out=$(SA_NOW=$now H 2>/dev/null); rc=$?
check "a scorecard that fails is reported and holds nothing" "0 null true" \
  "$rc $(jq -r .scorecard.row <<<"$out") $(jq -r '.scorecard.error | contains("archive")' <<<"$out")"
rm -f "$led.archive.jsonl"

# --- the super agent folder: rewritten at every handover, the successor launched in it ---
seed; rm -rf "$XDG_STATE_HOME/super-agent/home"
out=$(H); rc=$?
check "a handover writes the folder's settings with the state guard and names the folder's project" "0 true true p-home $folder" \
  "$rc $(jq .home.written <<<"$out") $(jq .home.guard <<<"$out") $(jq -r .home.project_id <<<"$out") $(jq -r .home.folder <<<"$out")"
check "the settings file's PreToolUse entries are the guard, the observe hook and the call guard" 3 "$(jq '.hooks.PreToolUse | length' "$hc")"
check "a healthy folder adds no Needs you line" 0 "$(grep -c 'Super agent folder\|State guard' "$bear")"
mkdir -p "$tmp/sysbin"; printf '#!/bin/sh\necho inactive\nexit 3\n' > "$tmp/sysbin/systemctl"; chmod +x "$tmp/sysbin/systemctl"
check "a wake timer systemctl does not report running is one Needs you line" 1 \
  "$(PATH="$tmp/sysbin:$PATH" H >/dev/null; grep -c '^- Wake timer: ' "$bear")"
jq -n '{projects: [{id: "p-other", workspaceRoot: "/repo"}]}' > "$tmp/noproj.json"
out=$(bash "$s/handover.sh" --ledger "$led" --from th-old --out "$bear" --projects "$tmp/noproj.json"); rc=$?
check "a missing T3 project for the folder is one Needs you line saying what the owner creates" "0 null 1" \
  "$rc $(jq -r .home.project_id <<<"$out") $(grep -c "^- Super agent folder: no T3 project has $folder as its workspace" "$bear")"
jq -n --arg f "$folder/" '{projects: [{id: "p-slash", workspaceRoot: $f, archivedAt: null, deletedAt: null}]}' > "$tmp/slash.json"
check "a project root written with a trailing slash is still the folder's" p-slash \
  "$(bash "$s/handover.sh" --ledger "$led" --from th-old --out "$bear" --projects "$tmp/slash.json" | jq -r .home.project_id)"
jq -n --arg f "$folder" '[{id: "p-gone", workspaceRoot: $f, archivedAt: "2026-11-01T00:00:00Z"}]' > "$tmp/archived.json"
check "an archived project is not the folder's, and the rows may be a bare array" "null 1" \
  "$(bash "$s/handover.sh" --ledger "$led" --from th-old --out "$bear" --projects "$tmp/archived.json" | jq -r .home.project_id) $(grep -c '^- Super agent folder: no T3 project' "$bear")"
rm -rf "$folder"; mkdir -p "$folder"; printf 'x' > "$folder/.claude"
out=$(H); rc=$?
check "a guard entry the handover could not write is one Needs you line" "0 false 1" \
  "$rc $(jq .home.guard <<<"$out") $(grep -c "^- Super agent folder: the state guard's hook is missing from $hc" "$bear")"
rm -rf "$folder"
mkdir -p "$HOME/.claude"
old='{"matcher":"Edit|Write|MultiEdit|NotebookEdit|Bash","hooks":[{"type":"command","command":"bash '\''/old/copy/super-agent/scripts/guard.sh'\''"}]}'
jq -n --argjson o "$old" '{hooks: {PreToolUse: [$o]}}' > "$HOME/.claude/settings.json"
H >/dev/null
check "a stale guard entry in user settings is a Needs you line with the line to remove" 1 \
  "$(grep -cF -- "- State guard: remove its stale entry from $HOME/.claude/settings.json: $old" "$bear")"
rm -f "$HOME/.claude/settings.json"

finish
