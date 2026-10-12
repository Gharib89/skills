#!/usr/bin/env bash
# The frontmatter of every skill this repo writes, the lock's `source: "."`
# entries. An agent picks a skill by its frontmatter alone, so five rules hold:
# a frontmatter opening on line 1 with `---` and closed by another; only the
# keys `name`, `description`, `argument-hint`, `disable-model-invocation` and
# `metadata` at column 0 (a key outside this set is one no skill here relies
# on, so it is a typo or an untested setting); a value that opens a quote
# closes it, and one YAML would read as structure is quoted, since a YAML loader
# rejects the frontmatter otherwise while the text still passes the rules below; a `description` of at most 1,024
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

# <file>: `key<TAB><key>` per column-0 key, `unbalanced<TAB><key>` per one
# whose value opens a quote it does not close (an escaped `\"` closes nothing),
# `plain<TAB><key>` per unquoted one YAML reads as structure (a `: ` inside it,
# or an indicator such as `[` or a backtick first), then `dmi<TAB><value>`,
# `desc<TAB><description>` and `fence<TAB><none|open|closed>`. A value's
# indented continuation lines join with one space, so plain, quoted and folded
# scalars all come out as the one line an agent reads. A `#` comment after an
# unquoted value, or after a quoted one's closing quote, is YAML's, not the
# value's, so it is dropped. In a `>` or `|` block scalar a quote is literal
# text, so it is neither checked nor stripped.
fields() {
  awk 'function flush() {
         if (key != "" && !block && v ~ /^["\047]/) {
           if (substr(v, 1, 1) == "\"") closed = match(v, /^"([^"\\]|\\.)*"/)
           else closed = match(v, "^\047([^\047]|\047\047)*\047")
           if (!closed || substr(v, RLENGTH + 1) !~ /^([ \t]+#.*)?$/) print "unbalanced\t" key
           else v = substr(v, 2, RLENGTH - 2) }
         else if (key != "" && !block && !nested && (v ~ /^[][{}&*!|>%@`]/ || v ~ /:([ \t]|$)/))
           print "plain\t" key
         if (key == "description") desc = v }
       NR == 1 { if ($0 != "---") exit; fm = 1; fence = "open"; next }
       fm && $0 == "---" { fence = "closed"; exit }
       /^[^ \t#][^:]*:/ {
         flush()
         key = substr($0, 1, index($0, ":") - 1); val = substr($0, length(key) + 2)
         sub(/^[ \t]+/, "", val)
         if (val !~ /^["\047]/) sub(/[ \t]+#.*$/, "", val)
         sub(/[ \t]+$/, "", val)
         print "key\t" key
         if (key == "disable-model-invocation") dmi = val
         block = (val ~ /^[>|]([1-9]?[-+]?|[-+][1-9])$/); nested = (val == ""); v = block ? "" : val
         next }
       /^[ \t]/ { line = $0; sub(/^[ \t]+/, "", line); v = (v == "" ? line : v " " line) }
       END { flush()
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
      unbalanced) echo "$rel: frontmatter key $value has an unbalanced quote"; rc=1 ;;
      plain) echo "$rel: frontmatter key $value needs quoting"; rc=1 ;;
      dmi) dmi=$value ;;
      desc) desc=$value ;;
      fence) fence=$value ;;
    esac
  done <<<"$out"
  [ "$fence" != none ] || { echo "$rel: frontmatter has no opening ---"; rc=1; continue; }
  [ "$fence" = closed ] || { echo "$rel: frontmatter has no closing ---"; rc=1; continue; }
  # Characters under any locale: the cloud sandbox runs with LANG and LC_ALL
  # empty, where ${#desc} counts bytes, so drop UTF-8 continuation bytes first.
  len=$(printf %s "$desc" | LC_ALL=C tr -d '\200-\277' | wc -c) || exit 2
  [ "$len" -le 1024 ] || { echo "$rel: description is $len characters, over 1024"; rc=1; }
  [ "$dmi" = true ] && continue
  case $desc in *"Use when"*) ;; *) echo "$rel: description has no \"Use when\" clause"; rc=1 ;; esac
done <<<"$names"
exit $rc
