#!/usr/bin/env bash
# Split by behaviour from tests/pr-body-headings.test.sh: the Change outline and closed-issue cases.
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

# --- the Change outline ------------------------------------------------------

tplc=$T/tplc.md
printf '## Why\n\n## Change outline\n\n## Attribution\n' > "$tplc"
# <section text>: a body whose Change outline holds it, in a file.
outline_body() { body_of "## Why\n\nx\n\n## Change outline\n\n$1\n\n## Attribution\n\nfooter\n"; }
oc_rc() { rc_of "$(outline_body "$1")" "$tplc"; }
oc_out() { out_of "$(outline_body "$1")" "$tplc"; }
err_of() { { PR_TEMPLATE=${2:-$tplc} bash scripts/check-pr-body.sh "$1" >/dev/null; } 2>&1; }

# The symbol check reads the files the outline names under PR_ROOT: a fixture
# tree holding every symbol the fixtures below call a node.
export PR_ROOT=$T/root
mkdir -p "$PR_ROOT/scripts"
{ printf 'helper() { :; }\nchild() { :; }\nother() { :; }\nrun() { :; }\n'
  for i in $(seq 1 30); do printf 'node%s() { :; }\n' "$i"; done; } > "$PR_ROOT/a.sh"
cp "$PR_ROOT/a.sh" "$PR_ROOT/scripts/a.sh"

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

# Every depth-1 call node under a root is a symbol in the root's file.
absent='pr-body: change outline: node missing_fn is not in scripts/a.sh'
check_rc "a node whose symbol is absent from its root's file fails" \
  1 "$(oc_rc '```diff\n scripts/a.sh\n+  missing_fn()\n```')"
check "and the refusal names the node and the file" \
  "$absent" "$(oc_out '```diff\n scripts/a.sh\n+  missing_fn()\n```')"
check_rc "a node whose symbol is in the file passes" \
  0 "$(oc_rc '```diff\n scripts/a.sh\n+  helper()\n```')"
check_rc "a qualified node is matched by its last part" \
  0 "$(oc_rc '```diff\n scripts/a.sh\n+  Foo.helper()\n+  Foo::child()\n```')"
check "and the refusal names the last part" \
  "$absent" "$(oc_out '```diff\n scripts/a.sh\n+  Foo::missing_fn()\n```')"
check_rc "a symbol is a whole word, not a prefix of one" \
  1 "$(oc_rc '```diff\n scripts/a.sh\n+  help()\n```')"
check_rc "a removed node is not checked" \
  0 "$(oc_rc '```diff\n scripts/a.sh\n-  gone()\n```')"
check_rc "a removed root's nodes are not checked" \
  0 "$(oc_rc '```diff\n-scripts/gone.sh\n-  gone()\n```')"
check_rc "a node deeper than the first level is not checked" \
  0 "$(oc_rc '```diff\n scripts/a.sh\n   child()\n     deep_missing()\n```')"
check_rc "a node that is not a call is not checked" \
  0 "$(oc_rc '```diff\n scripts/a.sh\n+  refuses a missing thing\n```')"
check_rc "a root naming a directory searches under it" \
  0 "$(oc_rc '```diff\n scripts/\n+  helper()\n```')"
check_rc "a node the root file calls but another file defines passes" \
  0 "$({ printf 'source lib.sh\nhelper\n' > "$PR_ROOT/c.sh"; oc_rc '```diff\n c.sh\n+  helper()\n```'; })"
check "an absolute root is read under the root, not the filesystem" \
  "pr-body: change outline: node helper: file not found: /etc/hostname" \
  "$(oc_out '```diff\n /etc/hostname\n+  helper()\n```')"
printf 'helper\n' > "$T/a.sh" # outside PR_ROOT, where `../a.sh` would land
check "a root that climbs out of the tree is not found" \
  "pr-body: change outline: node helper: file not found: ../a.sh" \
  "$(oc_out '```diff\n ../a.sh\n+  helper()\n```')"
check "a root with a middle .. component is not found" \
  "pr-body: change outline: node helper: file not found: scripts/../a.sh" \
  "$(oc_out '```diff\n scripts/../a.sh\n+  helper()\n```')"
mkdir -p "$PR_ROOT/dir.."; printf 'helper\n' > "$PR_ROOT/a..b.sh"; printf 'helper\n' > "$PR_ROOT/dir../c.sh"
check_rc "a file name that merely contains two dots is read" \
  0 "$(oc_rc '```diff\n a..b.sh\n+  helper()\n```')"
check_rc "and so is a directory name ending in two dots" \
  0 "$(oc_rc '```diff\n dir../c.sh\n+  helper()\n```')"
check_rc "a tab-indented node is a node" \
  1 "$(oc_rc '```diff\n scripts/a.sh\n+\tmissing_fn()\n```')"
check_rc "a root with a glob is not resolved" \
  0 "$(oc_rc '```diff\n scripts/*.sh\n+  missing_fn()\n```')"
check "a root whose file is absent is named" \
  "pr-body: change outline: node helper: file not found: scripts/none.sh" \
  "$(oc_out '```diff\n scripts/none.sh\n+  helper()\n```')"
if [ "$(id -u)" -ne 0 ]; then # a mode-000 file stays readable to root
  printf 'helper\n' > "$PR_ROOT/locked.sh"; chmod 000 "$PR_ROOT/locked.sh"
  check_rc "a root file that exists but cannot be read is tooling" \
    2 "$(oc_rc '```diff\n locked.sh\n+  helper()\n```')"
  mkdir -p "$PR_ROOT/lockdir"; printf 'x\n' > "$PR_ROOT/lockdir/f.sh"; chmod 000 "$PR_ROOT/lockdir/f.sh"
  check_rc "a directory root with an unreadable file is tooling" \
    2 "$(oc_rc '```diff\n lockdir/\n+  helper()\n```')"
  chmod 600 "$PR_ROOT/locked.sh" "$PR_ROOT/lockdir/f.sh"
else
  skipped "unreadable root file and directory cases: running as root"
fi
check "each root's nodes are read against that root's file" \
  "pr-body: change outline: node other is not in b.sh" \
  "$({ printf 'helper() { :; }\n' > "$PR_ROOT/b.sh"; oc_out '```diff\n a.sh\n+  other()\n b.sh\n+  helper()\n+  other()\n```'; })"
check_rc "the root defaults to the script's own checkout" \
  0 "$(env -u PR_ROOT PR_TEMPLATE=$tplc bash scripts/check-pr-body.sh "$(outline_body '```diff\n scripts/check-pr-body.sh\n+  outline_violations()\n```')" >/dev/null 2>&1; printf '%s' "$?")"

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


finish
