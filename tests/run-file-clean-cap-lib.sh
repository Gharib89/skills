#!/usr/bin/env bash
# The clean-gate fixture the cap and local-review tests share: a Run file and
# profile with a primary and its fallback, the gate call and its verdict checks.
# Sourced after tests/lib.sh and tests/run-file-lib.sh, never run.
# shellcheck disable=SC2154,SC2120 # the globals run_file_clean_setup sets; call's arguments come from its callers
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
# A primary that spent its Cap: on a tree-changing last round owes its fallback a run (#531).
capped() { base; sed 's/^Fallback-for: None.$/Cap: 2\n&/' "$profile" > "$profile.new"; mv "$profile.new" "$profile"; change_run 's/Stop: primary: tree unchanged at abcdef0123456789/Round: primary 2: fixes pushed\nStop: primary: cap/'; }
