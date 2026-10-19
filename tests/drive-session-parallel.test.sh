#!/usr/bin/env bash
# Split by behaviour from tests/drive-session.test.sh: parallel calls and frontier cases.
# drive-session's scripts, driven end to end through their command lines over a
# fake `herdr` on PATH (tests/herdr-fake.sh) that answers from per-agent state
# files and records every call. The real binary is never reached: the suite's
# host stub puts a failing `herdr` behind the fake.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
source tests/herdr-fake.sh

s=skills/drive-session/scripts
tmp=$(mktemp -d) || exit 2
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/fake" "$tmp/cwd"
herdr_fake_install "$tmp/bin"
export PATH="$tmp/bin:$PATH" HERDR_FAKE=$tmp/fake HERDR_ENV=1 HERDR_WORKSPACE_ID=w1
roster=$tmp/scratch/roster.json
calls() { cat "$HERDR_FAKE/calls" 2>/dev/null; : > "$HERDR_FAKE/calls"; }
seen() { jq -r --arg n "$1" '.sessions[] | select(.name == $n) | .seen_seq' "$roster"; }

# --- parallel calls ------------------------------------------------------------
# A supervisor reading two sessions in one message runs both reads at once:
# each read-modify-write of the roster keeps its update, and the roster parses.
par=$tmp/par.json
for n in p1 p2; do
  printf 'idle 1\n' > "$HERDR_FAKE/$n.states"
  bash "$s/spawn.sh" "$n" --roster "$par" --cwd "$tmp/cwd" --prompt x >/dev/null
done
lost=0
for i in $(seq 2 31); do
  printf 'done %s\n' "$i" > "$HERDR_FAKE/p1.states"
  printf 'done %s\n' "$((i + 100))" > "$HERDR_FAKE/p2.states"
  bash "$s/read.sh" p1 --roster "$par" >/dev/null 2>&1 &
  bash "$s/read.sh" p2 --roster "$par" >/dev/null 2>&1 &
  wait
  [ "$(jq -c '[.sessions[].seen_seq]' "$par" 2>/dev/null)" = "[$i,$((i + 100))]" ] || lost=$((lost + 1))
done
check "two reads in parallel each keep their seen_seq, in every one of 30 rounds" 0 "$lost"
check "and leave no lock behind" "" "$(ls "$par.lock" 2>/dev/null)"
rm -f "$tmp/par2.json"
for n in p3 p4; do printf 'idle 1\n' > "$HERDR_FAKE/$n.states"; done
bash "$s/spawn.sh" p3 --roster "$tmp/par2.json" --cwd "$tmp/cwd" --prompt x >/dev/null 2>&1 &
bash "$s/spawn.sh" p4 --roster "$tmp/par2.json" --cwd "$tmp/cwd" --prompt x >/dev/null 2>&1 &
wait
check "two spawns in parallel each add their row" '["p3","p4"]' "$(jq -c '[.sessions[].name] | sort' "$tmp/par2.json")"
# A lock a killed script left behind is a not-ok answer naming it, not a hang.
: > "$par.lock"
out=$(bash "$s/read.sh" p1 --roster "$par" 2>/dev/null); rc=$?
check_rc "a roster locked past 10 s fails the write" 1 "$rc"
check "the failure names the lock to remove" \
  "the roster $par stays locked: remove $par.lock once no drive-session script runs" "$(jq -r .error <<<"$out")"
rm -f "$par.lock"
calls >/dev/null

# --- frontier --------------------------------------------------------------------
# frontier reads GitHub alone, over the fake `gh` answering by endpoint, and
# needs no Herdr: every case runs with HERDR_ENV unset.
source tests/gh-fake.sh
gh_fake_install "$tmp/bin"
export GH_ROUTES=$tmp/routes
gh_reset; export GH_STATUS_SEQ=200
calls >/dev/null
here=https://api.github.com/repos/o/r there=https://api.github.com/repos/o/other
issues="repos/{owner}/{repo}/issues"
# iss <number> <title> <state> <repository_url> [<assignee>]: one issue as the API answers it.
iss() { jq -cn --argjson n "$1" --arg t "$2" --arg s "$3" --arg u "$4" --arg a "${5:-}" \
  '{number: $n, title: $t, state: $s, repository_url: $u, assignees: (if $a == "" then [] else [{login: $a}] end)}'; }
