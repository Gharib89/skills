#!/usr/bin/env bash
# The clean gate consumes only recorded evidence and the supplied CI answer.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
m=${RUN_FILE_MECHANIC:-$PWD/skills/ship/scripts/run-file.sh}
tmp=$(mktemp -d) || exit 2
trap 'rm -rf "$tmp"' EXIT
repo="$tmp/repo with spaces"
mkdir -p "$repo/docs/agents" "$tmp/records/ship-clean"
git init -q "$repo"
head=abcdef0123456789
f="$tmp/records/ship-clean/run.md"
ci="$tmp/ci.json"
profile="$repo/docs/agents/ship.md"
base() {
  cat > "$profile" <<'PROFILE'
## CI
Legs:
  test: prove the change

## Reviewers
### primary
Trigger: on-request
Fallback-for: None.
### fallback
Trigger: on-request
Fallback-for: primary

## Verification
### live check: punctuation
Also proven by CI: test
PROFILE
  cat > "$f" <<'RUN'
# ship run
## Verification results
- live check: punctuation: pass
## Local gate
- 10:00 abcdef0123456789 pass {"tests":"pass","secrets":"pass"}
## Review evidence
Round: primary 1: all dispositioned
Stop: primary: tree unchanged
Stop: fallback: not reviewed
RUN
  printf '%s\n' '{"status":"green","head_sha":"abcdef0123456789","checks":[{"name":"test","status":"success"}],"legs":["test"],"missing_legs":[],"failing":[],"non_leg_failing":[],"unlisted":[],"waited_s":0}' > "$ci"
  rm -f "$tmp/records/ship-clean/defect-1.md" "$tmp/records/ship-clean/tracker-1.md" "$tmp/records/ship-clean/defect-1.base.md"
}
call() { (cd "$repo" && bash "$m" gate clean "$ci" --head "$head" --file "$f" "$@" 2>"$tmp/err"); }
held() {
  local name=$1 reason=$2 answer rc
  answer=$(call); rc=$?
  check_rc "$name refuses" 1 "$rc"
  check "$name names its hold" true "$(jq -r --arg r "$reason" '.clean == false and (.held_by | index($r) != null)' <<<"$answer")"
  check "$name reports evidence on stderr" true "$(if grep -Fq -- "$reason" "$tmp/err"; then echo true; else echo false; fi)"
}
clean() {
  local name=$1 answer rc
  answer=$(call); rc=$?
  check_rc "$name exits clean" 0 "$rc"
  check "$name has the public key set" 'clean,held_by' "$(jq -r 'keys | join(",")' <<<"$answer")"
  check "$name has no holds" '{"clean":true,"held_by":[]}' "$(jq -c . <<<"$answer")"
}
unheld() { check "$1 does not hold $2" false "$(call | jq -r --arg r "$2" '.held_by | index($r) != null')"; }
change_run() { sed "$1" "$f" > "$f.new" && mv "$f.new" "$f"; }
change_ci() { jq "$1" "$ci" > "$ci.new" && mv "$ci.new" "$ci"; }
base; clean 'all recorded conditions holding'
base; change_run 's/abcdef0123456789/1111111111111111/'; held 'stale gate' 'local gate: recorded head differs'
base; change_run '/^- 10:00/d'; held 'missing gate' 'local gate: no record'
for status in fail unavailable; do
  base; change_run "s/10:00 abcdef0123456789 pass /10:00 abcdef0123456789 $status /"; held "$status verdict" "local gate: $status"
  base; change_run "s/\"tests\":\"pass\"/\"tests\":\"$status\"/"; held "$status gate" "local gate tests: $status"
