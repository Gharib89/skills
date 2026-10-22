#!/usr/bin/env bash
# `spawn` presses Enter once when its first prompt stalls (`agent_prompt_stalled`:
# the text reached the pane, no turn started) before it fails, since every stall
# in the #819 batch cleared with one Enter. Driven over the fake `herdr`
# (tests/herdr-fake.sh): a `enter` stall clears on the key, any other survives it.
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
# The keys and waits spawn sent, with the prompt they follow.
keys() { grep -E '^agent (prompt|send-keys|wait)' "$HERDR_FAKE/calls"; : > "$HERDR_FAKE/calls"; }
spawn() { # <name> <seq> <prompt>
  printf 'idle %s\n' "$2" > "$HERDR_FAKE/$1.states"
  out=$(bash "$s/spawn.sh" "$1" --roster "$tmp/$1.json" --cwd "$tmp/cwd" --prompt "$3" 2>/dev/null); rc=$?
}

# A first stall that one Enter clears: the retry starts the agent.
printf enter > "$HERDR_FAKE/a.prompt-stall"
spawn a 61 "task a"
check_rc "a first stall cleared by Enter exits 0" 0 "$rc"
check "its answer reads as an ordinary spawn" '{"name":"a","prompted":true}' "$(jq -c '{name, prompted}' <<<"$out")"
check "the Enter goes between the prompt and the wait for its turn" \
  "agent prompt a task a --wait --until working --until blocked --timeout 8000
agent send-keys a Enter
agent wait a --until working --until blocked --timeout 8000" "$(keys)"
check "the row keeps the sequence number from before the prompt" 61 "$(jq -r '.sessions[0].seen_seq' "$tmp/a.json")"

# A second stall fails with the message a stall gave before the retry existed.
: > "$HERDR_FAKE/b.prompt-stall"
spawn b 62 "/rename x"
check_rc "a second stall exits 1" 1 "$rc"
check "it carries herdr's code" agent_prompt_stalled "$(jq -r .code <<<"$out")"
check "it names the session and says the text reached its pane" \
  "agent prompt: the text reached b's pane but started no turn (agent_prompt_stalled); it stays in the roster with tab w1:t-b open: read it before sending anything" \
  "$(jq -r .error <<<"$out")"
check "the stalled session keeps its row" b "$(jq -r '.sessions[0].name' "$tmp/b.json")"
check "one Enter and one wait were all it tried" \
  "agent prompt b /rename x --wait --until working --until blocked --timeout 8000
agent send-keys b Enter
agent wait b --until working --until blocked --timeout 8000" "$(keys)"

# A retry herdr refuses (the pane gone since the stall) carries that refusal, not
# the stall's code, and does not tell the supervisor to read a session that is gone.
: > "$HERDR_FAKE/f.prompt-stall"; printf agent_not_found > "$HERDR_FAKE/f.keys-error"
spawn f 66 "task f"
check_rc "a retry herdr refuses exits 1" 1 "$rc"
check "it carries the retry's code" agent_not_found "$(jq -r .code <<<"$out")"
check "and its message names the open tab, not a read" \
  "agent prompt: send-keys failed; f stays in the roster with tab w1:t-f open: send the task with answer --text" "$(jq -r .error <<<"$out")"
keys >/dev/null

# Nothing else is retried: a prompt that starts its turn sends no key, and a
# refusal that is no stall (or herdr's own timeout) fails as it did.
spawn c 63 "task c"
check "a prompt that starts its turn sends no key" "agent prompt c task c --wait --until working --until blocked --timeout 8000" "$(keys)"
printf agent_busy > "$HERDR_FAKE/d.prompt-error"
spawn d 64 "task d"
check_rc "a refusal that is no stall exits 1" 1 "$rc"
check "and is not retried" "agent prompt d task d --wait --until working --until blocked --timeout 8000" "$(keys)"
printf timeout > "$HERDR_FAKE/e.prompt-error"
spawn e 65 "task e"
check_rc "herdr's own timeout exits 1" 1 "$rc"
check "and is not retried either" "agent prompt e task e --wait --until working --until blocked --timeout 8000" "$(keys)"

finish
