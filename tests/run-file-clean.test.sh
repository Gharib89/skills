#!/usr/bin/env bash
# The clean gate consumes only recorded evidence and the supplied CI answer.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
source tests/run-file-lib.sh
run_file_clean_setup
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
- live check: punctuation: pass at abcdef0123456789
## Local gate
- 10:00 abcdef0123456789 pass {"tests":"pass","secrets":"pass"}
## Review evidence
Round: primary 1: all dispositioned
Stop: primary: tree unchanged at abcdef0123456789
Stop: fallback: not reviewed
RUN
  printf '%s\n' '{"status":"green","head_sha":"abcdef0123456789","checks":[{"name":"test","status":"success"}],"legs":["test"],"missing_legs":[],"failing":[],"non_leg_failing":[],"unlisted":[],"waited_s":0}' > "$ci"
  rm -f "$tmp/records/ship-clean/defect-1.md" "$tmp/records/ship-clean/tracker-1.md" "$tmp/records/ship-clean/defect-1.base.md"
}
# shellcheck disable=SC2120 # the cases of tests/run-file-clean-cap.test.sh pass arguments
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
# Evidence that names no head covers none: an unstamped stop or pass is stale.
base; change_run 's/Stop: primary: tree unchanged at abcdef0123456789/Stop: primary: tree unchanged/'; held 'an unstamped tree-unchanged stop' 'reviewer primary: tree unchanged with no head stamp to cover head abcdef0123456789'
base; change_run 's/punctuation: pass at abcdef0123456789/punctuation: pass/'; held 'an unstamped verification pass' 'verification live check: punctuation: pass with no head stamp to cover head abcdef0123456789'
base; change_run 's/punctuation: pass at abcdef0123456789/punctuation: pass at abcdef0123456789: ran the fixture/'; clean 'a stamp with a note'
# A self-review stopped at its cap left fixes unread: a settled reviewer read them.
capped='self-review: stopped at cap, its last fixes read by no reviewer'
base; printf '%s\n' 'Stop: self-review: cap' >> "$f"; clean 'a capped self-review a settled reviewer read'
base; printf '%s\n' 'Stop: self-review: cap' >> "$f"; change_run 's/^Stop: primary: tree unchanged at abcdef0123456789/Stop: primary: not reviewed/'; held 'a capped self-review no reviewer read' "$capped"
base; printf '%s\n' 'Stop: self-review: cap' >> "$f"; printf '## CI\nLegs:\n  test: prove the change\n\n## Reviewers\nNone.\n' > "$profile"; held 'a capped self-review in a repo with no reviewer' "$capped"
base; printf '%s\n' 'Stop: self-review: cap' 'Stop: self-review: tree unchanged' >> "$f"; change_run 's/^Stop: primary: tree unchanged at abcdef0123456789/Stop: primary: not reviewed/'; unheld 'a later tree-unchanged stop' "$capped"
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
  base; change_run "s/punctuation: pass at abcdef0123456789/punctuation: $status/"; held "$status verification" "verification live check: punctuation: $status"
done
base; change_run '/^- live check/d'; held 'missing verification' 'verification live check: punctuation: missing; record it with `run-file close 3 --result "live check: punctuation=<word>"`'
base; change_run 's/punctuation: pass at abcdef0123456789/punctuation: n\/a/'; clean 'inapplicable verification'
base; change_run 's/punctuation: pass at abcdef0123456789/punctuation: deferred-to-ci: test/'; clean 'deferred verification with green associated leg'
base; change_run 's/punctuation: pass at abcdef0123456789/punctuation: deferred-to-ci: test/'; sed 's/Also proven by CI: test/Also proven by CI: None./' "$profile" > "$profile.new"; mv "$profile.new" "$profile"; held 'deferred verification without association' 'verification live check: punctuation: no associated green CI leg'
for stop in cap 'small lane' 'not reviewed'; do
  base; change_run "s/Stop: primary: tree unchanged at abcdef0123456789/Stop: primary: $stop/"; held "$stop primary without fallback" "reviewer primary: $stop"
done
# An inline run with no --review requested no round: --inline waived it, so the stop settles the reviewer.
inline() { base; change_run '/^Round: primary/d; s/Stop: primary: tree unchanged at abcdef0123456789/Stop: primary: inline lane/; s/Stop: fallback: not reviewed/Stop: fallback: inline lane/; $a Lane: inline'; }
inline; clean 'inline-lane stops on the primary and its fallback'
# The last Lane: line decides: a run with none, or one revoked out of the lane, keeps no waiver.
inline; change_run '/^Lane: inline/d'; held 'inline-lane stops with no Lane: line' 'reviewer primary: inline lane'
inline; change_run '$a Lane: small'; held 'inline-lane stops after a revocation to the small lane' 'reviewer primary: inline lane'
inline; change_ci '.status="checks-failed" | .checks[0].status="failure"'; held 'inline lane with red CI' 'CI test: failure'
inline; touch "$tmp/records/ship-clean/tracker-1.md"; held 'inline lane with a Tracker draft' 'Tracker draft: tracker-1.md'
for trigger in auto-once on-push; do
  inline; sed "0,/Trigger: on-request/s//Trigger: $trigger/" "$profile" > "$profile.new"; mv "$profile.new" "$profile"; held "an inline-lane stop on an $trigger reviewer" 'reviewer primary: inline lane'
done
base; change_run 's/Stop: primary: tree unchanged at abcdef0123456789/Stop: primary: not reviewed/; s/Stop: fallback: not reviewed/Stop: fallback: inline lane/'; held 'an inline-lane fallback does not cover a primary that was not reviewed' 'reviewer primary: not reviewed'
base; printf 'Round: primary 2:   \n' >> "$f"; held 'blank latest round' 'reviewer primary: no dispositioned round'
base; change_run '/^Round: primary/d'; held 'stop without dispositioned round' 'reviewer primary: no dispositioned round'
base; change_run '/^Stop: primary/d'; held 'missing reviewer stop' 'reviewer primary: missing stop'
base; change_run 's/Stop: primary: tree unchanged at abcdef0123456789/Stop: primary: not reviewed/'; printf 'Round: fallback 1: dispositioned\nStop: fallback: tree unchanged at abcdef0123456789\n' >> "$f"; clean 'not reviewed primary covered by a fallback stopped on tree unchanged'
# `not reviewed: <reason>` reads as `not reviewed` (#787).
base; change_run 's/Stop: primary: tree unchanged at abcdef0123456789/Stop: primary: not reviewed: unreachable/'; printf 'Round: fallback 1: dispositioned\nStop: fallback: tree unchanged at abcdef0123456789\n' >> "$f"; clean 'a not-reviewed primary with a reason covered by a fallback'
base; change_run 's/Stop: primary: tree unchanged at abcdef0123456789/Stop: primary: not reviewed: unreachable/'; held 'a not-reviewed primary with a reason and no fallback' 'reviewer primary: not reviewed'
base; change_run 's/Stop: fallback: not reviewed/Stop: fallback: not reviewed: the primary reviewed/'; clean 'a not-reviewed fallback with a reason behind a settled primary'
base; change_run 's/Stop: primary: tree unchanged at abcdef0123456789/Stop: primary: cap/'; printf 'Round: fallback 1: dispositioned\nStop: fallback: tree unchanged at abcdef0123456789\n' >> "$f"; held 'cap is not rescued by fallback' 'reviewer primary: cap'

finish
