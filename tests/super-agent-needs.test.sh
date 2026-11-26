#!/usr/bin/env bash
# super-agent's needs (#1386): a need is blocking or an offer by its reason word,
# `ledger need` refuses one the needs-you message cannot print, `status` prints the
# message in place of the `Needs you` row and sets the alert mark, a blocking need
# is raised once more after 4 working hours, an acknowledge mark quiets an escalate
# row until the entry's stage changes, and `ledger answer` resolves `88 1`. The clock
# is pinned with SA_NOW and TZ=UTC, so the work week's days are UTC days.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
source tests/super-agent-fake.sh

s=skills/super-agent/scripts
tmp=$(mktemp -d) || exit 2
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/fake"
export PATH="$tmp/bin:$PATH" SA_FAKE=$tmp/fake TZ=UTC
sa_fake_install "$tmp/bin"
led=$tmp/ledger.json
repo=acme/widgets
L() { bash "$s/ledger.sh" --ledger "$led" "$@"; }
S() { bash "$s/status.sh" --ledger "$led" "$@"; }
at() { date -d "$1" +%s; }
fresh() { rm -f "$led" "$tmp/needs-alerts.jsonl"; L self th-own >/dev/null; }
opts=(--option "Relaunch on Opus: a fresh thread with the failure quoted"
  --option "Requeue the ticket: drop the thread, keep it on the waiting list"
  --option "I'll take the thread: it becomes yours")
need88() { L need $repo#88 --action "Restart widgets#88 after 3 stalls" --reason "${1:-stall-cap}" \
  --why "its thread rested 3 times on the same failing migration test" "${opts[@]}"; }
offer41() { L need $repo#41 --action "Close widgets#41 as a duplicate of widgets#39" --reason ask-first \
  --why "both describe the same exporter retry loss" --option "Close it: with a comment linking widgets#39" --option "Leave it open"; }

# --- each reason word is blocking or an offer; an unknown word is refused --------------
fresh
export SA_NOW; SA_NOW=$(at "2026-11-23 09:00")
for w in permission-hold merge-gate scope stall-cap fault no-instance no-owner-skill no-project \
  stale-ship route-ask owner-steered triage; do
  check "$w is blocking" blocking "$(need88 "$w" | jq -r .need.class)"
done
for w in daily-offer unqueued parents-done stale-skill issue-closed pr-closed ask-first owner-run \
  verify cleanup; do
  check "$w is an offer" offer "$(need88 "$w" | jq -r .need.class)"
done
out=$(need88 because 2>/dev/null); rc=$?
check_rc "an unknown reason word is refused" 2 $rc
check "the refusal names the word" true "$(jq -r '.error | contains("because")' <<<"$out")"
L need $repo#88 --action "Restart widgets#88 after 3 stalls" --why w --option a --option b >/dev/null 2>&1
check_rc "a need with no reason word is refused" 2 $?

