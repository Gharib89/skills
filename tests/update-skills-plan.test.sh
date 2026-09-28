#!/usr/bin/env bash
# update-skills' plan mechanic, driven end to end over fixture consumer
# checkouts: a throwaway git repo whose HEAD commit is the tree before the
# refresh and whose working tree is the tree after it, with the upstream heads
# an injected file. No call in this file reaches a host or the network.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

plan=skills/update-skills/scripts/plan.sh
usage='usage: plan <checkout> <heads-file> [--old <ref>]'
A=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa; B=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
C=cccccccccccccccccccccccccccccccccccccccc; D=dddddddddddddddddddddddddddddddddddddddd

tmp=$(mktemp -d) || exit 2
trap 'rm -rf "$tmp"' EXIT

# --help and the malformed calls: the usage line, exit 0 and exit 2.
out=$(bash "$plan" --help 2>"$tmp/err"); rc=$?
check "--help prints its usage" "$usage" "$out"
check_rc "--help exits 0" 0 "$rc"
check "--help writes nothing on stderr" "" "$(cat "$tmp/err")"
out=$(bash "$plan" 2>/dev/null); rc=$?
check "a bare call answers its usage line" "$usage" "$(jq -r .error <<<"$out")"
check_rc "a bare call exits 2" 2 "$rc"
out=$(bash "$plan" --x --x 2>/dev/null); rc=$?
check "a leading-dash positional answers its usage line" "$usage" "$(jq -r .error <<<"$out")"
check_rc "a leading-dash positional exits 2" 2 "$rc"

# <dir> <skill> <version> [<composes>]: a derived copy's SKILL.md.
skill() {
  mkdir -p "$1/.claude/skills/$2"
  { echo ---; echo "name: $2"; echo metadata:; echo "  version: $3"
    [ -z "${4:-}" ] || echo "  composes: $4"; echo ---; echo "# $2"
  } > "$1/.claude/skills/$2/SKILL.md"
}
# <dir> <json>: skills-lock.json from a {skill: {source, ref?}} object.
lock() { jq '{version: 1, skills: .}' <<<"$2" > "$1/skills-lock.json"; }

# The tree before the refresh, committed: ship 1.0.0 composing tdd (installed
# at its pin) and code-review (installed with no ref), setup-skills composing
# triage, and one other skill at a recorded ref.
repo=$tmp/repo
mkdir -p "$repo" && git -C "$repo" init -q && git -C "$repo" config user.email t@t && git -C "$repo" config user.name t
skill "$repo" ship 1.0.0 "o/r#$A:tdd o/r#$A:code-review"
skill "$repo" setup-skills 2.0.0 "o/r#$A:triage"
mkdir -p "$repo/.claude/skills/setup-skills/reviewers"
for f in pull_request_template.md local-gate.sh coding-standards.md dimension-labels.md issue-tracker-ado.md ship-block.md reviewers/github-claude-review.md; do
  echo "old $f" > "$repo/.claude/skills/setup-skills/$f"
done
lock "$repo" '{"ship": {"source": "Gharib89/skills"}, "setup-skills": {"source": "gharib89/skills"},
  "tdd": {"source": "o/r", "ref": "'$A'"}, "code-review": {"source": "o/r"}, "triage": {"source": "o/r", "ref": "'$A'"},
  "grilling": {"source": "o/r", "ref": "'$A'"}, "research": {"source": "o/r", "ref": "'$A'"}}'
git -C "$repo" add -A && git -C "$repo" commit -qm old

# The refresh: ship moves to 1.1.0 and its pins to B; setup-skills' own SKILL.md
# changes, and so does exactly one template file. setup-skills now also names
# tdd, at a pin ship's first entry overrides, and grilling unpinned, which is
# no composes entry. The installs have begun, so the working-tree lock already
# records tdd at B and grilling at D: the old refs come from the old tree.
skill "$repo" ship 1.1.0 "o/r#$B:tdd o/r#$B:code-review"
skill "$repo" setup-skills 2.0.1 "o/r#$A:triage o/r#$C:tdd o/r:grilling"
echo "new" > "$repo/.claude/skills/setup-skills/pull_request_template.md"
# ship's retired terms: one row below the refresh's range, one on each
# boundary, one inside it and one above it.
cat > "$repo/.claude/skills/ship/retired-terms.md" <<'EOF'
# Retired terms

| Version | Term | Replacement |
|---|---|---|
| 0.9.0 | below | x |
| 1.0.0 | old-boundary | x |
| 1.0.10 | inside | inner words |
| 1.1.0 | new-boundary | None. |
| 1.2.0 | above | x |
EOF
jq --arg b "$B" --arg d "$D" '.skills.tdd.ref = $b | .skills.grilling.ref = $d' "$repo/skills-lock.json" > "$tmp/l" && mv "$tmp/l" "$repo/skills-lock.json"

