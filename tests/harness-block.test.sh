#!/usr/bin/env bash
# skills/setup-harness/templates/harness-block.md: the CLAUDE.md block a
# setup-harness run writes. The subject is the template's text, read as a
# file: its fill comment says when the `LSP` paragraph is written, and that
# paragraph says when to use `LSP` and when not to trust it, in at most four
# sentences naming no particular server, since one passage serves every
# language server the catalog vendors. A copy with the paragraph's meaning
# negated must fail the point checks. Reads files only; no call here reaches a
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

# Prints each point the `LSP` paragraph of <file> fails to make.
missing_points() {
  local p point
  p=$(passages "$1" | tr '\n' ' ')
  for point in 'rather than grep' findReferences 'cross-check the list with a grep' \
    'only the declaration' 'retry once' 'changed through Bash' worktree 'main checkout' 'use grep there'; do
    case "$p" in *"$point"*) ;; *) printf '%s\n' "$point" ;; esac
  done
}

passage=$(passages "$tpl")
comment=$(awk '/^<!--/ { c = 1 } c { print } c && /-->$/ { exit }' "$tpl")

check "the block carries exactly one LSP paragraph" 1 \
  "$(printf '%s' "$passage" | awk 'BEGIN { RS = "" } END { print NR }')"

check "the LSP paragraph makes every point" "" "$(missing_points "$tpl")"

awk '!/^<!--/ && /`LSP`/ { print "Use grep rather than `LSP` goToDefinition, and never cross-check findReferences. Do not retry a first call. In a worktree the server reads the worktree, so trust it."; next } { print }' \
  "$tpl" > "$fx/negated.md"
check "a negated LSP paragraph misses its points" \
  "rather than grep
cross-check the list with a grep
only the declaration
retry once
changed through Bash
main checkout
use grep there" "$(missing_points "$fx/negated.md")"

check "the LSP paragraph is at most four sentences" yes \
  "$(printf '%s' "$passage" | tr '\n' ' ' | grep -o '[.!?]\( \|$\)' | wc -l | awk '{ print ($1 >= 1 && $1 <= 4) ? "yes" : "no" }')"

check "the LSP paragraph names no particular server" "" \
  "$(printf '%s' "$passage" | grep -oiE 'pyright|typescript-language-server|gopls|rust-analyzer|csharp-ls|jdtls|kotlin-lsp')"

case "$comment" in
  *'LSP'*'language server is wired'*) ;;
  *) check "the fill comment says when the LSP paragraph is written" "present" "absent" ;;
esac

finish
