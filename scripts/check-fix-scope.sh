#!/usr/bin/env bash
# Fix scope: a fix to a skill or a profile names its scope. The rule is in
# docs/contributing/standards/prose.md and only a reviewer checked it: of the 20
# merged PRs titled `fix(...)` when this was written, 4 carried the line and 16
# did not. A PR whose title's type is `fix` and whose diff touches `skills/` or
# `docs/agents/` needs a line starting `Fix scope:` that names `procedure` or
# `domain` (any list marker may precede it), outside an HTML comment, which renders
# as nothing.
#
# It cannot see a fix shipped under a `feat` title (a skill fix often is one),
# and it does not judge whether the stated scope is right: both stay the
# reviewer's.
#
#   PR_TITLE=... PR_BODY=... PR_BASE=<ref> [PR_ROOT=<checkout>] scripts/check-fix-scope.sh
#
# PR_BASE is the ref the PR's diff counts from (the diff is `PR_BASE...HEAD`);
# PR_ROOT defaults to the checkout holding this script.
#
# stdout: one `fix-scope: ...` line naming the line to add
# exit: 0 no line owed, or present · 1 a line owed and absent · 2 tooling
set -uo pipefail

# shellcheck source=scripts/pr-check-lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/pr-check-lib.sh"
pr_check_init check-fix-scope

type=${title%%[(:!]*}
[ "$type" = fix ] || { echo "fix-scope: the title's type is not fix, no Fix scope: line owed."; exit 0; }

changed=$(git -C "$root" diff --name-only "$base...HEAD") || exit 2
touched=$(printf '%s\n' "$changed" | grep -E '^(skills|docs/agents)/' | head -n 1)
[ -n "$touched" ] || { echo "fix-scope: the diff touches neither skills/ nor docs/agents/, no Fix scope: line owed."; exit 0; }

stated=$(pr_body_has_line '' '^[ \t]*(([-*+]|[0-9]+[.)])[ \t]+)?fix scope:[ \t]*(procedure|domain)([^a-z]|$)')
[ "$stated" = yes ] && { echo "fix-scope: Fix scope: line present."; exit 0; }

printf 'fix-scope: a fix title touching %s needs a line starting `Fix scope:` naming `procedure` or `domain` in the PR body.\n' "$touched"
exit 1
