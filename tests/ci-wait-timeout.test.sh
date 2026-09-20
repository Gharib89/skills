#!/usr/bin/env bash
# ci-wait's no-checks grace: where it comes from, and the --timeout floor that
# follows it. The mechanic waits the grace out before it will believe a PR has
# no checks, so a window shorter than that grace can only report `timeout` where
# the mechanic itself would have answered `no-checks` a minute later (#203). A
# repo whose profile says every PR carries a check keeps both; a repo whose
# profile declares no legs and legal no-checks has already answered the question
# the grace asks, so it waits nothing (#218).
#
# The end-to-end case drives the mechanic against a fake `gh` and a throwaway
# checkout whose origin names GitHub: no case here reaches a host.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
source skills/ship/scripts/_lib.sh

m=$PWD/skills/ship/scripts/ci-wait.sh
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
nogit=$work/nogit; mkdir -p "$nogit"

err() { ( cd "$1" && shift && bash "$m" "$@" 2>/dev/null | jq -r '.error' ); }
rc()  { ( cd "$1" && shift && bash "$m" "$@" >/dev/null 2>&1 ); echo $?; }

usage='usage: ci-wait <pr> [--timeout <s>, at least the no-checks grace (120s, 0 where the profile has Legs: None. and No-checks legal: yes)] [--interval <s>]'
floor='--timeout below the 120s no-checks grace: a shorter window reports timeout where this mechanic answers no-checks'

# --- where the grace comes from ------------------------------------------------

# The two facts are read together: a repo with no legs whose profile still calls
# an empty check list illegal is waiting for a leg someone forgot to name, and a
# repo with legs has a check coming whatever the second line says.
none_yes='## CI

Legs: None.
No-checks legal: yes, nothing runs on a PR here
Push policy: Default.

## Reviewers
'
check_rc "no legs and legal no-checks expects an empty check list" 0 \
  "$(ship_no_checks_expected "$none_yes" && echo 0 || echo 1)"

none_no='## CI

Legs: None.
No-checks legal: no, a leg is coming
Push policy: Default.
'
check_rc "no legs but illegal no-checks still waits" 1 \
  "$(ship_no_checks_expected "$none_no" && echo 0 || echo 1)"

legs_yes='## CI

Legs: bump-guard: the PR title is a Conventional Commit
No-checks legal: yes
Push policy: Default.
'
check_rc "a named leg waits, whatever the second line says" 1 \
  "$(ship_no_checks_expected "$legs_yes" && echo 0 || echo 1)"

# The two lines are read inside `## CI` and nowhere else: `Legs:` is that
# section's word, and a line of the same shape under another heading is prose.
elsewhere='## CI

Legs: bump-guard: the PR title is a Conventional Commit
No-checks legal: no
Push policy: Default.

## Verification

Legs: None.
No-checks legal: yes
'
check_rc "the lines are read inside ## CI alone" 1 \
  "$(ship_no_checks_expected "$elsewhere" && echo 0 || echo 1)"

# Both values are matched as the profile spells them: a function reading its own
# section case-sensitively on one line and case-insensitively on the other is
# where the two readings start to disagree.
cap_yes='## CI

Legs: None.
No-checks legal: Yes
Push policy: Default.
'
check_rc "a capitalised value is not the profile's spelling, so the grace stands" 1 \
  "$(ship_no_checks_expected "$cap_yes" && echo 0 || echo 1)"

check_rc "a profile that could not be read waits" 1 \
  "$(ship_no_checks_expected "" && echo 0 || echo 1)"

# This repo's own profile names a leg, so its runs keep the grace.
check_rc "this repo's profile waits the grace" 1 \
  "$(ship_no_checks_expected "$(cat docs/agents/ship.md)" && echo 0 || echo 1)"

# --- the floor, and the fixtures it reads --------------------------------------

# The grace is read from the checkout's profile before the adapter loads, so
# these fixtures carry a profile and no origin remote: a window the floor admits
# goes on to fail on the host it cannot derive, which is as far as a case here
# may get.
noremote='cannot derive the host from the origin remote'
fixture() { # fixture <dir> <legs> <no-checks legal> [<origin>]
  mkdir -p "$1/docs/agents"
  printf '# Ship profile\n\nSchema: 3\n\n## CI\n\nLegs: %s\nNo-checks legal: %s\nPush policy: Default.\n' \
    "$2" "$3" > "$1/docs/agents/ship.md"
  git -C "$1" init -q
  [ -z "${4:-}" ] || git -C "$1" remote add origin "$4"
}
quiet=$work/quiet; mkdir -p "$quiet"; fixture "$quiet" 'None.' 'yes, nothing runs on a PR here'
noisy=$work/noisy; mkdir -p "$noisy"; fixture "$noisy" 'bump-guard: the PR title' 'no'

check "a timeout under the grace names the grace" "$floor" "$(err "$noisy" 1 --timeout 30)"
check_rc "a timeout under the grace is tooling" 2 "$(rc "$noisy" 1 --timeout 30)"
check "the grace itself is accepted" "$noremote" "$(err "$noisy" 1 --timeout 120)"
check "a non-numeric timeout is the usage line" "$usage" "$(err "$noisy" 1 --timeout later)"

# With no profile to read the default stands, so a checkout outside a repo keeps
# the floor the constant sets.
check "no profile keeps the floor" "$floor" "$(err "$nogit" 1 --timeout 30)"

# A repo whose profile expects no checks has no floor left to hold: the window
# the floor protected is the grace, and there is none.
check "a zero grace admits a window under 120s" "$noremote" "$(err "$quiet" 1 --timeout 30)"

# --- the first empty poll ------------------------------------------------------

bin=$work/bin; mkdir -p "$bin"
cat > "$bin/gh" <<'FAKE'
#!/usr/bin/env bash
path=$2; [ "$2" = -i ] && { path=$3; printf 'HTTP/2.0 200 OK\r\nContent-Type: application/json\r\n\r\n'; }
case $path in
  */pulls/[0-9]*) printf '{"number":1,"head_sha":"abc1234","mergeable":"clean","state":"open"}\n' ;;
  */commits/*)    ;;
esac
exit 0
FAKE
chmod +x "$bin/gh"

live=$work/live; mkdir -p "$live"
fixture "$live" 'None.' 'yes, nothing runs on a PR here' https://github.com/owner/repo.git

drive() { ( cd "$live" && PATH="$bin:$PATH" bash "$m" 1 --timeout 120 --interval 30 2>/dev/null ); }
out=$(drive)
check "a profile expecting no checks answers on the first empty poll" \
  no-checks "$(jq -r '.status' <<<"$out")"
check "and answers inside one interval" true "$(jq '.waited_s < 30' <<<"$out")"
check_rc "no-checks exits 0" 0 "$(drive >/dev/null 2>&1; echo $?)"

finish
