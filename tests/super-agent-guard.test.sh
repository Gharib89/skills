#!/usr/bin/env bash
# super-agent's `guard`: the PreToolUse hook refuses an Edit, a Write, a shell
# redirection or an `mv` that targets the ledger, fleet or quota file and names the
# script that updates it; a call through that script passes; `--install` adds the hook
# to a Claude settings file once and `--status` says whether it is there.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

s=skills/super-agent/scripts
tmp=$(mktemp -d) || exit 2
trap 'rm -rf "$tmp"' EXIT
st=~/.local/state/super-agent
G() { bash "$s/guard.sh" <<<"$1" 2>"$tmp/err"; }
tool() { jq -cn --arg t "$1" --arg p "$2" '{tool_name: $t, tool_input: {file_path: $p}}'; }
bash_call() { jq -cn --arg c "$1" '{tool_name: "Bash", tool_input: {command: $c}}'; }
refused() { # <case> <input> <word the message names>
  G "$2"; local rc=$?
  check_rc "$1 is refused" 2 "$rc"
  check "$1 names the supported way" 1 "$(grep -c -- "$3" "$tmp/err")"
}
passes() { G "$2"; check_rc "$1 passes" 0 "$?"; }

# --- --help ------------------------------------------------------------------
out=$(bash "$s/guard.sh" --help 2>"$tmp/err"); rc=$?
check "--help opens with its usage line" "usage: guard" "$(sed -n 1p <<<"$out" | cut -d' ' -f1-2)"
check_rc "--help exits 0" 0 "$rc"

# --- a direct write is refused, naming the flag or subcommand ------------------
refused "an Edit of the ledger" "$(tool Edit "$st/ledger.json")" 'ledger.sh'
refused "a Write of the ledger" "$(tool Write "$st/ledger.json")" 'ledger.sh'
refused "an Edit of the fleet file" "$(tool Edit ~/.config/super-agent/fleet.json)" 'fleet.sh'
refused "a Write of the quota file" "$(tool Write "$st/quota.json")" 'quota.sh --fleet'
refused "a redirection into the ledger" "$(bash_call "jq .x $st/ledger.json > $st/ledger.json")" 'ledger.sh'
refused "a redirection to a quoted path with spaces" "$(bash_call "cat /tmp/new.json > '/home/a b/.local/state/super-agent/ledger.json'")" 'ledger.sh'
passes "a comparison in a jq filter over the ledger" "$(bash_call "jq '.a > 1' $st/ledger.json")"
passes "a quoted > in a read of the ledger" "$(bash_call "grep '<a>' $st/ledger.json")"
refused "a redirection to a double-quoted path with spaces" "$(bash_call "echo x > \"/home/a b/.config/super-agent/fleet.json\"")" 'fleet.sh'
refused "an appended redirection" "$(bash_call "echo '{}' >> $st/ledger.json")" 'ledger.sh'
refused "a mv over the ledger" "$(bash_call "mv /tmp/new.json $st/ledger.json")" 'ledger.sh'
refused "a tee into the fleet file" "$(bash_call "echo '{}' | tee ~/.config/super-agent/fleet.json")" 'fleet.sh'
refused "a sed -i on the ledger" "$(bash_call "sed -i s/a/b/ $st/ledger.json")" 'ledger.sh'
refused "a write after a chained command" "$(bash_call "cd /tmp && echo x > $st/quota.json")" 'quota.sh --fleet'