# --- recording a need is refused when the message could not print it ---------------
refused() { L need $repo#88 --reason stall-cap "$@" >/dev/null 2>&1; echo $?; }
check "one option is refused" 2 "$(refused --action "Restart widgets#88 now" --why w --option a)"
check "five options are refused" 2 "$(refused --action "Restart widgets#88 now" --why w --option a --option b --option c --option d --option e)"
check "no option without --answer-in is refused" 2 "$(refused --action "Restart widgets#88 now" --why w)"
check "options with --answer-in are refused" 2 "$(refused --action "Approve widgets#88 held call" --why w --answer-in https://t3.example/t/9 --option a --option b)"
check "a label of six words is refused" 2 "$(refused --action "Restart widgets#88 now" --why w --option "one two three four five six: so" --option b)"
check "a label of five words passes" 0 "$(refused --action "Restart widgets#88 now" --why w --option "one two three four five: so" --option b)"
check "a ticket ending past character 30 is refused" 2 "$(refused --action "Reconsider-and-restart widgets#88 now" --why w --option a --option b)"
check "an action whose second word is no ticket is refused" 2 "$(refused --action "Restart the widgets#88 thread" --why w --option a --option b)"
check "no --why is refused" 2 "$(refused --action "Restart widgets#88 now" --option a --option b)"
check "a need answered in its own thread takes no options" 0 "$(refused --action "Approve widgets#88 held call" --why w --answer-in https://t3.example/t/9)"
check "a task key's ticket can be another repo's issue" 0 \
  "$(L need task:ask-first-close-12 --action "Close acme/widgets#12 as a duplicate" --reason ask-first --why w --option a --option b >/dev/null 2>&1; echo $?)"

# --- the needs-you message ---------------------------------------------------------
fresh
offer41 >/dev/null
need88 >/dev/null
L need $repo#90 --action "Approve widgets#90 held git push" --reason permission-hold --why "the run asks to push its branch" --answer-in "https://t3.example/t/90" >/dev/null
out=$(S)
block=$(jq -r .block <<<"$out")
want='**Restart [widgets#88](https://github.com/acme/widgets/issues/88) after 3 stalls?**
Why: its thread rested 3 times on the same failing migration test.
1. Relaunch on Opus (recommended): a fresh thread with the failure quoted
2. Requeue the ticket: drop the thread, keep it on the waiting list
3. I'\''ll take the thread: it becomes yours

**Approve [widgets#90](https://github.com/acme/widgets/issues/90) held git push?**
Why: the run asks to push its branch.
Answer in [its thread](https://t3.example/t/90).

Offer: Close [widgets#41](https://github.com/acme/widgets/issues/41) as a duplicate of widgets#39?
Why: both describe the same exporter retry loss.
1. Close it (recommended): with a comment linking widgets#39
2. Leave it open'
check "blocking needs print first in the order recorded, bold, each restarting at 1, then the offer" "$want" "$block"
check "no Needs you row beside the needs printed in full" 0 "$(grep -c '^Needs you' <<<"$block")"
# shown as rendered: a link's target and the bold marks are not seen
first=$(head -n 1 <<<"$block" | sed -E 's/\[([^]]*)\]\([^)]*\)/\1/g; s/\*\*//g')
check "the action is within the first 80 characters" true "$([ ${#first} -le 80 ] && echo true || echo false)"
check "at most 6 lines a need" true "$(awk 'BEGIN{RS=""} {n=split($0, l, "\n"); if (n > 6) bad=1} END{print bad ? "false" : "true"}' <<<"$block")"
check "every need printed is raised once" "3" "$(jq '.raised | length' <<<"$out")"
check "and marked alerted" '[true,true,true]' "$(L list | jq -c '[.needs[] | .alerted != null]')"
check "nothing raised on the next run" '[] ""' "$(S | jq -r '"\(.raised | tojson) \(.block | tojson)"')"
L ruling "x" >/dev/null; L wait $repo#7 --reason queued >/dev/null
out=$(S | jq -r .block)
check "a block of other rows alone leaves the needs out" "Waiting (1): [widgets#7](https://github.com/acme/widgets/issues/7)" "$out"
L unneed $repo#41 >/dev/null
out=$(S | jq -r .block)
check "a changed need set prints the needs again" "**Restart" "$(head -n 1 <<<"$out" | cut -d' ' -f1)"
check "and no offer is left" 0 "$(grep -c '^Offer:' <<<"$out")"
L unneed $repo#88 >/dev/null; L unneed $repo#90 >/dev/null
check "emptied needs read Nothing needs you now." "Nothing needs you now." "$(S | jq -r .block)"
L need $repo#88 --action "Restart widgets#88 after 3 stalls" --reason stall-cap --why "x" --option a --option b >/dev/null
L need $repo#88 --action "Restart widgets#88 after 3 stalls" --reason stall-cap --why x \
  --option "Retry at 10:30: after the deploy" --option b >/dev/null
check "an option's label ends at its first ': '" "Retry at 10:30|after the deploy" \
  "$(L list | jq -r '.needs[0].options[0] | "\(.label)|\(.consequence)"')"
check "a digest prints the needs in full, not a row" 0 "$(S --digest | jq -r .block | grep -c '^Needs you')"

# --- a blocking need open past 4 working hours is raised once more -----------------
fresh
L need $repo#88 --action "Restart widgets#88 after 3 stalls" --reason stall-cap --why x --option a --option b >/dev/null
offer41 >/dev/null
S >/dev/null
SA_NOW=$(at "2026-11-23 12:59")
check "under 4 working hours: nothing raised" 0 "$(S | jq '.raised | length')"
SA_NOW=$(at "2026-11-23 13:01")
out=$(S)
check "past 4 working hours the blocking need is raised once more" "$repo#88 true" "$(jq -r '.raised[] | "\(.key) \(.reminder)"' <<<"$out")"
check "and the needs print again" "**Restart" "$(jq -r .block <<<"$out" | head -n 1 | cut -d' ' -f1)"
SA_NOW=$(at "2026-11-30 12:00")
check "never again" 0 "$(S | jq '.raised | length')"
check "the offer is never reminded" null "$(L list | jq -r '.needs[] | select(.key == "acme/widgets#41") | .reminded')"
fresh
SA_NOW=$(at "2026-11-28 22:00")
L need $repo#88 --action "Restart widgets#88 after 3 stalls" --reason stall-cap --why x --option a --option b >/dev/null
S >/dev/null
SA_NOW=$(at "2026-11-30 03:59")
check "a weekend is no working hours" 0 "$(S | jq '.raised | length')"
SA_NOW=$(at "2026-11-30 04:01")
check "the work week's hours are" 1 "$(S | jq '.raised | length')"
check "the alert log holds the alert and the reminder" "alert reminder" \
  "$(jq -sr 'map(select((.at | type) == "string" and .key == "acme/widgets#88" and .class == "blocking") | .event) | join(" ")' "$tmp/needs-alerts.jsonl")"
printf '{"work_week": [0,1,2,3,4,5,6]}\n' > "$tmp/fleet.json"
fresh
SA_NOW=$(at "2026-11-28 22:00")
L need $repo#88 --action "Restart widgets#88 after 3 stalls" --reason stall-cap --why x --option a --option b >/dev/null
S --fleet "$tmp/fleet.json" >/dev/null
SA_NOW=$(at "2026-11-29 02:01")
check "the fleet file's work week counts" 1 "$(S --fleet "$tmp/fleet.json" | jq '.raised | length')"
fresh
SA_NOW=$(at "2026-11-27 20:30")
L need $repo#88 --action "Restart widgets#88 after 3 stalls" --reason stall-cap --why x --option a --option b >/dev/null
S >/dev/null
SA_NOW=$(at "2026-11-28 00:30")
check "an hour across midnight into a weekend counts only its Friday part" 0 "$(S | jq '.raised | length')"
SA_NOW=$(at "2026-11-30 00:31")
check "the rest of the 4 hours falls on Monday" 1 "$(S | jq '.raised | length')"

# --- a need is raised once, and only once its alert is logged ----------------------
fresh
SA_NOW=$(at "2026-11-23 09:00")
L need $repo#88 --action "Restart widgets#88 after 3 stalls" --reason stall-cap --why x --option a --option b >/dev/null
mkdir "$tmp/needs-alerts.jsonl"
S >/dev/null 2>&1
check_rc "an alert log that cannot be written is refused" 2 $?
rmdir "$tmp/needs-alerts.jsonl"
check "and the need is raised on the next run" 1 "$(S | jq '.raised | length')"
fresh
L need $repo#88 --action "Restart widgets#88 after 3 stalls" --reason stall-cap --why x --option a --option b >/dev/null
for i in 1 2 3 4; do S > "$tmp/race-$i.json" & done; wait
check "runs at once raise a need once" 1 "$(cat "$tmp"/race-*.json | jq -s 'map(.raised | length) | add')"
check "and log it once" 1 "$(wc -l < "$tmp/needs-alerts.jsonl")"

# --- a need 0.46.0 pushed counts as alerted at its since ---------------------------
fresh
SA_NOW=$(at "2026-11-23 09:00")
jq '.needs = [{key: "acme/widgets#88", action: "Restart widgets#88 after 3 stalls", reason: "stall-cap", since: "2026-11-23T09:00:00Z", pushed: true}]' "$led" > "$led.new" && mv "$led.new" "$led"
check "a pushed need is not alerted again" 0 "$(S | jq '.raised | length')"
SA_NOW=$(at "2026-11-23 13:01")
check "and is reminded 4 working hours after its since" "true" "$(S | jq -r '.raised[0].reminder')"
fresh
jq '.needs = [{key: "acme/widgets#88", action: "Restart widgets#88 after 3 stalls", reason: "stall-cap", since: "2026-11-23T09:00:00Z", pushed: true}]' "$led" > "$led.new" && mv "$led.new" "$led"
L need $repo#88 --action "Restart widgets#88 after 3 stalls" --reason stall-cap --why x --option a --option b >/dev/null
check "recorded again with the same action, it keeps the push as its alert mark" "2026-11-23T09:00:00Z" "$(L list | jq -r '.needs[0].alerted')"
fresh
jq '.needs = [{key: "acme/widgets#88", action: "approve the held call", since: "2026-11-23T09:00:00Z", pushed: true}]' "$led" > "$led.new" && mv "$led.new" "$led"
check "a free-text 0.46.0 need prints behind its ticket's link" "**[widgets#88](https://github.com/acme/widgets/issues/88) approve the held call?**" "$(S --digest | jq -r .block | head -n 1)"
L need $repo#88 --action "Approve widgets#88 held call" --reason permission-hold --why x --option a --option b >/dev/null
check "recorded again with a ticket-led action, it keeps its marks" "2026-11-23T09:00:00Z 2026-11-23T09:00:00Z" "$(L list | jq -r '.needs[0] | "\(.since) \(.alerted)"')"
check "and is not alerted again" 0 "$(S | jq '.raised | length')"

# --- the acknowledge mark ----------------------------------------------------------
fresh
R() { bash "$s/reconcile.sh" --ledger "$led"; }
L add --repo $repo --number 5 --thread t-5 --worktree /wt/5 --branch feat/x-5 >/dev/null
sa_thread t-5 idle 4 0 /wt/5 feat/x-5; sa_pr $repo feat/x-5 none; sa_issue $repo 5 open
R >/dev/null
sa_stage "$led" $repo#5 at-rest
jq '.entries["acme/widgets#5"].stalls = 3' "$led" > "$led.new" && mv "$led.new" "$led"
esc() { R | jq -r '[.escalate[] | "\(.key) \(.reason)"] | join(",")'; }
check "a stall at the cap is an escalate row" "$repo#5 stall-cap" "$(esc)"
L ack $repo#5 --reason stall-cap >/dev/null
check "an acknowledge mark hides it" "" "$(esc)"
check "and makes no Needs you row" 0 "$(S --digest | jq -r .block | grep -c 'Needs you')"
L ack $repo#9 --reason stall-cap >/dev/null 2>&1
check_rc "an acknowledge mark on a key the ledger lacks is refused" 1 $?
L ack $repo#5 --reason because >/dev/null 2>&1
check_rc "and one with an unknown reason word" 2 $?
sa_thread t-5 running 5 0 /wt/5 feat/x-5; R >/dev/null
sa_thread t-5 idle 6 0 /wt/5 feat/x-5; R >/dev/null
sa_stage "$led" $repo#5 at-rest
jq '.entries["acme/widgets#5"].stalls = 3' "$led" > "$led.new" && mv "$led.new" "$led"
check "it lapses when the entry's stage changes" "$repo#5 stall-cap" "$(esc)"

# --- the owner's answer: `88 1` ------------------------------------------------------
fresh
need88 >/dev/null
check "a bare number is accepted with exactly one need with options" "$repo#88 1 Relaunch on Opus" "$(L answer 1 | jq -r '"\(.key) \(.option) \(.label)"')"
offer41 >/dev/null
out=$(L answer 1 2>/dev/null)
check_rc "a bare number is refused with two needs with options" 1 $?
check "the refusal says to name the ticket" true "$(jq -r '.error | contains("answer <ticket> <option>")' <<<"$out")"
check "88 1 resolves to that need's option" "$repo#88 1 Relaunch on Opus a fresh thread with the failure quoted" \
  "$(L answer "88 1" | jq -r '"\(.key) \(.option) \(.label) \(.consequence)"')"
check "41 2 resolves to the offer's second option" "$repo#41 2 Leave it open" "$(L answer "41 2" | jq -r '"\(.key) \(.option) \(.label)"')"
out=$(L answer "88 4" 2>/dev/null)
check_rc "an option the need lacks is refused" 1 $?
check "the refusal names the options it has" "$repo#88 has options 1 to 3" "$(jq -r .error <<<"$out")"
out=$(L answer "77 1" 2>/dev/null)
check_rc "a number no need holds is refused" 1 $?
check "the refusal counts the needs it names" "77 names 0 open needs with options; name the ticket as owner/name#n" "$(jq -r .error <<<"$out")"
out=$(L answer "nonsense" 2>/dev/null)
check_rc "a reply that is no ticket and option is refused" 1 $?
check "the refusal quotes it" "nonsense: not a reply to an open need, <ticket> <option>" "$(jq -r .error <<<"$out")"
jq '.needs = "x"' "$led" > "$led.bad"
bash "$s/ledger.sh" --ledger "$led.bad" answer 1 >/dev/null 2>&1
check_rc "needs of the wrong shape are a tooling refusal" 2 $?
jq '.needs = [{key: 5, action: "x", options: [{label: "a"}]}]' "$led" > "$led.bad"
bash "$s/ledger.sh" --ledger "$led.bad" answer 1 >/dev/null 2>&1
check_rc "a need whose key is no string is a tooling refusal" 2 $?
L need $repo#90 --action "Approve widgets#90 held git push" --reason permission-hold --why w --answer-in https://t3.example/t/90 >/dev/null
L unneed $repo#41 >/dev/null
check "a need answered in its own thread does not count against a bare number" "$repo#88" "$(L answer 2 | jq -r .key)"

finish
