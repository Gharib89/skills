#!/usr/bin/env bash
# #1341: `gate clean`, `gate summary` and `gate admit clean` share one evaluator,
# so one Run file and one host state get one `clean` and `held_by` from all
# three. Driven at run-file.sh over the Host fake in a throwaway checkout whose
# origin names GitHub. A local check deferred to CI holds when the CI answer
# carries no check that could cover it, and a tracked issue's criteria hold
# every entrypoint when the Run file records no `## Criteria`.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
source tests/run-file-lib.sh

m=$PWD/skills/ship-run/scripts/run-file.sh
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
repo=$work/repo; export SHIP_FAKE=$work/fake SHIP_HOST_ADAPTER=$PWD/tests/host-fake.sh
mkdir -p "$SHIP_FAKE" "$repo/docs/agents"
git init -q -b main "$repo"
cat > "$repo/docs/agents/ship.md" <<'PROFILE'
## CI
Legs: None.
No-checks legal: yes, the repo runs no CI.

## Reviewers
### primary
Trigger: on-request
Fallback-for: None.
PROFILE
head=$(run_file_commit_profile "$repo" "$work/github.com/owner/repo.git") || exit 2
jq -n --arg h "$head" '{status: "no-checks", head_sha: $h, checks: []}' > "$work/ci.json"
jq -n --arg h "$head" '{number: 7, title: "fix: x", head_sha: $h, head_ref: "fix/x-9", base_ref: "main", state: "open"}' \
  > "$SHIP_FAKE/host_pr_get.1.json"

rf=$work/records/ship-9/run.md
# run_file <secrets> <lint> [criteria]: a Run file for issue #9, settled but for
# the local gate results and, with a third argument, the Criteria it records.
run_file() {
  rm -rf "$work/records"; mkdir -p "$work/records/ship-9"
  printf '%s\n' '## Local gate' "- 00:00 $head pass {\"secrets\":\"$1\",\"lint\":\"$2\"}" \
    '## Review evidence' 'Round: primary 1: all dispositioned' "Stop: primary: tree unchanged at $head" > "$rf"
  [ $# -lt 3 ] || printf '%s\n' '## Criteria' "$3" >> "$rf"
  cp "$work/ci.json" "$work/records/ship-9/ci-wait.json"
}
issue() { echo "[]" > "$SHIP_FAKE/host_issue_blockers_open.1.json"; jq -n --arg b "$1" '{number: 9, title: "t", body: $b, state: "open", is_pr: false, labels: [], assignees: [], created_at: "2026-01-01T00:00:00Z", url: "u"}' > "$SHIP_FAKE/host_issue_get.1.json"; }
gate() { # gate <clean|summary|admit>: prints `[<clean>, <held_by>]`
  local out
  case $1 in
    clean) out=$(cd "$repo" && bash "$m" gate clean "$work/ci.json" --head "$head" --file "$rf" 2>/dev/null) ;;
    summary) out=$(cd "$repo" && bash "$m" gate summary 7 --file "$rf" 2>/dev/null) ;;
    admit) out=$(cd "$repo" && bash "$m" gate admit clean "$work/ci.json" --head "$head" --file "$rf" 2>/dev/null)
      out=$(jq -c '.clean // .' <<<"$out") ;;
  esac
  jq -c '[.clean, .held_by]' <<<"$out"
}
admitted() { grep -c '^## Merge admission' "$rf"; }
# same <case> <expected [clean, held_by]>: all three entrypoints answer it.
same() {
  local e
  for e in clean summary admit; do check "$1: gate $e" "$2" "$(gate "$e")"; done
}

issue $'## Acceptance criteria\n\n- [ ] one'

# --- a deferral no check covers ---------------------------------------------------
run_file pass deferred-to-ci '- 1: one'; printf '%s\n' 'Criterion 1: met: a test' >> "$rf"
same 'Legs: None., legal no-checks, zero check rows, one local check deferred to CI' \
  '[false,["local gate lint: deferred-to-ci but CI reported no check to cover it"]]'
check_rc 'and gate clean exits 1' 1 "$(cd "$repo" && bash "$m" gate clean "$work/ci.json" --head "$head" --file "$rf" >/dev/null 2>&1; echo $?)"
check 'and admit clean writes no admission' 0 "$(admitted)"

run_file pass pass '- 1: one'; printf '%s\n' 'Criterion 1: met: a test' >> "$rf"
same 'the same profile with every local check passed' '[true,[]]'
check_rc 'and gate clean exits 0' 0 "$(cd "$repo" && bash "$m" gate clean "$work/ci.json" --head "$head" --file "$rf" >/dev/null 2>&1; echo $?)"
check 'and admit clean writes the admission' 1 "$(admitted)"

# --- criteria the issue states and the Run file never recorded --------------------
hold='["criteria: the Run file has no ## Criteria but issue #9 has 1 criteria; record each with `run-file note Criteria <text>`"]'
run_file pass pass; before=$(cat "$rf")
same 'a tracked issue with criteria and no Criteria section' "[false,$hold]"
check_rc 'and gate admit clean exits 1' 1 "$(cd "$repo" && bash "$m" gate admit clean "$work/ci.json" --head "$head" --file "$rf" >/dev/null 2>&1; echo $?)"
check 'and admit clean writes no admission' 0 "$(admitted)"
check 'and the Run file is left as it was' "$before" "$(cat "$rf")"

run_file pass pass ''
same 'an intentionally empty recorded Criteria section' '[true,[]]'

# An issue the gate cannot read is no verdict: exit 2, and no admission.
touch "$SHIP_FAKE/host_issue_get.1.fail"
run_file pass pass
for e in clean admit; do
  case $e in clean) a=(gate clean "$work/ci.json") ;; admit) a=(gate admit clean "$work/ci.json") ;; esac
  out=$(cd "$repo" && bash "$m" "${a[@]}" --head "$head" --file "$rf" 2>/dev/null); rc=$?
  check_rc "an unreadable issue: gate $e exits 2" 2 "$rc"
  check "and gate $e names the read" yes "$(jq -r '.error' <<<"$out" | grep -q 'cannot read issue 9' && echo yes)"
done
check 'and admit clean writes no admission' 0 "$(admitted)"
rm "$SHIP_FAKE/host_issue_get.1.fail"

issue 'no criteria here'
run_file pass pass
same 'an issue with no criteria and no Criteria section' '[true,[]]'

finish