done
# deferred-to-ci is a pass under the local-gate contract: CI green, already required, covers it.
base; change_run 's/"tests":"pass"/"tests":"deferred-to-ci"/'; clean 'deferred-to-ci gate'
base; change_run 's/"tests":"pass"/"tests":"deferred-to-ci"/'; change_ci '.status="checks-failed" | .checks[0].status="failure"'; held 'deferred-to-ci gate with red CI' 'CI test: failure'
# A deferral names no leg, so a red or pending check outside Legs: could be the one covering it.
base; change_run 's/"tests":"pass"/"tests":"deferred-to-ci"/'; change_ci '.checks += [{name:"lint",status:"success"}]'; clean 'deferred-to-ci gate with a green non-leg check'
base; change_run 's/"tests":"pass"/"tests":"deferred-to-ci"/'; change_ci '.checks += [{name:"lint",status:"failure"}]'; held 'deferred-to-ci gate with a red non-leg check' 'local gate tests: deferred-to-ci while CI lint: failure'
base; change_run 's/"tests":"pass"/"tests":"deferred-to-ci"/'; change_ci '.checks += [{name:"lint",status:"pending"}]'; held 'deferred-to-ci gate with a pending non-leg check' 'local gate tests: deferred-to-ci while CI lint: pending'
base; change_run 's/ {.*}//'; held 'missing gate results' 'local gate: missing gate results'
base; change_run 's/{.*}/{"tests":"pass"}/'; held 'missing secrets result' 'local gate: missing secrets result'
base; change_run 's/{.*}/{}/'; held 'empty gate results' 'local gate: missing gate results'
base; change_ci '.head_sha="1111111111111111"'; held 'stale CI' 'CI: head differs'
base; change_ci '.status="checks-failed" | .checks[0].status="failure"'; held 'red CI' 'CI test: failure'
base; change_ci '.status="pending" | .checks[0].status="pending"'; held 'pending CI' 'CI test: pending'
base; change_ci '.checks=[]'; held 'missing CI leg' 'CI test: missing'
base; change_ci '.checks += [{name:"test (linux)",status:"failure"}]'; held 'red matrix sibling' 'CI test (linux): failure'
base; change_ci '.checks[0].name="testing"'; held 'partial leg token' 'CI test: missing'
base; change_ci '.checks[0].name="test (linux)"'; clean 'successful matrix leg'
base; change_ci '.checks += [{name:"unlisted",status:"failure"}]'; clean 'non-leg red is independent'
for status in fail unavailable unexercised pending; do
  base; change_run "s/punctuation: pass/punctuation: $status/"; held "$status verification" "verification live check: punctuation: $status"
done
base; change_run '/^- live check/d'; held 'missing verification' 'verification live check: punctuation: missing'
base; change_run 's/punctuation: pass/punctuation: n\/a/'; clean 'inapplicable verification'
base; change_run 's/punctuation: pass/punctuation: deferred-to-ci: test/'; clean 'deferred verification with green associated leg'
base; change_run 's/punctuation: pass/punctuation: deferred-to-ci: test/'; sed 's/Also proven by CI: test/Also proven by CI: None./' "$profile" > "$profile.new"; mv "$profile.new" "$profile"; held 'deferred verification without association' 'verification live check: punctuation: no associated green CI leg'
for stop in cap 'small lane' 'not reviewed'; do
  base; change_run "s/Stop: primary: tree unchanged/Stop: primary: $stop/"; held "$stop primary without fallback" "reviewer primary: $stop"
done
# An inline run with no --review requested no round: --inline waived it, so the stop settles the reviewer.
inline() { base; change_run '/^Round: primary/d; s/Stop: primary: tree unchanged/Stop: primary: inline lane/; s/Stop: fallback: not reviewed/Stop: fallback: inline lane/; $a Lane: inline'; }
inline; clean 'inline-lane stops on the primary and its fallback'
# The last Lane: line decides: a run with none, or one revoked out of the lane, keeps no waiver.
inline; change_run '/^Lane: inline/d'; held 'inline-lane stops with no Lane: line' 'reviewer primary: inline lane'
inline; change_run '$a Lane: small'; held 'inline-lane stops after a revocation to the small lane' 'reviewer primary: inline lane'
inline; change_ci '.status="checks-failed" | .checks[0].status="failure"'; held 'inline lane with red CI' 'CI test: failure'
inline; touch "$tmp/records/ship-clean/defect-1.md"; held 'inline lane with a Ship defect draft' 'Ship defect draft: defect-1.md'
for trigger in auto-once on-push; do
  inline; sed "0,/Trigger: on-request/s//Trigger: $trigger/" "$profile" > "$profile.new"; mv "$profile.new" "$profile"; held "an inline-lane stop on an $trigger reviewer" 'reviewer primary: inline lane'
