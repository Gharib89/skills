#!/usr/bin/env bash
# super-agent settles a one-off task on its last line (#1388): `reconcile` settles it on
# `Result:`, raises a `needs-owner` escalate row on `Needs owner:` with no stall, and
# counts any other rest as a stall; `status` prints a settled task once in a `Finished`
# row; `ledger adopt` answers one adoption step-in carrying the contract line for a new
# one-off task thread, and none for a ship, triage or interactive thread or a re-adopt.
# Driven through the command lines over fake `t3` and `gh` (tests/super-agent-fake.sh).
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
source tests/super-agent-fake.sh

s=skills/super-agent/scripts
tmp=$(mktemp -d) || exit 2
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/fake"
export PATH="$tmp/bin:$PATH" SA_FAKE=$tmp/fake
sa_fake_install "$tmp/bin"
led=$tmp/ledger.json
repo=acme/widgets
contract=$(bash -c 'source skills/super-agent/scripts/_lib.sh && printf %s "$sa_task_contract"')
L() { bash "$s/ledger.sh" --ledger "$led" "$@"; }
R() { bash "$s/reconcile.sh" --ledger "$led"; }
S() { bash "$s/status.sh" --ledger "$led" "$@"; }
fresh() { rm -rf "$led" "$SA_FAKE"; mkdir -p "$SA_FAKE/threads" "$SA_FAKE/gh"; }
# baseline <slug> <thread>: a task entry whose launch reconcile saw its thread running
baseline() { L add --task "$1" --thread "$2" >/dev/null; sa_thread "$2" running 0 0 '' ''; R >/dev/null; }
# rests <thread> <last message>: the thread ran once and rests, past any stall window
rests() { sa_thread "$1" idle 1 0 '' '' "$2" 2020-01-01T00:00:00Z; }

# --- Result: settles it, and Finished prints it once ---------------------------------------
fresh
baseline research-x t-r
rests t-r "$(printf 'The cache key drops the tenant.\n\nResult: the cache key drops the tenant https://github.com/acme/widgets/blob/main/notes/cache.md\n')"
out=$(R)
check "a task resting on a Result: line is settled" "task:research-x" "$(jq -r '[.settled[].key] | join(" ")' <<<"$out")"
check "the entry keeps the result" "the cache key drops the tenant https://github.com/acme/widgets/blob/main/notes/cache.md" \
  "$(L get task:research-x | jq -r .result)"
check "the block prints it in a Finished row" \
  "Finished (1): task:research-x: the cache key drops the tenant https://github.com/acme/widgets/blob/main/notes/cache.md" \
  "$(jq -r .status.block <<<"$out" | grep '^Finished')"
check "the next block does not print it again" "" "$(S --digest | jq -r .block | grep '^Finished')"
check "nor does the next reconcile's" "" "$(R | jq -r .status.block | grep '^Finished')"
jq '.status.finished_ack = "x"' "$led" > "$led.bad"
out=$(bash "$s/status.sh" --ledger "$led.bad" 2>&1); rc=$?
check_rc "a finished_ack that is no array is refused at load" 2 "$rc"
check "naming the field" yes "$(grep -q finished_ack <<<"$out" && echo yes || echo no)"
check "it stalled no count" 0 "$(L get task:research-x | jq -r .stalls)"

# --- Needs owner: an escalate row, no stall --------------------------------------------------
fresh
baseline ask-x t-a
rests t-a "$(printf 'I cannot pick the account.\nNeeds owner: which account deploys the dashboard?')"
out=$(R)
check "a task resting on Needs owner: is at rest, not settled" "at-rest 0" "$(jq -r '"\(.entries[0].stage) \(.settled | length)"' <<<"$out")"
check "it raises a needs-owner escalate row with the question" "task:ask-x needs-owner which account deploys the dashboard?" \
  "$(jq -r '.escalate[] | "\(.key) \(.reason) \(.detail)"' <<<"$out")"
