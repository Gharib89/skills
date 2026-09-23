#!/usr/bin/env bash
# scripts/cloud-ship-bootstrap.sh: the profile's cloud-lane `Bootstrap:`. The
# subject is what it asks apt for and how it answers: nothing where both tools
# are on PATH, only the missing one otherwise, and a non-zero exit, which ship
# reads as `bootstrap-failed`, where the tool is still missing afterwards. apt,
# sudo and the tools are fakes on a PATH built for the case.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

fixture=$(mktemp -d); trap 'rm -rf "$fixture"' EXIT
script=$PWD/scripts/cloud-ship-bootstrap.sh
bash_bin=$(command -v bash)

# <case> <apt-installs: yes|no>: a bin dir with `id`, a pass-through `sudo` and
# an `apt-get` that logs its arguments to <bin>/calls and, given yes, installs
# each named package as a stub tool; prints its path.
bindir() {
  local b="$fixture/bin-$1"; mkdir -p "$b"
  ln -s "$(command -v id)" "$b/id"
  printf '#!%s\nexec "$@"\n' "$bash_bin" > "$b/sudo"
  printf '#!%s\necho "apt-get $*" >> "%s/calls"\n[ "$1" = install ] && [ %s = yes ] || exit 0\nshift 2\nfor p in "$@"; do printf "#!/bin/sh\\n" > "%s/$p"; %s +x "%s/$p"; done\n' \
    "$bash_bin" "$b" "$2" "$b" "$(command -v chmod)" "$b" > "$b/apt-get"
  chmod +x "$b/sudo" "$b/apt-get"
  printf '%s' "$b"
}
tool() { printf '#!/bin/sh\n' > "$1/$2"; chmod +x "$1/$2"; }
rc_of() { PATH=$1 "$bash_bin" "$script" >/dev/null 2>&1; printf '%s' "$?"; }

b=$(bindir both yes); tool "$b" shellcheck; tool "$b" gitleaks
check_rc "both tools on PATH is a pass" 0 "$(rc_of "$b")"
check "both tools on PATH reaches no apt" "" "$(cat "$b/calls" 2>/dev/null)"

b=$(bindir one yes); tool "$b" shellcheck
check_rc "a missing tool apt installs is a pass" 0 "$(rc_of "$b")"
check "only the missing tool is asked for" "apt-get install -y gitleaks" "$(cat "$b/calls")"

b=$(bindir none no)
check_rc "a tool still missing after apt fails" 1 "$(rc_of "$b")"

finish
