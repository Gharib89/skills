#!/usr/bin/env bash
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

# --- the contract every script keeps ------------------------------------------
for m in spawn watch read answer; do
  out=$(bash "$s/$m.sh" --help 2>"$tmp/err"); rc=$?
  check "$m --help opens with its usage line" "usage: $m" "$(sed -n 1p <<<"$out" | cut -d' ' -f1-2)"
  check "$m --help names its stdout fields next" stdout: "$(sed -n 2p <<<"$out" | cut -c1-7)"
  check_rc "$m --help exits 0" 0 "$rc"
  check "$m --help writes nothing on stderr" "" "$(cat "$tmp/err")"
  out=$(bash "$s/$m.sh" 2>/dev/null); rc=$?
  check "$m: a bare call answers its usage line" "$(sed -n 1p <<<"$(bash "$s/$m.sh" --help)")" "$(jq -r .error <<<"$out")"
  check_rc "$m: a bare call exits 2" 2 "$rc"
done
# Outside Herdr every script refuses before it touches anything.
out=$(HERDR_ENV='' bash "$s/spawn.sh" s1 --roster "$roster" --cwd "$tmp/cwd" --prompt hi 2>/dev/null); rc=$?
check_rc "spawn outside Herdr exits 2" 2 "$rc"
check "spawn outside Herdr says why" "drive-session runs inside Herdr only: HERDR_ENV=1 is not set" "$(jq -r .error <<<"$out")"
for call in "watch.sh --roster $roster" "read.sh s1 --roster $roster" "answer.sh s1 --roster $roster --keys Enter"; do
  # shellcheck disable=SC2086  # the call's words are split on purpose
  HERDR_ENV='' bash $s/$call >/dev/null 2>&1; rc=$?
  check_rc "${call%% *} outside Herdr exits 2" 2 "$rc"
done
check "no script reached herdr outside Herdr" "" "$(calls)"

# --- spawn ---------------------------------------------------------------------
printf 'idle 10\n' > "$HERDR_FAKE/s1.states"
out=$(bash "$s/spawn.sh" s1 --roster "$roster" --cwd "$tmp/cwd" --prompt "do the task" --model haiku); rc=$?
check_rc "spawn exits 0" 0 "$rc"
check "spawn answers the session, its tab and pane, and that it prompted" \
  '{"roster":"'"$roster"'","name":"s1","tab":"w1:t-s1","pane":"w1:p-s1","status":"idle","prompted":true}' "$(jq -c . <<<"$out")"
check "spawn opens an unfocused tab in this workspace, starts claude on the model, then prompts without waiting" \
  "tab create --workspace w1 --label s1 --cwd $tmp/cwd --no-focus
agent start s1 --kind claude --pane w1:p-s1 -- --model haiku
agent prompt s1 do the task" "$(calls)"
check "spawn records the row with the sequence number from before the prompt" \
  '{"name":"s1","pane":"w1:p-s1","tab":"w1:t-s1","cwd":"'"$tmp/cwd"'","task":"do the task","seen_seq":10}' \
  "$(jq -c '.sessions[0]' "$roster")"
out=$(bash "$s/spawn.sh" s1 --roster "$roster" --cwd "$tmp/cwd" --prompt again 2>/dev/null); rc=$?
check_rc "spawn refuses a name already in the roster" 1 "$rc"
check "the refusal names the roster holding it" "s1 is already in the roster $roster" "$(jq -r .error <<<"$out")"
check "the refusal reaches no herdr" "" "$(calls)"
# Herdr's name rule, [a-z][a-z0-9_-]{0,31}, held on its edges.
for bad in Bad _s1 1s s.1 "s 1" " s1" .. "s1/x" "a$(printf 'b%.0s' {1..32})"; do
  out=$(bash "$s/spawn.sh" "$bad" --roster "$roster" --cwd "$tmp/cwd" --prompt x 2>/dev/null); rc=$?
  check_rc "spawn refuses the name '$bad'" 2 "$rc"
  check "spawn says why it refuses '$bad'" "spawn: $bad is no Herdr agent name; use [a-z][a-z0-9_-]{0,31}" "$(jq -r .error <<<"$out")"
done
check "a refused name reaches no herdr" "" "$(calls)"
long="a$(printf 'b%.0s' {1..31})"
printf 'idle 5\n' > "$HERDR_FAKE/$long.states"
bash "$s/spawn.sh" "$long" --roster "$tmp/long.json" --cwd "$tmp/cwd" --prompt x >/dev/null; rc=$?
check_rc "spawn takes a 32-character name" 0 "$rc"
calls >/dev/null

