#!/usr/bin/env bash
# Every super-agent script that compares a repo name, a ledger key or an area
# path normalises both sides through _lib.sh: a mixed-case repo name and a path
# with a trailing slash or a leading `./` answer as the exact spelling does.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
source tests/super-agent-fake.sh

s=skills/super-agent/scripts
tmp=$(mktemp -d) || exit 2
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/tools" "$tmp/fake"
for t in bash env jq awk sed grep cat mktemp mv rm mkdir dirname basename tr head tail date timeout sort cut find wc diff chmod; do
  ln -s "$(command -v "$t")" "$tmp/tools/$t" || exit 2
done
export PATH="$tmp/bin:$tmp/tools" SA_FAKE=$tmp/fake
sa_fake_install "$tmp/bin"
fleet=$tmp/fleet.json led=$tmp/ledger.json
printf '%s\n' '{"machines":{"home":{"slots":5},"box":{"slots":5}},"active_repos":["Acme/Widgets"]}' > "$fleet"
L() { bash "$s/ledger.sh" --ledger "$led" "$@"; }
LC() { bash "$s/launch-check.sh" --fleet "$fleet" --ledger "$led" --own home --machine box --load 1 --free-gb 8 "$@"; }
L add --repo acme/widgets --number 5 --thread t5 --worktree /wt/5 --branch b5 --area skills/ship >/dev/null

# --- launch-check: repo name and area path ---------------------------------------
for spelling in "acme/widgets skills/ship" "ACME/Widgets skills/ship" "acme/widgets ./skills/ship/" "Acme/WIDGETS skills/ship//"; do
  read -r repo area <<<"$spelling"
  check "launch-check: $spelling conflicts with the open ticket" '["acme/widgets#5"]' "$(LC --repo "$repo" --area "$area" | jq -c .repo.conflicts)"
done
check "launch-check: a mixed-case repo with an apart area is free" '[]' "$(LC --repo ACME/Widgets --area docs/ | jq -c .repo.conflicts)"
check "launch-check: --key in another case leaves the ticket's own entry out" '[]' "$(LC --repo acme/widgets --key ACME/Widgets#5 --area skills/ship | jq -c .repo.conflicts)"

# --- ledger: a key in another case names the same entry ----------------------------
check "ledger get: a mixed-case key finds the entry" acme/widgets#5 "$(L get ACME/Widgets#5 | jq -r .key)"
out=$(L add --repo Acme/Widgets --number 5 --thread t --worktree /w --branch b 2>/dev/null); rc=$?
check_rc "ledger add: a mixed-case key is already in the ledger" 1 "$rc"
check "and the refusal says so" "Acme/Widgets#5 is already in the ledger" "$(jq -r .error <<<"$out")"
L set ACME/WIDGETS#5 branch '"b2"' >/dev/null
check "ledger set: a mixed-case key writes the entry" b2 "$(L get acme/widgets#5 | jq -r .branch)"
L wait acme/widgets#6 --reason r >/dev/null; L wait ACME/Widgets#6 --reason r2 >/dev/null
check "ledger wait: a repeat in another case is one row" 1 "$(L list | jq '.waiting | length')"
check "ledger unwait: a mixed-case key removes it" true "$(L unwait ACME/WIDGETS#6 | jq .removed)"