done
base; change_run 's/Stop: primary: tree unchanged/Stop: primary: not reviewed/; s/Stop: fallback: not reviewed/Stop: fallback: inline lane/'; held 'an inline-lane fallback does not cover a primary that was not reviewed' 'reviewer primary: not reviewed'
base; printf 'Round: primary 2:   \n' >> "$f"; held 'blank latest round' 'reviewer primary: no dispositioned round'
base; change_run '/^Round: primary/d'; held 'stop without dispositioned round' 'reviewer primary: no dispositioned round'
base; change_run '/^Stop: primary/d'; held 'missing reviewer stop' 'reviewer primary: missing stop'
base; change_run 's/Stop: primary: tree unchanged/Stop: primary: not reviewed/'; printf 'Round: fallback 1: dispositioned\nStop: fallback: tree unchanged\n' >> "$f"; clean 'not reviewed primary covered by a fallback stopped on tree unchanged'
base; change_run 's/Stop: primary: tree unchanged/Stop: primary: cap/'; printf 'Round: fallback 1: dispositioned\nStop: fallback: tree unchanged\n' >> "$f"; held 'cap is not rescued by fallback' 'reviewer primary: cap'
# A primary that spent its Cap: on a tree-changing last round owes its fallback a run (#531).
capped() { base; sed 's/^Fallback-for: None.$/Cap: 2\n&/' "$profile" > "$profile.new"; mv "$profile.new" "$profile"; change_run 's/Stop: primary: tree unchanged/Round: primary 2: fixes pushed\nStop: primary: cap/'; }
capped; held 'capped primary owes its fallback' 'reviewer fallback: not reviewed'
capped; printf 'Round: fallback 1: dispositioned\nStop: fallback: tree unchanged\n' >> "$f"; clean 'capped primary covered by a fallback stopped on tree unchanged'
capped; printf 'Round: fallback 1: dispositioned\nStop: fallback: cap\n' >> "$f"; held 'capped primary with a capped fallback' 'reviewer fallback: cap'
capped; printf 'Stop: fallback: tree unchanged\n' >> "$f"; held 'capped primary with an undispositioned fallback' 'reviewer fallback: no dispositioned round'
capped; change_run 's/Round: primary 2:/Round: primary 3:/'; printf 'Round: fallback 1: dispositioned\nStop: fallback: tree unchanged\n' >> "$f"; held 'gapped round numbers do not spend the cap' 'reviewer primary: cap'
capped; change_run 's/Round: primary 2: fixes pushed/Round: primary 2:   /'; printf 'Round: fallback 1: dispositioned\nStop: fallback: tree unchanged\n' >> "$f"; held 'a blank round does not spend the cap' 'reviewer primary: cap'
capped; change_run 's/Stop: primary: cap/Stop: primary: tree unchanged/'; clean 'primary at its cap with an unchanged tree owes no fallback'
# A docs-only fix-only diff ends the loop before Cap: is spent: no fallback is owed, and none covers it.
capped; change_run '/^Round: primary 2/d'; held 'docs-only end before the cap' 'reviewer primary: cap'
capped; change_run '/^Round: primary 2/d'; unheld 'docs-only end before the cap' 'reviewer fallback: not reviewed'
base; change_run 's/Stop: primary: tree unchanged/Stop: primary: auto-once/'; held 'auto-once changed round' 'reviewer primary: auto-once'
base; sed 's/Trigger: on-request/Trigger: auto-once/' "$profile" > "$profile.new"; mv "$profile.new" "$profile"; clean 'auto-once unchanged round records tree unchanged'
base; printf 'Override: declined gating finding\n' >> "$f"; held 'override needed' 'override needed: declined gating finding'
base; printf 'Ship-defect: upstream gap #42\n' >> "$f"; held 'source repo defect without draft' 'Ship defect: upstream gap #42'
base; touch "$tmp/records/ship-clean/defect-1.md"; held 'Ship defect draft' 'Ship defect draft: defect-1.md'
base; touch "$tmp/records/ship-clean/tracker-1.md"; held 'Tracker draft' 'Tracker draft: tracker-1.md'
base; touch "$tmp/records/ship-clean/defect-1.base.md"; printf 'Deviation: accepted scoped departure\nOverride: None.\nShip-defect: none\n' >> "$f"; clean 'deviation and draft base are independent'
base; printf '  Override: quoted\n`Ship-defect: quoted`\nOverrides: partial token\n' >> "$f"; clean 'quoted indented partial evidence does not match'
base; change_run 's/Stop: primary: tree unchanged/Stop: primary: cap/'; printf '\n```\nStop: primary: tree unchanged\n```\n' >> "$f"; held 'fenced stop cannot override cap' 'reviewer primary: cap'
base; printf '\n~~~\nOverride: example\nShip-defect: example\n~~~\n' >> "$f"; clean 'fenced examples are not evidence'
base; change_run 's/"tests":"pass"/"tests":"fail"/'; printf '\n```\n## Local gate\n- 11:00 abcdef0123456789 pass {"tests":"pass","secrets":"pass"}\n```\n' >> "$f"; held 'fenced gate cannot replace failing gate' 'local gate tests: fail'
base; change_run 's/punctuation: pass/punctuation: fail/'; printf '\n```\n## Verification results\n- live check: punctuation: pass\n```\n' >> "$f"; held 'fenced verification cannot replace failing result' 'verification live check: punctuation: fail'
base; printf '\n```\n' >> "$f"; answer=$(call); check_rc 'unclosed Run file fence is tooling' 2 "$?"; check 'unclosed fence names its record' "cannot read Run file evidence at $f" "$(jq -r .error <<<"$answer")"
if [ "$(id -u)" -ne 0 ]; then
  base; touch "$tmp/records/ship-clean/defect-1.md"; chmod 111 "$tmp/records/ship-clean"
  answer=$(call); rc=$?; chmod 755 "$tmp/records/ship-clean"
  check_rc 'unreadable draft directory is tooling' 2 "$rc"
  check 'unreadable draft directory names its path' "cannot read draft directory at $tmp/records/ship-clean" "$(jq -r .error <<<"$answer")"
