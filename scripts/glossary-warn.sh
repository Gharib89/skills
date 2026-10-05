#!/usr/bin/env bash
# Glossary warning: names each `_Avoid_` word of GLOSSARY.md that a diff adds to
# a markdown file.
#
# GLOSSARY.md lists, per term, the words a doc should not use for it, and a word
# creeps back in through a PR nobody re-reads against the glossary. This reads
# the lines the branch adds, not the whole tree, so the words already in the
# docs are not a backlog this reports. It is a warning, never a gate: an avoided
# word is often a plain English word (`check`, `run`) in a sentence that is not
# about the term, so a hit asks for a look, not a fix.
#
#   scripts/glossary-warn.sh [<base>]      <base> defaults to origin/HEAD
#
# Reads the `**<Term>**:` entries and each one's `_Avoid_: a, b, c` line, drops a
# parenthetical and backticks from each word, and matches it case-insensitively
# as a whole word or phrase (a letter, digit or underscore beside it is no
# match). Added lines come from `git diff <base>...HEAD` over `*.md`, minus
# every CHANGELOG.md (the release run writes those) and the root GLOSSARY.md.
#
# stdout: per hit, `glossary: <file>:<line>: "<word>" is on the _Avoid_ list of
#         <Term>`; nothing when clean
# stderr: on tooling, the reason
# exit: 0 it ran, hits or not · 2 tooling (no GLOSSARY.md, base not a commit)
set -uo pipefail

die() { echo "glossary-warn: $*" >&2; exit 2; }

cd "$(git rev-parse --show-toplevel 2>/dev/null)" || die "not inside a git checkout"
[ -r GLOSSARY.md ] || die "no GLOSSARY.md at the repo root"

base=${1:-}
if [ -z "$base" ]; then
  base=$(git symbolic-ref -q refs/remotes/origin/HEAD 2>/dev/null) \
    || die "cannot resolve origin/HEAD; run git remote set-head origin -a or pass a base"
  base=${base#refs/remotes/}
fi
git rev-parse --verify -q "$base^{commit}" >/dev/null || die "base $base is not a commit"

tmp=$(mktemp -d) || exit 2
trap 'rm -rf "$tmp"' EXIT

# One `<Term> TAB <word>` line per avoided word.
awk '
  /^\*\*.*\*\*:[ \t]*$/ { term = $0; sub(/^\*\*/, "", term); sub(/\*\*:[ \t]*$/, "", term); next }
  /^_Avoid_:/ {
    s = $0; sub(/^_Avoid_:/, "", s)
    gsub(/\([^)]*\)/, "", s); gsub(/`/, "", s)
    n = split(s, w, ",")
    for (i = 1; i <= n; i++) {
      sub(/^[ \t]+/, "", w[i]); sub(/[ \t]+$/, "", w[i])
      if (w[i] != "" && term != "") printf "%s\t%s\n", term, w[i]
    }
  }
' GLOSSARY.md > "$tmp/avoid"

git -c core.quotepath=off diff --no-color --no-ext-diff --unified=0 "$base...HEAD" -- '*.md' > "$tmp/diff" \
  || die "git diff $base...HEAD failed"

# The avoid list first, then the diff: each added line is checked against every
# word, once per (term, word) pair.
awk -F'\t' '
  function isword(c) { return c ~ /^[A-Za-z0-9_]$/ }
  FNR == NR { terms[++n] = $1; words[n] = $2; next }
  /^\+\+\+ / { file = substr($0, 7); if ($0 == "+++ /dev/null") file = ""; skip = (file ~ /(^|\/)CHANGELOG\.md$/ || file == "GLOSSARY.md"); next }
  /^@@ / { split($0, f, " "); split(f[3], h, ","); line = substr(h[1], 2) + 0; next }
  /^\+/ {
    if (file != "" && !skip) {
      text = tolower(substr($0, 2))
      for (i = 1; i <= n; i++) {
        w = tolower(words[i]); pos = 1
        while ((k = index(substr(text, pos), w)) > 0) {
          at = pos + k - 1
          if (!isword(at > 1 ? substr(text, at - 1, 1) : "") && !isword(substr(text, at + length(w), 1))) {
            printf "glossary: %s:%d: \"%s\" is on the _Avoid_ list of %s\n", file, line, words[i], terms[i]
            break
          }
          pos = at + 1
        }
      }
    }
    line++
  }
' "$tmp/avoid" "$tmp/diff"
exit 0
