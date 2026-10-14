#!/usr/bin/env bash
# The clean gate's covered head: a reviewer stop or a Verification result
# stamped at an earlier head still covers the PR head only through clean base
# merges, or, for a Verification with `Paths:`, through changes none of its
# globs match. Driven end to end over a real git history (a PR branch, a base
# that moves, clean and conflicting merges of it) and a fixture Run file; the
# mechanic reaches no host.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
m=${RUN_FILE_MECHANIC:-$PWD/skills/ship/scripts/run-file.sh}
tmp=$(mktemp -d) || exit 2
trap 'rm -rf "$tmp"' EXIT
repo=$tmp/repo
f=$tmp/records/ship-9/run.md
ci=$tmp/ci.json
mkdir -p "$tmp/records/ship-9"
git init -q -b main "$repo"
g() { git -C "$repo" -c user.email=t@t -c user.name=t -c commit.gpgsign=false "$@"; }
put() { mkdir -p "$(dirname "$repo/$1")" && printf '%s\n' "$2" > "$repo/$1" && g add "$1"; }

# main: c0. PR branch: the stamped commit. main moves on a file the PR never
# touches, then on the PR's own file, so one merge is clean and one conflicts.
put docs/agents/ship.md placeholder; put skills/ship/SKILL.md one; put skills/index.md index; put skills/ship/reference/verify.md v; put feat.txt base
g commit -q -m c0
g checkout -q -b pr
put feat.txt pr; g commit -q -m 'pr work'
stamp=$(g rev-parse HEAD)
g checkout -q main
put other.txt main; g commit -q -m 'base moves'
g update-ref refs/remotes/origin/main HEAD
g symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
g checkout -q pr
g merge -q --no-edit main
clean_merge=$(g rev-parse HEAD)
g checkout -q main
put feat.txt main-side; g commit -q -m 'base edits the pr file'
g update-ref refs/remotes/origin/main HEAD
g checkout -q pr
g merge -q --no-edit main >/dev/null 2>&1
put feat.txt resolved; g commit -q --no-edit
conflict_merge=$(g rev-parse HEAD)
# Own commits after the stamp: one outside the Verification's Paths, one inside.
g checkout -q -b own "$stamp"
put notes.txt fix; g commit -q -m 'post-loop fix'
outside=$(g rev-parse HEAD)
put skills/ship/SKILL.md two; g commit -q -m 'skill prose'
inside=$(g rev-parse HEAD)
# A file its glob matches only at the head (added), or only at the stamp (deleted).
g checkout -q -b added "$stamp"
put skills/added.md new; g commit -q -m 'add a file'
added=$(g rev-parse HEAD)
g checkout -q -b removed "$stamp"
g rm -q skills/index.md; g commit -q -m 'remove a file'
removed=$(g rev-parse HEAD)
# A clean merge of a branch that is not the base is no base merge.
g checkout -q -b side "$stamp"
put side.txt side; g commit -q -m 'side work'
g checkout -q -b offbase "$stamp"
g merge -q --no-edit side
offbase=$(g rev-parse HEAD)

profile() { # profile [<Paths: line>]
  {
    printf '## CI\nLegs:\n  test: prove the change\n\n## Reviewers\n### primary\nTrigger: on-request\nFallback-for: None.\n\n## Verification\n### live\n'
    [ -z "${1:-}" ] || printf '%s\n' "$1"
    printf 'Also proven by CI: None.\n'
  } > "$repo/docs/agents/ship.md"
}
run() { # run <head> <reviewer stop> <verification result>
  printf '# ship run\n## Verification results\n- live: %s\n## Local gate\n- 10:00 %s pass {"tests":"pass","secrets":"pass"}\n## Review evidence\nRound: primary 1: dispositioned\nStop: primary: %s\n' \
    "$3" "$1" "$2" > "$f"
  jq -n --arg h "$1" '{status: "green", head_sha: $h, checks: [{name: "test", status: "success"}], legs: ["test"], missing_legs: [], failing: [], non_leg_failing: [], unlisted: [], waited_s: 0}' > "$ci"
}
gate() { (cd "$repo" && bash "$m" gate clean "$ci" --head "$1" --file "$f" 2>"$tmp/err"); }
holds() { # holds <case> <head> <reason>
  local answer
  answer=$(gate "$2")
  check "$1 holds" true "$(jq -r --arg r "$3" '.clean == false and (.held_by | index($r) != null)' <<<"$answer")"
}
passes() { check "$1 passes" '{"clean":true,"held_by":[]}' "$(gate "$2" | jq -c .)"; }
reviewer_stale() { printf 'reviewer primary: tree unchanged at %s, which does not cover head %s' "$1" "$2"; }
verif_stale() { printf 'verification live: pass at %s, which does not cover head %s' "$1" "$2"; }

