#!/usr/bin/env bash
# scripts/clock-lint.sh: the tests standard's clock rule. A test file that reads
# the current time with `date` fails, and what it must not fail is a read through
# a `date` stub the file defines, a conversion of a fixed time, and an elapsed-time
# bound carrying the `# clock-exception: <reason>` marker. Each case writes one
# fixture test file and asserts on the lint's exit code and report.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

fixture=$(mktemp -d); trap 'rm -rf "$fixture"' EXIT

# <name> <<body: the fixture test file; leaves the lint's exit code in `rc` and
# its stdout in `out`.
lint() {
  cat > "$fixture/$1.test.sh"
  out=$(bash scripts/clock-lint.sh "$fixture/$1.test.sh" 2>/dev/null); rc=$?
}

lint reads-now <<'T'
now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
T
check_rc "a read of the current time fails" 1 "$rc"
check "and the report names the file and line" "$fixture/reads-now.test.sh:1" "$(printf '%s' "$out" | cut -d: -f1,2)"

lint reads-relative <<'T'
old=$(date -u -d '2 hours ago' +%Y-%m-%dT%H:%M:%SZ)
T
check_rc "a date relative to now fails" 1 "$rc"

lint reads-epoch <<'T'
deadline=$(( $(date +%s) + 30 ))
T
check_rc "an epoch read inside arithmetic fails" 1 "$rc"

lint fixed-epoch <<'T'
check "a reset epoch" "$(date -u -d @1794383419 +%Y-%m-%dT%H:%M:%SZ)" x
ts() { date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ; }
T
check_rc "a conversion of a fixed epoch passes" 0 "$rc"

lint fixed-variable <<'T'
now=$(ts "$pin")
a=$(date -u -d "$now" +%s)
b=$(date -d "${last_seen}" +%s)
T
check_rc "a conversion of a variable, whatever its name, passes" 0 "$rc"

lint relative-word <<'T'
x=$(date -d "now" +%s)
T
check_rc "a relative word that is the whole value still fails" 1 "$rc"

lint fixed-literal <<'T'
day=$(date -u -d 2026-11-10 +%s)
T
check_rc "a conversion of a literal date passes" 0 "$rc"

lint stubbed <<'T'
mkdir -p "$work/bin"
cat > "$work/bin/date" <<'STUB'
#!/usr/bin/env bash
echo 1800000000
STUB
chmod +x "$work/bin/date"
now=$(PATH="$work/bin:$PATH" date +%s)
T
check_rc "a read through a date stub the file defines passes" 0 "$rc"

lint stubbed-fn <<'T'
date() { echo 1800000000; }
now=$(date +%s)
T
check_rc "a read through a date function the file defines passes" 0 "$rc"

lint marked <<'T'
start=$(date +%s) # clock-exception: elapsed bound proving the watchdog fired
T
check_rc "a marked elapsed-time bound passes" 0 "$rc"

lint marker-without-reason <<'T'
start=$(date +%s) # clock-exception:
T
check_rc "a marker with no reason fails" 1 "$rc"

lint not-a-call <<'T'
for t in bash date sort; do ln -s "$(command -v $t)" "$tmp/tools/$t"; done
check "each ruling is dated" 1 "$x"
# date +%s in a comment
T
check_rc "the word date as a tool name, in a string or in a comment passes" 0 "$rc"

lint heredoc-body <<'T'
cat > "$d/mechanic.sh" <<'EOS'
now=$(date +%s)
EOS
T
check_rc "a quoted heredoc body is a fixture script, not a read" 0 "$rc"

# Two violations in one file: both are reported, one line each.
lint two <<'T'
a=$(date +%s)
b=$(date +%s)
T
check "every violation is reported" 2 "$(printf '%s\n' "$out" | grep -c clock-exception)"

# The repo's own tests hold it, which is what makes the row green.
out=$(bash scripts/clock-lint.sh 2>/dev/null); rc=$?
check_rc "the repo's tests pass it" 0 "$rc"

finish
