#!/usr/bin/env bash
# scripts/cloud-ship-bootstrap.sh: the profile's cloud-lane `Bootstrap:`. The
# subject is what it adds to the harness cloud setup and how it answers: nothing
# outside a cloud session, the harness profile's `Setup:` run first, the secrets
# scanner asked of apt only when missing, and a non-zero exit, which ship reads
# as `bootstrap-failed`, where a step fails or the scanner is still missing
# afterwards. apt, sudo and the scanner are fakes on a PATH built for the case.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

fixture=$(mktemp -d); trap 'rm -rf "$fixture"' EXIT
script=$PWD/scripts/cloud-ship-bootstrap.sh
bash_bin=$(command -v bash)

# <case> <apt mode>: a bin dir with `id`, `git`, `awk`, `bash`, a pass-through `sudo` and
# an `apt-get` that logs its arguments to <bin>/calls; prints its path. Modes:
# `installs` installs each named package as a stub tool; `stale` fails an
# install until an `update` has run, as a fresh image with no package lists
# does; `broken` fails every call; `inert` succeeds and installs nothing.
bindir() {
  local b="$fixture/bin-$1" t; mkdir -p "$b"
  for t in id git awk bash; do ln -s "$(command -v "$t")" "$b/$t"; done
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

# <case> <Setup: value>: a checkout carrying the bootstrap and a harness profile
# whose cloud setup, when it is a path, logs its run to <checkout>/setup.log.
repo() {
  local d="$fixture/repo-$1"
  mkdir -p "$d/scripts" "$d/docs/agents" || return 1
  cp "$script" "$d/scripts/" || return 1
  printf '# Harness profile\n\n## Cloud\n\nVerdict: cloud-first\nSetup: %s\n' "$2" > "$d/docs/agents/harness.md"
  printf '#!/usr/bin/env bash\necho ran >> "%s/setup.log"\n' "$d" > "$d/scripts/setup.sh"
  chmod +x "$d/scripts/setup.sh"
  git -C "$d" init -q || return 1
  printf '%s' "$d"
}
# <repo> <bin> [CLAUDE_CODE_REMOTE value]: run the bootstrap once, leaving `rc`.
boot() {
  (cd "$1" && PATH=$2 CLAUDE_CODE_REMOTE=${3-true} "$bash_bin" scripts/cloud-ship-bootstrap.sh >/dev/null 2>&1); rc=$?
}

d=$(repo ok scripts/setup.sh); b=$(bindir both installs); tool "$b" gitleaks
boot "$d" "$b"
check_rc "the scanner on PATH is a pass" 0 "$rc"
check "the scanner on PATH reaches no apt" "" "$(cat "$b/calls" 2>/dev/null)"
check "the harness cloud setup named by Setup: runs first, once" "ran" "$(cat "$d/setup.log")"

d=$(repo local scripts/setup.sh); b=$(bindir local installs)
boot "$d" "$b" ""
check_rc "outside a cloud session it is a pass" 0 "$rc"
check "outside a cloud session it runs nothing" "" "$(cat "$b/calls" 2>/dev/null)$(cat "$d/setup.log" 2>/dev/null)"

d=$(repo none None.); b=$(bindir none installs); tool "$b" gitleaks
boot "$d" "$b"
check_rc "Setup: None. runs no cloud setup and still passes" 0 "$rc"
check "Setup: None. leaves no setup log" "absent" "$([ -e "$d/setup.log" ] && echo ran || echo absent)"

d=$(repo missing scripts/setup.sh); b=$(bindir one installs)
boot "$d" "$b"
check_rc "a missing scanner apt installs is a pass" 0 "$rc"
check "only the scanner is asked of apt" "apt-get install -y gitleaks" "$(cat "$b/calls")"

d=$(repo stale scripts/setup.sh); b=$(bindir stale stale)
boot "$d" "$b"
check_rc "an install that needs fresh package lists is a pass" 0 "$rc"
check "a failed install refreshes the lists once and retries" \
  "apt-get install -y gitleaks
apt-get update
apt-get install -y gitleaks" "$(cat "$b/calls")"

d=$(repo broken scripts/setup.sh); b=$(bindir broken broken)
boot "$d" "$b"
check "an apt whose update fails too exits non-zero, bootstrap-failed" nonzero "$([ "$rc" -ne 0 ] && echo nonzero)"

d=$(repo inert scripts/setup.sh); b=$(bindir inert inert)
boot "$d" "$b"
check_rc "a scanner still missing after apt fails" 1 "$rc"

d=$(repo failing scripts/setup.sh); b=$(bindir failing installs); tool "$b" gitleaks
printf '#!/usr/bin/env bash\nexit 1\n' > "$d/scripts/setup.sh"
boot "$d" "$b"
check "a failing cloud setup exits non-zero, bootstrap-failed" nonzero "$([ "$rc" -ne 0 ] && echo nonzero)"

d=$(repo noline scripts/setup.sh); b=$(bindir noline installs); tool "$b" gitleaks
printf '# Harness profile\n' > "$d/docs/agents/harness.md"
boot "$d" "$b"
check_rc "a harness profile with no Setup: line fails" 1 "$rc"

finish