else
  skipped 'unreadable draft directory: chmod does not stop root'
fi
base; printf 'Stop: primary: cap\n' >> "$f"; held 'last stop wins' 'reviewer primary: cap'
base; change_run 's/Stop: primary: tree unchanged/Stop: primary: not reviewed/'; printf 'Round: fallback 1: dispositioned\nStop: fallback: cap\n' >> "$f"; held 'fallback stopped at cap' 'reviewer primary: not reviewed'
base; change_ci '.status="no-checks" | .checks=[]'; held 'legal no-checks cannot replace expected green leg' 'CI test: missing'
base; sed 's/^Legs:$/Legs: None./; /  test: prove the change/d' "$profile" > "$profile.new"; mv "$profile.new" "$profile"; change_ci '.status="no-checks" | .checks=[]'; held 'no-checks not explicitly legal' 'CI: no-checks'
base; sed 's/^Legs:$/Legs: None./; /  test: prove the change/d' "$profile" > "$profile.new"; mv "$profile.new" "$profile"; printf '\n' >> "$profile"; sed '/^Legs:/a No-checks legal: yes' "$profile" > "$profile.new"; mv "$profile.new" "$profile"; change_ci '.status="no-checks" | .checks=[]'; clean 'legal no-checks with no expected legs'
base; rm "$ci"; answer=$(call); check_rc 'unreadable CI input is tooling' 2 "$?"; check 'unreadable CI names its path' "cannot read CI answer at $ci" "$(jq -r .error <<<"$answer")"
base; sed '/^## Verification/i ```' "$profile" > "$profile.new"; mv "$profile.new" "$profile"; answer=$(call); check_rc 'unclosed profile fence is tooling' 2 "$?"; check 'unclosed profile fence names failed read' "cannot read profile evidence at $profile" "$(jq -r .error <<<"$answer")"
base; sed 's/^Legs:$/Legs: None./; /  test: prove the change/d' "$profile" > "$profile.new"; mv "$profile.new" "$profile"; sed '/^Legs:/a No-checks legal: no' "$profile" > "$profile.new"; mv "$profile.new" "$profile"; printf '\n```\n## CI\nLegs: None.\nNo-checks legal: yes\n```\n' >> "$profile"; change_ci '.status="no-checks" | .checks=[]'; held 'fenced CI policy cannot authorize no-checks' 'CI: no-checks'
base; printf 'not-json\n' > "$ci"; answer=$(call); check_rc 'malformed CI is tooling' 2 "$?"; check 'malformed CI names failed read' 'CI answer is not a valid ci-wait object' "$(jq -r .error <<<"$answer")"
base; printf '{}\n' > "$ci"; answer=$(call); check_rc 'empty CI object is tooling' 2 "$?"; check 'empty CI names failed read' 'CI answer is not a valid ci-wait object' "$(jq -r .error <<<"$answer")"
base; change_run 's/{.*}/{broken}/'; answer=$(call); check_rc 'malformed recorded gates is tooling' 2 "$?"; check 'bad gate JSON names failed read' 'cannot read recorded local gate results' "$(jq -r .error <<<"$answer")"
base; answer=$(call --result x=pass); check_rc 'result flag is invalid for clean' 2 "$?"
base; answer=$(cd "$repo" && bash "$m" gate clean - --head "$head" --issue clean --scratchpad "$tmp/records" < "$ci" 2>/dev/null); check 'stdin and issue lookup answer clean' true "$(jq -r .clean <<<"$answer")"
base; cp "$f" "$repo/run.md"; touch "$repo/defect-relative.md"
answer=$(call --file run.md); check_rc 'relative Run file draft refuses' 1 "$?"; check 'relative Run file draft names hold' true "$(jq -r '.held_by | index("Ship defect draft: defect-relative.md") != null' <<<"$answer")"
base; before=$(cat "$f"); call >/dev/null; check 'clean is read-only' "$before" "$(cat "$f")"
finish
