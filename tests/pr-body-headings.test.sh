#!/usr/bin/env bash
# scripts/check-pr-body.sh: every `##` heading of the PR template is in the PR
# body, and its `## Change outline` holds a Shape fence within budget or the
# mechanical hatch. The seam is the script's CLI: the body as a file argument or
# on stdin and the template's path in PR_TEMPLATE in, an exit code and one line
# per violation out, which is what the bump-guard workflow runs. The `Closes #N`
# titles go to stderr as evidence and never change the verdict.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

# The script reads `Closes #N` titles through `gh`. tests/run.sh's stub is a
# host call the runner would flag, and run alone there is no stub at all, so
# this file puts a `gh` of its own in front: one that fails quietly.
mkdir "$T/nogh"
printf '#!/bin/sh\nexit 127\n' > "$T/nogh/gh"
chmod +x "$T/nogh/gh"
export PATH="$T/nogh:$PATH"

# A fixture template: three headings, a heading-shaped line inside a comment and
# inside a fence, neither of which is a heading the reader sees.
tpl=$T/template.md
cat > "$tpl" <<'TPL'
Closes #

## Why

<!-- one sentence about `## Nope` -->

## Outline

<!--
## Hidden in a comment
-->

```md
## Hidden in a fence
```

## Attribution
TPL

body=$T/body.md
printf '## Why\n\nBecause.\n\n## Outline\n\nA shape.\n\n## Attribution\n\nfooter\n' > "$body"

# <body file> [<template>]: the script's exit code and stdout.
rc_of() { PR_TEMPLATE=${2:-$tpl} bash scripts/check-pr-body.sh "$1" >/dev/null 2>&1; printf '%s' "$?"; }
out_of() { PR_TEMPLATE=${2:-$tpl} bash scripts/check-pr-body.sh "$1" 2>/dev/null; }
# <body text>: a body file holding it, byte for byte.
body_of() { printf '%b' "$1" > "$T/b.md"; printf '%s' "$T/b.md"; }

# --- the verdict -------------------------------------------------------------

check_rc "a body with every heading passes" 0 "$(rc_of "$body")"
check_rc "a body missing a heading fails" \
  1 "$(rc_of "$(body_of '## Why\n\nx\n\n## Attribution\n')")"
check "the refusal names the missing heading" \
  "pr-body: missing heading: ## Outline" \
  "$(out_of "$(body_of '## Why\n\nx\n\n## Attribution\n')")"
check "every missing heading is named, in template order" \
  "pr-body: missing heading: ## Why
pr-body: missing heading: ## Outline" \
  "$(out_of "$(body_of '## Attribution\n')")"
check_rc "an empty body fails" 1 "$(rc_of "$(body_of '')")"

# The template is the source, so a heading added to it is required of the body.
tpl2=$T/template2.md
{ cat "$tpl"; printf '\n## Review\n'; } > "$tpl2"
check_rc "the same body passes the old template" 0 "$(rc_of "$body" "$tpl")"
check_rc "a heading added to the template is required" 1 "$(rc_of "$body" "$tpl2")"
check "and is the one named" \
  "pr-body: missing heading: ## Review" "$(out_of "$body" "$tpl2")"

# --- the body on stdin -------------------------------------------------------

check_rc "the body on stdin is read the same way" \
  0 "$(PR_TEMPLATE=$tpl bash scripts/check-pr-body.sh < "$body" >/dev/null 2>&1; printf '%s' "$?")"
check_rc "a body on stdin missing a heading fails" \
  1 "$(printf '## Why\n' | PR_TEMPLATE=$tpl bash scripts/check-pr-body.sh >/dev/null 2>&1; printf '%s' "$?")"

# --- adversarial inputs, per the coding standards ----------------------------

# GitHub's web editor saves a body with CRLF line endings.
check_rc "a CRLF body passes" \
  0 "$(rc_of "$(body_of '## Why\r\n\r\nx\r\n\r\n## Outline\r\n\r\ny\r\n\r\n## Attribution\r\n')")"