# Upstream: tdd's folder has moved past B, code-review's has not; triage has no
# head reported; grilling has an update and research does not.
echo '{"heads": {"tdd": "'$C'", "code-review": "'$B'", "grilling": "'$D'", "research": "'$A'"}, "unreachable": []}' > "$tmp/heads.json"
out=$(bash "$plan" "$repo" "$tmp/heads.json"); rc=$?
check_rc "a plan exits 0" 0 "$rc"
check "a consumer checkout is consumer mode" consumer "$(jq -r .mode <<<"$out")"

check "each source-repo skill carries its old and new version and its changelog" \
  '[{"skill":"setup-skills","old_version":"2.0.0","new_version":"2.0.1","changelog":".claude/skills/setup-skills/CHANGELOG.md"},{"skill":"ship","old_version":"1.0.0","new_version":"1.1.0","changelog":".claude/skills/ship/CHANGELOG.md"}]' \
  "$(jq -c .source_skills <<<"$out")"

check "every composed skill refreshes at its first composes pin, from the old tree's lock ref; an unpinned entry is none" \
  '[{"skill":"code-review","source":"o/r","pin":"'$B'","old_ref":null,"install":"npx skills add o/r#'$B' --skill code-review --agent claude-code -y </dev/null"},{"skill":"tdd","source":"o/r","pin":"'$B'","old_ref":"'$A'","install":"npx skills add o/r#'$B' --skill tdd --agent claude-code -y </dev/null"},{"skill":"triage","source":"o/r","pin":"'$A'","old_ref":"'$A'","install":"npx skills add o/r#'$A' --skill triage --agent claude-code -y </dev/null"}]' \
  "$(jq -c .composed <<<"$out")"

check "a composed skill whose upstream head is past its pin is a drift row; one at its pin, or with no head, is not" \
  '[{"skill":"tdd","pin":"'$B'","head":"'$C'"}]' "$(jq -c .drift <<<"$out")"

check "an other skill whose head differs from its old ref is offered at the head; one at its head is not" \
  '[{"skill":"grilling","source":"o/r","old_ref":"'$A'","head":"'$D'","install":"npx skills add o/r#'$D' --skill grilling --agent claude-code -y </dev/null"}]' \
  "$(jq -c .others <<<"$out")"

check "a changed template file names its setup-skills section; a changed SKILL.md alone names none" \
  '[{"section":"pr-template","template":"pull_request_template.md"}]' "$(jq -c .sections <<<"$out")"

check "a retired term is planned when its version is above the old version and at or below the new one" \
  '[{"skill":"ship","version":"1.0.10","term":"inside","replacement":"inner words"},{"skill":"ship","version":"1.1.0","term":"new-boundary","replacement":null}]' \
  "$(jq -c .retired <<<"$out")"

# An added file under reviewers/ is a change to that section's template, though
# git diff would not see an untracked file.
echo new > "$repo/.claude/skills/setup-skills/reviewers/extra.md"
check "a file added under reviewers/ names reviewer scaffolding" \
  '["pr-template","reviewer-scaffolding"]' "$(bash "$plan" "$repo" "$tmp/heads.json" | jq -c '[.sections[].section]')"
rm "$repo/.claude/skills/setup-skills/reviewers/extra.md"

# The Ship block's template is a section of its own, unlike the SKILL.md it
# moved out of.
echo new > "$repo/.claude/skills/setup-skills/ship-block.md"
check "a changed Ship block template names the ship-block section" \
  '[{"section":"pr-template","template":"pull_request_template.md"},{"section":"ship-block","template":"ship-block.md"}]' \
  "$(bash "$plan" "$repo" "$tmp/heads.json" | jq -c .sections)"
git -C "$repo" checkout -q -- .claude/skills/setup-skills/ship-block.md

# With the templates reverted, setup-skills' SKILL.md is the one change left.
git -C "$repo" checkout -q -- .claude/skills/setup-skills/pull_request_template.md
check "a changed setup-skills SKILL.md alone re-runs no section" \
  '[]' "$(bash "$plan" "$repo" "$tmp/heads.json" | jq -c .sections)"

# A source skill new to this checkout has no old version.
skill "$repo" update-skills 1.0.0
jq '.skills["update-skills"] = {source: "Gharib89/skills"}' "$repo/skills-lock.json" > "$tmp/l" && mv "$tmp/l" "$repo/skills-lock.json"
check "a source-repo skill the old tree lacks has a null old version" \
  'null 1.0.0' "$(bash "$plan" "$repo" "$tmp/heads.json" | jq -r '.source_skills[] | select(.skill == "update-skills") | "\(.old_version) \(.new_version)"')"
printf '%s\n' '| Version | Term | Replacement |' '|---|---|---|' '| 1.0.0 | fresh | x |' > "$repo/.claude/skills/update-skills/retired-terms.md"
check "a source-repo skill the old tree lacks plans no retired rows" \
  '[]' "$(bash "$plan" "$repo" "$tmp/heads.json" | jq -c '[.retired[] | select(.skill == "update-skills")]')"

# --old names the tree before the refresh when it is not HEAD.
git -C "$repo" add -A && git -C "$repo" commit -qm refreshed
check "--old reads the old tree at that ref" \
  '1.0.0' "$(bash "$plan" "$repo" "$tmp/heads.json" --old HEAD~1 | jq -r '.source_skills[] | select(.skill == "ship") | .old_version')"

