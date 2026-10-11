#!/usr/bin/env bash
# skills/setup-harness/templates/harness-block.md: the CLAUDE.md block a
# setup-harness run writes. The subject is the template's text, read as a
# file: its fill comment says when the `LSP` paragraph is written, and that
# paragraph says when to use `LSP` and when not to trust it, in at most four
# sentences naming no particular server, since one passage serves every
# language server the catalog vendors. Reads files only; no call here reaches a
# host.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

tpl=skills/setup-harness/templates/harness-block.md

# The fill comment, one line or several, and the paragraph outside it that
# mentions `LSP`.
comment=$(awk '/^<!--/ { c = 1 } c { print } c && /-->$/ { exit }' "$tpl")
passage=$(awk '/^<!--/ { c = 1 } !c { print } c && /-->$/ { c = 0 }' "$tpl" | awk 'BEGIN { RS = "" } /`LSP`/')

check "the block carries one LSP paragraph" 1 \
  "$(printf '%s\n' "$passage" | awk 'BEGIN { RS = "" } END { print NR }')"

for point in goToDefinition findReferences grep 'only the declaration' 'retry once' worktree 'main checkout' Bash; do
  case "$passage" in
    *"$point"*) ;;
    *) check "the LSP paragraph covers: $point" "present" "absent" ;;
  esac
done

check "the LSP paragraph is at most four sentences" yes \
  "$(printf '%s' "$passage" | tr '\n' ' ' | grep -o '[.!?]\( \|$\)' | wc -l | awk '{ print ($1 >= 1 && $1 <= 4) ? "yes" : "no" }')"

check "the LSP paragraph names no particular server" "" \
  "$(printf '%s' "$passage" | grep -oiE 'pyright|typescript-language-server|gopls|rust-analyzer|csharp-ls|jdtls|kotlin-lsp')"

case "$comment" in
  *'LSP'*'language server'*) ;;
  *) check "the fill comment says when the LSP paragraph is written" "present" "absent" ;;
esac

finish
