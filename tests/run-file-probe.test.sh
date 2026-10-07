#!/usr/bin/env bash
# skills/ship/scripts/run-file.sh `probe`: the line a self-review decline's claim
# owes is written by the mechanic that ran the command, carrying its exit status
# and the head it ran on. The seam is `run-file probe <ref> --file <run file> --
# <command>...`: an exit code, one JSON answer, and the Run file's bytes. Driven
# end to end over a copy of the mechanic in a fixture checkout.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
bin=$T/bin repo=$T/repo
mkdir -p "$bin"
cp skills/ship/scripts/run-file.sh skills/ship/scripts/_lib.sh "$bin/"

git init -q -b main "$repo"
g() { git -C "$repo" -c user.email=t@t -c user.name=t -c commit.gpgsign=false "$@"; }
mkdir "$repo/sub"
printf 'line one\nline two\n' > "$repo/notes.txt"
g add -A && g commit -qm base
head=$(g rev-parse HEAD)

rf=$(cd "$repo" && bash "$bin/run-file.sh" init 9 --scratchpad "$T/sp" --state 4=open | jq -r .run_file)
# probe <cwd> <args>...: sets out and status for one call.
probe() { local d=$1; shift; out=$(cd "$d" && bash "$bin/run-file.sh" probe "$@" 2>/dev/null); status=$?; }

# --- the command's exit is recorded, never the probe's own ---------------------------

probe "$repo/sub" C1 --file "$rf" -- cat notes.txt
check_rc "a command that exits 0 records and exits 0" 0 "$status"
check "the answer names the ref, the command, its exit, the head and its last line" \
  "{\"run_file\":\"$rf\",\"ref\":\"C1\",\"command\":\"cat notes.txt\",\"exit\":0,\"head\":\"$head\",\"last\":\"line two\"}" \
  "$(jq -c . <<<"$out")"
check "the line lands under ## Evidence, run at the checkout top" \
  "## Evidence

Probe: C1: cat notes.txt => exit 0 at $head: line two" \
  "$(sed -n '/^## Evidence$/,$p' "$rf")"

probe "$repo" 'copilot r1 t2' --file "$rf" -- sh -c 'echo first; echo why it failed >&2; exit 3'
check_rc "a command that exits non-zero still exits 0" 0 "$status"
check "the non-zero exit and the last line of stdout and stderr are recorded" \
  "Probe: copilot r1 t2: sh -c echo first; echo why it failed >&2; exit 3 => exit 3 at $head: why it failed" \
  "$(tail -n 1 "$rf")"

probe "$repo" C2 --file "$rf" -- true
check "a command with no output says so" "Probe: C2: true => exit 0 at $head: (no output)" "$(tail -n 1 "$rf")"

probe "$repo" C3 --file "$rf" -- cat
check_rc "the command reads no terminal: stdin is /dev/null" 0 "$status"
check "so a command waiting on stdin ends at once" "Probe: C3: cat => exit 0 at $head: (no output)" "$(tail -n 1 "$rf")"

probe "$repo" C4 --file "$rf" -- sh -c 'echo "$0"' '$(touch pwned)'
check "the command runs as argv, never through a shell string" no "$([ -e "$repo/pwned" ] && echo yes || echo no)"

# --- the call itself -----------------------------------------------------------------

held=$(cat "$rf")
probe "$repo" --file "$rf" -- true
check_rc "no ref is a usage error" 2 "$status"
probe "$repo" C5 --file "$rf" --
check_rc "no command is a usage error" 2 "$status"
probe "$repo" C5 --file "$rf" true
check_rc "a command without the -- separator is a usage error" 2 "$status"
probe "$repo" 'C5: x' --file "$rf" -- true
check_rc "a ref holding ': ' names no decline and is refused" 2 "$status"
check "a refused call writes nothing" "$held" "$(cat "$rf")"

finish