# A new tab's shell can still be starting when claude is: `agent start` answers
# `agent_pane_busy` until it is up.
printf 'idle 50\n' > "$HERDR_FAKE/s5.states"
printf '2' > "$HERDR_FAKE/s5.start-busy"
bash "$s/spawn.sh" s5 --roster "$tmp/s5.json" --cwd "$tmp/cwd" --prompt x >/dev/null; rc=$?
check_rc "spawn waits out a pane whose shell is still starting" 0 "$rc"
check "it starts claude again until the pane takes it" 3 "$(calls | grep -c 'agent start s5')"
printf 'idle 51\n' > "$HERDR_FAKE/s6.states"
printf '99' > "$HERDR_FAKE/s6.start-busy"
out=$(bash "$s/spawn.sh" s6 --roster "$tmp/s6.json" --cwd "$tmp/cwd" --prompt x 2>/dev/null); rc=$?
check_rc "a pane that never takes claude fails the spawn" 1 "$rc"
check "the failure names the tab left open" "agent start: pane is not an available shell; tab w1:t-s6 left open" "$(jq -r .error <<<"$out")"
calls >/dev/null

# A session that stops on a startup dialog (an untrusted folder) is a row whose
# status is blocked and whose task is not yet sent, not a failed spawn.
printf 'agent_not_ready' > "$HERDR_FAKE/s2.start-error"
printf 'blocked 20\n' > "$HERDR_FAKE/s2.states"
out=$(bash "$s/spawn.sh" s2 --roster "$roster" --cwd "$tmp/cwd" --prompt "task two"); rc=$?
check_rc "spawn on a startup dialog exits 0" 0 "$rc"
check "spawn on a startup dialog answers blocked, unprompted" 'blocked false' "$(jq -r '"\(.status) \(.prompted)"' <<<"$out")"
check "spawn on a startup dialog sends no prompt" 0 "$(calls | grep -c 'agent prompt')"
check "the blocked row is in the roster, short of the dialog's sequence number" 19 "$(seen s2)"
out=$(bash "$s/watch.sh" --roster "$roster" --timeout 3000)
check "watch reports the startup dialog as the row's blocked event" '{"name":"s2","event":"blocked","seq":20}' "$out"
bash "$s/read.sh" s2 --roster "$roster" >/dev/null
calls >/dev/null

# A prompt Herdr refuses after the row is written leaves the row and the tab:
# the answer says so, and how to send the task.
printf 'idle 30\n' > "$HERDR_FAKE/s3.states"
printf 'agent_busy' > "$HERDR_FAKE/s3.prompt-error"
out=$(bash "$s/spawn.sh" s3 --roster "$tmp/s3.json" --cwd "$tmp/cwd" --prompt "task three" 2>/dev/null); rc=$?
check_rc "spawn whose prompt fails exits 1" 1 "$rc"
check "the failure names the tab left open and the way to send the task" \
  "agent prompt: prompt failed; s3 stays in the roster with tab w1:t-s3 open: send the task with answer --text" "$(jq -r .error <<<"$out")"
calls >/dev/null

# --- watch -----------------------------------------------------------------------
# The measured trap: after a prompt, status reads the previous turn's `done`
# until the turn starts. A settled status whose sequence number has not moved
# past the row's is no event.
printf 'done 10\n' > "$HERDR_FAKE/s1.states"
printf 'blocked 20\n' > "$HERDR_FAKE/s2.states"
out=$(bash "$s/watch.sh" --roster "$roster" --timeout 1500); rc=$?
check_rc "watch on stale states exits 0 at its timeout" 0 "$rc"
check "watch never reports a stale done or an acknowledged blocked" '{"name":null,"event":"timeout"}' "$out"

printf 'working 11\ndone 12\n' > "$HERDR_FAKE/s1.states"
out=$(bash "$s/watch.sh" --roster "$roster" --timeout 3000)
check "watch waits out the turn and reports its done" '{"name":"s1","event":"done","seq":12}' "$out"

printf 'done 12\n' > "$HERDR_FAKE/s1.states"
printf 'blocked 21\n' > "$HERDR_FAKE/s2.states"
out=$(bash "$s/watch.sh" --roster "$roster" --timeout 3000)
check "with two sessions holding events, watch reports the first in the roster" \
  '{"name":"s1","event":"done","seq":12}' "$out"
