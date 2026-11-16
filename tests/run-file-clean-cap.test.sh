#!/usr/bin/env bash
# Split by behaviour from tests/run-file-clean.test.sh: cap, fallback and skip cases.
# The clean gate consumes only recorded evidence and the supplied CI answer.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
source tests/run-file-lib.sh
source tests/run-file-clean-cap-lib.sh
capped; held 'capped primary owes its fallback' 'reviewer fallback: not reviewed'
capped; printf 'Round: fallback 1: dispositioned\nStop: fallback: tree unchanged at abcdef0123456789\n' >> "$f"; clean 'capped primary covered by a fallback stopped on tree unchanged'
capped; printf 'Round: fallback 1: dispositioned\nStop: fallback: cap\n' >> "$f"; held 'capped primary with a capped fallback' 'reviewer fallback: cap'
capped; printf 'Stop: fallback: tree unchanged at abcdef0123456789\n' >> "$f"; held 'capped primary with an undispositioned fallback' 'reviewer fallback: no dispositioned round'
capped; change_run 's/Round: primary 2:/Round: primary 3:/'; printf 'Round: fallback 1: dispositioned\nStop: fallback: tree unchanged at abcdef0123456789\n' >> "$f"; held 'gapped round numbers do not spend the cap' 'reviewer primary: cap'
capped; change_run 's/Round: primary 2: fixes pushed/Round: primary 2:   /'; printf 'Round: fallback 1: dispositioned\nStop: fallback: tree unchanged at abcdef0123456789\n' >> "$f"; held 'a blank round does not spend the cap' 'reviewer primary: cap'
capped; change_run 's/Stop: primary: cap/Stop: primary: tree unchanged at abcdef0123456789/'; clean 'primary at its cap with an unchanged tree owes no fallback'
# A cap stamped with the head its last round read is still a cap (#1045).
capped; change_run 's/Stop: primary: cap/& at abcdef0123456789/'; held 'a stamped capped primary owes its fallback' 'reviewer fallback: not reviewed'
capped; change_run 's/Stop: primary: cap/& at abcdef0123456789/'; printf 'Round: fallback 1: dispositioned\nStop: fallback: tree unchanged at abcdef0123456789\n' >> "$f"; clean 'a stamped capped primary covered by its fallback'
capped; change_run 's/Stop: primary: cap/& at abcdef0123456789/'; printf 'Round: fallback 1: dispositioned\nStop: fallback: cap at abcdef0123456789\n' >> "$f"; held 'a stamped capped fallback keeps the cap reason' 'reviewer fallback: cap'
# A primary whose later round did not land after a fix changed the tree owes its fallback a run (#551).
landed() { base; change_run 's/Stop: primary: tree unchanged at abcdef0123456789/Stop: primary: not landed/'; }
landed; held 'not-landed primary owes its fallback' 'reviewer fallback: not reviewed'
landed; printf 'Round: fallback 1: dispositioned\nStop: fallback: tree unchanged at abcdef0123456789\n' >> "$f"; clean 'not-landed primary covered by a fallback stopped on tree unchanged'
landed; printf 'Round: fallback 1: dispositioned\nStop: fallback: cap\n' >> "$f"; held 'not-landed primary with a capped fallback' 'reviewer primary: not landed'
base; change_run 's/Stop: primary: tree unchanged at abcdef0123456789/Stop: primary: auto-once/'; held 'auto-once changed round' 'reviewer primary: auto-once'
base; sed 's/Trigger: on-request/Trigger: auto-once/' "$profile" > "$profile.new"; mv "$profile.new" "$profile"; clean 'auto-once unchanged round records tree unchanged'
base; printf 'Override: declined gating finding\n' >> "$f"; held 'override needed' 'override needed: declined gating finding'
# A Ship defect never holds the gate on its own: a defect that breaks a gating
# step already fails that step's evidence (ADR 0010).
base; printf 'Ship-defect: upstream gap #42\n' >> "$f"; touch "$tmp/records/ship-clean/defect-1.md"; clean 'a Ship-defect line and a defect draft'
base; touch "$tmp/records/ship-clean/tracker-1.md"; held 'Tracker draft' 'Tracker draft: tracker-1.md'
base; touch "$tmp/records/ship-clean/defect-1.base.md"; printf 'Deviation: accepted scoped departure\nOverride: None.\nShip-defect: none\n' >> "$f"; clean 'deviation and draft base are independent'
base; printf '  Override: quoted\n`Ship-defect: quoted`\nOverrides: partial token\n' >> "$f"; clean 'quoted indented partial evidence does not match'
base; change_run 's/Stop: primary: tree unchanged at abcdef0123456789/Stop: primary: cap/'; printf '\n```\nStop: primary: tree unchanged at abcdef0123456789\n```\n' >> "$f"; held 'fenced stop cannot override cap' 'reviewer primary: cap'
base; printf '\n~~~\nOverride: example\nShip-defect: example\n~~~\n' >> "$f"; clean 'fenced examples are not evidence'
base; change_run 's/"tests":"pass"/"tests":"fail"/'; printf '\n```\n## Local gate\n- 11:00 abcdef0123456789 pass {"tests":"pass","secrets":"pass"}\n```\n' >> "$f"; held 'fenced gate cannot replace failing gate' 'local gate tests: fail'
base; change_run 's/punctuation: pass at abcdef0123456789/punctuation: fail/'; printf '\n```\n## Verification results\n- live check: punctuation: pass\n```\n' >> "$f"; held 'fenced verification cannot replace failing result' 'verification live check: punctuation: fail'
base; printf '\n```\n' >> "$f"; answer=$(call); check_rc 'unclosed Run file fence is tooling' 2 "$?"; check 'unclosed fence names its record' "cannot read Run file evidence at $f" "$(jq -r .error <<<"$answer")"
if [ "$(id -u)" -ne 0 ]; then
  base; touch "$tmp/records/ship-clean/tracker-1.md"; chmod 111 "$tmp/records/ship-clean"
  answer=$(call); rc=$?; chmod 755 "$tmp/records/ship-clean"
  check_rc 'unreadable draft directory is tooling' 2 "$rc"
  check 'unreadable draft directory names its path' "cannot read draft directory at $tmp/records/ship-clean" "$(jq -r .error <<<"$answer")"
