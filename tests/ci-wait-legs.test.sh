#!/usr/bin/env bash
# ci-wait over the Host fake: the profile's Legs: decide the grade (a red check
# no leg names is listed, not failed on, #487), a window longer than one call's
# cap is a chain of calls joined by a cursor, a read with no answer is polled
# again before it is a tooling error, and --rerun-failed re-runs a failing leg
# check once per head. Inside a throwaway checkout whose origin names GitHub,
# carrying a fixture profile; no call reaches a host.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

mech=$PWD/skills/ship/scripts/ci-wait.sh
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
export SHIP_FAKE=$work/fake SHIP_HOST_ADAPTER=$PWD/tests/host-fake.sh
mkdir -p "$SHIP_FAKE"

repo() { # <dir> <Legs: block, lines after "Legs:" on the CI section> <no-checks legal>
  mkdir -p "$1/docs/agents"
  printf '# Ship profile\n\nSchema: 3\n\n## CI\n\n%s\nNo-checks legal: %s\nPush policy: Default.\n\n## Reviewers\n' "$2" "$3" \
    > "$1/docs/agents/ship.md"
  git -C "$1" init -q
  git -C "$1" remote add origin https://github.com/owner/repo.git
}
two=$work/two; repo "$two" $'Legs:\ntest: npm test\nlint: ruff' no
one=$work/one; repo "$one" 'Legs: test: npm test' no
lax=$work/lax; repo "$lax" $'Legs:\ntest: npm test\nlint: ruff' yes
unk=$work/unk; mkdir -p "$unk/docs/agents"; printf '# Ship profile\n\n## CI\n\nPush policy: Default.\n' > "$unk/docs/agents/ship.md"
git -C "$unk" init -q; git -C "$unk" remote add origin https://github.com/owner/repo.git
nol=$work/nol; repo "$nol" 'Legs: None.' yes
bare=$work/bare; repo "$bare" $'Legs:\ntest\nlint' no

