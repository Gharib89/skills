#!/usr/bin/env bash
# skills/ship/scripts/run-file.sh `note`: one line appended under a `## ` section
# of the Run file, the section created at the end when the record has none, so a
# run writes its Round, Stop and evidence lines through a mechanic instead of a
# heredoc edit the worktree guard refuses (#787). The seam is
# `run-file note <section> <line> --file <run file>`: an exit code, one JSON
# answer, and the Run file's bytes.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
m=$PWD/skills/ship/scripts/run-file.sh
rf=$(bash "$m" init 9 --scratchpad "$T/sp" | jq -r .run_file)

# note <args>...: sets out and status for one call.
note() { out=$(bash "$m" note "$@" 2>/dev/null); status=$?; }
section() { awk -v h="## $1" '/^## /{ f = ($0 == h) } f' "$rf"; }

# A section the record already has: the line lands after its last line and
# before the next heading.
printf '\n## Evidence\n\nProbe: a: true => exit 0 at abc1234: ok\n\n## Zeta\n' >> "$rf"
note Evidence 'Round: self-review 1: clean' --file "$rf"
check_rc "a line under an existing section is accepted" 0 "$status"
check "the answer names the section and the line" '{"run_file":"'"$rf"'","section":"Evidence","line":"Round: self-review 1: clean"}' "$(jq -c . <<<"$out")"
check "the line follows the section's last line" $'Probe: a: true => exit 0 at abc1234: ok\nRound: self-review 1: clean' "$(section Evidence | grep -v '^$' | tail -n 2)"
note Evidence 'Stop: self-review: tree unchanged' --issue 9 --scratchpad "$T/sp"
check_rc "the --issue form finds the same record" 0 "$status"
check "a second line follows the first" $'Round: self-review 1: clean\nStop: self-review: tree unchanged' "$(section Evidence | grep -v '^$' | tail -n 2)"
check "the next section is untouched" "## Zeta" "$(tail -n 1 "$rf")"

# A section the record lacks is created at the end.
note 'Review notes' 'Round: self-review: report at scratch/standards/standards-report.md' --file "$rf"
check_rc "a missing section is created" 0 "$status"
check "the heading and the line close the file" $'## Review notes\n\nRound: self-review: report at scratch/standards/standards-report.md' "$(tail -n 3 "$rf")"

# Malformed calls are the usage error, and the record stays as it was.
before=$(cat "$rf")
for args in "" "Evidence" "Evidence ''" "'' x" "Evidence -x" "-x y" "'## Evidence' y" "Evidence '## heading'"; do
  eval "note $args --file \"\$rf\""
  check_rc "note $args is tooling" 2 "$status"
done
note Evidence $'two\nlines' --file "$rf"
check_rc "a two-line note is tooling" 2 "$status"
check "no malformed call touched the record" "$before" "$(cat "$rf")"

# A Criterion line is written only in the form `gate clean` reads (#853), so the
# gate never holds on a met line's form; the refusal names both forms.
forms="a Criterion line is \`Criterion <n>: met: <proof>\` or \`Criterion <n>: not met: <reason>\`, the form gate clean reads:"
for line in 'Criterion 2: met at 907b1bf: test green' 'Criterion 2: met:' $'Criterion 2: met: \t' 'Criterion 2: not met:' 'Criterion 2: done' 'Criterion two: met: x' 'Criterion 2 met: x'; do
  note Evidence "$line" --file "$rf"
  check_rc "$line is refused" 1 "$status"
  check "the refusal of $line names the accepted forms" "$forms $line" "$(jq -r .error <<<"$out")"
done
check "no refused Criterion line touched the record" "$before" "$(cat "$rf")"
for line in 'Criterion 2: met: tests/run-file-note.test.sh green at 907b1bf' 'Criterion 3: not met: the host action needs a human'; do
  note Evidence "$line" --file "$rf"
  check_rc "$line is accepted" 0 "$status"
  check "$line is written unchanged" "$line" "$(section Evidence | grep -v '^$' | tail -n 1)"
done

# A line under `## Criteria` is an entry the gate holds: note numbers it after
# the highest entry, so a phase-1 rewrite's replacement is owed its own line
# (#863). A Criterion line there stays an attestation, written unchanged.
crf=$(printf '%s\n' '- [ ] a' '- [ ] b' | bash "$m" init 10 --scratchpad "$T/sp" --criteria - | jq -r .run_file)
rf=$crf
note Criteria 'the replacement criterion' --file "$crf"
check_rc "a Criteria line is accepted" 0 "$status"
check "the line is the next numbered entry" '- 3: the replacement criterion' "$(jq -r .line <<<"$out")"
note Criteria 'Criterion 3: met: tests/run-file-note.test.sh green' --file "$crf"
note Criteria 'another' --file "$crf"
check "a Criterion line stays unchanged and the next entry is 4" \
  $'- 1: a\n- 2: b\n- 3: the replacement criterion\nCriterion 3: met: tests/run-file-note.test.sh green\n- 4: another' \
  "$(section Criteria | grep -v -e '^$' -e '^## ')"
# Only `Criterion <n>: ` opens an attestation there: other text on that word is
# criterion text, and an attestation out of the gate's form is still refused.
note Criteria 'Criterion parser keeps the replacement text' --file "$crf"
check "criterion text opening on Criterion is numbered" '- 5: Criterion parser keeps the replacement text' "$(jq -r .line <<<"$out")"
note Criteria 'Criterion 3: met at 907b1bf: test green' --file "$crf"
check_rc "an off-form attestation under Criteria is refused" 1 "$status"
rf=$(bash "$m" init 11 --scratchpad "$T/sp" | jq -r .run_file)
note Criteria 'first of its kind' --file "$rf"
check "a record with no Criteria section starts at 1" '- 1: first of its kind' "$(section Criteria | grep -v -e '^$' -e '^## ')"

check "--help documents the verb and its answer" "2" "$(bash "$m" --help | grep -c -e 'note <section> <line>' -e 'note: {run_file, section, line}')"
finish
