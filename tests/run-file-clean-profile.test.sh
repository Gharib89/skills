#!/usr/bin/env bash
# #1338: the clean gate holds a PR that changes the ship profile. It grades the
# profile committed at the PR head, and holds when that copy differs from the
# freshly fetched base's, when the base has none, when the checkout's copy
# differs from the head's, or when any of those reads fails. Driven at
# run-file's own entrypoint, with read-pr stubbed as the host's answer, in a
# throwaway checkout with a bare origin.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
tmp=$(mktemp -d) || exit 2
trap 'rm -rf "$tmp"' EXIT
bin=$tmp/bin origin=$tmp/origin.git work=$tmp/work
mkdir -p "$bin"
cp -r skills/ship-run/scripts/run-file.sh skills/ship-run/scripts/_lib.sh skills/ship-run/scripts/lib "$bin/"
cat > "$bin/read-pr.sh" <<STUB
#!/usr/bin/env bash
printf '{"head_sha":"%s"}\n' "\$(cat "$tmp/pr-head")"
STUB
chmod +x "$bin/read-pr.sh"
g() { git -C "$work" -c user.email=t@t -c user.name=t -c commit.gpgsign=false "$@"; }
profile=$work/docs/agents/ship.md
two_reviewers='## CI
Legs:
  test: prove the change

## Reviewers
### primary
Trigger: on-request
Fallback-for: None.
### second
Trigger: on-request
Fallback-for: None.'
one_reviewer='## CI
Legs:
  test: prove the change

## Reviewers
### primary
Trigger: on-request
Fallback-for: None.'

# A fresh origin and checkout per case: main carries <base profile> (none for
# "-"), the PR branch commits <head profile> (unchanged for "=") beside a code
# change, and the Run file and CI answer hold every other condition at that head.
n=0
fixture() { # fixture <base profile|-> <head profile|=>
  n=$((n + 1))
  rm -rf "$origin" "$work"
  git init -q --bare -b main "$origin"
  git init -q -b main "$work"
  mkdir -p "$work/docs/agents"
  printf 'x\n' > "$work/x.txt"
  [ "$1" = - ] || printf '%s\n' "$1" > "$profile"
  g add -A && g commit -q -m base
  g remote add origin "$origin"
  g push -q origin main 2>/dev/null
  g remote set-head origin main
  g checkout -q -b fix/x-1338
  printf 'y\n' > "$work/x.txt"
  [ "$2" = = ] || printf '%s\n' "$2" > "$profile"
  g add -A && g commit -q -m change
  head=$(g rev-parse HEAD)
  printf '%s\n' "$head" > "$tmp/pr-head"
  rf=$(printf '%s\n' '- [ ] it holds' \
    | bash "$bin/run-file.sh" init "c$n" --scratchpad "$tmp/sp" --criteria - | jq -r .run_file)
  printf '%s\n' 'Criterion 1: met: tests/run-file-clean-profile.test.sh' \
    'Round: primary 1: clean' "Stop: primary: tree unchanged at $head" \
    'Round: second 1: clean' "Stop: second: tree unchanged at $head" \
    '## Local gate' "- 10:00 $head pass {\"secrets\":\"pass\"}" >> "$rf"
  printf '{"status":"green","head_sha":"%s","checks":[{"name":"test","status":"success"}]}\n' "$head" > "$(dirname "$rf")/ci-wait.json"
}
call() { out=$(cd "$work" && bash "$bin/run-file.sh" "$@" 2>"$tmp/err"); status=$?; }
admissions() { grep -c "^- [0-9][0-9]:[0-9][0-9] $head clean\$" "$rf"; }
# held <case> <hold>: gate clean, gate summary and gate admit clean each hold
# with exit 1 naming <hold>, and the admission leaves no record.
held() {
  local ci
  ci="$(dirname "$rf")/ci-wait.json"
  call gate clean "$ci" --head "$head" --file "$rf"
  check_rc "$1: gate clean exits 1" 1 "$status"
  check "$1: gate clean names the hold" true "$(jq --arg h "$2" '.clean == false and (.held_by | index($h) != null)' <<<"$out")"
  check "$1: gate clean writes it on stderr" yes "$(grep -Fq -- "$2" "$tmp/err" && echo yes || echo no)"
  call gate summary 7 --file "$rf"
  check_rc "$1: gate summary exits 1" 1 "$status"
  check "$1: gate summary names the hold" true "$(jq --arg h "$2" '.clean == false and (.held_by | index($h) != null)' <<<"$out")"
  call gate admit clean "$ci" --head "$head" --file "$rf"
  check_rc "$1: gate admit clean exits 1" 1 "$status"
  check "$1: gate admit clean names the hold" true "$(jq --arg h "$2" '.clean == false and (.held_by | index($h) != null)' <<<"$out")"
  check "$1: gate admit clean writes no admission" 0 "$(admissions)"
}

