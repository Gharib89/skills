#!/usr/bin/env bash
# Split by behaviour from tests/run-file-clean-cap.test.sh: the local review a
# non-converged reviewer records (`Past-cap:`, `Docs-only:`) and how gate clean reads it.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
source tests/run-file-lib.sh
source tests/run-file-clean-cap-lib.sh
# A run past the cap records its local review as `Past-cap:`, never as a reviewer
# `Round:`, so the capped reviewer's rounds still read 1..Cap (ship-849). The
# gate stays held, naming the cap and the head the local review read (#880).
# The local review's line names its Report file and result (#1248).
printf 'Findings: none\n' > "$tmp/standards-report-local.md"; rv=": local review $tmp/standards-report-local.md: no findings"
pastcap='reviewer primary: past cap 2, local review read abcdef0123456789, no host reviewer read it'
capped; before=$(grep -c '^Round: primary' "$f"); printf 'Past-cap: primary: tree unchanged at abcdef0123456789%s\n' "$rv" >> "$f"
held 'a local review past the cap' "$pastcap"
check 'the local review adds no reviewer Round line' "$before" "$(grep -c '^Round: primary' "$f")"
capped; unheld 'a capped primary with no local review' "$pastcap"
capped; held 'a capped primary with no local review keeps the cap reason' 'reviewer primary: cap'
capped; printf 'Past-cap: primary: tree unchanged at 1234567%s\n' "$rv" >> "$f"; held 'a local review at an uncovered head names the range to read' 'reviewer primary: past cap 2, local review read 1234567, head moved: read 1234567..abcdef0123456789'
capped; printf 'Past-cap: primary: tree unchanged at abcdef0123456789%s\nRound: fallback 1: dispositioned\nStop: fallback: tree unchanged at abcdef0123456789\n' "$rv" >> "$f"; clean 'a fallback that read the head settles a past-cap primary'
capped; printf 'Past-cap: primary: tree unchanged at abcdef0123456789%s\n' "$rv" >> "$f"; unheld 'a past-cap local review' 'reviewer primary: cap'
base; printf 'Past-cap: primary: tree unchanged at abcdef0123456789%s\n' "$rv" >> "$f"; clean 'a past-cap line on a reviewer that settled'
# `note` takes the one form the gate reads.
base; check_rc 'note takes a past-cap line' 0 "$(bash "$m" note 'Review evidence' "Past-cap: primary: tree unchanged at abcdef0123456789$rv" --file "$f" >/dev/null 2>&1; echo $?)"
check 'the past-cap line landed' 1 "$(grep -cxF "Past-cap: primary: tree unchanged at abcdef0123456789$rv" "$f")"
capped; bash "$m" note 'Review evidence' "Past-cap: primary: tree unchanged at abcdef0123456789$rv" --file "$f" >/dev/null 2>&1; held 'the gate reads the sha of a noted past-cap line' "$pastcap"
for bad in '' ': local review' ": local review $tmp/no-such.md: no findings" ": local review $tmp/standards-report-local.md:" ": local review $tmp/standards-report-local.md: "; do
  base; check_rc "note refuses a past-cap line ending '$bad'" 1 "$(bash "$m" note 'Review evidence' "Past-cap: primary: tree unchanged at abcdef0123456789$bad" --file "$f" >/dev/null 2>&1; echo $?)"
done
capped; printf 'Past-cap: fallback: tree unchanged at abcdef0123456789%s\n' "$rv" >> "$f"; unheld "another reviewer's past-cap line" "$pastcap"
for bad in 'abc123' 'ABCDEF0123456789'; do
  base; check_rc "note refuses a past-cap line at $bad" 1 "$(bash "$m" note 'Review evidence' "Past-cap: primary: tree unchanged at $bad$rv" --file "$f" >/dev/null 2>&1; echo $?)"
done
base; answer=$(bash "$m" note 'Review evidence' 'Past-cap: primary: tree unchanged' --file "$f" 2>/dev/null); rc=$?
check_rc 'note refuses a past-cap line with no head' 1 "$rc"
check 'the refusal names the form' 'a Past-cap line is `Past-cap: <reviewer>: tree unchanged at <sha>: local review <report file>: <result>`, its Report file non-empty, the form close 7 and gate clean read: Past-cap: primary: tree unchanged' "$(jq -r .error <<<"$answer")"
# A docs-only fix-only diff ends the loop before Cap: is spent: no fallback is owed, and none covers it.
capped; change_run '/^Round: primary 2/d'; held 'docs-only end before the cap' 'reviewer primary: cap'
capped; change_run '/^Round: primary 2/d'; unheld 'docs-only end before the cap' 'reviewer fallback: not reviewed'
# Its local review, recorded as `Docs-only:` on the head it read, clears the hold:
# the loop's own rule ended it, and no fix went unread (#1034).
docsonly() { capped; change_run '/^Round: primary 2/d'; }
docsonly; printf 'Docs-only: primary: tree unchanged at abcdef0123456789%s\n' "$rv" >> "$f"; clean 'a docs-only end whose local review read the head'
base; change_run 's/Stop: primary: tree unchanged at abcdef0123456789/Stop: primary: cap/'; printf 'Docs-only: primary: tree unchanged at abcdef0123456789%s\n' "$rv" >> "$f"; clean 'an uncapped docs-only end whose local review read the head'
docsonly; printf 'Docs-only: primary: tree unchanged at 1234567%s\n' "$rv" >> "$f"; held 'a docs-only local review at an uncovered head names the range to read' 'reviewer primary: docs-only end, local review read 1234567, head moved: read 1234567..abcdef0123456789'
docsonly; printf 'Docs-only: fallback: tree unchanged at abcdef0123456789%s\n' "$rv" >> "$f"; held "another reviewer's docs-only line" 'reviewer primary: cap'
capped; printf 'Docs-only: primary: tree unchanged at abcdef0123456789%s\n' "$rv" >> "$f"; held 'a docs-only line on a spent cap' 'reviewer primary: cap'
docsonly; change_run 's/Round: primary 1:/Round: primary 2:/'; printf 'Docs-only: primary: tree unchanged at abcdef0123456789%s\n' "$rv" >> "$f"; held 'a docs-only line on gapped rounds' 'reviewer primary: cap'
docsonly; change_run 's/Round: primary 1: all dispositioned/Round: primary 1: re-raised declined: a finding/'; printf 'Docs-only: primary: tree unchanged at abcdef0123456789%s\n' "$rv" >> "$f"; held 'a docs-only line on a re-raised declined finding' 'reviewer primary: cap'
base; check_rc 'note takes a docs-only line' 0 "$(bash "$m" note 'Review evidence' "Docs-only: primary: tree unchanged at abcdef0123456789$rv" --file "$f" >/dev/null 2>&1; echo $?)"
for bad in 'abc123' 'ABCDEF0123456789'; do
  base; check_rc "note refuses a docs-only line at $bad" 1 "$(bash "$m" note 'Review evidence' "Docs-only: primary: tree unchanged at $bad$rv" --file "$f" >/dev/null 2>&1; echo $?)"
done
base; answer=$(bash "$m" note 'Review evidence' 'Docs-only: primary: tree unchanged' --file "$f" 2>/dev/null); rc=$?
check_rc 'note refuses a docs-only line with no head' 1 "$rc"
check 'the docs-only refusal names the form' 'a Docs-only line is `Docs-only: <reviewer>: tree unchanged at <sha>: local review <report file>: <result>`, its Report file non-empty, the form close 7 and gate clean read: Docs-only: primary: tree unchanged' "$(jq -r .error <<<"$answer")"
finish
