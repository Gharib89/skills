#!/usr/bin/env bash
# shellcheck disable=SC2034 # every variable here is read by the test file that sources this one
# Setup shared by the split run-file test files, sourced after tests/lib.sh by
# each file's own `cd` to the repo root (tests/lib.sh derives the test's name
# from its caller, so it cannot be sourced from here). A function assigns
# the globals the test body reads; its trap and any `exit` act on the test.

# The clean gate's fixture: tests/run-file-clean.test.sh and run-file-clean-cap.test.sh.
run_file_clean_setup() {
m=${RUN_FILE_MECHANIC:-$PWD/skills/ship/scripts/run-file.sh}
tmp=$(mktemp -d) || exit 2
trap 'rm -rf "$tmp"' EXIT
repo="$tmp/repo with spaces"
mkdir -p "$repo/docs/agents" "$tmp/records/ship-clean"
git init -q "$repo"
head=abcdef0123456789
f="$tmp/records/ship-clean/run.md"
ci="$tmp/ci.json"
profile="$repo/docs/agents/ship.md"
}

# A fixture repo with an origin, the dropped-lines stub and a feature branch:
# tests/run-file-gates.test.sh and run-file-close7.test.sh.
run_file_gates_setup() {
tmp=$(mktemp -d) || exit 2
trap 'rm -rf "$tmp"' EXIT

bin=$tmp/bin work=$tmp/work origin=$tmp/origin.git
mkdir -p "$bin"
cp -r skills/ship/scripts/run-file.sh skills/ship/scripts/_lib.sh skills/ship/scripts/lib "$bin/"
cat > "$bin/dropped-lines.sh" <<'STUB'
#!/usr/bin/env bash
printf '{"base":"x","blocks":[{"id":"scripts/old.sh:1","file":"scripts/old.sh","line":1,"lines":3,"text":"t"}]}\n'
STUB

git init -q --bare -b main "$origin"
git init -q -b main "$work"
g() { git -C "$work" -c user.email=t@t -c user.name=t -c commit.gpgsign=false "$@"; }
put() { mkdir -p "$(dirname "$work/$1")"; printf '%s\n' "$2" > "$work/$1"; }
put tests/old.test.sh 'echo old'
put scripts/old.sh 'grep -q a b'
put src/x.txt 'x'
put keep.txt 'k'
g add -A && g commit -q -m base
g remote add origin "$origin"
g push -q origin main 2>/dev/null
g remote set-head origin main
base=$(g rev-parse HEAD)
g checkout -q -b feat/x-488
reset() { g reset -q --hard "$base"; g clean -fdq; }
}
