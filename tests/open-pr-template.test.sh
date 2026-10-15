#!/usr/bin/env bash
# open-pr refuses a body file that lacks a heading of the profile's `## PR`
# `Template:`, before any push or host write, by the same rule read-pr reports
# `missing` with (#647): once such a PR is open, no mechanic can rename the
# reworded section back. Driven over the Host fake (tests/host-fake.sh) in a
# throwaway repo whose origin names GitHub and whose pushes land in a local bare
# repository, so "no push" is read off that bare repo and "no create" off the
# fake's calls log. XDG_STATE_HOME points at a fresh directory, so no Run file
# grades the title.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

open=$PWD/skills/ship/scripts/open-pr.sh
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
repo=$work/repo; bare=$work/origin.git; export SHIP_FAKE=$work/fake
mkdir -p "$SHIP_FAKE"
g() { git -c user.name=t -c user.email=t@t -c init.defaultBranch=main "$@"; }
{
  g init -q --bare "$bare"
  g init -q "$repo"
  git -C "$repo" remote add origin https://github.com/owner/repo.git
  git -C "$repo" config "url.$bare.pushInsteadOf" https://github.com/owner/repo.git
  g -C "$repo" commit -q --allow-empty -m init
  git -C "$repo" update-ref refs/remotes/origin/main HEAD
  git -C "$repo" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
  g -C "$repo" checkout -q -b feat/thing-7
} >/dev/null 2>&1 || { echo "fixture setup failed" >&2; exit 2; }
export SHIP_HOST_ADAPTER=$PWD/tests/host-fake.sh
export XDG_STATE_HOME=$work/state

mkdir -p "$repo/docs/agents" "$repo/.github"
printf '## Summary\n\n## Change outline\n\n## Review\n' > "$repo/.github/pull_request_template.md"
profile() { printf '## Host\n\nHost: github\n\n## PR\n\n%s\n\n## Public surface\n' "$1" > "$repo/docs/agents/ship.md"; }
reset()   { rm -f "$SHIP_FAKE"/*; git -C "$bare" update-ref -d refs/heads/feat/thing-7 2>/dev/null; }
opn()     { printf '%s' "$1" > "$work/body.md"; ( cd "$repo" && bash "$open" 7 --title "fix: a thing" --body-file "$work/body.md" 2>/dev/null ); }
pushed()  { git -C "$bare" rev-parse -q --verify refs/heads/feat/thing-7 >/dev/null && echo pushed || echo none; }
created() { cut -f1 "$SHIP_FAKE/calls" 2>/dev/null | paste -sd' '; }

full=$'## Summary\nx\n\n## Change outline\ny\n\n## Review\nz\n'
reworded=$'## Summary\nx\n\n## Change outline, files\ny\n\n## Review\nz\n'

reset; profile 'Template: .github/pull_request_template.md'
out=$(opn "$reworded"); rc=$?
check_rc "a body missing a template heading exits 1" 1 "$rc"
check "it names the missing heading" 'body lacks the template headings: Change outline' "$(jq -r .error <<<"$out")"
check "nothing is pushed" none "$(pushed)"
check "no PR is created" "" "$(created)"

reset; profile 'Template: .github/pull_request_template.md'
fenced=$'## Summary\nx\n\n```\n## Change outline\n```\n\n<details>\n\n## Review\n\n</details>\n'
out=$(opn "$fenced"); rc=$?
check_rc "a heading only inside a fence or a <details> record is not present" 1 "$rc"
check "both are named, in template order" 'body lacks the template headings: Change outline, Review' "$(jq -r .error <<<"$out")"

reset; profile 'Template: .github/pull_request_template.md'
opn "$full" >/dev/null; rc=$?
check_rc "a body with every template heading opens" 0 "$rc"
check "it pushes and creates" "pushed host_pr_create" "$(pushed) $(created)"

reset; rm -f "$repo/docs/agents/ship.md"
opn "$reworded" >/dev/null; rc=$?
check_rc "no profile means no check" 0 "$rc"

reset; profile 'Template: None.'
opn "$reworded" >/dev/null; rc=$?
check_rc "Template: None. means no check" 0 "$rc"

reset; profile 'Template: .github/absent.md'
out=$(opn "$full"); rc=$?
check_rc "a template file that cannot be read is tooling" 2 "$rc"
check "it names the file" 'cannot read the PR template .github/absent.md' "$(jq -r .error <<<"$out")"
check "and nothing is pushed" none "$(pushed)"
check "nor created" "" "$(created)"

finish