out=$(bash "$s/watch.sh" --roster "$roster" --timeout 3000)
check "an unread event is reported again" '{"name":"s1","event":"done","seq":12}' "$out"
calls >/dev/null
printf 'done\n' > "$HERDR_FAKE/s1.states"
bash "$s/watch.sh" --roster "$roster" --timeout 3000 >/dev/null 2>&1; rc=$?
check_rc "an agent answer watch cannot read is exit 2 rather than a poll forever" 2 "$rc"
for m in "read.sh s1" "answer.sh s1 --keys Enter"; do
  # shellcheck disable=SC2086  # the call's words are split on purpose
  out=$(bash $s/$m --roster "$roster" 2>/dev/null); rc=$?
  check_rc "${m%%.*} on an agent answer it cannot read exits 2" 2 "$rc"
  check "${m%%.*} names the unreadable answer" "agent get s1: unreadable answer from herdr" "$(jq -r .error <<<"$out")"
done
check "nothing was acknowledged from an unreadable answer" 10 "$(seen s1)"
printf 'not json' > "$tmp/bad.json"
for m in "watch.sh" "read.sh s1" "answer.sh s1 --keys Enter"; do
  # shellcheck disable=SC2086  # the call's words are split on purpose
  out=$(bash $s/$m --roster "$tmp/bad.json" 2>/dev/null); rc=$?
  check_rc "${m%%.*} on an unreadable roster exits 2" 2 "$rc"
  check "${m%%.*} names the unreadable roster" "cannot read the roster $tmp/bad.json" "$(jq -r .error <<<"$out")"
done
printf 'done 12\n' > "$HERDR_FAKE/s1.states"
calls >/dev/null

# --- read ----------------------------------------------------------------------
out=$(bash "$s/read.sh" s1 --roster "$roster" --lines 40); rc=$?
check_rc "read exits 0" 0 "$rc"
check "read answers the status, the sequence number and the recent output" \
  '{"name":"s1","status":"done","seq":12,"output":"output of s1"}' "$(jq -c . <<<"$out")"
check "read takes the unwrapped recent output" "agent get s1
agent read s1 --source recent-unwrapped --lines 40" "$(calls)"
check "read acknowledges the event" 12 "$(seen s1)"
out=$(bash "$s/watch.sh" --roster "$roster" --timeout 3000)
check "after the read, watch moves on to the next session's event" '{"name":"s2","event":"blocked","seq":21}' "$out"
out=$(bash "$s/read.sh" s9 --roster "$roster" 2>/dev/null); rc=$?
check_rc "read refuses a session the roster does not hold" 1 "$rc"
check "the refusal names the roster" "s9 is not in the roster $roster" "$(jq -r .error <<<"$out")"
for n in 0 00 -1 abc 1x " 5"; do
  bash "$s/read.sh" s1 --roster "$roster" --lines "$n" >/dev/null 2>&1; rc=$?
  check_rc "read refuses --lines $n" 2 "$rc"
done
for n in abc 1x -1; do
  bash "$s/watch.sh" --roster "$roster" --timeout "$n" >/dev/null 2>&1; rc=$?
  check_rc "watch refuses --timeout $n" 2 "$rc"
done
calls >/dev/null

# --- answer --------------------------------------------------------------------
out=$(bash "$s/answer.sh" s2 --roster "$roster" --text yes 2>/dev/null); rc=$?
check_rc "answer refuses text to a blocked session as a usage error" 2 "$rc"
check "the refusal names the way to answer a dialog" "answer: s2 is blocked on a dialog; answer it with --keys" "$(jq -r .error <<<"$out")"
check "text to a blocked session sends nothing" "agent get s2" "$(calls)"
check "a refused answer leaves the row's sequence number" 20 "$(seen s2)"

out=$(bash "$s/answer.sh" s2 --roster "$roster" --keys 1 Enter); rc=$?
check_rc "answer with keys exits 0" 0 "$rc"
check "answer records what it sent and the acknowledged sequence number" '{"name":"s2","sent":"keys","seen_seq":21}' "$(jq -c . <<<"$out")"
check "a blocked session is answered with send-keys" "agent get s2
agent send-keys s2 1 Enter" "$(calls)"

# Herdr refuses a blocked agent's scrollback past the viewport, so read takes
# the visible screen, where the dialog is.
printf 'blocked 22\n' > "$HERDR_FAKE/s2.states"
out=$(bash "$s/read.sh" s2 --roster "$roster"); rc=$?
check_rc "read of a blocked session exits 0" 0 "$rc"
check "read of a blocked session takes the visible screen" "agent get s2
agent read s2 --source visible" "$(calls)"
check "and acknowledges the dialog" 22 "$(seen s2)"