check "and counts no stall" "0 0" "$(jq -r '"\(.stalled | length) \(.entries[0].stalls)"' <<<"$out")"
out=$(R)
check "a later wake past the window counts none either" "0 0" "$(jq -r '"\(.stalled | length) \(.entries[0].stalls)"' <<<"$out")"
L need task:ask-x --action "Answer task:ask-x account" --reason needs-owner --why "it cannot pick the account" --answer-in https://t3.example/t/a >/dev/null; rc=$?
check_rc "needs-owner is a reason word a need takes" 0 "$rc"
check "the need silences the row" '[]' "$(R | jq -c '[.escalate[].key]')"
L unneed task:ask-x >/dev/null
sa_thread t-a running 2 0 '' ''
check "once the owner answered and the thread runs again, the row is gone" '[] null' \
  "$(R | jq -c '[.escalate[].key]') $(L get task:ask-x | jq -c .needs_owner)"

# --- any other rest is a stall ---------------------------------------------------------------
fresh
baseline plain-x t-p
rests t-p "All done, the tests pass."
out=$(R)
check "a task resting on no contract line is not settled" "at-rest 0" "$(jq -r '"\(.entries[0].stage) \(.settled | length)"' <<<"$out")"
check "it counts a stall" "task:plain-x 1 run-completed" "$(jq -r '.stalled[] | "\(.key) \(.stalls) \(.reason)"' <<<"$out")"
check "and raises no needs-owner row" '[]' "$(jq -c '[.escalate[].reason]' <<<"$out")"

# --- the forms a model writes: a list marker, backticks, emphasis -----------------------------
# ends <last line>: the stage and result a one-off task gets resting on that last line
ends() { fresh; baseline form-x t-f; rests t-f "$(printf 'Done.\n%s' "$1")"; R >/dev/null; L get task:form-x | jq -r '"\(.stage) \(.result) \(.needs_owner // "" | length > 0)"'; }
for line in '`Result: x`' '**Result:** x' '- Result: x' '* **Result:** x'; do
  check "$line settles, the result read past the markup" "settled x false" "$(ends "$line")"
done
for line in 'Result:' 'result: x' 'Results: x' '**Result:**'; do
  check "$line is no result: a stall" "at-rest null false" "$(ends "$line")"
done
for line in '`Needs owner: which?`' '**Needs owner:** which?' '- Needs owner: which?'; do
  check "$line raises needs-owner" "task:form-x needs-owner which?" \
    "$(fresh; baseline form-x t-f; rests t-f "$line"; R | jq -r '.escalate[] | "\(.key) \(.reason) \(.detail)"')"
done
for line in 'Needs owner:' 'needs owner: which?'; do
  check "$line raises no row" '[]' "$(fresh; baseline form-x t-f; rests t-f "$line"; R | jq -c '[.escalate[].reason]')"
done

# --- the adoption step-in ----------------------------------------------------------------------
fresh
out=$(L adopt --task deploy-y --thread t-d)
check "adopting a task thread answers one step-in, the contract line" "$contract" "$(jq -r .step_in <<<"$out")"
out=$(L adopt --task deploy-y --thread t-d)
check "re-adopting the same thread answers the same entry and no step-in" "true false" "$(jq -r '"\(.existing) \(has("step_in"))"' <<<"$out")"
check "adopting a ship thread answers none" false "$(L adopt --repo $repo --number 12 --thread t-s --worktree /wt/s --branch feat/s-12 | jq -r 'has("step_in")')"
check "adopting a triage thread answers none" false \
  "$(L adopt --repo $repo --number 13 --kind triage --thread t-t --worktree /wt/t --branch triage/t-13 | jq -r 'has("step_in")')"
check "adopting an interactive task answers none" false "$(L adopt --task grill-z --thread t-z --interactive | jq -r 'has("step_in")')"

finish