check_rc "trailing spaces on a heading are not a different heading" \
  0 "$(rc_of "$(body_of '## Why  \n## Outline\t\n## Attribution \n')")"
# What renders as prose is not a heading, in the body or in the template (the
# first case above holds the template side: the body carries neither hidden one).
check_rc "a heading only inside a fence does not count" \
  1 "$(rc_of "$(body_of '## Why\n## Outline\n```\n## Attribution\n```\n')")"
check_rc "a heading only inside a tilde fence does not count" \
  1 "$(rc_of "$(body_of '## Why\n## Outline\n~~~\n## Attribution\n~~~\n')")"
# A fence is closed by its own marker: the other one inside it is content, and
# reading it as a closer would hide every heading after the block.
check_rc "a tilde line inside a backtick fence does not close it" \
  0 "$(rc_of "$(body_of '## Why\n```\n~~~\n```\n## Outline\n## Attribution\n')")"
check_rc "a backtick line inside a tilde fence does not close it" \
  0 "$(rc_of "$(body_of '## Why\n~~~\n```\n~~~\n## Outline\n## Attribution\n')")"
check_rc "a heading after a tilde line inside a backtick fence still hides" \
  1 "$(rc_of "$(body_of '## Why\n## Outline\n```\n~~~\n## Attribution\n```\n')")"
check_rc "a heading only inside a comment does not count" \
  1 "$(rc_of "$(body_of '## Why\n## Outline\n<!--\n## Attribution\n-->\n')")"
check_rc "a heading only inside a one-line comment does not count" \
  1 "$(rc_of "$(body_of '## Why\n## Outline\n<!-- ## Attribution -->\n')")"
check_rc "a comment opened mid-line hides the headings inside it" \
  1 "$(rc_of "$(body_of '## Why\n## Outline\ntext <!--\n## Attribution\n-->\n')")"
check_rc "an indented comment hides the headings inside it" \
  1 "$(rc_of "$(body_of '## Why\n## Outline\n  <!--\n## Attribution\n-->\n')")"
check_rc "a fence after a comment closes normally" \
  0 "$(rc_of "$(body_of '<!--\nx\n-->\n```\ny\n```\n## Why\n## Outline\n## Attribution\n')")"
# Level, spelling and anchoring.
check_rc "a level-3 heading is not the level-2 one" \
  1 "$(rc_of "$(body_of '## Why\n## Outline\n### Attribution\n')")"
check_rc "a heading that only starts with the template's is not it" \
  1 "$(rc_of "$(body_of '## Why\n## Outline\n## Attribution notes\n')")"
check_rc "a heading that is only the start of the template's is not it" \
  1 "$(rc_of "$(body_of '## Why\n## Outline\n## Attrib\n')")"
check_rc "a different case is a different heading" \
  1 "$(rc_of "$(body_of '## why\n## Outline\n## Attribution\n')")"
check_rc "a heading mid-line is prose" \
  1 "$(rc_of "$(body_of '## Why\n## Outline\ntext ## Attribution\n')")"
check_rc "extra headings in the body are allowed" \
  0 "$(rc_of "$(body_of '## Why\n## Outline\n## Extra\n## Attribution\n')")"

# --- this repo's own template ------------------------------------------------

# A body that is the template itself carries every heading it owes, and one that
# drops the last heading, the footer's, does not: the default template path is
# the repo's. The template's Change outline holds only a comment, which the
# outline rule rightly refuses, so the body gets the hatch line under it.
awk '{ print } /^## Change outline/ { print "\nShape: none, mechanical (test)." }' \
  .github/pull_request_template.md > "$T/tplbody.md"
check_rc "the repo's template passes as a body" \
  0 "$(env -u PR_TEMPLATE bash scripts/check-pr-body.sh "$T/tplbody.md" >/dev/null 2>&1; printf '%s' "$?")"
