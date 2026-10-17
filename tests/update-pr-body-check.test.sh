#!/usr/bin/env bash
# update-pr-body runs the repo's body checker, the `Body-check:` line under the
# profile's `## PR`, on the body it would publish, and refuses with the checker's
# output when it fails, so an outline update that breaks the repo's own body
# rule is stopped before the host holds it rather than found red in CI (#787).
# A repo with no profile, no line or `None.` publishes as before. Driven over
# the Host fake (tests/host-fake.sh) in a throwaway checkout whose origin names
# GitHub, with a fixture checker that fails a Shape fence over three lines.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

scripts=$PWD/skills/ship/scripts
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
repo=$work/repo
export SHIP_FAKE=$work/fake SHIP_HOST_ADAPTER=$PWD/tests/host-fake.sh
mkdir -p "$repo/docs/agents" "$repo/scripts" "$SHIP_FAKE"
git -C "$repo" init -q
git -C "$repo" remote add origin https://github.com/owner/repo.git

cat > "$repo/scripts/check-outline.sh" <<'CHECK'
#!/bin/sh
n=$(awk '/^```diff/ { f = 1; next } /^```/ { f = 0 } f' "$1" | wc -l)
[ "$n" -le 3 ] || { echo "pr-body: change outline: the Shape fence is $n lines, over 3"; exit 1; }
CHECK
chmod +x "$repo/scripts/check-outline.sh"

profile() { # profile <line>...: a ship profile whose `## PR` carries the lines
  { printf '## PR\n\nTemplate: None.\n'; printf '%s\n' "$@"; printf '\n## Public surface\n\nDefault.\n'; } > "$repo/docs/agents/ship.md"
}
# pr_body <fence lines>: the PR the host holds, a Shape fence of that many lines
pr_body() {
  local body='Closes #7\n\n## Change outline\n\n```diff\n' i
  for ((i = 1; i <= $1; i++)); do body+="a/file$i.sh\n"; done
  printf '{"number":7,"body":"%s```\\n\\n## Review\\n\\nold review\\n","head_sha":"x"}\n' "$body" > "$SHIP_FAKE/host_pr_get.1.json"
}
reset() { rm -f "$SHIP_FAKE"/*; }
mech() { ( cd "$repo" && bash "$scripts/update-pr-body.sh" "$@" ); }
wrote() { if grep -q '^host_pr_set_body' "$SHIP_FAKE/calls" 2>/dev/null; then echo yes; else echo no; fi; }

printf 'new review\n' > "$work/review"
printf '```diff\na\nb\nc\nd\n```\n' > "$work/outline"

# No profile at all: nothing to read a checker from, so the write goes through.
rm -f "$repo/docs/agents/ship.md"
reset; pr_body 5
out=$(mech 7 --section Review --body-file "$work/review" 2>/dev/null); rc=$?
check_rc "no profile publishes" 0 "$rc"
check "and writes" yes "$(wrote)"

profile 'Merge: Default.'
reset; pr_body 5
out=$(mech 7 --section Review --body-file "$work/review" 2>/dev/null); rc=$?
check_rc "a profile with no Body-check line publishes" 0 "$rc"
check "and writes the body unchanged but for the section" yes "$(wrote)"

profile 'Body-check: None.'
reset; pr_body 5
out=$(mech 7 --section Review --body-file "$work/review" 2>/dev/null); rc=$?
check_rc "Body-check: None. publishes" 0 "$rc"

profile 'Body-check: scripts/check-outline.sh'
reset; pr_body 3
out=$(mech 7 --section Review --body-file "$work/review" 2>/dev/null); rc=$?
check_rc "a body the checker passes publishes" 0 "$rc"
check "and writes" yes "$(wrote)"

# The checker reads the body the write would publish, not the section file: the
# stored outline is the over-limit part here, and the Review write is refused.
reset; pr_body 5
out=$(mech 7 --section Review --body-file "$work/review" 2>/dev/null); rc=$?
check_rc "a published body the checker fails is refused" 1 "$rc"
check "the refusal quotes the checker" "PR body fails the repo's body check (scripts/check-outline.sh): pr-body: change outline: the Shape fence is 5 lines, over 3" "$(jq -r .error <<<"$out")"
check "and nothing is written" no "$(wrote)"

# The write that would take the body over the limit is the one refused.
reset; pr_body 2
out=$(mech 7 --section 'Change outline' --body-file "$work/outline" 2>/dev/null); rc=$?
check_rc "an outline write that breaks the rule is refused" 1 "$rc"
check "with the checker's count for the new body" "PR body fails the repo's body check (scripts/check-outline.sh): pr-body: change outline: the Shape fence is 4 lines, over 3" "$(jq -r .error <<<"$out")"
check "and nothing is written" no "$(wrote)"

# A checker that cannot run is tooling, not a pass, and writes nothing.
reset; pr_body 2
chmod -x "$repo/scripts/check-outline.sh"
out=$(mech 7 --section Review --body-file "$work/review" 2>/dev/null); rc=$?
check_rc "a checker that is not executable is tooling" 2 "$rc"
check "and nothing is written" no "$(wrote)"
chmod +x "$repo/scripts/check-outline.sh"
printf '#!/bin/sh\necho oops >&2\nexit 2\n' > "$repo/scripts/check-outline.sh"
reset; pr_body 2
out=$(mech 7 --section Review --body-file "$work/review" 2>/dev/null); rc=$?
check_rc "a checker that exits 2 is tooling" 2 "$rc"
check "its stderr is the reason" "body check scripts/check-outline.sh failed (exit 2): oops" "$(jq -r .error <<<"$out")"
check "and nothing is written" no "$(wrote)"
finish
