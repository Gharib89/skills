#!/usr/bin/env bash
# The frontmatter of every skill this repo writes, the lock's `source: "."`
# entries. An agent picks a skill by its frontmatter alone, so four rules hold:
# a frontmatter opening on line 1 with `---` and closed by another; only the
# keys `name`, `description`, `argument-hint`, `disable-model-invocation` and
# `metadata` at column 0 (a key outside this set is one no skill here relies
# on, so it is a typo or an untested setting); a `description` of at most 1,024
# characters, counted as the agent reads it, a folded scalar's lines joined by
# one space; and a "Use when" clause in the `description` of every skill
# without `disable-model-invocation: true`, because that clause is what routes
# an agent to a skill it may invoke on its own. `scripts/check.sh full` runs
# this as its `frontmatter` row, which scripts/local-gate.sh reports under the
# same name, in every lane.
#
#   scripts/frontmatter-check.sh [<root>]
#
# stdout: one line per violation, nothing when every skill passes
# exit: 0 clean · 1 a violation · 2 tooling
set -uo pipefail
root=${1:-.}
[ -d "$root" ] || { printf 'not a directory: %s\n' "$root" >&2; exit 2; }
names=$(jq -r '.skills | to_entries[] | select(.value.source == ".") | .key' "$root/skills-lock.json") || exit 2

# <file>: `key<TAB><key>` per column-0 key, then `dmi<TAB><value>`,
# `desc<TAB><description>` and `fence<TAB><none|open|closed>`. A
# description's indented continuation lines join with one space, so plain,
# quoted and folded scalars all come out as the one line an agent reads.
fields() {
  awk 'NR == 1 { if ($0 != "---") exit; fm = 1; fence = "open"; next }
       fm && $0 == "---" { fence = "closed"; exit }
       /^[^ \t#][^:]*:/ {
         key = substr($0, 1, index($0, ":") - 1); val = substr($0, length(key) + 2)
         sub(/^[ \t]+/, "", val); sub(/[ \t]+$/, "", val)
         print "key\t" key; indesc = (key == "description")
         if (key == "disable-model-invocation") dmi = val
         if (indesc) desc = (val ~ /^[>|][-+]?$/) ? "" : val
         next }
       indesc && /^[ \t]/ { line = $0; sub(/^[ \t]+/, "", line); desc = (desc == "" ? line : desc " " line) }
       END { if (desc ~ /^".*"$/ || desc ~ /^'\''.*'\''$/) desc = substr(desc, 2, length(desc) - 2)
             print "dmi\t" dmi; print "desc\t" desc; print "fence\t" (fence == "" ? "none" : fence) }' "$1"
}

rc=0
while IFS= read -r n; do
  [ -n "$n" ] || continue
  rel=skills/$n/SKILL.md
  out=$(fields "$root/$rel") || { printf 'cannot read %s\n' "$rel" >&2; exit 2; }
  dmi='' desc='' fence=none
  while IFS=$'\t' read -r kind value; do
    case $kind in
      key)
        case $value in
          name|description|argument-hint|disable-model-invocation|metadata) ;;
          *) echo "$rel: frontmatter key $value is not allowed"; rc=1 ;;
        esac ;;
      dmi) dmi=$value ;;
      desc) desc=$value ;;
      fence) fence=$value ;;
    esac
  done <<<"$out"
  [ "$fence" != none ] || { echo "$rel: frontmatter has no opening ---"; rc=1; continue; }
  [ "$fence" = closed ] || { echo "$rel: frontmatter has no closing ---"; rc=1; continue; }
  [ "${#desc}" -le 1024 ] || { echo "$rel: description is ${#desc} characters, over 1024"; rc=1; }
  [ "$dmi" = true ] && continue
  case $desc in *"Use when"*) ;; *) echo "$rel: description has no \"Use when\" clause"; rc=1 ;; esac
done <<<"$names"
exit $rc
