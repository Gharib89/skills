#!/usr/bin/env bash
# Bump guard: refuse a PR whose Conventional-Commit title implies a MAJOR version
# bump unless the maintainer has applied the `major` label.
#
# The release run reads the squash subject, which is the PR title, to pick the
# bump: `feat:` minor, `!` or a `BREAKING CHANGE:` footer major, every other type
# patch. A major bump must be a maintainer's decision and never an agent's, so
# only that grade is label-gated; `feat:` flows without a label so an agent's
# feature PR is not stalled on a human. A title that is not a valid Conventional
# Commit fails outright, because the release run would otherwise have to guess.
# See docs/adr/0003-version-and-changelog-cut-on-merge.md.
#
#   PR_TITLE=... PR_BODY=... PR_LABELS=... scripts/check-bump-label.sh
#
# stdout: one line saying which grade was read and what it needs
# exit: 0 the PR may merge · 1 it may not
#
# Bash 3.2, like everything under skills/: this runs on a GitHub runner and in
# tests/bump-label.test.sh, and there is no reason for it to need more.
set -uo pipefail

title=${PR_TITLE:-}
body=${PR_BODY:-}
labels=${PR_LABELS:-}

# The host pads a title it round-trips through a form, and the author did not.
title=${title#"${title%%[![:space:]]*}"}
title=${title%"${title##*[![:space:]]}"}

# The types the release run recognises, which is `patch_tags` plus `feat` in
# every `.release/*.toml`. Any other lowercase word parses as a Conventional
# Commit and then releases nothing, because python-semantic-release grades an
# unknown type at its default bump level of none: a typo like `fx(ship):` would
# skip that skill's release silently, so it is refused here instead.
types='build|chore|ci|docs|feat|fix|perf|refactor|revert|style|test'

# type, optional (scope), optional !, ": ", description. The `!` sits after the
# closing paren, so a `!` inside the scope is part of the scope and not the
# breaking marker.
if [[ ! $title =~ ^($types)(\([^\)]+\))?(!)?:[[:space:]]+[^[:space:]] ]]; then
  printf "bump-guard: title '%s' is not a Conventional Commit of a type the release run reads (%s). PR titles must be, e.g. 'fix: ...' or 'feat(ship): ...', because the squash subject drives the release version bump.\n" "$title" "$types"
  exit 1
fi
bang=${BASH_REMATCH[3]}

# Line-anchored, both spellings, because the release run treats either as major.
# A mention of the words mid-sentence is prose.
footer=no
printf '%s\n' "$body" | grep -Eq '^BREAKING[ -]CHANGE:' && footer=yes

if [ -z "$bang" ] && [ "$footer" = no ]; then
  echo "bump-guard: no major bump implied, no bump label required."
  exit 0
fi

# Comma, newline or whitespace separated, whichever the workflow's `join` and the
# host produced. Lowercased through `tr` rather than `${var,,}`, a Bash 4 builtin.
have=$(printf '%s' "$labels" | tr ',[:space:]' '\n\n' | tr '[:upper:]' '[:lower:]')
if printf '%s\n' "$have" | grep -qx 'major'; then
  echo "bump-guard: breaking change carries the 'major' label."
  exit 0
fi

printf "bump-guard: this PR is a breaking change (a '!' in the title or a 'BREAKING CHANGE:' footer in the body), which bumps the major version. A major bump must be opted in by a maintainer: add the 'major' label to confirm, or remove the breaking change (drop the '!' / the footer).\n"
exit 1
