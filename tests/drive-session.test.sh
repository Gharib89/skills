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
check "the refusal reaches no herdr" "" "$(calls)"
bash "$s/spawn.sh" Bad --roster "$roster" --cwd "$tmp/cwd" --prompt x >/dev/null 2>&1; rc=$?
check_rc "spawn refuses a name Herdr would refuse" 2 "$rc"

# A session that stops on a startup dialog (an untrusted folder) is a row whose
# status is blocked and whose task is not yet sent, not a failed spawn.
printf 'agent_not_ready' > "$HERDR_FAKE/s2.start-error"
printf 'blocked 20\n' > "$HERDR_FAKE/s2.states"
out=$(bash "$s/spawn.sh" s2 --roster "$roster" --cwd "$tmp/cwd" --prompt "task two"); rc=$?
check_rc "spawn on a startup dialog exits 0" 0 "$rc"
check "spawn on a startup dialog answers blocked, unprompted" 'blocked false' "$(jq -r '"\(.status) \(.prompted)"' <<<"$out")"
check "spawn on a startup dialog sends no prompt" 0 "$(calls | grep -c 'agent prompt')"
check "the blocked row is in the roster" 20 "$(seen s2)"

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
check_rc "an agent answer watch cannot read fails rather than polling on" 1 "$rc"
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
bash "$s/read.sh" s9 --roster "$roster" >/dev/null 2>&1; rc=$?
check_rc "read refuses a session the roster does not hold" 1 "$rc"
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
bash "$s/answer.sh" s2 --roster "$roster" --text a --keys b >/dev/null 2>&1; rc=$?
check_rc "answer takes text or keys, not both" 2 "$rc"
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
