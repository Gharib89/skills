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
for f in pull_request_template.md local-gate.sh coding-standards.md dimension-labels.md issue-tracker-ado.md reviewers/github-claude-review.md; do
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
  '[{"skill":"code-review","source":"o/r","pin":"'$B'","old_ref":null,"install":"npx skills add o/r#'$B' --skill code-review --agent claude-code -y"},{"skill":"tdd","source":"o/r","pin":"'$B'","old_ref":"'$A'","install":"npx skills add o/r#'$B' --skill tdd --agent claude-code -y"},{"skill":"triage","source":"o/r","pin":"'$A'","old_ref":"'$A'","install":"npx skills add o/r#'$A' --skill triage --agent claude-code -y"}]' \
  "$(jq -c .composed <<<"$out")"

check "a composed skill whose upstream head is past its pin is a drift row; one at its pin, or with no head, is not" \
  '[{"skill":"tdd","pin":"'$B'","head":"'$C'"}]' "$(jq -c .drift <<<"$out")"

check "an other skill whose head differs from its old ref is offered at the head; one at its head is not" \
  '[{"skill":"grilling","source":"o/r","old_ref":"'$A'","head":"'$D'","install":"npx skills add o/r#'$D' --skill grilling --agent claude-code -y"}]' \
  "$(jq -c .others <<<"$out")"

check "a changed template file names its setup-skills section; a changed SKILL.md alone names none" \
  '[{"section":"pr-template","template":"pull_request_template.md"}]' "$(jq -c .sections <<<"$out")"

# An added file under reviewers/ is a change to that section's template, though
# git diff would not see an untracked file.
echo new > "$repo/.claude/skills/setup-skills/reviewers/extra.md"
check "a file added under reviewers/ names reviewer scaffolding" \
  '["pr-template","reviewer-scaffolding"]' "$(bash "$plan" "$repo" "$tmp/heads.json" | jq -c '[.sections[].section]')"
rm "$repo/.claude/skills/setup-skills/reviewers/extra.md"

# With the templates reverted, setup-skills' SKILL.md is the one change left.
git -C "$repo" checkout -q -- .claude/skills/setup-skills/pull_request_template.md
check "a changed setup-skills SKILL.md alone re-runs no section" \
  '[]' "$(bash "$plan" "$repo" "$tmp/heads.json" | jq -c .sections)"

# A source skill new to this checkout has no old version.
skill "$repo" update-skills 1.0.0
jq '.skills["update-skills"] = {source: "Gharib89/skills"}' "$repo/skills-lock.json" > "$tmp/l" && mv "$tmp/l" "$repo/skills-lock.json"
check "a source-repo skill the old tree lacks has a null old version" \
  'null 1.0.0' "$(bash "$plan" "$repo" "$tmp/heads.json" | jq -r '.source_skills[] | select(.skill == "update-skills") | "\(.old_version) \(.new_version)"')"

# --old names the tree before the refresh when it is not HEAD.
git -C "$repo" add -A && git -C "$repo" commit -qm refreshed
check "--old reads the old tree at that ref" \
  '1.0.0' "$(bash "$plan" "$repo" "$tmp/heads.json" --old HEAD~1 | jq -r '.source_skills[] | select(.skill == "ship") | .old_version')"

# The source repo installs its own skills from `.`.
jq '.skills.ship.source = "."' "$repo/skills-lock.json" > "$tmp/l" && mv "$tmp/l" "$repo/skills-lock.json"
check "a lock recording ship from . is source mode" source "$(bash "$plan" "$repo" "$tmp/heads.json" | jq -r .mode)"

out=$(bash "$plan" "$repo" "$tmp/nope.json" 2>/dev/null); rc=$?
check_rc "an unreadable heads file exits 1" 1 "$rc"
check "an unreadable heads file names it" "cannot read heads: $tmp/nope.json" "$(jq -r .error <<<"$out")"

finish
