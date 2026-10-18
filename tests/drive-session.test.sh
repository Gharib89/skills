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
for m in spawn watch read answer frontier; do
  out=$(bash "$s/$m.sh" --help 2>"$tmp/err"); rc=$?
  check "$m --help opens with its usage line" "usage: $m" "$(sed -n 1p <<<"$out" | cut -d' ' -f1-2)"
  check "$m --help names its stdout fields next" stdout: "$(sed -n 2p <<<"$out" | cut -c1-7)"
  check_rc "$m --help exits 0" 0 "$rc"
  check "$m --help writes nothing on stderr" "" "$(cat "$tmp/err")"
  out=$(bash "$s/$m.sh" 2>/dev/null); rc=$?
  check "$m: a bare call answers its usage line" "$(sed -n 1p <<<"$(bash "$s/$m.sh" --help)")" "$(jq -r .error <<<"$out")"
  check_rc "$m: a bare call exits 2" 2 "$rc"
done
# Outside Herdr every roster script refuses before it touches anything.
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
check "spawn opens an unfocused tab in this workspace, starts claude on the model, then prompts until the turn starts or opens a dialog" \
  "tab create --workspace w1 --label s1 --cwd $tmp/cwd --no-focus
agent start s1 --kind claude --pane w1:p-s1 -- --model haiku
agent prompt s1 do the task --wait --until working --until blocked --timeout 8000" "$(calls)"
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
check "a failed first spawn still leaves an empty roster" '{"sessions":[]}' "$(jq -c . "$tmp/s6.json")"
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

# A prompt that starts no turn (a local slash command, an Enter that did not
# register) never moves the sequence number, so watch would never report it:
# spawn says so instead, and keeps the row.
printf 'idle 60\n' > "$HERDR_FAKE/s7.states"
: > "$HERDR_FAKE/s7.prompt-stall"
out=$(bash "$s/spawn.sh" s7 --roster "$tmp/s7.json" --cwd "$tmp/cwd" --prompt "/rename x" 2>/dev/null); rc=$?
check_rc "spawn whose prompt starts no turn exits 1" 1 "$rc"
check "the answer carries herdr's code" agent_prompt_stalled "$(jq -r .code <<<"$out")"
check "the answer names the session and says the text reached its pane" \
  "agent prompt: the text reached s7's pane but started no turn (agent_prompt_stalled); it stays in the roster with tab w1:t-s7 open: read it before sending anything" \
  "$(jq -r .error <<<"$out")"
check "the stalled session keeps its row" s7 "$(jq -r '.sessions[0].name' "$tmp/s7.json")"
calls >/dev/null

# --- watch -----------------------------------------------------------------------
# The measured trap: after a prompt, status reads the previous turn's `done`
# until the turn starts. A settled status whose sequence number has not moved
# past the row's is no event.
# A case that asserts on more than one poll gives its timeout room for those
# polls on a loaded machine, where each one can take seconds (#597).
printf 'done 10\n' > "$HERDR_FAKE/s1.states"
printf 'blocked 20\n' > "$HERDR_FAKE/s2.states"
out=$(bash "$s/watch.sh" --roster "$roster" --timeout 5000); rc=$?
check_rc "watch on stale states exits 0 at its timeout" 0 "$rc"
check "watch never reports a stale done or an acknowledged blocked" null "$(jq -c .name <<<"$out")"
check "its timeout lists each session's status and sequence number" \
  '{"event":"timeout","sessions":[{"name":"s1","status":"done","seq":10},{"name":"s2","status":"blocked","seq":20}]}' \
  "$(jq -c '{event, sessions: [.sessions[] | {name, status, seq}]}' <<<"$out")"
check "and how long each sequence number stood still, in seconds" true \
  "$(jq '[.sessions[].still_s] | all(type == "number" and . >= 1)' <<<"$out")"
# A sequence number that moves starts its count again: a session working
# through 70, 71 and 72 has stood still only since 72, at least two seconds (the
# sleeps before the third poll) less long than one beside it whose number never
# moved.
for w in w1 w2; do
  printf 'idle 69\n' > "$HERDR_FAKE/$w.states"
  bash "$s/spawn.sh" "$w" --roster "$tmp/moved.json" --cwd "$tmp/cwd" --prompt x >/dev/null
done
printf 'working 70\nworking 71\nworking 72\n' > "$HERDR_FAKE/w1.states"
printf 'working 70\n' > "$HERDR_FAKE/w2.states"
out=$(bash "$s/watch.sh" --roster "$tmp/moved.json" --timeout 8000)
check "a moved sequence number restarts still_s" '72 true' \
  "$(jq -r '.sessions | "\(.[0].seq) \(.[0].still_s + 2 <= .[1].still_s)"' <<<"$out")"
calls >/dev/null