# --- the scripts' own writes, and reads, pass -----------------------------------
passes "ledger.sh pause" "$(bash_call "bash $s/ledger.sh --ledger $st/ledger.json pause acme/widgets#7")"
passes "fleet.sh pin" "$(bash_call "$s/fleet.sh --fleet ~/.config/super-agent/fleet.json pin acme/widgets box")"
passes "quota.sh --save" "$(bash_call "$s/quota.sh --fleet ~/.config/super-agent/fleet.json --save $st/quota.json --wake 1")"
refused "a cp onto the ledger" "$(bash_call "cp /tmp/new.json $st/ledger.json")" 'ledger.sh'
passes "a backup copy of the ledger" "$(bash_call "cp $st/ledger.json /tmp/ledger.bak")"
passes "a script call chained before an unrelated rm" "$(bash_call "bash $s/ledger.sh --ledger $st/ledger.json pause x; rm /tmp/foo")"
passes "a ledger.sh ruling whose text names rm and mv" "$(bash_call "bash $s/ledger.sh --ledger $st/ledger.json ruling 'may rm build output' --allow 'rm -rf build'; bash $s/ledger.sh --ledger $st/ledger.json need k --action 'mv the fixture'")"
refused "a mutating command after an env assignment and sudo" "$(bash_call "FOO=1 sudo rm $st/ledger.json")" 'ledger.sh'
passes "a read through jq" "$(bash_call "jq .entries $st/ledger.json > /tmp/out.json")"
passes "a read piped to tee" "$(bash_call "jq . $st/ledger.json | tee /tmp/out.json")"
passes "an Edit of another file" "$(tool Edit /repo/ledger.json)"
passes "a file that only looks like it" "$(tool Write "$st/ledger.json.md")"
passes "a call that is no JSON" "not json"

# --- --install and --status -----------------------------------------------------
cfg=$tmp/settings.json
check "status before install" false "$(bash "$s/guard.sh" --status --settings "$cfg" | jq .installed)"
check "status leaves a missing settings file missing" no "$([ -e "$cfg" ] && echo yes || echo no)"
out=$(bash "$s/guard.sh" --install --settings "$cfg"); rc=$?
check_rc "--install exits 0" 0 "$rc"
check "--install reports a change" true "$(jq .changed <<<"$out")"
check "the settings hold one PreToolUse hook" 1 "$(jq '.hooks.PreToolUse | length' "$cfg")"
check "status after install" true "$(bash "$s/guard.sh" --status --settings "$cfg" | jq .installed)"
check "installing again changes nothing" false "$(bash "$s/guard.sh" --install --settings "$cfg" | jq .changed)"
check "and adds no second hook" 1 "$(jq '.hooks.PreToolUse | length' "$cfg")"
printf '%s\n' '{"model":"x","hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"other"}]}]}}' > "$cfg"
bash "$s/guard.sh" --install --settings "$cfg" >/dev/null
check "an existing hook and key are kept" '"x" 2' "$(jq -r '"\(.model|@json) \(.hooks.PreToolUse|length)"' "$cfg")"
for shape in '{"hooks":"x"}' '{"hooks":{"PreToolUse":{}}}'; do
  printf '%s\n' "$shape" > "$cfg"
  for m in --install --status; do
    out=$(bash "$s/guard.sh" "$m" --settings "$cfg" 2>/dev/null); rc=$?
    check_rc "$m on $shape exits 2" 2 "$rc"
    check "$m on $shape names the field" 1 "$(jq -r .error <<<"$out" | grep -c hooks)"
  done
done
mkdir -p "$tmp/dir.json"
for m in --install --status; do
  check_rc "$m on a settings path that cannot be read exits 2" 2 "$(bash "$s/guard.sh" "$m" --settings "$tmp/dir.json" >/dev/null 2>&1; echo $?)"
done
check "and the path is left a directory" yes "$([ -d "$tmp/dir.json" ] && echo yes || echo no)"
printf '{}\n' > "$cfg"; chmod 600 "$cfg"
(umask 022; bash "$s/guard.sh" --install --settings "$cfg" >/dev/null)
check "--install keeps the settings file's mode" 600 "$(stat -c %a "$cfg")"
check_rc "a settings file that is no JSON exits 2" 2 "$(printf 'x' > "$cfg"; bash "$s/guard.sh" --install --settings "$cfg" >/dev/null 2>&1; echo $?)"
# --- the default settings file is the super agent folder's, never user settings ----
export HOME=$tmp/u XDG_STATE_HOME=$tmp/state
hc=$XDG_STATE_HOME/super-agent/home/.claude/settings.local.json
check "--status reads the super agent folder's local settings by default" "$hc false" \
  "$(bash "$s/guard.sh" --status | jq -r '"\(.settings) \(.installed)"')"
