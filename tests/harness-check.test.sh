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

r=$(repo root "TURN_ROWS='|app|*.py||bad|'")
run "$r" turn lib/x.py
check "an empty prefix is the root member, and an empty typecheck is no check" \
  '{"rung":"turn","verdict":"fail","checks":{"tests:app":"fail"}}' "$out"
check_rc "a failing test exits 1" 1 "$rc"
run "$r" turn "$fixture/outside.py"
check "a file outside the repo is no member's, even the root member's" \
  '{"rung":"turn","verdict":"skipped","checks":{"turn":"skipped"}}' "$out"

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

r=$(repo full "FULL_RUN='ok'
TURN_ROWS='$rows'
FULL_ROWS='check-target|ok'")
mkdir -p "$r/api" "$r/web"
: > "$ARGS_LOG"
run "$r" full
check "full runs the runner, every member's whole suite and the extra checks" \
  '{"rung":"full","verdict":"pass","checks":{"runner":"pass","typecheck:api":"pass","tests:api":"pass","typecheck:web":"pass","tests:web":"pass","check-target":"pass"}}' "$out"
check "full never runs affected tests" "typecheck-api
tests-api
typecheck-web
tests-web" "$(cat "$ARGS_LOG")"

r=$(repo local-only "FULL_ROWS='semver-core|bad
after|ok'
LOCAL_ONLY='semver-core'")
out=$(cd "$r" && CLAUDE_CODE_REMOTE=true PATH="$bin:$PATH" bash scripts/check.sh full 2>/dev/null); rc=$?
check "a cloud session skips a LOCAL_ONLY row unrun" \
  '{"rung":"full","verdict":"pass","checks":{"semver-core":"skipped","after":"pass"}}' "$out"
check_rc "and full still passes there" 0 "$rc"
run "$r" full
check "outside the cloud a LOCAL_ONLY row runs" \
  '{"rung":"full","verdict":"fail","checks":{"semver-core":"fail","after":"pass"}}' "$out"

# check.sh reads a stopped clock here, so the runner always starts a second
# before the deadline, however late in a second the case begins (#445).
r=$(repo deadline "FULL_RUN='slow'
FULL_ROWS='after|ok'")
clock=$fixture/clock; mkdir -p "$clock"
printf '#!/bin/sh\necho 1000\n' > "$clock/date"; chmod +x "$clock/date"
start=$(date +%s)
out=$(cd "$r" && CHECK_DEADLINE=1001 PATH="$clock:$bin:$PATH" bash scripts/check.sh full 2>/dev/null); rc=$?
took=$(( $(date +%s) - start ))
check "the check running at the deadline is over-budget, the rest skipped" \
  '{"rung":"full","verdict":"over-budget","checks":{"runner":"over-budget","after":"skipped"}}' "$out"
check_rc "over budget exits 3" 3 "$rc"
check "the deadline stops the running check rather than waiting it out" yes "$([ "$took" -lt 4 ] && echo yes)"

r=$(repo both "FULL_RUN='bad'
FULL_ROWS='slow|slow'")
out=$(cd "$r" && CHECK_DEADLINE=$(( $(date +%s) + 2 )) PATH="$bin:$PATH" bash scripts/check.sh full 2>/dev/null); rc=$?
check_rc "a failure outranks an over-budget check" 1 "$rc"

r=$(repo late "FULL_RUN='ok'
FULL_ROWS='after|ok'")
out=$(cd "$r" && CHECK_DEADLINE=$(( $(date +%s) - 1 )) PATH="$bin:$PATH" bash scripts/check.sh full 2>/dev/null); rc=$?
check "a check the deadline passed before it started is skipped, never blamed" \
  '{"rung":"full","verdict":"over-budget","checks":{"runner":"skipped","after":"skipped"}}' "$out"
check_rc "and the rung is still over budget" 3 "$rc"

# Twenty runs at once, each killed at its deadline: every one is over-budget,
# never a fail, however the watchdog's own exit races the check's.
r=$(repo race "FULL_RUN='slow'")
d=$(( $(date +%s) + 1 ))
for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
  (cd "$r" && CHECK_DEADLINE=$d PATH="$bin:$PATH" bash scripts/check.sh full > "$fixture/race.$i" 2>&1) &
done
wait
check "a check killed at the deadline is over-budget in every run" 0 \
  "$(cat "$fixture"/race.* | grep -vc '"verdict":"over-budget"' | tr -d ' ')"

r=$(repo quiet "FULL_RUN='ok'")
out=$(cd "$r" && CHECK_DEADLINE=$(( $(date +%s) + 30 )) PATH="$bin:$PATH" bash scripts/check.sh full 2>"$fixture/err"); rc=$?
check "a passing run under a deadline writes nothing to stderr" '' "$(cat "$fixture/err")"

# A check that reads stdin gets none, so it cannot drain the row list the rung
# loops over and silently drop the members after it.
stub drain 'cat > /dev/null'
r=$(repo stdin "TURN_ROWS='api/|api|*.py|drain||
web/|web|*.ts|ok||'")
mkdir -p "$r/api" "$r/web"
run "$r" full
check "a check reading stdin leaves every later member checked" \
  '{"rung":"full","verdict":"pass","checks":{"typecheck:api":"pass","typecheck:web":"pass"}}' "$out"
out=$(cd "$r" && CHECK_DEADLINE=$(( $(date +%s) + 30 )) PATH="$bin:$PATH" bash scripts/check.sh full 2>/dev/null)
check "and the same under a deadline" \
  '{"rung":"full","verdict":"pass","checks":{"typecheck:api":"pass","typecheck:web":"pass"}}' "$out"

stub e124 'exit 124'
r=$(repo own124 "FULL_RUN='e124'")
run "$r" full
check "a command's own exit 124 is a fail, not over-budget" \
  '{"rung":"full","verdict":"fail","checks":{"runner":"fail"}}' "$out"

# The default file set holds names the porcelain format quotes or that carry
# a shell metacharacter, and drops a deleted file.
r=$(repo names "TURN_ROWS='web/|web|*.ts|||args related {files}'")
mkdir -p "$r/web/src"; echo x > "$r/web/src/gone.ts"
git -C "$r" add -A >/dev/null; git -C "$r" -c user.name=t -c user.email=t@t commit -qm seed
rm "$r/web/src/gone.ts"; echo y > "$r/web/src/sp ace.ts"; echo z > "$r/web/src/a&b.ts"
: > "$ARGS_LOG"
run "$r" turn
check "quoted, metacharacter and deleted names reach affected tests as they are" \
  "related src/a&b.ts src/sp ace.ts" "$(cat "$ARGS_LOG")"

r=$(repo deleted "TURN_ROWS='web/|web|*.ts|args typecheck|args suite|args related {files}'")
mkdir -p "$r/web"; echo x > "$r/web/gone.ts"
git -C "$r" add -A >/dev/null; git -C "$r" -c user.name=t -c user.email=t@t commit -qm seed
rm "$r/web/gone.ts"
: > "$ARGS_LOG"
run "$r" turn
check "a deleted file alone still checks its member, whole suite" "typecheck
suite" "$(cat "$ARGS_LOG")"

finish
