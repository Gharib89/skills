#!/usr/bin/env bash
# update-skills' heads mechanic: each upstream skill's head, folder-aware, read
# from GitHub's public REST API with curl. A fake `curl` in front of PATH
# answers from fixtures keyed by URL and logs each one, so the requests the
# mechanic sends are asserted and nothing reaches the network.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

heads=skills/update-skills/scripts/heads.sh
usage='usage: heads <checkout>'
A=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa; H=1111111111111111111111111111111111111111
X=2222222222222222222222222222222222222222

tmp=$(mktemp -d) || exit 2
trap 'rm -rf "$tmp"' EXIT

out=$(bash "$heads" --help 2>"$tmp/err"); rc=$?
check "--help prints its usage" "$usage" "$out"
check_rc "--help exits 0" 0 "$rc"
check "--help writes nothing on stderr" "" "$(cat "$tmp/err")"
out=$(bash "$heads" 2>/dev/null); rc=$?
check "a bare call answers its usage line" "$usage" "$(jq -r .error <<<"$out")"
check_rc "a bare call exits 2" 2 "$rc"

# The fake: the URL is the last argument; its fixture is the URL's path under
# api.github.com with `/` read as `_`. No fixture is a failed request, as
# `curl -f` answers a 404.
mkdir -p "$tmp/bin" "$tmp/fix"
cat > "$tmp/bin/curl" <<'EOF'
#!/usr/bin/env bash
for url; do :; done
printf '%s\n' "$url" >> "$FAKE_CURL_LOG"
f=$FAKE_CURL_FIX/$(printf '%s' "${url#https://api.github.com/}" | tr '/' '_')
[ -f "$f" ] || exit 22
cat "$f"
EOF
chmod +x "$tmp/bin/curl"
export FAKE_CURL_LOG=$tmp/log FAKE_CURL_FIX=$tmp/fix PATH="$tmp/bin:$PATH"
fix() { printf '%s' "$2" > "$tmp/fix/$(printf '%s' "$1" | tr '/' '_')"; }

repo=$tmp/repo
mkdir -p "$repo/.claude/skills/ship" "$repo/.claude/skills/setup-skills"
# setup-skills composes code-review a second time, at a pin the first entry
# overrides, and grilling unpinned, which is no pin at all.
printf -- '---\nname: ship\nmetadata:\n  composes: o/r#%s:tdd o/r#%s:code-review o/r#%s:find-docs\n---\n' "$A" "$A" "$H" > "$repo/.claude/skills/ship/SKILL.md"
printf -- '---\nname: setup-skills\nmetadata:\n  composes: o/r#%s:code-review o/r:grilling\n---\n' "$X" > "$repo/.claude/skills/setup-skills/SKILL.md"
jq -n --arg a "$A" '{version: 1, skills: {
  ship: {source: "gharib89/skills", sourceType: "github", skillPath: "skills/ship/SKILL.md"},
  tdd: {source: "o/r", ref: $a, sourceType: "github", skillPath: "skills/engineering/tdd/SKILL.md"},
  "code-review": {source: "o/r", sourceType: "github", skillPath: "skills/engineering/code-review/SKILL.md"},
  "find-docs": {source: "o/r", ref: $a, sourceType: "github", skillPath: "skills/find-docs/SKILL.md"},
  grilling: {source: "o/r", ref: $a, sourceType: "github", skillPath: "skills/grilling/SKILL.md"},
  research: {source: "o/r", sourceType: "github", skillPath: "skills/research/SKILL.md"},
  solo: {source: "p/q", ref: $a, sourceType: "github", skillPath: "SKILL.md"},
  wide: {source: "w/w", ref: $a, sourceType: "github", skillPath: "skills/wide/SKILL.md"},
  far: {source: "z/z", sourceType: "github", skillPath: "skills/far/SKILL.md"},
  mine: {source: "./local", sourceType: "local"}}}' > "$repo/skills-lock.json"

fix "repos/o/r/commits/HEAD" '{"sha": "'$H'"}'
# Between A and HEAD, tdd's folder changed, and a folder whose name only starts
# with code-review's did; code-review's own and grilling's did not.
fix "repos/o/r/compare/$A...$H" '{"files": [{"filename": "skills/engineering/tdd/SKILL.md"}, {"filename": "skills/engineering/code-review-extra/SKILL.md"}]}'
# A skill at the repo root owns the whole repo, so any changed file moves it.
fix "repos/p/q/commits/HEAD" '{"sha": "'$H'"}'
fix "repos/p/q/compare/$A...$H" '{"files": [{"filename": "README.md"}]}'
# A compare lists 300 files at most, so a full list cannot show a folder
# unchanged. z/z answers nothing.
fix "repos/w/w/commits/HEAD" '{"sha": "'$H'"}'
fix "repos/w/w/compare/$A...$H" "$(jq -cn '{files: [range(300) | {filename: "other/\(.)"}]}')"

out=$(bash "$heads" "$repo" 2>"$tmp/err"); rc=$?
check_rc "heads exits 0 with one upstream unreachable" 0 "$rc"
check "a skill whose folder changed since its base is at HEAD; one unchanged stays at its base; one with no base is at HEAD" \
  '{"code-review":"'$A'","find-docs":"'$H'","grilling":"'$A'","research":"'$H'","solo":"'$H'","tdd":"'$H'","wide":"'$H'"}' "$(jq -cS .heads <<<"$out")"
check "an unreachable upstream is a row naming its skill and the request, not a head" \
  '[{"skill":"far","error":"cannot read https://api.github.com/repos/z/z/commits/HEAD"}]' "$(jq -c .unreachable <<<"$out")"
check "the first composes pin, not a later one or the lock's ref, is a composed skill's base; a source-repo or local entry is never asked for" \
  "https://api.github.com/repos/o/r/commits/HEAD
https://api.github.com/repos/o/r/compare/$A...$H
https://api.github.com/repos/p/q/commits/HEAD
https://api.github.com/repos/p/q/compare/$A...$H
https://api.github.com/repos/w/w/commits/HEAD
https://api.github.com/repos/w/w/compare/$A...$H
https://api.github.com/repos/z/z/commits/HEAD" "$(sort -u "$tmp/log")"
check "each upstream's HEAD is asked for once" 1 "$(grep -c 'repos/o/r/commits/HEAD' "$tmp/log")"

echo '[' > "$repo/skills-lock.json"
out=$(bash "$heads" "$repo" 2>/dev/null); rc=$?
check_rc "an unreadable lock exits 1" 1 "$rc"
check "an unreadable lock names it" "cannot read lock: $repo/skills-lock.json" "$(jq -r .error <<<"$out")"

finish