printf 'working 11\ndone 12\n' > "$HERDR_FAKE/s1.states"
out=$(bash "$s/watch.sh" --roster "$roster" --timeout 30000)
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
bash "$s/read.sh" s1 --roster "$roster" >/dev/null
check "read takes 40 lines by default" "agent get s1
agent read s1 --source recent-unwrapped --lines 40" "$(calls)"
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
agent prompt s2 task two --wait --until working --until blocked --timeout 8000" "$(calls)"
check "answer with text records the sequence number before the prompt" 23 "$(seen s2)"
# A send Herdr refuses acknowledges nothing, so watch reports the event again.
printf 'idle 24\n' > "$HERDR_FAKE/s2.states"
printf 'agent_busy' > "$HERDR_FAKE/s2.prompt-error"
bash "$s/answer.sh" s2 --roster "$roster" --text again >/dev/null 2>&1; rc=$?
check_rc "an answer Herdr refuses exits 1" 1 "$rc"
check "a refused send leaves the row's sequence number" 23 "$(seen s2)"
rm "$HERDR_FAKE/s2.prompt-error"
: > "$HERDR_FAKE/s2.prompt-stall"
out=$(bash "$s/answer.sh" s2 --roster "$roster" --text "/help" 2>/dev/null); rc=$?
check_rc "an answer that starts no turn exits 1" 1 "$rc"
check "its answer carries herdr's code and names the session" \
  "agent_prompt_stalled agent prompt s2: the text reached the pane but started no turn (agent_prompt_stalled): read s2 before sending anything" \
  "$(jq -r '"\(.code) \(.error)"' <<<"$out")"
rm "$HERDR_FAKE/s2.prompt-stall"
printf 'timeout' > "$HERDR_FAKE/s2.prompt-error"
out=$(bash "$s/answer.sh" s2 --roster "$roster" --text "/help" 2>/dev/null); rc=$?
check "herdr's own timeout is the same answer" \
  "1 timeout agent prompt s2: the text reached the pane but started no turn (timeout): read s2 before sending anything" \
  "$rc $(jq -r '"\(.code) \(.error)"' <<<"$out")"
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
agent prompt s2 - continue --wait --until working --until blocked --timeout 8000" "$(calls)"
bash "$s/answer.sh" s2 --roster "$roster" --text= >/dev/null 2>&1; rc=$?
check_rc "answer refuses an empty --text=" 2 "$rc"
printf 'idle 40\n' > "$HERDR_FAKE/s4.states"
bash "$s/spawn.sh" s4 --roster "$tmp/s4.json" --cwd "$tmp/cwd" --prompt="- review these items" >/dev/null; rc=$?
check_rc "spawn takes a dash-led task as --prompt=" 0 "$rc"
check "spawn prompts the dash-led task verbatim" "agent prompt s4 - review these items --wait --until working --until blocked --timeout 8000" "$(calls | grep 'agent prompt')"
usage_line=$(sed -n 1p <<<"$(bash "$s/answer.sh" --help)")
out=$(bash "$s/answer.sh" s2 --roster "$roster" --text a --keys b 2>/dev/null); rc=$?
check_rc "answer takes text or keys, not both" 2 "$rc"
check "text and keys together answer the usage line" "$usage_line" "$(jq -r .error <<<"$out")"
calls >/dev/null

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

# --- gone ----------------------------------------------------------------------
rm "$HERDR_FAKE/s1.states"
out=$(bash "$s/watch.sh" --roster "$roster" --timeout 3000)
check "a session Herdr no longer knows is gone" '{"name":"s1","event":"gone"}' "$out"
out=$(bash "$s/read.sh" s1 --roster "$roster")
check "read answers a gone session with no output" '{"name":"s1","status":"gone","seq":null,"output":null}' "$(jq -c . <<<"$out")"
check "read marks the row gone" true "$(jq -r '.sessions[0].gone' "$roster")"
out=$(bash "$s/watch.sh" --roster "$roster" --timeout 1000)
check "a gone row is not watched again" '["s2"]' "$(jq -c '[.sessions[].name]' <<<"$out")"
bash "$s/answer.sh" s1 --roster "$roster" --text hi >/dev/null 2>&1; rc=$?
check_rc "answer to a gone session exits 1" 1 "$rc"
rm "$HERDR_FAKE/s2.states"
bash "$s/read.sh" s2 --roster "$roster" >/dev/null
out=$(bash "$s/watch.sh" --roster "$roster" 2>/dev/null); rc=$?
check_rc "watch with every session gone exits 1" 1 "$rc"
check "and says there is nothing to watch" "no live session in the roster $roster" "$(jq -r .error <<<"$out")"

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
gh_reset
for bad in "--parent x" "--parent 0" "--parent" "--parent -1" "--parent 1 --roster r" "1"; do
  # shellcheck disable=SC2086  # the call's words are split on purpose
  out=$(HERDR_ENV='' bash "$s/frontier.sh" $bad 2>/dev/null); rc=$?
  check_rc "frontier refuses '$bad'" 2 "$rc"
  check "frontier answers '$bad' with its usage line" "usage: frontier --parent <n>" "$(jq -r .error <<<"$out")"
done
check "a refused call reaches no gh" "" "$(gh_args)"

finish
