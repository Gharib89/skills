#!/usr/bin/env bash
# skills/setup-harness/templates/check.sh: the check entry point's contract. The
# subject is what a caller reads: one JSON line on stdout, each failing check's
# tail on stderr, and the exit code (0 pass, 1 fail, 2 unavailable, 3 over
# budget under CHECK_DEADLINE). Each case writes the template into a throwaway
# git repo with its own configuration block, the way setup-harness writes it,
# and the tools that block names are stubs on a PATH built for the case.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

fixture=$(mktemp -d); trap 'rm -rf "$fixture"' EXIT
template=$PWD/skills/setup-harness/templates/check.sh
bin=$fixture/bin; mkdir -p "$bin"

# <name> <body>: a stub tool on the case PATH.
stub() { printf '#!/bin/sh\n%s\n' "$2" > "$bin/$1"; chmod +x "$bin/$1"; }
# lint: fails naming each argument file that holds BAD. fmt: rewrites UGLY to
# pretty in each argument file, as a formatter in fix mode does, and fails when
# it changed one, as a pre-commit runner reports a modified file.
stub lint 'rc=0; for f; do grep -q BAD "$f" && { echo "lint: $f: BAD found"; rc=1; }; done; exit $rc'
stub fmt 'rc=0; for f; do grep -q UGLY "$f" && { sed "s/UGLY/pretty/" "$f" > "$f.t" && mv "$f.t" "$f"; rc=1; }; done; exit $rc'
stub ok 'exit 0'
stub bad 'echo "bad: something broke"; exit 1'
stub slow 'sleep 5'
stub args 'echo "$@" >> "$ARGS_LOG"'

# <name> <config>: a git repo at $fixture/<name> whose scripts/check.sh is the
# template with its configuration block replaced by <config>; prints its path.
repo() {
  local r=$fixture/$1
  mkdir -p "$r/scripts"
  git -C "$r" init -q
  awk -v cfg="$2" '
    /^# >>> setup-harness/ { print; print cfg; skip = 1; next }
    /^# <<< setup-harness/ { skip = 0 }
    !skip' "$template" > "$r/scripts/check.sh"
  printf '%s' "$r"
}

# <repo> <args...>: run check.sh there; leaves stdout in `out`, stderr in
# `err` and the exit code in `rc`.
# Every case but the cloud ones runs outside the cloud, so the variable a cloud
# session sets is cleared rather than inherited.
run() {
  local r=$1; shift
  out=$(cd "$r" && CLAUDE_CODE_REMOTE='' PATH="$bin:$PATH" bash scripts/check.sh "$@" 2>"$fixture/err"); rc=$?
  err=$(cat "$fixture/err")
}