# <n> <json> : the n-th host_pr_checks answer
ans() { printf '%s\n' "$2" > "$SHIP_FAKE/host_pr_checks.$1.json"; }
row() { jq -cn --arg n "$1" --arg s "$2" '{name: $n, status: $s}'; }
rows() { printf '%s\n' "$@" | jq -sc .; }
reset() { rm -f "$SHIP_FAKE"/*; }
ci() { local d=$1; shift; ( cd "$d" && SHIP_CI_WAIT_GRACE=${GRACE:-1} bash "$mech" 7 --interval 1 "$@" 2>/dev/null ); }
count() { grep -c "^$1" "$SHIP_FAKE/calls" 2>/dev/null || true; }

# --- legs grade, the rest is listed -------------------------------------------

reset; ans 1 "$(rows "$(row test success)" "$(row lint success)" "$(row codeql failure)")"
out=$(ci "$two" --timeout 5); rc=$?
check_rc "a red check outside Legs: leaves the PR green" 0 "$rc"
check "green" green "$(jq -r .status <<<"$out")"
check "the red check outside Legs: is named, not failing" '[] ["codeql"] ["codeql"]' \
  "$(jq -c '[.failing, .non_leg_failing, .unlisted] | map(tojson) | join(" ")' -r <<<"$out")"
check "legs ride the answer" '["test","lint"]' "$(jq -c .legs <<<"$out")"

reset; ans 1 "$(rows "$(row test success)" "$(row lint success)" "$(row extra success)")"
out=$(ci "$two" --timeout 5)
check "a check Legs: does not name is unlisted, not failing" '["extra"] []' \
  "$(jq -r '[(.unlisted | tojson), (.non_leg_failing | tojson)] | join(" ")' <<<"$out")"

reset; ans 1 "$(rows "$(row 'test (ubuntu-22.04)' success)" "$(row 'test (macos)' success)" "$(row testing success)")"
out=$(ci "$one" --timeout 5)
check "a matrix job counts for its leg, a longer name does not" 'green [] ["testing"]' \
  "$(jq -r '[.status, (.missing_legs | tojson), (.unlisted | tojson)] | join(" ")' <<<"$out")"

reset; ans 1 "$(rows "$(row 'test (ubuntu-22.04)' failure)" "$(row 'test (macos)' success)")"
out=$(ci "$one" --timeout 5); rc=$?
check_rc "a red matrix job fails its leg" 1 "$rc"
check "and is the failing leg check" 'checks-failed ["test (ubuntu-22.04)"]' \
  "$(jq -r '[.status, (.failing | tojson)] | join(" ")' <<<"$out")"

reset; ans 1 "$(rows "$(row codeql failure)")"
out=$(ci "$unk" --timeout 5); rc=$?
check "a profile with no Legs: line counts every check as a leg" 'checks-failed ["codeql"] null' \
  "$(jq -r '[.status, (.failing | tojson), (.legs | tojson)] | join(" ")' <<<"$out")"

reset; ans 1 "$(rows "$(row test failure)")"
out=$(ci "$bare" --timeout 5); rc=$?
check_rc "colon-less Legs: entries are unknown legs, so a red check fails the PR" 1 "$rc"
check "checks-failed, legs null" 'checks-failed ["test"] null' \
  "$(jq -r '[.status, (.failing | tojson), (.legs | tojson)] | join(" ")' <<<"$out")"

reset; ans 1 "$(rows "$(row codeql failure)")"
out=$(ci "$nol" --timeout 5); rc=$?
check_rc "Legs: None. with a red unlisted check is no-checks" 0 "$rc"
check "no-checks, the red check unlisted" 'no-checks ["codeql"]' \
  "$(jq -r '[.status, (.non_leg_failing | tojson)] | join(" ")' <<<"$out")"

# --- a leg no check names ------------------------------------------------------

reset; ans 1 "$(rows "$(row test success)")"
out=$(GRACE=1 ci "$two" --timeout 2); rc=$?
check_rc "a missing leg where no-checks is not legal holds the wait to the window" 1 "$rc"
check "the timeout names the missing leg" 'timeout ["lint"]' \
  "$(jq -r '[.status, (.missing_legs | tojson)] | join(" ")' <<<"$out")"

out=$(GRACE=1 ci "$lax" --timeout 6); rc=$?
check_rc "a missing leg stops holding once the grace passes where no-checks is legal" 0 "$rc"
check "green, the leg still named missing" 'green ["lint"]' \
  "$(jq -r '[.status, (.missing_legs | tojson)] | join(" ")' <<<"$out")"
check "and not before the grace" true "$(jq '.waited_s >= 1' <<<"$out")"

reset; ans 1 '[]'
out=$(GRACE=1 ci "$lax" --timeout 6)
check "every leg missing past the grace is no-checks" no-checks "$(jq -r .status <<<"$out")"

# --- the call cap and the cursor -----------------------------------------------

reset
for i in 1 2 3 4 5; do ans "$i" "$(rows "$(row test pending)" "$(row lint success)")"; done
ans 6 "$(rows "$(row test success)" "$(row lint success)")"
out=$(SHIP_CALL_CAP=3 ci "$two" --timeout 60); rc=$?
check_rc "a call that would pass the cap answers pending, exit 1" 1 "$rc"
check "pending, with a cursor" 'pending true' "$(jq -r '[.status, (.cursor | length > 0)] | join(" ")' <<<"$out")"
# waited_s counts the poll's own work too, which a loaded machine stretches past
# the cap (#507): the bound holds the call far short of the 60 s window.
check "within the cap" true "$(jq '.waited_s <= 10' <<<"$out")"
cur=$(jq -r .cursor <<<"$out")
out2=$(SHIP_CALL_CAP=3 ci "$two" --cursor "$cur"); rc=$?
check_rc "the resumed call answers green" 0 "$rc"
check "green" green "$(jq -r .status <<<"$out2")"
check "waited_s continues across the cursor" true "$(jq --argjson a "$(jq .waited_s <<<"$out")" '.waited_s >= $a' <<<"$out2")"

reset
out=$(ci "$two" --cursor "$cur" --timeout 60); rc=$?
check_rc "--cursor with --timeout is tooling" 2 "$rc"
check "and reaches no host" '' "$(cat "$SHIP_FAKE/calls" 2>/dev/null)"
out=$(ci "$two" --cursor garbage); rc=$?
check_rc "an unreadable cursor is tooling" 2 "$rc"
check "and says so in poll-pr's words" '--cursor does not read' "$(jq -r '.error | split(":")[0]' <<<"$out")"
check "and reaches no host either" '' "$(cat "$SHIP_FAKE/calls" 2>/dev/null)"

# A push between two calls: the resumed call waits for the new head, and the
# no-checks grace counts from that head's arrival, not from the old head's.
reset
ans 1 "$(rows "$(row test pending)" "$(row lint pending)")"
printf '%s\n' '{"number":7,"head_sha":"aaaaaaa","head_ref":"fix/fake-1","mergeable":"clean"}' > "$SHIP_FAKE/host_pr_get.1.json"
out=$(GRACE=2 SHIP_CALL_CAP=3 ci "$lax" --sha aaaaaaa --timeout 60)
check "the first call is pending on the old head" 'pending aaaaaaa' "$(jq -r '[.status, .head_sha] | join(" ")' <<<"$out")"
# The old head's clock is aged far past a grace no loaded machine reaches in one
# capped call (#507), so only a restart on the new head answers pending.
cur=$(jq -r .cursor <<<"$out" | base64 -d | jq -c '.head_at -= 100' | base64 -w0)
reset; ans 1 '[]'
printf '%s\n' '{"number":7,"head_sha":"bbbbbbb","head_ref":"fix/fake-1","mergeable":"clean"}' > "$SHIP_FAKE/host_pr_get.1.json"
out2=$(GRACE=30 SHIP_CALL_CAP=1 ci "$lax" --sha bbbbbbb --cursor "$cur"); rc=$?
check_rc "a resumed call on a new head with no checks yet is not answered" 1 "$rc"
check "no-checks waits for the grace on the new head" 'pending bbbbbbb' "$(jq -r '[.status, .head_sha] | join(" ")' <<<"$out2")"

# The local HEAD moving mid-wait (a push of a review fix while a background wait
# runs) moves the expected head with it, in one call and across a cursor: only
# a --sha pins it. The host fake's adapter is wrapped so its second PR read
# moves the checkout to commit B, as a push would, and answers B.
mv=$work/mv; repo "$mv" 'Legs: test: npm test' no
git -C "$mv" checkout -q -b fix/fake-1
for m in a b; do git -C "$mv" -c user.name=t -c user.email=t@t commit -q --allow-empty -m "$m"; done
sha_a=$(git -C "$mv" rev-parse HEAD~1); sha_b=$(git -C "$mv" rev-parse HEAD)
cat > "$work/moving-host.sh" <<ADAPTER
source "$PWD/tests/host-fake.sh"
eval "\$(declare -f host_pr_get | sed '1s/host_pr_get/fake_pr_get/')"
host_pr_get() {
  if [ "\$(cat "\$SHIP_FAKE/host_pr_get.n" 2>/dev/null || echo 0)" -eq "\${MOVE_AFTER:-1}" ]; then
    git -C "$mv" reset -q --hard $sha_b
  fi
  fake_pr_get "\$@"
}
ADAPTER
pr_at() { printf '{"number":7,"head_sha":"%s","head_ref":"fix/fake-1","mergeable":"clean"}\n' "$2" > "$SHIP_FAKE/host_pr_get.$1.json"; }

reset; git -C "$mv" reset -q --hard "$sha_a"
pr_at 1 "$sha_a"; pr_at 2 "$sha_b"
ans 1 "$(rows "$(row test pending)")"; ans 2 "$(rows "$(row test success)")"
out=$(SHIP_HOST_ADAPTER=$work/moving-host.sh ci "$mv" --timeout 20); rc=$?
check_rc "a HEAD that moves during the call is graded, not timed out on the old one" 0 "$rc"
check "green on the new head" "green $sha_b" "$(jq -r '[.status, .head_sha] | join(" ")' <<<"$out")"

reset; git -C "$mv" reset -q --hard "$sha_a"
pr_at 1 "$sha_a"; ans 1 "$(rows "$(row test pending)")"
out=$(SHIP_CALL_CAP=1 ci "$mv" --timeout 60)
check "the first call is pending on the old head" "pending $sha_a" "$(jq -r '[.status, .head_sha] | join(" ")' <<<"$out")"
cur=$(jq -r .cursor <<<"$out")
git -C "$mv" reset -q --hard "$sha_b"; reset; pr_at 1 "$sha_b"; ans 1 "$(rows "$(row test success)")"
out2=$(ci "$mv" --cursor "$cur"); rc=$?
check_rc "a resumed call follows a HEAD that moved since the cursor was made" 0 "$rc"
check "green on the new head, resumed" "green $sha_b" "$(jq -r '[.status, .head_sha] | join(" ")' <<<"$out2")"

# --- reads with no answer ------------------------------------------------------

green=$(rows "$(row test success)" "$(row lint success)")
reset; : > "$SHIP_FAKE/host_pr_checks.1.fail"; ans 2 "$green"
out=$(ci "$two" --timeout 30); rc=$?
check_rc "one read with no answer is polled again" 0 "$rc"
check "and the window answers green" green "$(jq -r .status <<<"$out")"

reset; : > "$SHIP_FAKE/host_pr_checks.1.fail"
out=$(ci "$two" --timeout 30); rc=$?
check_rc "three reads in a row with no answer are tooling" 2 "$rc"
check "after three reads" 3 "$(count host_pr_checks)"

reset; : > "$SHIP_FAKE/host_pr_checks.1.fail"; : > "$SHIP_FAKE/host_pr_checks.2.fail"
ans 3 "$(rows "$(row test pending)" "$(row lint success)")"
: > "$SHIP_FAKE/host_pr_checks.4.fail"; : > "$SHIP_FAKE/host_pr_checks.5.fail"; ans 6 "$green"
out=$(ci "$two" --timeout 30); rc=$?
check_rc "an answered read resets the count of reads with no answer" 0 "$rc"

reset; : > "$SHIP_FAKE/host_pr_checks.1.fail"; echo 404 > "$SHIP_FAKE/host_pr_checks.1.status"
out=$(ci "$two" --timeout 30); rc=$?
check_rc "a read the host refused with a status is tooling at once" 2 "$rc"
check "after one read" 1 "$(count host_pr_checks)"

reset; : > "$SHIP_FAKE/host_pr_get.1.fail"; echo 401 > "$SHIP_FAKE/host_pr_get.1.status"
out=$(ci "$two" --timeout 30); rc=$?
check_rc "the PR read is held to the same rule" 2 "$rc"
check "refused after one read" 1 "$(count host_pr_get)"

# --- --rerun-failed ------------------------------------------------------------

reset; ans 1 "$(rows "$(row test failure)" "$(row lint success)")"
echo '{"job_id":9,"attempt":1,"log_tail":"boom"}' > "$SHIP_FAKE/host_check_job.1.json"
out=$(ci "$two" --timeout 5 --rerun-failed); rc=$?
check_rc "a failing leg stays exit 1 after its re-run" 1 "$rc"
check "the first attempt is re-run once" '[{"name":"test","rerun":true,"attempt":1,"log_tail":"boom"}]' "$(jq -c .rerun <<<"$out")"
check "with exactly one host write" "host_check_rerun	9" "$(grep '^host_check_rerun' "$SHIP_FAKE/calls")"
check "the job was read for the failing leg on the head" "host_check_job	7	deadbee	test" "$(grep '^host_check_job' "$SHIP_FAKE/calls")"

echo '{"job_id":9,"attempt":2,"log_tail":"boom again"}' > "$SHIP_FAKE/host_check_job.1.json"
: > "$SHIP_FAKE/calls"
out=$(ci "$two" --timeout 5 --rerun-failed)
check "a second call on the same head does not re-run" '[{"name":"test","rerun":false,"attempt":2,"log_tail":"boom again"}]' "$(jq -c .rerun <<<"$out")"
check "and writes nothing" 0 "$(count host_check_rerun)"

: > "$SHIP_FAKE/calls"
out=$(ci "$two" --timeout 5)
check "without the flag the checks are not read as jobs" '0 null' "$(count host_check_job) $(jq -c .rerun <<<"$out")"

reset; ans 1 "$(rows "$(row test failure)")"; : > "$SHIP_FAKE/host_check_job.1.fail"
out=$(ci "$two" --timeout 5 --rerun-failed); rc=$?
check "a host that cannot read the job answers unavailable" '"unavailable" 1' "$(jq -c .rerun <<<"$out") $rc"
check "and writes nothing then" 0 "$(count host_check_rerun)"

finish