check_rc "the repo's template alone is refused for its empty outline" \
  1 "$(env -u PR_TEMPLATE bash scripts/check-pr-body.sh .github/pull_request_template.md >/dev/null 2>&1; printf '%s' "$?")"
grep -v '^## Attribution' "$T/tplbody.md" > "$T/short.md"
check "a body short of the repo's last heading is refused" \
  "pr-body: missing heading: ## Attribution" \
  "$(env -u PR_TEMPLATE bash scripts/check-pr-body.sh "$T/short.md" 2>/dev/null)"
# The Door line opens with its coloured circle, which the template asks for and
# the check takes as ordinary section text, in either colour.
check "the repo's template asks for the coloured Door line" 1 \
  "$(grep -c '`- 🟢 Door: two-way\..*`- 🔴 Door: one-way\.' .github/pull_request_template.md)"
# The template setup-skills installs carries the same instructions as this
# repo's, and update-skills writes the Door line in the same coloured shapes.
check "setup-skills' template matches the repo's" "" \
  "$(diff .github/pull_request_template.md skills/setup-skills/pull_request_template.md)"
check "update-skills writes the coloured Door line" 2 \
  "$(grep -cE '`- (🟢 Door: two-way|🔴 Door: one-way)\.' skills/update-skills/SKILL.md)"
awk '{ print } /^## Special things to note/ { print "\n- 🟢 Door: two-way. Blast radius: this repo.\n- 🔴 Door: one-way. Blast radius: consumers." }' \
  "$T/tplbody.md" > "$T/door.md"
check_rc "a body with coloured Door lines passes" \
  0 "$(env -u PR_TEMPLATE bash scripts/check-pr-body.sh "$T/door.md" >/dev/null 2>&1; printf '%s' "$?")"

# --- inputs that are not a verdict -------------------------------------------

check_rc "a template that is not there is tooling" 2 "$(rc_of "$body" "$T/nope.md")"
check_rc "a body file that is not there is tooling" 2 "$(rc_of "$T/nope.md")"
# A template with no headings would pass every body, which is a broken template
# and not a clean bill.
printf 'Closes #\n\nno headings\n' > "$T/bare.md"
check_rc "a template with no headings is tooling" 2 "$(rc_of "$body" "$T/bare.md")"
# grep exits 2 when it fails, and the empty answer it leaves behind must not read
# as every heading present.
mkdir "$T/stub"
printf '#!/bin/sh\nexit 2\n' > "$T/stub/grep"
chmod +x "$T/stub/grep"
check_rc "a failing grep is tooling, not a pass" \
  2 "$(PATH=$T/stub:$PATH rc_of "$body")"

# --- arguments that are not a body file --------------------------------------

# `--help` once went to `cat`, whose own usage text was checked as the body and
# failed every heading: a failed check of a body nobody passed.
help_out=$(bash scripts/check-pr-body.sh --help 2>&1)
check_rc "--help is a usage answer, exit 0" 0 "$(bash scripts/check-pr-body.sh --help >/dev/null 2>&1; printf '%s' "$?")"
check "--help prints no violation line" "0" "$(printf '%s\n' "$help_out" | grep -c '^pr-body:')"
check "--help names the script's call" "1" "$(printf '%s\n' "$help_out" | grep -c '^usage: scripts/check-pr-body.sh \[<body-file>\]')"
dash_out=$(bash scripts/check-pr-body.sh -x 2>/dev/null)
check_rc "an unknown dash argument is tooling" 2 "$(bash scripts/check-pr-body.sh -x >/dev/null 2>&1; printf '%s' "$?")"
check "an unknown dash argument prints no violation" "" "$dash_out"
check "an unknown dash argument answers the usage line on stderr" "1" \
  "$(bash scripts/check-pr-body.sh -x 2>&1 >/dev/null | grep -c '^usage: scripts/check-pr-body.sh')"

finish
