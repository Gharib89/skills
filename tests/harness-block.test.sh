#!/usr/bin/env bash
# skills/setup-harness/templates/harness-block.md: the CLAUDE.md block a
# setup-harness run writes. The subject is the template's text, read as a
# file: its fill comment says when the `LSP` paragraph is written, and that
# paragraph says when to use `LSP` and when not to trust it, in at most four
# sentences naming no particular server, since one passage serves every
# language server the catalog vendors. Each check also runs on a copy with
# one violation, which it must catch. Reads files only; no call here reaches a
# host.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

tpl=skills/setup-harness/templates/harness-block.md
fx=$(mktemp -d) || exit 2
trap 'rm -rf "$fx"' EXIT

# The paragraphs outside the fill comment that mention `LSP`, blank-line
# separated.
passages() {
  awk '/^<!--/ { c = 1 } !c { print } c && /-->$/ { c = 0 }' "$1" |
    awk 'BEGIN { RS = ""; ORS = "\n\n" } /`LSP`/'
}

# Each point the `LSP` paragraph makes: the phrase that carries it, then that
# phrase with its meaning negated.
points=(
  'rather than grep|only after grep'
  'call `findReferences` on it|skip `findReferences` on it'
  'cross-check the list with a grep|trust the list without a grep'
  'only the declaration|any reference'
  'run it twice|run it once'
  'changed through Bash|changed through Edit'
  'in a worktree|in a fresh session'
  'read the main checkout|read the worktree'
  'use grep there|trust it there'
)

# Prints the phrase of each point the `LSP` paragraph of <file> fails to make.
missing_points() {
  local p point
  p=$(passages "$1" | tr '\n' ' ')
  for point in "${points[@]}"; do
    case "$p" in *"${point%%|*}"*) ;; *) printf '%s\n' "${point%%|*}" ;; esac
  done
}

# The shape checks, each a function of a file so a negated copy can be run
# through it.
paragraphs() { passages "$1" | awk 'BEGIN { RS = "" } END { print NR }'; }
short() { passages "$1" | tr '\n' ' ' | grep -o '[.!?]\( \|$\)' | wc -l | awk '{ print ($1 >= 1 && $1 <= 4) ? "yes" : "no" }'; }
servers() { passages "$1" | grep -oiE 'pyright|typescript-language-server|gopls|rust-analyzer|csharp-ls|jdtls|kotlin-lsp'; }
fill_rule() { awk '/^<!--/ { c = 1 } c { print } c && /-->$/ { exit }' "$1" | grep -c 'LSP.*language server is wired'; }

text=$(cat "$tpl")
# <name> <from> <to>: a copy of the template with every <from> made <to>.
variant() { printf '%s\n' "${text//"$2"/"$3"}" > "$fx/$1.md"; printf '%s' "$fx/$1.md"; }

check "the block carries exactly one LSP paragraph" 1 "$(paragraphs "$tpl")"
check "a second LSP paragraph is counted" 2 \
  "$(paragraphs "$(variant two 'use grep there.' 'use grep there.

A second `LSP` paragraph.')")"

check "the LSP paragraph makes every point" "" "$(missing_points "$tpl")"
for point in "${points[@]}"; do
  check "negating \"${point%%|*}\" misses that point alone" "${point%%|*}" \
    "$(missing_points "$(variant negated "${point%%|*}" "${point#*|}")")"
done

check "the LSP paragraph is at most four sentences" yes "$(short "$tpl")"
check "a fifth sentence is refused" no "$(short "$(variant five 'use grep there.' 'use grep there. Then stop.')")"

check "the LSP paragraph names no particular server" "" "$(servers "$tpl")"
check "a named server is caught" pyright "$(servers "$(variant named 'tool answers' 'tool (pyright) answers')")"

check "the fill comment says when the LSP paragraph is written" 1 "$(fill_rule "$tpl")"
check "a fill comment without the rule is caught" 0 \
  "$(fill_rule "$(variant norule 'language server is wired' 'language server is absent')")"

finish
