#!/usr/bin/env bash
# The stub host CLIs `tests/run.sh` puts in front of every test file. Their job
# is to turn a test that reaches a host from a silent pass into a named failure,
# so the "none of these reaches a host" premise is enforced rather than asserted.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
source tests/host-stub.sh

d=$(mktemp -d) || exit 2
trap 'rm -rf "$d"' EXIT
ship_test_host_stub "$d"
export SHIP_TEST_HOSTLOG="$d/calls"

for cli in gh az; do
  : > "$SHIP_TEST_HOSTLOG"
  out=$("$d/$cli" api repos/o/r --jq .x 2>&1); rc=$?
  check_rc "the stub $cli fails rather than reaching a host" 127 "$rc"
  check "the stub $cli records the call it refused" \
    "$cli api repos/o/r --jq .x" "$(cat "$SHIP_TEST_HOSTLOG")"
  check "the stub $cli says nothing on stdout, so a caller reading it gets no answer to mistake for one" \
    '' "$out"
done

# One line per call, so the gate's report names every host the file reached and
# not just the first.
: > "$SHIP_TEST_HOSTLOG"
"$d/gh" pr view 1 >/dev/null 2>&1
"$d/az" repos pr show >/dev/null 2>&1
check "each refused call is its own line" \
  'gh pr view 1
az repos pr show' "$(cat "$SHIP_TEST_HOSTLOG")"

# --- the runner: files run concurrently, each with a log of its own -------------
# A fixture tree holds a copy of the runner and its stub library beside a few
# fixture test files, so the runner's own glob and `cd` land in the fixture and
# nothing here depends on the real suite. `SHIP_TEST_JOBS` bounds the workers.
fixture() { # <name> -> path of a fresh tree carrying the runner
  local t="$d/$1"; mkdir -p "$t/tests" && cp tests/run.sh tests/host-stub.sh "$t/tests/" && printf '%s' "$t"
}
# <tree> <name> <body>: a fixture test file that records the host log it was given.
fx() { printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$SHIP_TEST_HOSTLOG" >> "$LOGPATHS"\n%s\n' "$3" > "$1/tests/$2.test.sh"; }
run_in() { # <tree> <jobs>: stdout, then stderr, then the exit code, each on its own
  SHIP_TEST_JOBS=$2 LOGPATHS="$1/logpaths" bash "$1/tests/run.sh" >"$1/stdout.$2" 2>"$1/stderr.$2"; echo $? >"$1/rc.$2"
}

t=$(fixture ordered)
fx "$t" 01-slow 'sleep 1'
fx "$t" 02-host 'gh pr view 9'
fx "$t" 03-fail 'echo "FAIL 03: a case" >&2; exit 1'
fx "$t" 04-pass 'true'
run_in "$t" 4
check "the FAIL line names the file that reached the host, and only that file" \
  'FAIL tests/02-host.test.sh: reached a host; no test here may:' "$(grep '^FAIL tests/02' "$t/stderr.4")"
check "the refused call is listed under the file that made it" \
  '    gh pr view 9' "$(grep '^    ' "$t/stderr.4")"
check "a failing case's own output reaches stderr" 'FAIL 03: a case' "$(grep '^FAIL 03' "$t/stderr.4")"
check "no two files share a host log" 4 "$(sort -u "$t/logpaths" | wc -l | tr -d ' ')"
check "results print in file order however the workers finish, then the count" \
  'ok   tests/01-slow.test.sh
FAIL tests/02-host.test.sh
FAIL tests/03-fail.test.sh
ok   tests/04-pass.test.sh
2 passed, 2 failed' "$(cat "$t/stdout.4")"
check_rc "a failing file makes the exit non-zero" 1 "$(cat "$t/rc.4")"
rm -f "$t/logpaths"; run_in "$t" 1
check "one worker is the serial run: same report" "$(cat "$t/stdout.4")" "$(cat "$t/stdout.1")"
check "one worker is the serial run: same exit code" "$(cat "$t/rc.4")" "$(cat "$t/rc.1")"

t=$(fixture green)
fx "$t" 01-pass 'true'
fx "$t" 02-pass 'true'
run_in "$t" 2
check_rc "all files passing exits 0" 0 "$(cat "$t/rc.2")"

# Two files that each wait for the other to start finish only if they run at once.
t=$(fixture concurrent)
rendezvous() { # <me> <other>
  printf 'touch "%s/%s"; for _ in $(seq 60); do [ -e "%s/%s" ] && exit 0; sleep 0.1; done; exit 1' "$t" "$1" "$t" "$2"
}
fx "$t" 01-a "$(rendezvous a b)"
fx "$t" 02-b "$(rendezvous b a)"
run_in "$t" 2
check_rc "two workers run two files at the same time" 0 "$(cat "$t/rc.2")"
rm -f "$t/a" "$t/b"; run_in "$t" 1
check_rc "one worker does not: the pair waits on each other in turn" 1 "$(cat "$t/rc.1")"

t=$(fixture badjobs)
fx "$t" 01-pass 'true'
run_in "$t" 0
check_rc "a worker count that is not a positive integer is refused" 2 "$(cat "$t/rc.0")"


finish