# --- worktree: the ledger form resolves a key in another case ------------------------
out=$(bash "$s/worktree.sh" remove --ledger "$led" ACME/Widgets#5 2>/dev/null)
check "worktree: a mixed-case ledger key finds the entry" acme/widgets#5 "$(jq -r .key <<<"$out")"

# --- track: a mixed-case repo is the tracked one --------------------------------------
check "track: tracking it in another case changes nothing" false "$(bash "$s/track.sh" --fleet "$fleet" track ACME/widgets | jq .changed)"
check "track: stopping it in another case removes it" '[]' "$(bash "$s/track.sh" --fleet "$fleet" stop acme/WIDGETS | jq -c .active_repos)"

# --- intake: the ledger holds the ticket under another case -----------------------------
printf '%s\n' '{"machines":{"alpha":{}},"active_repos":["Acme/Widgets"]}' > "$fleet"
sa_route user '{"login":"octo"}'
sa_route "repos/Acme/Widgets/issues?state=open&labels=ready-for-agent&per_page=100" '[{"number":5,"title":"Five","labels":[{"name":"ready-for-agent"}]}]'
out=$(bash "$s/intake.sh" --fleet "$fleet" --ledger "$led" --machine alpha --thread th-a 2>/dev/null)
check "intake: a ticket the ledger holds under another case is held" '["Acme/Widgets#5"]' "$(jq -c .held <<<"$out")"

# --- ledger need, limit and wait --after: the same row in another case ------------------
L need acme/widgets#7 --action a >/dev/null; L need ACME/Widgets#7 --action b >/dev/null
check "ledger need: a repeat in another case is one row" 1 "$(jq '.needs | length' "$led")"
check "ledger pushed: a mixed-case key marks it" true "$(L pushed ACME/WIDGETS#7 | jq -r .need.pushed)"
check "ledger unneed: a mixed-case key removes it" 0 "$(L unneed Acme/widgets#7 >/dev/null; jq '.needs | length' "$led")"
L limit acme/widgets --reviewer claude >/dev/null; L limit ACME/Widgets --reviewer codex >/dev/null
check "ledger limit: a repeat in another case is one row" 1 "$(jq '.review_limits | length' "$led")"
check "ledger unlimit: a mixed-case repo removes it" 0 "$(L unlimit Acme/WIDGETS >/dev/null; jq '.review_limits | length' "$led")"
out=$(L wait acme/widgets#8 --reason r --after ACME/Widgets#8 2>/dev/null); rc=$?
check_rc "ledger wait: a row cannot wait on itself in another case" 2 "$rc"

# --- status: a merged ticket acknowledged under another case is not reported again -----
printf '%s\n' '{"rulings":[],"entries":{"acme/widgets#5":{"key":"acme/widgets#5","repo":"acme/widgets","number":5,"stage":"merged","observed":{"pr":{"number":9,"state":"merged"}}}},"status":{"merged_ack":["ACME/Widgets#5"]}}' > "$tmp/status.json"
check "status: a merged key acked in another case is not listed" '' "$(bash "$s/status.sh" --ledger "$tmp/status.json" | jq -r '.block | select(contains("Merged"))')"

# --- reconcile: the cap, a blocker, a need, an offered parent or task, each in another case
rled=$tmp/reconcile.json
RC() { bash "$s/reconcile.sh" --ledger "$rled" "$@"; }
RL() { bash "$s/ledger.sh" --ledger "$rled" "$@"; }
rfix() {
  rm -f "$rled" "$SA_FAKE/calls"
  RL add --repo acme/widgets --number 5 --thread t-5 --worktree /wt/5 --branch b5 >/dev/null
  sa_thread t-5 running 1 0 /wt/5 b5; sa_pr acme/widgets b5 none; sa_issue acme/widgets 5 open
  sa_issue acme/widgets 9 open; sa_issue ACME/Widgets 9 open
}
rfix; RL wait ACME/Widgets#9 --reason r >/dev/null
printf '%s\n' '{"repos":{"Acme/WIDGETS":{"max_ships":1}}}' > "$tmp/cap.json"
check "reconcile: a fleet repo key in another case caps the repo's open tickets" '[]' "$(RC --fleet "$tmp/cap.json" | jq -c '[.ready[].key]')"
printf '%s\n' '{"repos":{"Acme/WIDGETS":{"max_ships":2}}}' > "$tmp/cap.json"
check "and a roomier cap in that case frees the row" '["ACME/Widgets#9"]' "$(RC --fleet "$tmp/cap.json" | jq -c '[.ready[].key]')"
rfix; RL add --repo acme/widgets --number 6 --thread t-6 --worktree /wt/6 --branch b6 >/dev/null
sa_thread t-6 running 1 0 /wt/6 b6; sa_pr acme/widgets b6 merged; sa_issue acme/widgets 6 open
RL wait acme/widgets#9 --reason r --after ACME/WIDGETS#6 >/dev/null
check "reconcile: a blocker named in another case is the merged ticket" '["acme/widgets#9"]' "$(RC | jq -c '[.ready[].key]')"
rfix; sa_thread t-5 idle 4 1 /wt/5 b5 "Stopped after the tests."
check "reconcile: a permission hold is escalated" "acme/widgets#5" "$(RC | jq -r '[.escalate[].key] | join(",")')"
RL need ACME/Widgets#5 --action x --reason permission-hold >/dev/null
check "and a need on it in another case silences it" '[]' "$(RC | jq -c '[.escalate[].key]')"
# a waiting row that duplicates a settled entry in another case is no error row for pulse
printf '%s\n' '{"rulings":[],"entries":{"acme/widgets#5":{"key":"acme/widgets#5","repo":"acme/widgets","number":5,"stage":"settled","observed":{}}},"waiting":[{"key":"ACME/Widgets#5","reason":"r","since":"2026-11-01T00:00:00Z"}]}' > "$rled"
sa_issue acme/widgets 5 open; sa_gh_fail "/issues/5" 2
check "pulse: an error on a key the ledger holds in another case is not a change" false "$(bash "$s/pulse.sh" --ledger "$rled" | jq .changed)"
rm -f "$SA_FAKE/gh-fail"

# --- the guard: no script compares a repo or path by hand ----------------------------------
# A hand-rolled lowercase or a raw `[ "$repo" = ... ]` is the class #1154 and #1180 closed. The
# two lowercase uses left name no repo: a quota bucket id and a branch slug.
hand=$(grep -rnE 'ascii_downcase|tr .?A-Z.? .?a-z|\[\[? "?\$\{?(repo|key|after|pkey|path|area|areas)\}?"? +(=|==|!=) ' "$s" \
  | grep -v "$s/_lib.sh:" | grep -v "$s/quota.sh:.*week-" | grep -v "$s/launch.sh:.*slug=" | grep -vF "[ \"\$areas\" = '[]' ]" || true)
check "no script lowercases or compares a repo, key or path by hand (use norm_repo, norm_path, sa_key)" '' "$hand"

finish