fixture "$two_reviewers" =
ci="$(dirname "$rf")/ci-wait.json"
call gate clean "$ci" --head "$head" --file "$rf"
check_rc "an unchanged profile: gate clean exits 0" 0 "$status"
check "an unchanged profile: no holds" '{"clean":true,"held_by":[]}' "$(jq -c . <<<"$out")"
call gate summary 7 --file "$rf"
check_rc "an unchanged profile: gate summary exits 0" 0 "$status"
call gate admit clean "$ci" --head "$head" --file "$rf"
check_rc "an unchanged profile: gate admit clean exits 0" 0 "$status"
check "an unchanged profile: the admission is recorded" 1 "$(admissions)"

# The head drops the second reviewer's block, which no Stop line then owes.
fixture "$two_reviewers" "$one_reviewer"
held "a head that removes a reviewer block" "ship profile: head $head differs from base origin/main"

fixture "$two_reviewers" "$one_reviewer"
printf '%s\n' "$two_reviewers" > "$profile"
held "a committed change the checkout reverted" "ship profile: head $head differs from base origin/main"
check "a committed change the checkout reverted: also names the checkout" true "$(jq --arg h "ship profile: the checkout's copy differs from the one committed at head $head" '.held_by | index($h) != null' <<<"$out")"

fixture - "$two_reviewers"
held "a PR that adds the first profile" "ship profile: absent from base origin/main, so head $head adds it"

fixture "$two_reviewers" =
printf '%s\n' "$one_reviewer" > "$profile"
# With no evidence for the reviewer the checkout's copy drops, only the
# committed profile still owes it.
sed -i '/: second\| second 1:/d' "$rf"
held "a checkout edit with no committed profile change" "ship profile: the checkout's copy differs from the one committed at head $head"
check "a checkout edit: grades the committed profile, so the second reviewer is still owed" true "$(jq '.held_by | index("reviewer second: missing stop") != null' <<<"$out")"

fixture "$two_reviewers" =
g remote set-url origin "$tmp/no-such-origin.git"
held "an unreadable base" "ship profile: cannot fetch base origin/main, so a change to it cannot be ruled out"

# The base moved on origin after the checkout last fetched: the gate fetches it.
fixture "$two_reviewers" =
other=$tmp/other
rm -rf "$other"
git clone -q "$origin" "$other"
printf '%s\n' "$one_reviewer" > "$other/docs/agents/ship.md"
git -C "$other" -c user.email=t@t -c user.name=t -c commit.gpgsign=false commit -q -am 'base edits the profile'
git -C "$other" push -q origin main 2>/dev/null
held "a base that changed the profile since the last fetch" "ship profile: head $head differs from base origin/main"

fixture "$two_reviewers" =
fake=1111111111111111111111111111111111111111
sed -i "s/$head/$fake/g" "$rf" "$(dirname "$rf")/ci-wait.json"
head=$fake
printf '%s\n' "$head" > "$tmp/pr-head"
held "a head the checkout cannot read" "ship profile: cannot read it at head $head"

finish
