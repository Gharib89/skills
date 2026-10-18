# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154 # variables set by the sourcing script
# Shared fixtures of the contract-gate tests (tests/contract-gate*.test.sh),
# sourced after tests/lib.sh, which each test file sources for itself.

fixture=$(mktemp -d); trap 'rm -rf "$fixture"' EXIT

# <case-dir> [<mechanic>...]: a mechanics directory for one case, always
# carrying `_lib.sh` and the real host adapters, plus a real copy of each named
# mechanic for a case that mutates one rather than replacing it.
copy_mechanics() {
  local d="$fixture/$1" m; shift
  rm -rf "$d"; mkdir -p "$d"
  cp -r skills/ship/scripts/_lib.sh skills/ship/scripts/lib "$d/" || exit 2
  cp -r skills/ship/scripts/host "$d/" || exit 2
  # A mechanic renamed out from under this file would otherwise leave the case
  # appending its mutation to a file holding nothing else, still green.
  for m; do cp "skills/ship/scripts/$m.sh" "$d/" || exit 2; done
  printf '%s' "$d"
}
# <case-dir>: a fresh copy of the whole skills tree, for one Bash 4+ mutation.
copy_skills() { local d="$fixture/$1"; rm -rf "$d"; cp -r skills "$d"; printf '%s' "$d"; }

# Run the checker once and leave its exit code in `rc` and its stdout in `out`,
# which is what every assertion below reads.
run() { out=$(bash scripts/contract-check.sh "$1" "${2:-skills}" 2>/dev/null); rc=$?; }

# 0 when the last run's stdout contains this line, for a fixture that trips more
# than one check and whose whole stdout is therefore not one assertion's
# business.
named() { case $out in *"$1"*) printf 0 ;; *) printf 1 ;; esac; }

# A mechanics directory with no mechanic in it: checks 1, 2, 4 and 5 have
# nothing of their own to read, so the verdict is check 3's alone, which is the
# only check a `copy_skills` fixture mutates.
inert=$(copy_mechanics inert)