# Answering a startup dialog leaves the agent idle, not done: that is an event,
# because the held-back task is still to be sent.
printf 'idle 23\n' > "$HERDR_FAKE/s2.states"
out=$(bash "$s/watch.sh" --roster "$roster" --timeout 3000)
check "a session settling at idle is an event" '{"name":"s2","event":"idle","seq":23}' "$out"
calls >/dev/null
out=$(bash "$s/answer.sh" s2 --roster "$roster" --text "task two")
check "a session at its prompt is answered with text" "agent get s2
agent prompt s2 task two" "$(calls)"
check "answer with text records the sequence number before the prompt" 23 "$(seen s2)"
# A send Herdr refuses acknowledges nothing, so watch reports the event again.
printf 'idle 24\n' > "$HERDR_FAKE/s2.states"
printf 'agent_busy' > "$HERDR_FAKE/s2.prompt-error"
bash "$s/answer.sh" s2 --roster "$roster" --text again >/dev/null 2>&1; rc=$?
check_rc "an answer Herdr refuses exits 1" 1 "$rc"
check "a refused send leaves the row's sequence number" 23 "$(seen s2)"
rm "$HERDR_FAKE/s2.prompt-error"
bash "$s/answer.sh" s2 --roster "$roster" --text again >/dev/null
check "a sent answer acknowledges the state it answered" 24 "$(seen s2)"
# Text opening with a dash goes in the --flag=<value> form, which no flag can
# be mistaken for.
calls >/dev/null
bash "$s/answer.sh" s2 --roster "$roster" --text "- continue" >/dev/null 2>&1; rc=$?
check_rc "answer refuses a dash-led --text value as a usage error" 2 "$rc"
out=$(bash "$s/answer.sh" s2 --roster "$roster" --text="- continue"); rc=$?
check_rc "answer takes dash-led text as --text=" 0 "$rc"
check "the dash-led text is prompted verbatim" "agent get s2
agent prompt s2 - continue" "$(calls)"
bash "$s/answer.sh" s2 --roster "$roster" --text= >/dev/null 2>&1; rc=$?
check_rc "answer refuses an empty --text=" 2 "$rc"
printf 'idle 40\n' > "$HERDR_FAKE/s4.states"
bash "$s/spawn.sh" s4 --roster "$tmp/s4.json" --cwd "$tmp/cwd" --prompt="- review these items" >/dev/null; rc=$?
check_rc "spawn takes a dash-led task as --prompt=" 0 "$rc"
check "spawn prompts the dash-led task verbatim" "agent prompt s4 - review these items" "$(calls | grep 'agent prompt')"
usage_line=$(sed -n 1p <<<"$(bash "$s/answer.sh" --help)")
out=$(bash "$s/answer.sh" s2 --roster "$roster" --text a --keys b 2>/dev/null); rc=$?
check_rc "answer takes text or keys, not both" 2 "$rc"
check "text and keys together answer the usage line" "$usage_line" "$(jq -r .error <<<"$out")"
calls >/dev/null

# --- gone ----------------------------------------------------------------------
rm "$HERDR_FAKE/s1.states"
out=$(bash "$s/watch.sh" --roster "$roster" --timeout 3000)
check "a session Herdr no longer knows is gone" '{"name":"s1","event":"gone"}' "$out"
out=$(bash "$s/read.sh" s1 --roster "$roster")
check "read answers a gone session with no output" '{"name":"s1","status":"gone","seq":null,"output":null}' "$(jq -c . <<<"$out")"
check "read marks the row gone" true "$(jq -r '.sessions[0].gone' "$roster")"
out=$(bash "$s/watch.sh" --roster "$roster" --timeout 1000)
check "a gone row is not watched again" '{"name":null,"event":"timeout"}' "$out"
bash "$s/answer.sh" s1 --roster "$roster" --text hi >/dev/null 2>&1; rc=$?
check_rc "answer to a gone session exits 1" 1 "$rc"
rm "$HERDR_FAKE/s2.states"
bash "$s/read.sh" s2 --roster "$roster" >/dev/null
out=$(bash "$s/watch.sh" --roster "$roster" 2>/dev/null); rc=$?
check_rc "watch with every session gone exits 1" 1 "$rc"
check "and says there is nothing to watch" "no live session in the roster $roster" "$(jq -r .error <<<"$out")"

finish
