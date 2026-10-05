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

# --- the Change outline ------------------------------------------------------

tplc=$T/tplc.md
printf '## Why\n\n## Change outline\n\n## Attribution\n' > "$tplc"
# <section text>: a body whose Change outline holds it, in a file.
outline_body() { body_of "## Why\n\nx\n\n## Change outline\n\n$1\n\n## Attribution\n\nfooter\n"; }
oc_rc() { rc_of "$(outline_body "$1")" "$tplc"; }
oc_out() { out_of "$(outline_body "$1")" "$tplc"; }
err_of() { { PR_TEMPLATE=${2:-$tplc} bash scripts/check-pr-body.sh "$1" >/dev/null; } 2>&1; }

neither='pr-body: change outline: neither a Shape diff fence nor a "Shape: none, mechanical (" line'
good_fence='```diff\n scripts/a.sh\n+  helper()\n-  old()\n```'

check_rc "a diff fence satisfies the outline" 0 "$(oc_rc "$good_fence")"
check "a diff fence prints nothing" "" "$(oc_out "$good_fence")"
check_rc "the hatch line satisfies the outline" \
  0 "$(oc_rc 'Shape: none, mechanical (comment reword).')"
check_rc "a CRLF outline with the hatch line passes" \
  0 "$(rc_of "$(body_of '## Why\r\n\r\nx\r\n\r\n## Change outline\r\n\r\nShape: none, mechanical (x).\r\n\r\n## Attribution\r\n')" "$tplc")"
check_rc "an outline of prose only fails" 1 "$(oc_rc 'It changes things.')"
check "and names neither the fence nor the hatch" "$neither" "$(oc_out 'It changes things.')"
check "a fence of another language is not the Shape fence" \
  "$neither" "$(oc_out '```text\n scripts/a.sh\n```')"
check "a hatch line inside a fence is not the hatch" \
  "$neither" "$(oc_out '```text\nShape: none, mechanical (x).\n```')"
check "a hatch line inside a comment is not the hatch" \
  "$neither" "$(oc_out '<!--\nShape: none, mechanical (x).\n-->')"
check "a hatch line in the next section is not this one's" \
  "$neither" "$(out_of "$(body_of '## Why\n\n## Change outline\n\ntext\n\n## Attribution\n\nShape: none, mechanical (x).\n')" "$tplc")"
check "a diff fence in the next section is not this one's" \
  "$neither" "$(out_of "$(body_of '## Why\n\n## Change outline\n\ntext\n\n## Attribution\n\n```diff\n a.sh\n```\n')" "$tplc")"
check "a body without the heading gets only the missing-heading line" \
  "pr-body: missing heading: ## Change outline" \
  "$(out_of "$(body_of '## Why\n## Attribution\nShape: none, mechanical (x).\n')" "$tplc")"
check "an empty outline at the end of the body is refused" \
  "$neither" "$(out_of "$(body_of '## Why\n## Attribution\n## Change outline\n')" "$tplc")"

# The fence budget is the first fence's alone.
fence_of() { # <n lines>: a diff fence of n lines, the first holding a path
  local i out='```diff\n scripts/a.sh'
  for ((i = 1; i < $1; i++)); do out="$out\n   node$i()"; done
  printf '%s\n```' "$out"
}
check_rc "a 15-line fence is within budget" 0 "$(oc_rc "$(fence_of 15)")"
check_rc "a 16-line fence is over budget" 1 "$(oc_rc "$(fence_of 16)")"
check "and the refusal counts the fence's lines" \
  "pr-body: change outline: the Shape fence is 16 lines, over 15" "$(oc_out "$(fence_of 16)")"
check_rc "a long carrier fence after the Shape fence is not counted" \
  0 "$(oc_rc "$good_fence\n\n$(fence_of 30)")"
check "a long first fence is counted though a short one follows" \
  "pr-body: change outline: the Shape fence is 20 lines, over 15" \
  "$(oc_out "$(fence_of 20)\n\n$good_fence")"

# Every root line of the first fence carries a file path.
check_rc "a root with a slash path passes" 0 "$(oc_rc '```diff\n+scripts/a.sh\n```')"
check_rc "a root with a bare file name and colon passes" \
  0 "$(oc_rc '```diff\n a.sh: run()\n```')"
check_rc "a root with a trailing comma after the file name passes" \
  0 "$(oc_rc '```diff\n README.md, then\n```')"
