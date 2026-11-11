#!/usr/bin/env bash
# scripts/contract-check.sh and a mechanic whose bare invocation is a real run:
# the `# contract: bare-run` header marker exempts it where the hardcoded list
# of eight does, and every mechanic the check runs sees an empty home and empty
# XDG directories. The fixture is a mechanic with a default path, in a directory
# of its own beside the real `_lib.sh` and host adapters, so the host-failure
# check runs it bare.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
source tests/contract-gate-lib.sh

# <case-dir> <marker line, or empty>: a scanner mechanic whose bare call logs
# the home and XDG directories it sees to $SCAN_LOG, and whether a file planted
# in that home is there.
scanner() {
  local d; d=$(copy_mechanics "$1")
  { printf '#!/usr/bin/env bash\n# stdout: {scanned}\n'
    [ -n "$2" ] && printf '%s\n' "$2"
    cat <<'EOS'
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh" || { printf '{"error":"cannot source _lib.sh"}\n'; exit 2; }
usage='usage: scanner [--path <dir>]'
ship_help "$usage" "$@"
[ $# -eq 0 ] || ship_tooling "$usage"
ship_load_host
printf 'home=%s config=%s state=%s planted=%s\n' "$HOME" "${XDG_CONFIG_HOME:-}" "${XDG_STATE_HOME:-}" \
  "$([ -e "$HOME/planted" ] && echo yes || echo no)" >> "${SCAN_LOG:-/dev/null}"
printf '{"scanned":true}\n'
EOS
  } > "$d/scanner.sh"
  printf '%s' "$d"
}

d=$(scanner marked '# contract: bare-run')
run "$d"
check_rc "a mechanic with the marker and a default path passes the contract check" 0 "$rc"

d=$(scanner unmarked '')
run "$d"
check_rc "the same mechanic without the marker fails it" 1 "$rc"
check "naming the mechanic and its bare exit" 'scanner: bare invocation exited 0, expected 2' "$out"

# The marker is read from the header, not from anywhere in the file.
d=$(scanner late-marker '')
{ printf '%.0s# filler\n' $(seq 70); echo '# contract: bare-run'; } >> "$d/scanner.sh"
run "$d"
check_rc "a marker past the header's first 60 lines does not count" 1 "$rc"

# The hardcoded list keeps working unedited.
run skills/ship/scripts
check_rc "the real mechanics, listed ones unedited, pass" 0 "$rc"

# A file planted in the real home and XDG directories is not readable by a bare
# invocation the check makes.
d=$(scanner planted '# contract: bare-run')
home=$fixture/home; mkdir -p "$home/config" "$home/state"
: > "$home/planted"; : > "$home/config/planted"; : > "$home/state/planted"
log=$fixture/scan.log; : > "$log"
HOME=$home XDG_CONFIG_HOME=$home/config XDG_STATE_HOME=$home/state SCAN_LOG=$log \
  bash scripts/contract-check.sh "$d" skills >/dev/null 2>&1
check "the check ran the mechanic bare" 1 "$([ -s "$log" ] && echo 1 || echo 0)"
check "none of its runs saw the planted file" 0 "$(grep -c 'planted=yes' "$log")"
check "none ran in the real home" 0 "$(grep -c "home=$home" "$log")"
check "none ran in the real XDG config directory" 0 "$(grep -c "config=$home/config" "$log")"
check "none ran in the real XDG state directory" 0 "$(grep -c "state=$home/state" "$log")"

finish