# The source repo installs its own skills from `.`.
jq '.skills.ship.source = "."' "$repo/skills-lock.json" > "$tmp/l" && mv "$tmp/l" "$repo/skills-lock.json"
check "a lock recording ship from . is source mode" source "$(bash "$plan" "$repo" "$tmp/heads.json" | jq -r .mode)"

# The renumber to 0.x (#369) moves every version down, M.m.p to 0.M.p, so an
# installed pre-renumber version is read as its 0.x counterpart: 5.2.1 as 0.5.1,
# whose range to 0.11.4 still holds the 0.9.0 rows.
r2=$tmp/renumbered
mkdir -p "$r2" && git -C "$r2" init -q && git -C "$r2" config user.email t@t && git -C "$r2" config user.name t
skill "$r2" ship 5.2.1; lock "$r2" '{"ship": {"source": "Gharib89/skills"}}'
git -C "$r2" add -A && git -C "$r2" commit -qm old
skill "$r2" ship 0.11.4
printf '%s\n' '| Version | Term | Replacement |' '|---|---|---|' '| 0.5.1 | at-old | x |' '| 0.9.0 | crossed | x |' '| 0.11.4 | at-new | x |' '| 0.12.0 | above | x |' \
  > "$r2/.claude/skills/ship/retired-terms.md"
echo '{"heads": {}, "unreachable": []}' > "$tmp/heads0.json"
out=$(bash "$plan" "$r2" "$tmp/heads0.json"); rc=$?
check_rc "a plan across the renumber exits 0" 0 "$rc"
check "a plan across the renumber reads the installed M.m.p as 0.M.p" \
  '["crossed","at-new"]' "$(jq -c '[.retired[].term]' <<<"$out")"
check "a plan across the renumber still reports the installed version as it was" \
  '5.2.1' "$(jq -r '.source_skills[0].old_version' <<<"$out")"
# A consumer that skips the whole 0.x line, 8.0.0 straight to a public 1.0.0,
# still crosses the renumber: the version went down, which only it does.
git -C "$r2" checkout -q -- . && skill "$r2" ship 8.0.0 && git -C "$r2" commit -qam eight
skill "$r2" ship 1.0.0
printf '%s\n' '| Version | Term | Replacement |' '|---|---|---|' '| 0.8.0 | at-old | x |' '| 0.9.0 | crossed | x |' '| 1.0.0 | at-new | x |' \
  > "$r2/.claude/skills/ship/retired-terms.md"
check "a plan from a pre-renumber version to a 1.x one reads the installed M.m.p as 0.M.p" \
  '["crossed","at-new"]' "$(bash "$plan" "$r2" "$tmp/heads0.json" | jq -c '[.retired[].term]')"

# A prerelease version compares by its release part, in the skill's version
# and in a row's, and a row with no replacement cell, or a lowercase none, has
# no replacement. An aligned separator row is no row.
skill "$repo" setup-skills 2.1.0-rc.1 "o/r#$A:triage"
printf '%s\n' '| Version | Term | Replacement |' '| :--- |:---:| ---: |' '| 2.0.5 | short-row |' '| 2.0.6 | lower | none |' '| 2.0.7-rc.1 | pre | x |' \
  > "$repo/.claude/skills/setup-skills/retired-terms.md"
out=$(bash "$plan" "$repo" "$tmp/heads.json"); rc=$?
check_rc "a prerelease version still plans" 0 "$rc"
check "a missing or lowercase none replacement is null" \
  '[{"skill":"setup-skills","version":"2.0.5","term":"short-row","replacement":null},{"skill":"setup-skills","version":"2.0.6","term":"lower","replacement":null},{"skill":"setup-skills","version":"2.0.7-rc.1","term":"pre","replacement":"x"}]' \
  "$(jq -c .retired <<<"$out")"
skill "$repo" setup-skills not-a-version "o/r#$A:triage"
out=$(bash "$plan" "$repo" "$tmp/heads.json" 2>/dev/null); rc=$?
check_rc "a version the retired range cannot compare exits 1" 1 "$rc"
check "a version the retired range cannot compare names the file" \
  "cannot read retired terms: $repo/.claude/skills/setup-skills/retired-terms.md" "$(jq -r .error <<<"$out")"
# A row whose version cell is no version fails the plan rather than vanish.
skill "$repo" setup-skills 2.1.0 "o/r#$A:triage"
echo '| 2.0 | typo | x |' >> "$repo/.claude/skills/setup-skills/retired-terms.md"
out=$(bash "$plan" "$repo" "$tmp/heads.json" 2>/dev/null); rc=$?
check_rc "a malformed version cell exits 1" 1 "$rc"

out=$(bash "$plan" "$repo" "$tmp/nope.json" 2>/dev/null); rc=$?
check_rc "an unreadable heads file exits 1" 1 "$rc"
check "an unreadable heads file names it" "cannot read heads: $tmp/nope.json" "$(jq -r .error <<<"$out")"

finish
