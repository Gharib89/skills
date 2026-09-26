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
printf -- '---\nname: ship\nmetadata:\n  composes: o/r#%s:tdd o/r#%s:code-review o/r#%s:find-docs\n---\n' "$A" "$A" "$H" > "$repo/.claude/skills/ship/SKILL.md"
printf -- '---\nname: setup-skills\n---\n' > "$repo/.claude/skills/setup-skills/SKILL.md"
jq -n --arg a "$A" '{version: 1, skills: {
  ship: {source: "gharib89/skills", sourceType: "github", skillPath: "skills/ship/SKILL.md"},
  tdd: {source: "o/r", ref: $a, sourceType: "github", skillPath: "skills/engineering/tdd/SKILL.md"},
  "code-review": {source: "o/r", sourceType: "github", skillPath: "skills/engineering/code-review/SKILL.md"},
  "find-docs": {source: "o/r", ref: $a, sourceType: "github", skillPath: "skills/find-docs/SKILL.md"},
  grilling: {source: "o/r", ref: $a, sourceType: "github", skillPath: "skills/grilling/SKILL.md"},
  research: {source: "o/r", sourceType: "github", skillPath: "skills/research/SKILL.md"},
  mine: {source: "./local", sourceType: "local"}}}' > "$repo/skills-lock.json"

fix "repos/o/r/commits/HEAD" '{"sha": "'$H'"}'
# Between A and HEAD, tdd's folder changed, and a folder whose name only starts
# with code-review's did; code-review's own and grilling's did not.
fix "repos/o/r/compare/$A...$H" '{"files": [{"filename": "skills/engineering/tdd/SKILL.md"}, {"filename": "skills/engineering/code-review-extra/SKILL.md"}]}'

out=$(bash "$heads" "$repo"); rc=$?
check_rc "heads exits 0" 0 "$rc"
check "a skill whose folder changed since its base is at HEAD; one unchanged stays at its base; one with no base is at HEAD" \
  '{"code-review":"'$A'","find-docs":"'$H'","grilling":"'$A'","research":"'$H'","tdd":"'$H'"}' "$(jq -cS . <<<"$out")"
check "the composes pin, not the lock's ref, is a composed skill's base; a source-repo or local entry is never asked for" \
  "https://api.github.com/repos/o/r/commits/HEAD
https://api.github.com/repos/o/r/compare/$A...$H" "$(sort -u "$tmp/log")"

# A request that fails is an unreachable upstream, not a head.
rm "$tmp/fix/repos_o_r_commits_HEAD"
out=$(bash "$heads" "$repo" 2>/dev/null); rc=$?
check_rc "an unreachable upstream exits 1" 1 "$rc"
check "an unreachable upstream names the request" "cannot read https://api.github.com/repos/o/r/commits/HEAD" "$(jq -r .error <<<"$out")"

finish
