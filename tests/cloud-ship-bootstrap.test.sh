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

# <case> <apt mode>: a bin dir with `id`, a pass-through `sudo` and an
# `apt-get` that logs its arguments to <bin>/calls; prints its path. Modes:
# `installs` installs each named package as a stub tool; `stale` fails an
# install until an `update` has run, as a fresh image with no package lists
# does; `broken` fails every call; `inert` succeeds and installs nothing.
bindir() {
  local b="$fixture/bin-$1"; mkdir -p "$b"
  ln -s "$(command -v id)" "$b/id"
  printf '#!%s\nexec "$@"\n' "$bash_bin" > "$b/sudo"
  cat > "$b/apt-get" <<FAKE
#!$bash_bin
echo "apt-get \$*" >> "$b/calls"
mode=$2
[ "\$mode" = broken ] && exit 100
if [ "\$1" = update ]; then : > "$b/updated"; exit 0; fi
[ "\$mode" = stale ] && [ ! -e "$b/updated" ] && exit 100
[ "\$mode" = inert ] && exit 0
shift 2
for p in "\$@"; do printf '#!/bin/sh\\n' > "$b/\$p"; $(command -v chmod) +x "$b/\$p"; done
FAKE
  chmod +x "$b/sudo" "$b/apt-get"
  printf '%s' "$b"
}
tool() { printf '#!/bin/sh\n' > "$1/$2"; chmod +x "$1/$2"; }
rc_of() { PATH=$1 "$bash_bin" "$script" >/dev/null 2>&1; printf '%s' "$?"; }

b=$(bindir both installs); tool "$b" shellcheck; tool "$b" gitleaks
check_rc "both tools on PATH is a pass" 0 "$(rc_of "$b")"
check "both tools on PATH reaches no apt" "" "$(cat "$b/calls" 2>/dev/null)"

b=$(bindir one installs); tool "$b" shellcheck
check_rc "a missing tool apt installs is a pass" 0 "$(rc_of "$b")"
check "only the missing tool is asked for" "apt-get install -y gitleaks" "$(cat "$b/calls")"

b=$(bindir stale stale); tool "$b" shellcheck
check_rc "an install that needs fresh package lists is a pass" 0 "$(rc_of "$b")"
check "a failed install refreshes the lists once and retries" \
  "apt-get install -y gitleaks
apt-get update
apt-get install -y gitleaks" "$(cat "$b/calls")"

b=$(bindir broken broken); tool "$b" shellcheck
rc=$(rc_of "$b")
check "an apt whose update fails too exits non-zero, bootstrap-failed" nonzero "$([ "$rc" -ne 0 ] && echo nonzero)"

b=$(bindir inert inert)
check_rc "a tool still missing after apt fails" 1 "$(rc_of "$b")"

finish
