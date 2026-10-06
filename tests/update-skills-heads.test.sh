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
check "--help opens with its usage" "$usage" "$(sed -n 1p <<<"$out")"
check "--help names its stdout fields next" stdout: "$(sed -n 2p <<<"$out" | cut -c1-7)"
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
printf '%s\n' "$*" >> "$FAKE_CURL_LOG.args"
# A config read from stdin (`-K -`) is how the token travels; log it.
case " $* " in *" -K - "*) cat >> "$FAKE_CURL_LOG.stdin" ;; esac
f=$FAKE_CURL_FIX/$(printf '%s' "${url#https://api.github.com/}" | tr '/' '_')
[ -f "$f" ] || exit 22
cat "$f"
EOF
chmod +x "$tmp/bin/curl"
# A retry waits between attempts; the fake sleep keeps the test from doing so.
printf '#!/bin/sh\nexit 0\n' > "$tmp/bin/sleep"; chmod +x "$tmp/bin/sleep"
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
check "every request is time-bounded, so a stalled upstream fails into an unreachable row rather than hanging" \
  0 "$(grep -vc -- '--connect-timeout 10 --max-time 30' "$tmp/log.args")"
check "each upstream's HEAD is asked for once" 1 "$(grep -c 'repos/o/r/commits/HEAD' "$tmp/log")"

# The token is an Authorization header on curl's stdin as a config, never on
# argv, where any user on the host reads it from /proc/<pid>/cmdline; with no
# token, no header and no stdin config at all.
rm -f "$tmp"/log*
GH_TOKEN=tok-secret-123 GITHUB_TOKEN='' bash "$heads" "$repo" >/dev/null 2>&1
check "a set token is on no curl argv" 0 "$(grep -c 'tok-secret-123' "$tmp/log.args")"
check "a set token reaches curl as a config on stdin" \
  'header = "Authorization: Bearer tok-secret-123"' "$(sort -u "$tmp/log.stdin" 2>/dev/null)"
rm -f "$tmp"/log*
env -u GH_TOKEN -u GITHUB_TOKEN bash "$heads" "$repo" >/dev/null 2>&1
check "with no token, no argv names an Authorization header or a config" 0 "$(grep -cE 'Authorization|-K' "$tmp/log.args")"
check "with no token, curl gets no stdin config" "" "$(cat "$tmp/log.stdin" 2>/dev/null)"

# A GET that fails is tried again: a flaky route must not empty `heads`. A curl
# that fails the first attempts at each URL, then answers, gives the same result.
real_curl=$tmp/bin/curl; mv "$real_curl" "$tmp/curl.real"
cat > "$real_curl" <<'EOF'
#!/usr/bin/env bash
for url; do :; done
n=$FAKE_CURL_LOG.tries.$(printf '%s' "$url" | tr '/:' '__')
echo x >> "$n"
[ "$(wc -l < "$n")" -gt "${FAKE_CURL_FLAKY:-0}" ] || exit 28
exec "$(dirname "$0")/../curl.real" "$@"
EOF
chmod +x "$real_curl"
rm -f "$tmp"/log*
out=$(FAKE_CURL_FLAKY=1 bash "$heads" "$repo" 2>/dev/null); rc=$?
check_rc "a first attempt that fails at every URL still exits 0" 0 "$rc"
check "the retried reads give the same heads" \
  '{"code-review":"'$A'","find-docs":"'$H'","grilling":"'$A'","research":"'$H'","solo":"'$H'","tdd":"'$H'","wide":"'$H'"}' "$(jq -cS .heads <<<"$out")"
rm -f "$tmp"/log*
FAKE_CURL_FLAKY=99 bash "$heads" "$repo" >/dev/null 2>&1
check "a read that never answers is tried three times, not forever" \
  3 "$(wc -l < "$tmp/log.tries.https___api.github.com_repos_z_z_commits_HEAD" | tr -d ' ')"

# When no upstream answers there is nothing to plan against: the exit says so,
# with the count, where a clean exit 0 over an empty `heads` would read as "no
# drift".
one=$tmp/one; mkdir -p "$one"
jq -n --arg a "$A" '{version: 1, skills: {
  tdd: {source: "o/r", ref: $a, sourceType: "github", skillPath: "skills/tdd/SKILL.md"},
  far: {source: "z/z", sourceType: "github", skillPath: "skills/far/SKILL.md"}}}' > "$one/skills-lock.json"
rm -f "$tmp"/log*
out=$(FAKE_CURL_FLAKY=99 bash "$heads" "$one" 2>"$tmp/err"); rc=$?
check_rc "every upstream read failing exits 1" 1 "$rc"
check "the exit names the count on stderr" \
  "every upstream read failed: 2 skills unreachable" "$(cat "$tmp/err")"
check "stdout still carries the unreachable rows" 2 "$(jq '.unreachable | length' <<<"$out")"
rm -f "$tmp"/log*
out=$(FAKE_CURL_FLAKY=1 bash "$heads" "$one" 2>/dev/null); rc=$?
check_rc "every read answering on its second attempt keeps exit 0" 0 "$rc"

echo '[' > "$repo/skills-lock.json"
out=$(bash "$heads" "$repo" 2>/dev/null); rc=$?
check_rc "an unreadable lock exits 1" 1 "$rc"
check "an unreadable lock names it" "cannot read lock: $repo/skills-lock.json" "$(jq -r .error <<<"$out")"

finish
