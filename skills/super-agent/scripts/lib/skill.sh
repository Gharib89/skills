# The super agent's own skill version against its source's, sourced by _lib.sh.

# The repo the super agent's own skill is published from: a refresh
# (`npx skills@1.8.1 add`) installs from it, so its default branch holds the version a
# refresh would bring.
sa_skill_source='Gharib89/skills'

# `ver`: an X.Y.Z version as an array of numbers, so versions compare by number.
# `skill_version`: the one `  version: X.Y.Z` line in a SKILL.md's frontmatter (between
# its opening and closing `---`, under any key; a SKILL.md carries it as
# `metadata.version`), else "": a missing, repeated or malformed version
# (`0.67`, `v1.0.0`, a pre-release) is unread, never a number, and a body line is never read.
sa_jq_ver='def ver: split(".") | map(tonumber);
  def skill_version: split("\n") | if .[0] != "---" then "" else .[1:]
    | [.[:(index("---") // 0)][] | capture("^  version: (?<v>.*)$").v]
    | if length == 1 and (.[0] | test("^[0-9]+\\.[0-9]+\\.[0-9]+$")) then .[0] else "" end end;'

# sa_skill_version <owner/name> <path>: the version of the SKILL.md at <path> on the
# repo's default branch, through `gh` REST; nothing printed when it cannot be read.
sa_skill_version() {
  gh api "repos/$1/contents/$2" 2>/dev/null </dev/null \
    | jq -r "$sa_jq_ver"'.content // "" | gsub("\\s"; "") | @base64d | skill_version' 2>/dev/null
}

# sa_skill_stale: {loaded, source, stale}, the version of the super-agent copy running
# this script against the one on `sa_skill_source`; `stale` true when the loaded one is
# older, null with either version unread.
sa_skill_stale() {
  jq -cn --arg l "$(jq -Rsr "$sa_jq_ver"'skill_version' "$(dirname "${BASH_SOURCE[0]}")/../../SKILL.md" 2>/dev/null)" \
    --arg s "$(sa_skill_version "$sa_skill_source" skills/super-agent/SKILL.md)" "$sa_jq_ver"'
    {loaded: (if $l == "" then null else $l end), source: (if $s == "" then null else $s end),
     stale: (if $l == "" or $s == "" then null else ($l | ver) < ($s | ver) end)}'
}