else
  skipped 'unreadable draft directory: chmod does not stop root'
fi
base; printf 'Stop: primary: cap\n' >> "$f"; held 'last stop wins' 'reviewer primary: cap'
base; change_run 's/Stop: primary: tree unchanged at abcdef0123456789/Stop: primary: not reviewed/'; printf 'Round: fallback 1: dispositioned\nStop: fallback: cap\n' >> "$f"; held 'fallback stopped at cap' 'reviewer primary: not reviewed'
base; change_ci '.status="no-checks" | .checks=[]'; held 'legal no-checks cannot replace expected green leg' 'CI test: missing'
base; sed 's/^Legs:$/Legs: None./; /  test: prove the change/d' "$profile" > "$profile.new"; mv "$profile.new" "$profile"; change_ci '.status="no-checks" | .checks=[]'; held 'no-checks not explicitly legal' 'CI: no-checks'
base; sed 's/^Legs:$/Legs: None./; /  test: prove the change/d' "$profile" > "$profile.new"; mv "$profile.new" "$profile"; printf '\n' >> "$profile"; sed '/^Legs:/a No-checks legal: yes' "$profile" > "$profile.new"; mv "$profile.new" "$profile"; change_ci '.status="no-checks" | .checks=[]'; clean 'legal no-checks with no expected legs'
# A path-filtered leg: No-checks legal: yes admits a leg with no check on the head (#589).
legal() { sed '/^  test: prove the change$/a\  docs: path-filtered\nNo-checks legal: yes' "$profile" > "$profile.new" && mv "$profile.new" "$profile"; }
base; legal; change_ci '.legs=["test","docs"] | .missing_legs=["docs"]'; clean 'legal missing leg'
base; legal; change_ci '.status="no-checks" | .checks=[]'; clean 'legal no-checks with listed legs'
base; legal; change_ci '.checks[0].status="failure"'; held 'legal policy keeps a red leg' 'CI test: failure'
base; legal; change_run 's/"tests":"pass"/"tests":"deferred-to-ci"/'; change_ci '.status="no-checks" | .checks=[]'; held 'legal missing leg cannot cover a deferred local gate' 'CI test: missing'
base; legal; change_run 's/"tests":"pass"/"tests":"deferred-to-ci"/'; change_ci '.legs=["test","docs"] | .missing_legs=["docs"]'; held 'deferred local gate keeps a filtered leg held' 'CI docs: missing'
base; legal; change_run 's/punctuation: pass at abcdef0123456789/punctuation: deferred-to-ci/'; change_ci '.checks=[]'; held 'legal missing leg proves no deferred verification' 'verification live check: punctuation: no associated green CI leg'
base; rm "$ci"; answer=$(call); check_rc 'unreadable CI input is tooling' 2 "$?"; check 'unreadable CI names its path' "cannot read CI answer at $ci" "$(jq -r .error <<<"$answer")"
base; sed '/^## Verification/i ```' "$profile" > "$profile.new"; mv "$profile.new" "$profile"; answer=$(call); check_rc 'unclosed profile fence is tooling' 2 "$?"; check 'unclosed profile fence names failed read' "cannot read profile evidence at $profile" "$(jq -r .error <<<"$answer")"
base; sed 's/^Legs:$/Legs: None./; /  test: prove the change/d' "$profile" > "$profile.new"; mv "$profile.new" "$profile"; sed '/^Legs:/a No-checks legal: no' "$profile" > "$profile.new"; mv "$profile.new" "$profile"; printf '\n```\n## CI\nLegs: None.\nNo-checks legal: yes\n```\n' >> "$profile"; change_ci '.status="no-checks" | .checks=[]'; held 'fenced CI policy cannot authorize no-checks' 'CI: no-checks'
# A background task's output file ends in an exit-code trailer: the first JSON
# object is the answer (#787).
base; printf '[exit 0]\n' >> "$ci"; clean 'a ci-wait answer followed by a trailing non-JSON line'
base; { jq . "$ci"; printf 'Background command exited with code 0\n'; } > "$ci.new"; mv "$ci.new" "$ci"; clean 'a pretty-printed ci-wait answer followed by a trailer'
base; { printf 'preamble line\n'; cat "$ci"; } > "$ci.new"; mv "$ci.new" "$ci"; answer=$(call); check_rc 'a non-JSON line before the answer is still tooling' 2 "$?"
base; printf 'not-json\n' > "$ci"; answer=$(call); check_rc 'malformed CI is tooling' 2 "$?"; check 'malformed CI names failed read' 'CI answer is not a valid ci-wait object' "$(jq -r .error <<<"$answer")"
base; printf '{}\n' > "$ci"; answer=$(call); check_rc 'empty CI object is tooling' 2 "$?"; check 'empty CI names failed read' 'CI answer is not a valid ci-wait object' "$(jq -r .error <<<"$answer")"
base; change_run 's/{.*}/{broken}/'; answer=$(call); check_rc 'malformed recorded gates is tooling' 2 "$?"; check 'bad gate JSON names failed read' 'cannot read recorded local gate results' "$(jq -r .error <<<"$answer")"
base; answer=$(call --result x=pass); check_rc 'result flag is invalid for clean' 2 "$?"
base; answer=$(cd "$repo" && bash "$m" gate clean - --head "$head" --issue clean --scratchpad "$tmp/records" < "$ci" 2>/dev/null); check 'stdin and issue lookup answer clean' true "$(jq -r .clean <<<"$answer")"
base; cp "$f" "$repo/run.md"; touch "$repo/tracker-relative.md"
answer=$(call --file run.md); check_rc 'relative Run file draft refuses' 1 "$?"; check 'relative Run file draft names hold' true "$(jq -r '.held_by | index("Tracker draft: tracker-relative.md") != null' <<<"$answer")"
base; before=$(cat "$f"); call >/dev/null; check 'clean is read-only' "$before" "$(cat "$f")"
# A run that skips phase 3 settles its verifications through the skip, so the
# gate is not held by results no close could record (#564).
base; printf '### beta\nAlso proven by CI: None.\n' >> "$profile"
sk=$(cd "$repo" && bash "$m" init skip --scratchpad "$tmp/records" --from-profile 2>/dev/null | jq -r .run_file)
(cd "$repo" && { bash "$m" close 0 --file "$sk"; for p in 1 2; do bash "$m" open "$p" --file "$sk"; bash "$m" close "$p" --file "$sk"; done
  bash "$m" skip 3 'docs class: no verification applies' --file "$sk"
  printf '{"verdict":"pass","gates":{"tests":"pass","secrets":"pass"}}' | bash "$m" gate record - --head "$head" --file "$sk"; } >/dev/null 2>&1)
printf '## Review evidence\nRound: primary 1: all dispositioned\nStop: primary: tree unchanged at abcdef0123456789\nStop: fallback: not reviewed\n' >> "$sk"
answer=$(cd "$repo" && bash "$m" gate clean "$ci" --head "$head" --file "$sk" 2>/dev/null); rc=$?
check_rc 'a skipped phase 3 exits clean' 0 "$rc"
check 'a skipped phase 3 holds no verification' '{"clean":true,"held_by":[]}' "$(jq -c . <<<"$answer")"
finish