bash "$s/guard.sh" --install >/dev/null
check "--install writes the folder's settings, and no user settings" "true absent" \
  "$(bash "$s/guard.sh" --status | jq .installed) $([ -e "$HOME/.claude/settings.json" ] && echo present || echo absent)"
check "no stale entry while user settings hold none" null "$(bash "$s/guard.sh" --status | jq -c .stale)"
mkdir -p "$HOME/.claude"
old='{"matcher":"Edit|Write|MultiEdit|NotebookEdit|Bash","hooks":[{"type":"command","command":"bash '\''/old/copy/super-agent/scripts/guard.sh'\''"}]}'
jq -n --argjson o "$old" '{model: "x", hooks: {PreToolUse: [$o, {matcher: "Bash", hooks: [{type: "command", command: "other"}]}]}}' > "$HOME/.claude/settings.json"
out=$(bash "$s/guard.sh" --status)
check "a stale entry left in user settings is reported with the line to remove" "$HOME/.claude/settings.json $old" \
  "$(jq -r '.stale.settings' <<<"$out") $(jq -c '.stale.entries[]' <<<"$out")"

stale_of() { # <command>: the stale entries --status finds for a user-settings entry running it
  jq -n --arg c "$1" '{hooks: {PreToolUse: [{matcher: "Bash", hooks: [{type: "command", command: $c}]}]}}' > "$HOME/.claude/settings.json"
  bash "$s/guard.sh" --status | jq -c '.stale.entries // [] | length'
}
check "a double-quoted guard command is stale too" 1 "$(stale_of 'bash "/x/super-agent/scripts/guard.sh"')"
check "a trailing space still reads as the guard" 1 "$(stale_of "bash '/x/super-agent/scripts/guard.sh' ")"
check "a bare path is the guard" 1 "$(stale_of /x/super-agent/scripts/guard.sh)"
check "another skill's guard.sh is not" 0 "$(stale_of "bash '/x/my-super-agent/scripts/guard.sh'")"
check "a script beside it is not" 0 "$(stale_of "bash '/x/super-agent/scripts/guard.sh.bak'")"
q="$tmp/owner's skills/super-agent"; mkdir -p "$q" && cp -r "$s" "$q/"
c=$(bash "$q/scripts/guard.sh" --status | jq -r .entry.hooks[0].command)
check "a guard path holding a quote is one shell word" "$q/scripts/guard.sh" "$(eval "set -- ${c#bash }"; printf %s "$1")"
printf 'not json' > "$HOME/.claude/settings.json"
check "user settings that are no JSON are unreadable, never no entry" true "$(bash "$s/guard.sh" --status | jq .stale.unreadable)"
: > "$HOME/.claude/settings.json"
check "empty user settings are unreadable" true "$(bash "$s/guard.sh" --status | jq .stale.unreadable)"
printf 'null' > "$HOME/.claude/settings.json"
check "user settings holding null are unreadable" true "$(bash "$s/guard.sh" --status | jq .stale.unreadable)"

# --- the wake timer: --install prints its unit files, --status reads systemctl ----
source tests/super-agent-fake.sh
export SA_FAKE=$tmp/fake
mkdir -p "$tmp/bin" "$SA_FAKE"; sa_fake_install "$tmp/bin"
export PATH="$tmp/bin:$PATH"
out=$(bash "$s/guard.sh" --install)
check "--install prints the timer's service and timer units and where they go" "1 1 $HOME/.config/systemd/user" \
  "$(jq -r .timer.service <<<"$out" | grep -c "^ExecStart=.*super-agent/scripts/wake-timer.sh") $(jq -r .timer.timer <<<"$out" | grep -c '^OnUnitActiveSec=5min$') $(jq -r .timer.dir <<<"$out")"
check "and the line that enables it" "systemctl --user daemon-reload && systemctl --user enable --now super-agent-wake.timer" "$(jq -r .timer.enable <<<"$out")"
check "--status reports a running timer through systemctl" true "$(bash "$s/guard.sh" --status | jq .timer.active)"
: > "$SA_FAKE/timer-inactive"
check "and a stopped one" false "$(bash "$s/guard.sh" --status | jq .timer.active)"

finish