check_rc "a path after prose on the root line passes" \
  0 "$(oc_rc '```diff\n the entry in tests/x.test.sh\n```')"
check_rc "indented nodes need no path" \
  0 "$(oc_rc '```diff\n a.sh\n   child()\n+  other()\n```')"
check_rc "a root without a path fails" 1 "$(oc_rc '```diff\n run the thing\n   child()\n```')"
check "and the refusal quotes the root, marker dropped" \
  "pr-body: change outline: tree root has no file path: run the thing" \
  "$(oc_out '```diff\n run the thing\n   child()\n```')"
check "a removed root is a root too" \
  "pr-body: change outline: tree root has no file path: old thing" \
  "$(oc_out '```diff\n a.sh\n-old thing\n```')"
check "a flush-left root is quoted as written, no marker to drop" \
  "pr-body: change outline: tree root has no file path: run the thing" \
  "$(oc_out '```diff\nrun the thing\n   child()\n```')"
check_rc "blank fence lines are not roots" 0 "$(oc_rc '```diff\n a.sh\n\n   child()\n```')"
check_rc "a word ending in a long extension is not a path" \
  1 "$(oc_rc '```diff\n thing.toolong\n```')"
check_rc "a version number is not a path" \
  1 "$(oc_rc '```diff\n bump semantic-release to 24.2.9\n```')"
check_rc "a file name with digits in its stem is a path" \
  0 "$(oc_rc '```diff\n v2.sh: run()\n```')"
check_rc "a carrier fence's rootless line is not checked" \
  0 "$(oc_rc "$good_fence\n\n"'```diff\n loose line\n```')"

# Both classes on one stdout: the missing heading first, then the outline line.
check "a body short a heading with a prose outline prints both, in that order" \
  "pr-body: missing heading: ## Attribution
$neither" \
  "$(out_of "$(body_of "## Why\n\nx\n\n## Change outline\n\nsome prose\n")" "$tplc")"

# --- the issues a body closes ------------------------------------------------

closes_body() { outline_body "Closes #$1\n\nShape: none, mechanical (x)."; }
cl_err() { err_of "$(outline_body "$1\n\nShape: none, mechanical (x).")"; }
mkdir "$T/titled"
cat > "$T/titled/gh" <<'FAKE'
#!/bin/sh
[ "$*" = "issue view $FAKE_N --json title --jq .title" ] || exit 1
printf '%s\n' "$FAKE_TITLE"
FAKE
chmod +x "$T/titled/gh"

check "an issue whose title cannot be read says so on stderr" \
  "pr-body: closes #12: title unavailable" "$(cl_err 'Closes #12')"
check_rc "and the evidence does not change the exit code" \
  0 "$(rc_of "$(outline_body 'Closes #12\n\nShape: none, mechanical (x).')" "$tplc")"
check "and prints nothing on stdout" \
  "" "$(out_of "$(outline_body 'Closes #12\n\nShape: none, mechanical (x).')" "$tplc")"
check "a readable title is printed" \
  "pr-body: closes #12: Fix the thing" \
  "$(PATH=$T/titled:$PATH FAKE_N=12 FAKE_TITLE='Fix the thing' cl_err 'Closes #12')"
check "the keyword is case-insensitive and any resolving verb counts" \
  "pr-body: closes #7: Seven" \
  "$(PATH=$T/titled:$PATH FAKE_N=7 FAKE_TITLE=Seven cl_err 'fixed #7')"
check "an issue named twice is printed once" \
  "pr-body: closes #12: title unavailable" "$(cl_err 'Closes #12\nand resolves #12')"
check "each distinct issue is printed" \
  "pr-body: closes #12: title unavailable
pr-body: closes #13: title unavailable" "$(cl_err 'Closes #12\nFixes #13')"
check "a Closes line inside a fence is prose" "" "$(cl_err '```text\nCloses #12\n```')"
check "a word that only ends in a keyword is not one" "" "$(cl_err 'disclose #12')"
check "a body with no Closes line prints no evidence" "" "$(cl_err 'plain')"
check_rc "a violation still fails with evidence beside it" \
  1 "$(rc_of "$(outline_body 'Closes #12')" "$tplc")"
check "and stdout carries the violation alone" "$neither" "$(oc_out 'Closes #12')"

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

finish