r=$(repo edit "EDIT_GLOBS='*.py'
EDIT_RUN='lint {files}'")
echo 'x = 1' > "$r/a.py"
run "$r" edit a.py
check "a clean file passes the edit rung" '{"rung":"edit","verdict":"pass","checks":{"runner":"pass"}}' "$out"
check_rc "a clean edit exits 0" 0 "$rc"

echo 'x = BAD' > "$r/b.py"
run "$r" edit "$r/b.py"
check "a lint finding fails the edit rung, given the absolute path hooks send" \
  '{"rung":"edit","verdict":"fail","checks":{"runner":"fail"}}' "$out"
check_rc "a failing edit exits 1" 1 "$rc"
check "the linter's own message reaches stderr" "--- runner ---
lint: b.py: BAD found" "$err"

mkdir -p "$r/sub"; echo 'x = BAD' > "$r/sub/c.py"
run "$r" edit sub/c.py
check "a glob matches a file in a subdirectory while the root holds one it also matches" \
  '{"rung":"edit","verdict":"fail","checks":{"runner":"fail"}}' "$out"

run "$r" edit README.md
check "a file no glob covers is skipped" '{"rung":"edit","verdict":"skipped","checks":{"runner":"skipped"}}' "$out"
check_rc "a skipped edit exits 0" 0 "$rc"

# A hook sends every Edit or Write path, the agent's own files outside the
# repo included (#459).
echo 'x = BAD' > "$fixture/outside.py"
run "$r" edit "$fixture/outside.py"
check "a file outside the repo is skipped" '{"rung":"edit","verdict":"skipped","checks":{"runner":"skipped"}}' "$out"
# A path that only names the root, or a link inside it, can still lead out
# (#539).
ln -s "$fixture" "$r/link"
for p in "$r/../outside.py" ../outside.py link/outside.py; do
  run "$r" edit "$p"
  check "$p, which leads outside the repo, is skipped" '{"rung":"edit","verdict":"skipped","checks":{"runner":"skipped"}}' "$out"
done
rm "$r/link"
# An exported CDPATH holding a directory named like a repo directory, or a
# directory whose name starts with `-`, still resolves inside the root, and the
# runner never takes a path as an option (#554).
mkdir -p "$fixture/elsewhere/sub"
CDPATH=$fixture/elsewhere run "$r" edit sub/c.py
check "an exported CDPATH holding a same-named directory still lints the repo's file" \
  '{"rung":"edit","verdict":"fail","checks":{"runner":"fail"}}' "$out"
mkdir -p "$r/-foo"; echo 'x = BAD' > "$r/-foo/d.py"
run "$r" edit -foo/d.py
check "a directory whose name starts with - still lints the file there" \
  '{"rung":"edit","verdict":"fail","checks":{"runner":"fail"}}' "$out"
check "the runner takes the dash-named file as ./-foo/d.py" "--- runner ---
lint: ./-foo/d.py: BAD found" "$err"

r=$(repo fix "EDIT_GLOBS='*.py'
EDIT_RUN='fmt {files}'")
echo 'x = UGLY' > "$r/a.py"
run "$r" edit a.py
check "a finding the formatter fixes passes" '{"rung":"edit","verdict":"pass","checks":{"runner":"pass"}}' "$out"
check "the fix is left in the file" 'x = pretty' "$(cat "$r/a.py")"

r=$(repo missing "EDIT_GLOBS='*.py'
EDIT_RUN='no-such-linter {files}'")
echo 'x = 1' > "$r/a.py"
run "$r" edit a.py
check "a missing tool is unavailable" '{"rung":"edit","verdict":"unavailable","checks":{"runner":"unavailable"}}' "$out"
check_rc "an unavailable check exits 2" 2 "$rc"
check "with no harness profile it names no local install" "" "$(grep 'installs with' <<<"$err")"

# A missing tool names the cloud setup's `--local` run, read from the harness
# profile's `Setup:`, since it installs every tool check.sh runs.
mkdir -p "$r/docs/agents"
printf '# Harness profile\n\n## Cloud\n\nVerdict: cloud-first\nSetup: .claude/hooks/cloud-setup.sh\n\n## Budgets\n\nSetup: not this one\n' > "$r/docs/agents/harness.md"
run "$r" edit a.py
check "an unavailable check names the local install last" \
  'a missing tool installs with: .claude/hooks/cloud-setup.sh --local' "$(tail -n 1 <<<"$err")"
sed -i 's/^Setup: \.claude.*/Setup: None./' "$r/docs/agents/harness.md"
run "$r" edit a.py
check "a local-only profile (Setup: None.) names none" "" "$(grep 'installs with' <<<"$err")"

# A runner hook whose tool is missing fails rather than exiting 127, so a
# failure whose output says a command was not found names the route too.
stub hookrun 'echo "Failed to run hook: No such file or directory (os error 2)"; exit 1'
r=$(repo hook "EDIT_GLOBS='*.py'
EDIT_RUN='hookrun {files}'")
mkdir -p "$r/docs/agents"
printf '## Cloud\n\nSetup: .claude/hooks/cloud-setup.sh\n' > "$r/docs/agents/harness.md"
echo 'x = 1' > "$r/a.py"
run "$r" edit a.py
check "a hook whose tool is missing fails" '{"rung":"edit","verdict":"fail","checks":{"runner":"fail"}}' "$out"
check "and names the local install" \
  'a missing tool installs with: .claude/hooks/cloud-setup.sh --local' "$(tail -n 1 <<<"$err")"
r=$(repo lintfail "EDIT_GLOBS='*.py'
EDIT_RUN='lint {files}'")
mkdir -p "$r/docs/agents"
printf '## Cloud\n\nSetup: .claude/hooks/cloud-setup.sh\n' > "$r/docs/agents/harness.md"
echo 'x = BAD' > "$r/a.py"
run "$r" edit a.py
check "a plain finding names no local install" "" "$(grep 'installs with' <<<"$err")"
r=$(repo testfail "FULL_ROWS='tests|hookrun'")
mkdir -p "$r/docs/agents"
printf '## Cloud\n\nSetup: .claude/hooks/cloud-setup.sh\n' > "$r/docs/agents/harness.md"
run "$r" full
check "a test failing with a not-found message is a plain failure" '{"rung":"full","verdict":"fail","checks":{"tests":"fail"}}' "$out"
check "and names no local install, the match being the runner's alone" "" "$(grep 'installs with' <<<"$err")"

# Two members of one stack and a root-level file kind no row claims. Commands
# run in the member's directory and log where they ran.
rows="api/|api|*.py|args typecheck-api|args tests-api|
web/|web|*.ts|args typecheck-web|args tests-web|args related {files}"
r=$(repo turn "TURN_ROWS='$rows'")
mkdir -p "$r/api" "$r/web/src" "$r/svc"
export ARGS_LOG=$fixture/args
: > "$ARGS_LOG"
run "$r" turn api/app.py
check "a changed file runs its own member's typecheck and tests only" \
  '{"rung":"turn","verdict":"pass","checks":{"typecheck:api":"pass","tests:api":"pass"}}' "$out"
check "a member without an affected-tests command runs its suite" "typecheck-api
tests-api" "$(cat "$ARGS_LOG")"

touch "$r/web/src/a.ts" "$r/web/src/b.ts"
: > "$ARGS_LOG"
run "$r" turn web/src/a.ts web/src/b.ts
check "affected tests get the changed files, relative to the member" "typecheck-web
related src/a.ts src/b.ts" "$(cat "$ARGS_LOG")"

run "$r" turn README.md
check "a file no row's globs match is skipped" '{"rung":"turn","verdict":"skipped","checks":{"turn":"skipped"}}' "$out"

run "$r" turn svc/new.py
check "a stack file under no listed prefix is a new root" \
  '{"rung":"turn","verdict":"unavailable","checks":{"new-root":"unavailable"}}' "$out"
check_rc "a new root exits 2" 2 "$rc"
check "the new root is named with the fix" "--- new-root: unavailable ---
new root svc: re-run setup-harness" "$err"

git -C "$r" add -A >/dev/null; git -C "$r" -c user.name=t -c user.email=t@t commit -qm seed --allow-empty
echo 'y' > "$r/web/src/new.ts"
: > "$ARGS_LOG"
run "$r" turn
check "with no files named, an untracked change is in the file set" \
  '{"rung":"turn","verdict":"pass","checks":{"typecheck:web":"pass","tests:web":"pass"}}' "$out"
check "the untracked file reaches affected tests" "typecheck-web
related src/new.ts" "$(cat "$ARGS_LOG")"

# Under an exported CDPATH holding a same-named directory, a member's commands
# still run in the member's own directory (#554).
stub where 'pwd -P >> "$ARGS_LOG"'
r=$(repo cdpath "TURN_ROWS='api/|api|*.py||where|'")
mkdir -p "$r/api" "$fixture/elsewhere/api"
: > "$ARGS_LOG"
CDPATH=$fixture/elsewhere run "$r" turn api/app.py
check "an exported CDPATH leaves a member's commands in its own directory" \
  "$(cd "$r/api" && pwd -P)" "$(cat "$ARGS_LOG")"
r=$(repo dash-member "TURN_ROWS='-foo/|dash|*.py||where|'")
mkdir -p "$r/-foo"
: > "$ARGS_LOG"
run "$r" turn -foo/app.py
check "a member whose directory starts with - runs its commands there" \
  "$(cd "$r/-foo" && pwd -P)" "$(cat "$ARGS_LOG")"

r=$(repo root "TURN_ROWS='|app|*.py||bad|'")
run "$r" turn lib/x.py
check "an empty prefix is the root member, and an empty typecheck is no check" \
  '{"rung":"turn","verdict":"fail","checks":{"tests:app":"fail"}}' "$out"
check_rc "a failing test exits 1" 1 "$rc"
run "$r" turn "$fixture/outside.py"
check "a file outside the repo is no member's, even the root member's" \
  '{"rung":"turn","verdict":"skipped","checks":{"turn":"skipped"}}' "$out"
for p in "$r/../outside.py" ../outside.py ../gone/x.py; do
  run "$r" turn "$p"
  check "$p, which leads outside the repo, is no member's" \
    '{"rung":"turn","verdict":"skipped","checks":{"turn":"skipped"}}' "$out"
done

# A fixture tree the profile excludes: its files belong to no row, even one
# whose prefix covers them, and are no new root.
r=$(repo excluded "EDIT_GLOBS='*.py'
EDIT_RUN='lint {files}'
TURN_ROWS='api/|api|*.py|ok|ok|'
EXCLUDED='tests/fixtures/
my data/'")
run "$r" turn tests/fixtures/bad/app.py 'my data/x.py'
check "a stack file under an EXCLUDED prefix is no new root" \
  '{"rung":"turn","verdict":"skipped","checks":{"turn":"skipped"}}' "$out"
run "$r" turn svc/new.py
check "a stack file outside every EXCLUDED prefix is still a new root" \
  '{"rung":"turn","verdict":"unavailable","checks":{"new-root":"unavailable"}}' "$out"
run "$r" turn my/x.py
check "a prefix holding a space is one prefix, not two" \
  '{"rung":"turn","verdict":"unavailable","checks":{"new-root":"unavailable"}}' "$out"
mkdir -p "$r/tests/fixtures"
echo 'BAD' > "$r/tests/fixtures/bad.py"
run "$r" edit tests/fixtures/bad.py
check "the edit rung skips a file under an EXCLUDED prefix, whatever the runner excludes" \
  '{"rung":"edit","verdict":"skipped","checks":{"runner":"skipped"}}' "$out"
r=$(repo excluded-root "TURN_ROWS='|app|*.py||bad|'
EXCLUDED='tests/fixtures/'")
run "$r" turn tests/fixtures/app.py
check "a file under an EXCLUDED prefix is not the root member's" \
  '{"rung":"turn","verdict":"skipped","checks":{"turn":"skipped"}}' "$out"

# Installed skills: derived copies detection never scans, excluded with no
# profile line.
r=$(repo installed "EDIT_GLOBS='*.mjs'
EDIT_RUN='lint {files}'
TURN_ROWS='skills/x/|x|*.mjs|ok|ok|'")
mkdir -p "$r/.claude/skills/x"
echo 'BAD' > "$r/.claude/skills/x/a.mjs"
run "$r" turn .claude/skills/x/a.mjs
check "an installed skill's file is no new root without an Excluded: line" \
  '{"rung":"turn","verdict":"skipped","checks":{"turn":"skipped"}}' "$out"

finish