profile
run "$stamp" "tree unchanged at $stamp" "pass at $stamp"
passes 'evidence stamped at the head' "$stamp"

# A reviewer stop stamped at an older head no longer covers the PR.
run "$outside" "tree unchanged at $stamp" "pass at $outside"
holds 'a reviewer stop before a post-loop fix' "$outside" "$(reviewer_stale "$stamp" "$outside")"
run "$offbase" "tree unchanged at $stamp" "pass at $offbase"
holds 'a reviewer stop before a clean merge of a non-base branch' "$offbase" "$(reviewer_stale "$stamp" "$offbase")"

# Clean base merges carry the coverage; a merge that resolved a conflict breaks it.
run "$clean_merge" "tree unchanged at $stamp" "pass at $stamp"
passes 'evidence stamped before a clean base merge' "$clean_merge"
run "$conflict_merge" "tree unchanged at $stamp" "pass at $stamp"
holds 'a reviewer stop before a conflict-resolving merge' "$conflict_merge" "$(reviewer_stale "$stamp" "$conflict_merge")"
holds 'a verification before a conflict-resolving merge' "$conflict_merge" "$(verif_stale "$stamp" "$conflict_merge")"
run "$conflict_merge" "tree unchanged at $clean_merge" "pass at $clean_merge"
holds 'evidence at a clean merge before a conflicting one' "$conflict_merge" "$(reviewer_stale "$clean_merge" "$conflict_merge")"

# A Verification without Paths: holds on any break in coverage.
run "$outside" "tree unchanged at $outside" "pass at $stamp"
holds 'a verification without Paths: before a fix' "$outside" "$(verif_stale "$stamp" "$outside")"
# With Paths:, only a changed file its globs match holds it.
profile 'Paths: skills/ship/SKILL.md, skills/ship/reference/**'
passes 'a verification whose Paths: no change matches' "$outside"
run "$inside" "tree unchanged at $inside" "pass at $stamp"
holds 'a verification whose Paths: a change matches' "$inside" "$(verif_stale "$stamp" "$inside")"
profile 'Paths: skills/*.md'
passes 'a single-star glob does not cross a directory' "$inside"
# A glob that matches no file, a typo or the sentinel spelling, proves nothing.
run "$outside" "tree unchanged at $outside" "pass at $stamp"
for p in 'Paths: None.' 'Paths: skill/ship/**' 'Paths: skills/ship/SKILL.md, skill/ship/**' 'Paths:  '; do
  profile "$p"
  holds "a verification whose '$p' matches no file" "$outside" "$(verif_stale "$stamp" "$outside")"
done
# A glob matching its file at one side only saw that file change.
profile 'Paths: skills/added.md'
run "$added" "tree unchanged at $added" "pass at $stamp"
holds 'a verification whose glob matches a file added since' "$added" "$(verif_stale "$stamp" "$added")"
profile 'Paths: skills/index.md'
run "$removed" "tree unchanged at $removed" "pass at $stamp"
holds 'a verification whose glob matches a file deleted since' "$removed" "$(verif_stale "$stamp" "$removed")"
# Near misses: an indented Paths: line is no Paths: line, and a stamp inside a
# longer word is no stamp.
profile '  Paths: skills/ship/SKILL.md'
run "$outside" "tree unchanged at $outside" "pass at $stamp"
holds 'a verification whose Paths: line is indented' "$outside" "$(verif_stale "$stamp" "$outside")"
profile
run "$stamp" "tree unchanged at ${stamp}g" "pass at $stamp"
holds 'a stop whose stamp runs into a longer word' "$stamp" "reviewer primary: tree unchanged at ${stamp}g"
# An unknown stamp proves nothing.
profile
run "$stamp" "tree unchanged at $stamp" "pass at 1234567890abcdef"
holds 'a verification stamped at an unknown commit' "$stamp" "$(verif_stale 1234567890abcdef "$stamp")"
# Trailing blanks or a carriage return leave a stop's stamp the same head.
run "$clean_merge" "tree unchanged at $stamp"$' \r' "pass at $clean_merge"
passes 'stamps with trailing blanks' "$clean_merge"
# A local branch named like the base does not stand in for it.
g branch origin/main "$stamp" 2>/dev/null
passes 'a walk beside a local branch named origin/main' "$clean_merge"
# A walk that cannot read the base is no verdict.
g symbolic-ref --delete refs/remotes/origin/HEAD
check_rc 'a walk with no origin/HEAD is unreadable' 2 "$(gate "$clean_merge" >/dev/null; echo $?)"
check 'the unreadable walk names what it needs' 1 "$(grep -cF "cannot read whether $stamp covers head $clean_merge: a read the walk needs failed (origin/HEAD, a commit's parents, the ancestry check, git merge-tree --write-tree)" "$tmp/err")"
finish