# Two pages, the shape --paginate prints, out of number order.
# One sub-issue lives in another repo under a number this repo also uses: its
# blockers are read from its own repo.
gh_route "$issues/1/sub_issues" "[$(iss 12 b open $here),$(iss 14 c closed $here)]
[$(iss 11 a open $here someone),$(iss 12 d open $there)]"
gh_route "repos/o/r/issues/11/dependencies/blocked_by" '[]'
gh_route "repos/o/r/issues/12/dependencies/blocked_by" "[$(iss 11 a open $here),$(iss 90 z open $here),$(iss 14 c closed $here),$(iss 11 elsewhere open $there)]"
gh_route "repos/o/other/issues/12/dependencies/blocked_by" "[$(iss 11 a open $here)]"
out=$(HERDR_ENV='' bash "$s/frontier.sh" --parent 1); rc=$?
check_rc "frontier exits 0 outside Herdr" 0 "$rc"
check "frontier lists each sub-issue lowest number first with its repo, assignees and open blockers, each with its repo and inside or outside the spec" \
  '{"parent":1,"sub_issues":[{"number":11,"title":"a","repo":"o/r","state":"open","assignees":["someone"],"blockers":[]},{"number":12,"title":"d","repo":"o/other","state":"open","assignees":[],"blockers":[{"number":11,"title":"a","repo":"o/r","inside":true}]},{"number":12,"title":"b","repo":"o/r","state":"open","assignees":[],"blockers":[{"number":11,"title":"a","repo":"o/r","inside":true},{"number":90,"title":"z","repo":"o/r","inside":false},{"number":11,"title":"elsewhere","repo":"o/other","inside":false}]},{"number":14,"title":"c","repo":"o/r","state":"closed","assignees":[],"blockers":[]}]}' \
  "$(jq -c . <<<"$out")"
check "frontier reads over REST, every page, and no blockers of a closed sub-issue" \
  "api --paginate $issues/1/sub_issues?per_page=100
api --paginate repos/o/r/issues/11/dependencies/blocked_by?per_page=100
api --paginate repos/o/other/issues/12/dependencies/blocked_by?per_page=100
api --paginate repos/o/r/issues/12/dependencies/blocked_by?per_page=100" "$(gh_args)"
check "frontier reaches no herdr" "" "$(calls)"
gh_reset
gh_route "$issues/2/sub_issues" '[]'
out=$(HERDR_ENV='' bash "$s/frontier.sh" --parent 2); rc=$?
check_rc "frontier on a parent with no sub-issues exits 0" 0 "$rc"
check "and lists none" '{"parent":2,"sub_issues":[]}' "$(jq -c . <<<"$out")"
out=$(HERDR_ENV='' bash "$s/frontier.sh" --parent 3 2>/dev/null); rc=$?
check_rc "frontier whose read GitHub refuses exits 1" 1 "$rc"
check "the refusal carries gh's message" "sub-issues of #3: gh: Not Found (HTTP 404)" "$(jq -r .error <<<"$out")"
gh_route "$issues/4/sub_issues" "[$(iss 5 e open $here)]"
out=$(HERDR_ENV='' bash "$s/frontier.sh" --parent 4 2>/dev/null); rc=$?
check_rc "frontier whose blocker read GitHub refuses exits 1" 1 "$rc"
check "that refusal names the sub-issue" "blockers of o/r#5: gh: Not Found (HTTP 404)" "$(jq -r .error <<<"$out")"
# A read that lands but is no list of issues (an object, nothing, not JSON, an
# entry that is no issue) is never "no sub-issues".
for body in '{"message":"moved"}' '' 'not json' '["oops"]' '[{"title":"x","state":"open"}]' '[]
{"number":1}' "[$(iss 7 g open $here | jq -c 'del(.repository_url)')]" "[$(iss 7 g open $here | jq -c 'del(.assignees)')]"; do
  gh_route "$issues/6/sub_issues" "$body"
  out=$(HERDR_ENV='' bash "$s/frontier.sh" --parent 6 2>/dev/null); rc=$?
  check_rc "frontier refuses the answer '$body' as unreadable" 2 "$rc"
  check "and says so" "sub-issues of #6: unreadable answer from gh" "$(jq -r .error <<<"$out")"
done
# One argv string over 128 KiB (MAX_ARG_STRLEN) must not reach jq: only the
# fields frontier reads are kept from each answer.
head -c 140000 /dev/zero | tr '\0' x > "$tmp/big"
# fat <number> <title>: iss with that body, built from the file so no argv string is large.
fat() { iss "$1" "$2" open $here | jq -c --rawfile b "$tmp/big" '. + {body: $b}'; }
fat 8 h | jq -s -c . > "$tmp/routes/$(tr / _ <<<"$issues/7/sub_issues")"
fat 9 i | jq -s -c . > "$tmp/routes/$(tr / _ <<<"repos/o/r/issues/8/dependencies/blocked_by")"
out=$(HERDR_ENV='' bash "$s/frontier.sh" --parent 7 2>/dev/null); rc=$?
check_rc "frontier on sub-issues with bodies over 128 KiB exits 0" 0 "$rc"
check "and lists them" '{"parent":7,"sub_issues":[{"number":8,"title":"h","repo":"o/r","state":"open","assignees":[],"blockers":[{"number":9,"title":"i","repo":"o/r","inside":false}]}]}' \
  "$(jq -c . <<<"$out")"
gh_reset
for bad in "--parent x" "--parent 0" "--parent" "--parent -1" "--parent 1 --roster r" "1"; do
  # shellcheck disable=SC2086  # the call's words are split on purpose
  out=$(HERDR_ENV='' bash "$s/frontier.sh" $bad 2>/dev/null); rc=$?
  check_rc "frontier refuses '$bad'" 2 "$rc"
  check "frontier answers '$bad' with its usage line" "usage: frontier --parent <n>" "$(jq -r .error <<<"$out")"
done
check "a refused call reaches no gh" "" "$(gh_args)"

finish
