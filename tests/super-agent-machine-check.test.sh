#!/usr/bin/env bash
# super-agent's machine check (#1382): `machine-check.sh <machine> <check>` runs one
# fixed, read-only command on a fleet machine over a fake `ssh` on PATH
# (tests/super-agent-fake.sh): each of the eight checks sends its own fixed command
# and prints the result, an unknown check, a process name that is no plain name and
# a log over 200 lines are refused before any call, an unreachable host is one
# attempt answering `unreachable` with SSH's reason, and a check needing root
# answers `needs-root` without calling sudo.
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
fleet=$tmp/fleet.json
printf '%s\n' '{"machines":{"server":{"environment_id":"env-s","ssh":"gharib@server","logs":["/var/log/app/deploy.log"]},"nas":{"ssh":"nas","check_only":true},"box":{"environment_id":"env-b"}}}' > "$fleet"
M() { bash "$s/machine-check.sh" --fleet "$fleet" "$@"; }
# the remote command of the last ssh call
sent() { tail -n1 "$SA_FAKE/ssh-calls" | cut -f2-; }
calls() { grep -c '^ssh ' "$SA_FAKE/calls" 2>/dev/null || echo 0; }

# --- the contract every script keeps ------------------------------------------
out=$(bash "$s/machine-check.sh" --help 2>"$tmp/err"); rc=$?
check "--help opens with its usage line" "usage: machine-check" "$(sed -n 1p <<<"$out" | cut -d' ' -f1-2)"
check "--help names its stdout fields next" stdout: "$(sed -n 2p <<<"$out" | cut -c1-7)"
check_rc "--help exits 0" 0 "$rc"
check "--help writes nothing on stderr" "" "$(cat "$tmp/err")"

# --- each check sends one fixed command and prints its result -----------------------
sa_ssh gharib@server 0 'remote says hi'
declare -A sent_by
for c in up load disk gpu t3 clis; do
  out=$(M server $c); rc=$?
  check_rc "$c exits 0" 0 "$rc"
  check "$c prints its result" "server $c ok remote says hi" "$(jq -r '"\(.machine) \(.check) \(.result) \(.output)"' <<<"$out")"
  sent_by[$c]=$(sent)
done
check "up sends its fixed command" 'echo up' "${sent_by[up]}"
check "load sends its fixed command" 'cat /proc/loadavg; free -m' "${sent_by[load]}"
check "disk sends its fixed command" 'df -hP -x tmpfs -x devtmpfs -x squashfs -x overlay' "${sent_by[disk]}"
check "gpu sends its fixed command" 'nvidia-smi --query-gpu=name,memory.used,memory.total,utilization.gpu --format=csv,noheader' "${sent_by[gpu]}"
check "t3 sends its fixed command" 'systemctl --user is-active t3code.service; t3 --version' "${sent_by[t3]}"
check "clis sends its fixed command" 'for c in claude codex agy gh t3; do printf "%s: " "$c"; if command -v "$c" >/dev/null; then "$c" --version 2>&1 | head -n1; else echo missing; fi; done' "${sent_by[clis]}"
M server process sshd >/dev/null
check "process sends pgrep for the exact name" 'pgrep -c -x -- sshd || true' "$(sent)"
M server log ssh.service >/dev/null
check "log reads a unit's journal, system and user, 50 lines by default" 'journalctl -n 50 --no-pager -u ssh.service --user-unit ssh.service' "$(sent)"
M server log ssh.service 200 >/dev/null
check "log takes a line count up to 200" 'journalctl -n 200 --no-pager -u ssh.service --user-unit ssh.service' "$(sent)"
M server log /var/log/app/deploy.log 20 >/dev/null
check "log tails a file the fleet file lists for that machine" 'tail -n 20 -- /var/log/app/deploy.log' "$(sent)"
check "every check went to the machine's ssh string, with batch mode, strict host keys and a 6 second connect timeout" 0 \
  "$(grep '^ssh ' "$SA_FAKE/calls" | grep -vc -- '-o BatchMode=yes -o StrictHostKeyChecking=yes -o ConnectTimeout=6 gharib@server ')"
check "a check-only machine is checked like any other" "nas up ok" "$(M nas up | jq -r '"\(.machine) \(.check) \(.result)"')"
check "no check ever calls sudo" 0 "$(grep -c sudo "$SA_FAKE/ssh-calls")"

# --- refusals, before any call -----------------------------------------------------------
before=$(calls)
refused() { local out rc; out=$(M "$@" 2>/dev/null); rc=$?; printf '%s %s' "$rc" "$(jq -r '.error | length > 0' <<<"$out")"; }
check "an unknown check is refused" "2 true" "$(refused server rm)"
check "a free-form command is no check" "2 true" "$(refused server 'uptime; reboot')"
check "a process name that is no plain name is refused" "2 true" "$(refused server process 'ss;hd')"
check "a process name with a path is refused" "2 true" "$(refused server process /usr/sbin/sshd)"
check "a process name starting with a dash is refused" "2 true" "$(refused server process -9)"
check "a log over 200 lines is refused" "2 true" "$(refused server log ssh.service 201)"
check "a line count that is no number is refused" "2 true" "$(refused server log ssh.service 5x)"
check "a file the fleet file does not list is refused" "2 true" "$(refused server log /etc/shadow)"
check "a unit name with a shell character is refused" "2 true" "$(refused server log 'ssh;id')"
check "a machine the fleet file lacks is refused" "2 true" "$(refused laptop up)"
check "a machine with no ssh string is refused" "2 true" "$(refused box up)"
check "an extra argument to a fixed check is refused" "2 true" "$(refused server up now)"
check "no refusal made an ssh call" "$before" "$(calls)"

# --- unreachable: one attempt, SSH's reason, no retry ----------------------------
sa_ssh gharib@server 255 '' 'ssh: connect to host server port 22: Connection timed out'
before=$(calls)
out=$(M server load); rc=$?
check_rc "an unreachable host still exits 0: it is an answer" 0 "$rc"
check "it prints unreachable with SSH's reason" "unreachable ssh: connect to host server port 22: Connection timed out" "$(jq -r '"\(.result) \(.reason)"' <<<"$out")"
check "after exactly one attempt" "$((before + 1))" "$(calls)"
sa_ssh gharib@server 255 '' $'No ED25519 host key is known for server and you have requested strict checking.\nHost key verification failed.'
check "an unknown host key is named, never accepted" "unreachable unknown-host-key" "$(M server up | jq -r '"\(.result) \(.reason)"')"

# --- a check that needs root prints needs-root, and never calls sudo ------------------------
sa_ssh gharib@server 1 '' "tail: cannot open '/var/log/app/deploy.log' for reading: Permission denied"
out=$(M server log /var/log/app/deploy.log)
check "a permission failure is needs-root" needs-root "$(jq -r .result <<<"$out")"
sa_ssh gharib@server 0 '-- No entries --' 'Hint: You are currently not seeing messages from other users and the system.'
check "a journal hidden from this user is needs-root" needs-root "$(M server log ssh.service | jq -r .result)"
check "and still no sudo anywhere" 0 "$(grep -c sudo "$SA_FAKE/ssh-calls")"
sa_ssh gharib@server 9 '' 'nvidia-smi: command not found'
check "any other failure is failed, with the last error line" "failed nvidia-smi: command not found" "$(M server gpu | jq -r '"\(.result) \(.reason)"')"

finish
