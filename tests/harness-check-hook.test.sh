#!/usr/bin/env bash
# skills/setup-harness/templates/check-hook.sh: the Claude Code hook wrapper
# over the check entry point. The subject is what Claude Code reads back: the
# exit code (2 blocks with stderr, the only failure Claude sees), a
# `systemMessage` on stdout for the human, and whether `check.sh` ran at all.
# `check.sh` is a stub in a throwaway git repo, answering the exit code and
# JSON line each case sets, and logging its arguments and CHECK_DEADLINE.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

fixture=$(mktemp -d); trap 'rm -rf "$fixture"' EXIT
hook=$PWD/skills/setup-harness/templates/check-hook.sh
r=$fixture/repo
mkdir -p "$r/scripts"
git -C "$r" init -q
cat > "$r/scripts/check.sh" <<'STUB'
#!/bin/sh
echo "$* deadline=${CHECK_DEADLINE:-none}" >> "$STUB_LOG"
[ -n "${STUB_ERR:-}" ] && printf '%s' "$STUB_ERR" >&2
printf '%s\n' "${STUB_OUT:-}"
exit "${STUB_RC:-0}"
STUB
chmod +x "$r/scripts/check.sh"
export STUB_LOG=$fixture/log

# <rung> <stdin>: run the hook in the repo; leaves stdout in `out`, stderr in
# `err` and the exit code in `rc`.
hook() {
  out=$(cd "$r" && printf '%s' "$2" | bash "$hook" "$1" 2>"$fixture/err"); rc=$?
  err=$(cat "$fixture/err")
}
calls() { wc -l < "$STUB_LOG" | tr -d ' '; }

edit_in='{"hook_event_name":"PostToolUse","tool_name":"Edit","tool_input":{"file_path":"'$r'/src/a b.py","old_string":"x"}}'

: > "$STUB_LOG"
now=$(date +%s)
STUB_RC=0 hook edit "$edit_in"
check_rc "a passing edit rung exits 0" 0 "$rc"
check "a passing edit rung says nothing" "" "$out"
logged=$(cat "$STUB_LOG")
check "the edited file reaches check.sh edit" "edit $r/src/a b.py" "${logged% deadline=*}"
d=${logged##*deadline=}
check "the edit deadline is the 5 s budget from now" yes "$([ "$d" -ge $((now + 5)) ] && [ "$d" -le $((now + 6)) ] && echo yes)"

big=$(head -c 30000 /dev/zero | tr '\0' 'e')
STUB_RC=1 STUB_ERR="lint: a.py:1: E501
$big" hook edit "$edit_in"
check_rc "a failing check blocks with exit 2, the code Claude reads" 2 "$rc"
check "the failure output opens with the linter's message" "lint: a.py:1: E501" "$(printf '%s\n' "$err" | head -n 1)"
check "the failure output stays under Claude Code's 10k-character limit" yes "$([ "${#err}" -lt 10000 ] && echo yes)"

STUB_RC=2 STUB_OUT='{"rung":"edit","verdict":"unavailable","checks":{"runner":"unavailable"}}' hook edit "$edit_in"
check_rc "an unavailable check never blocks" 0 "$rc"
check "an unavailable check is a message to the human naming it" \
  '{"systemMessage":"harness: edit rung unavailable: runner"}' "$out"

STUB_RC=3 STUB_OUT='{"rung":"edit","verdict":"over-budget","checks":{"runner":"over-budget"}}' hook edit "$edit_in"
check_rc "an over-budget check never blocks" 0 "$rc"
check "over budget names rung, check and time" \
  '{"systemMessage":"harness: edit rung over its 5 s budget: runner"}' "$out"

stop_in='{"hook_event_name":"Stop","stop_hook_active":false}'
cont_in='{"hook_event_name":"Stop","stop_hook_active": true}'
: > "$STUB_LOG"
now=$(date +%s)
STUB_RC=0 hook turn "$stop_in"
check_rc "a passing turn rung lets the stop through" 0 "$rc"
check "the turn rung runs check.sh turn once" 1 "$(calls)"
d=$(sed -n 's/.*deadline=//p' "$STUB_LOG")
check "the turn deadline is the 60 s budget from now" yes "$([ "$d" -ge $((now + 60)) ] && [ "$d" -le $((now + 61)) ] && echo yes)"

STUB_RC=0 hook turn "$stop_in"
check "a turn with no working-tree change skips the check" 1 "$(calls)"
check "a skipped turn says nothing" "" "$out"

echo 'x = 1' > "$r/new.py"
STUB_RC=1 STUB_ERR="tests: 1 failed" hook turn "$stop_in"
check "a changed tree is checked again" 2 "$(calls)"
check_rc "a failing turn sends the failure back to Claude" 2 "$rc"
check "the failure output reaches Claude" "tests: 1 failed" "$err"

STUB_RC=1 hook turn "$cont_in"
check "a continuation with no change does not re-check" 2 "$(calls)"
check_rc "a continuation with no change allows the stop" 0 "$rc"
check "the human is told the turn ended failing" \
  '{"systemMessage":"harness: turn rung still failing, unchanged since the last check"}' "$out"

echo 'x = 2' > "$r/new.py"
STUB_RC=0 hook turn "$cont_in"
check "a continuation after a change re-checks" 3 "$(calls)"
check_rc "a fixed continuation lets the stop through" 0 "$rc"

check "the real index is untouched by the fingerprint" "?? new.py
?? scripts/" "$(git -C "$r" status --porcelain)"

finish
