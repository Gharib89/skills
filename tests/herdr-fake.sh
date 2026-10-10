# A fake `herdr` for drive-session's tests: it answers the subcommands the
# scripts call from per-agent state files, and records every call. Sourced,
# never run.
#
#   bin=$(mktemp -d); source tests/herdr-fake.sh; herdr_fake_install "$bin"
#   export PATH="$bin:$PATH" HERDR_FAKE=<state dir>
#   printf 'done 5\nworking 6\ndone 7\n' > "$HERDR_FAKE/s1.states"
#
# `<name>.states` holds one `<status> <state_change_seq>` per line; each
# `agent get` answers the first line and drops it while more than one is left,
# so the last line repeats. No states file is an agent Herdr does not know:
# `agent_not_found` on stderr, exit 1, as the real CLI answers. `<name>.start-error`
# makes `agent start` fail with the code it holds, `<name>.prompt-error` the
# same for `agent prompt`; `<name>.start-busy` holds how many `agent start`
# calls answer `agent_pane_busy` first, the shell not yet up in a new tab.
# `agent prompt` refuses an agent whose current line reads `blocked` with
# `agent_blocked`, and `agent read` refuses it any source but `visible` with
# `agent_not_idle`, as herdr 0.9.3 does past the viewport. Every call is a line
# of `$HERDR_FAKE/calls`.
herdr_fake_install() { # <dir>
  cat > "$1/herdr" <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$HERDR_FAKE/calls"
err() { printf '{"error":{"code":"%s","message":"%s"},"id":"cli"}\n' "$1" "$2" >&2; exit 1; }
agent() { # <name> <status> <seq>
  printf '{"agent":"claude","name":"%s","agent_status":"%s","state_change_seq":%s,"pane_id":"w1:p-%s","tab_id":"w1:t-%s"}' "$1" "$2" "$3" "$1" "$1"
}
known() { # <name>: agent_not_found unless the agent has a states file
  [ -f "$HERDR_FAKE/$1.states" ] || err agent_not_found "agent target $1 not found"
}
case "$1 $2" in
  "tab create")
    label=x; while [ $# -gt 0 ]; do [ "$1" = --label ] && label=$2; shift; done
    printf '{"result":{"root_pane":{"pane_id":"w1:p-%s"},"tab":{"tab_id":"w1:t-%s"},"type":"tab_created"}}\n' "$label" "$label" ;;
  "agent start")
    [ -f "$HERDR_FAKE/$3.start-error" ] && err "$(cat "$HERDR_FAKE/$3.start-error")" "start failed"
    busy=$(cat "$HERDR_FAKE/$3.start-busy" 2>/dev/null || echo 0)
    [ "$busy" -gt 0 ] && { echo $((busy - 1)) > "$HERDR_FAKE/$3.start-busy"; err agent_pane_busy "pane is not an available shell"; }
    known "$3"; read -r st seq < "$HERDR_FAKE/$3.states"
    printf '{"result":{"agent":%s,"type":"agent_started"}}\n' "$(agent "$3" "$st" "$seq")" ;;
  "agent get")
    f=$HERDR_FAKE/$3.states
    known "$3"; read -r st seq < "$HERDR_FAKE/$3.states"
    [ "$(wc -l < "$f")" -gt 1 ] && { tail -n +2 "$f" > "$f.t"; mv "$f.t" "$f"; }
    printf '{"result":{"agent":%s,"type":"agent_info"}}\n' "$(agent "$3" "$st" "$seq")" ;;
  "agent prompt")
    [ -f "$HERDR_FAKE/$3.prompt-error" ] && err "$(cat "$HERDR_FAKE/$3.prompt-error")" "prompt failed"
    known "$3"; read -r st _ < "$HERDR_FAKE/$3.states"
    [ "$st" = blocked ] && err agent_blocked "agent $3 is blocked and requires interactive input"
    printf '{"result":{"type":"agent_prompted"}}\n' ;;
  "agent send-keys")
    known "$3"
    printf '{"result":{"type":"ok"}}\n' ;;
  "agent read")
    known "$3"; read -r st _ < "$HERDR_FAKE/$3.states"
    [ "$st" = blocked ] && [ "$5" != visible ] && err agent_not_idle "agent $3 is not idle"
    printf 'output of %s\n' "$3" ;;
  *) err unknown_command "the fake does not answer: $*" ;;
esac
FAKE
  chmod +x "$1/herdr"
}
