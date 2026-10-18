#!/usr/bin/env bash
# The file-size limit on agent-authored files. Agents read whole files into
# context, so a file over the limit costs every session that opens it and
# invites the next agent to append rather than place. The limit, whole: the
# `limit` variable below, in tokens, counted as bytes / 4 rounded up (no
# tokenizer, the same answer on every machine); a file of more than limit * 4
# bytes fails. It is the one place the figure is stated. The exclusions live in the
# `token-limit` hook's `exclude` in .pre-commit-config.yaml, so pre-commit never
# passes them: lockfiles (`*.lock`, `*-lock.json`), every CHANGELOG.md (the
# release run writes them), and the config's global exclude (the derived skill
# copies and the test fixtures). pre-commit stashes unstaged changes, so the
# files read here are the staged content.
#
#   scripts/token-limit-check.sh [<file>...]
#
# stdout: nothing when every file is inside the limit; else one block per
#         oversize file: its token count, the limit and a split instruction for
#         its kind, then the rules for the split
# exit: 0 inside the limit or no files · 1 a file over it · 2 tooling (a file
#       that is not readable)
set -uo pipefail
limit=5000 # tokens

# <path>: the split instruction for that kind of file.
instruction() {
  case $1 in
    */tests/*.sh|tests/*.sh) echo "Shell test: split it by behaviour into new tests/*.test.sh files the suite runner picks up by name; move fixtures several files share into tests/<name>-lib.sh." ;;
    *.sh) echo "Shell script: move a cohesive group of functions into sibling files the script sources by a path relative to its own location (lib/ for a library several scripts share, <script>.d/ for pieces private to one script), so the command line and every caller stay unchanged." ;;
    */SKILL.md|SKILL.md) echo "SKILL.md: move reference material into the skill's reference/ folder and link it; keep each reference file's ## Contents map so the prose budget still passes." ;;
    *.md) echo "Markdown: split by top-level section into sibling files, and link each from the original so readers still find everything." ;;
    *.js|*.mjs|*.cjs) echo "JavaScript module: extract cohesive exports into new modules and re-import them, so importers keep working." ;;
    *.html) echo "HTML page: move the style and script blocks into sibling files, so the markup stays small." ;;
    *) echo "Split it into smaller files along its natural seams, each under the limit, and keep every reference to it working." ;;
  esac
}

over=0
for f in "$@"; do
  [ -f "$f" ] && [ -r "$f" ] || { printf 'not a readable file: %s\n' "$f" >&2; exit 2; }
  bytes=$(wc -c < "$f") || exit 2
  tokens=$(((bytes + 3) / 4))
  [ "$bytes" -gt $((limit * 4)) ] || continue
  over=1
  printf '%s: %s tokens, over the %s-token limit\n  %s\n' "$f" "$tokens" "$limit" "$(instruction "$f")"
done
[ "$over" -eq 0 ] && exit 0
printf '\nSplit each file above: do not bypass with `--no-verify`, do not minify or strip comments to fit, stage the new files.\n'
exit 1
