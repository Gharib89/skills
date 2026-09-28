#!/usr/bin/env bash
# scripts/shellcheck-check.sh: which shellcheck the gate runs and how it grades
# the run. The subject is the three answers: a system `shellcheck` on PATH is
# used without reaching `npx`, a shellcheck that cannot be obtained at all is
# `unavailable` (exit 2) rather than a lint failure, and a real finding still
# fails (exit 1). The cloud sandbox's proxy refuses `npx`'s binary download,
# which the gate used to grade as `fail` (issue #249). Every tool is a fake on
# a PATH built for the case, so no case depends on what this machine has.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

fixture=$(mktemp -d); trap 'rm -rf "$fixture"' EXIT
check_script=$PWD/scripts/shellcheck-check.sh
bash_bin=$(command -v bash)

# A checkout with one tracked script.
repo="$fixture/repo"
mkdir -p "$repo/scripts" && printf '#!/usr/bin/env bash\necho ok\n' > "$repo/scripts/a.sh"
git -C "$repo" init -q && git -C "$repo" add -A

# <case>: a bin dir holding only git, so neither a real shellcheck nor a real
# npx is reachable; prints its path. `fake <bin> <name> <rc>` adds a tool that
# logs its arguments to <bin>/calls and exits <rc>.
bindir() {
  local b="$fixture/bin-$1"; mkdir -p "$b"
  ln -s "$(command -v git)" "$b/git"
  printf '%s' "$b"
}
fake() {
  printf '#!%s\necho "%s $*" >> "%s/calls"\nexit %s\n' "$bash_bin" "$2" "$1" "$3" > "$1/$2"
  chmod +x "$1/$2"
}
rc_of() { (cd "$repo" && PATH=$1 "$bash_bin" "$check_script" >/dev/null 2>&1); printf '%s' "$?"; }

b=$(bindir system-clean); fake "$b" shellcheck 0; fake "$b" npx 1
check_rc "a clean run of the system shellcheck passes" 0 "$(rc_of "$b")"
check "the system shellcheck lints the tracked scripts with the gate's flags" \
  "shellcheck -x -s bash -P SCRIPTDIR -S warning scripts/a.sh" "$(cat "$b/calls")"

b=$(bindir system-finding); fake "$b" shellcheck 1; fake "$b" npx 0
check_rc "a system shellcheck finding fails" 1 "$(rc_of "$b")"
check "a system shellcheck is used even where npx would work" \
  "shellcheck -x -s bash -P SCRIPTDIR -S warning scripts/a.sh" "$(cat "$b/calls")"

b=$(bindir npx-refused); fake "$b" npx 1
check_rc "no system shellcheck and an npx that cannot fetch it is unavailable" 2 "$(rc_of "$b")"
check "the refused fetch is probed once and nothing is linted" \
  "npx -y shellcheck --version" "$(cat "$b/calls")"

b=$(bindir no-tools)
check_rc "no shellcheck and no npx is unavailable" 2 "$(rc_of "$b")"

b=$(bindir npx-clean); fake "$b" npx 0
check_rc "a clean run through npx passes" 0 "$(rc_of "$b")"
check "npx is probed, then lints with the gate's flags" \
  "npx -y shellcheck --version
npx -y shellcheck -x -s bash -P SCRIPTDIR -S warning scripts/a.sh" "$(cat "$b/calls")"

# A real finding through npx: the probe answers, the lint does not.
b=$(bindir npx-finding)
printf '#!%s\necho "npx $*" >> "%s/calls"\ncase " $* " in *" --version "*) exit 0 ;; esac\nexit 1\n' \
  "$bash_bin" "$b" > "$b/npx"; chmod +x "$b/npx"
check_rc "a finding through npx fails" 1 "$(rc_of "$b")"

# A checkout carrying the scripts setup-harness and setup-skills land in a
# consumer: they get a second pass at the consumer's default severity, the
# Shell catalog entry's plain `shellcheck {files}` (issue #371).
landed="$fixture/landed"
mkdir -p "$landed/scripts" "$landed/skills/setup-harness/templates" "$landed/skills/setup-skills"
printf '#!/usr/bin/env bash\necho ok\n' > "$landed/scripts/a.sh"
printf '#!/usr/bin/env bash\necho ok\n' > "$landed/skills/setup-harness/templates/t.sh"
printf '#!/usr/bin/env bash\necho ok\n' > "$landed/skills/setup-skills/s.sh"
git -C "$landed" init -q && git -C "$landed" add -A
rc_in() { (cd "$2" && PATH=$1 "$bash_bin" "$check_script" >/dev/null 2>&1); printf '%s' "$?"; }

b=$(bindir landed-clean); fake "$b" shellcheck 0
check_rc "a clean run over landed templates passes" 0 "$(rc_in "$b" "$landed")"
check "the landed templates get a second pass at default severity" \
  "shellcheck -x -s bash -P SCRIPTDIR -S warning scripts/a.sh skills/setup-harness/templates/t.sh skills/setup-skills/s.sh
shellcheck skills/setup-harness/templates/t.sh skills/setup-skills/s.sh" "$(cat "$b/calls")"

# Where this machine has a real shellcheck, hold a real warning to `fail` too.
if real=$(command -v shellcheck); then
  # An info-level finding (SC2086) passes `-S warning` and fails a consumer.
  printf '#!/usr/bin/env bash\necho $1\n' > "$landed/skills/setup-harness/templates/t.sh"
  b=$(bindir landed-real); ln -s "$real" "$b/shellcheck"
  check_rc "an info-level finding in a landed template fails" 1 "$(rc_in "$b" "$landed")"

  b=$(bindir real); ln -s "$real" "$b/shellcheck"
  printf '#!/usr/bin/env bash\ncd /nowhere\n' > "$repo/scripts/b.sh"; git -C "$repo" add -A
  check_rc "a real shellcheck warning (SC2164) fails" 1 "$(rc_of "$b")"
fi

finish
