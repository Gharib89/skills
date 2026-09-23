#!/usr/bin/env bash
# ship_fence_unclosed and ship_body_headings: the two pure reads `update-pr-body`
# makes of a body string, both over the one fence rule in SHIP_AWK_FENCE. A body
# whose fence state ends open is what swallowed four sections in run #121, so the
# cases below are the fence forms that decide it. No call here reaches a host.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
source skills/ship/scripts/_lib.sh

check "a body with no fence is balanced" \
  "" "$(ship_fence_unclosed "$(printf '## Summary\n\nprose\n')")"

check "a closed backtick fence is balanced" \
  "" "$(ship_fence_unclosed "$(printf '## Summary\n\n```diff\n- a\n+ b\n```\n\n## Review\n')")"

check "an open backtick fence names its line and run" \
  "line 3: \`\`\`" "$(ship_fence_unclosed "$(printf '## Summary\n\n```diff\n- a\n+ b\n')")"

check "an open tilde fence names its line and run" \
  "line 1: ~~~" "$(ship_fence_unclosed "$(printf '~~~\nshape\n')")"

# CommonMark lets a fence sit up to three spaces in; four open an indented code
# block, which is not a fence form here. mawk, the default awk on Debian and
# Ubuntu, read the old `^ ? ? ?` de-indent as one optional space, so a
# two-space fence went unseen there.
check "a fence indented three spaces is a fence" \
  "line 1: \`\`\`" "$(ship_fence_unclosed "$(printf '   ```\ncode\n')")"

check "a fence indented four spaces is not" \
  "" "$(ship_fence_unclosed "$(printf '    ```\ncode\n')")"

# The fence rule closes on a run at least as long as the opener, so a four-tick
# line ends a three-tick block; the reverse leaves it open.
check "a longer run closes a shorter fence" \
  "" "$(ship_fence_unclosed "$(printf '```\ncode\n````\n')")"

check "a shorter run inside a longer fence leaves it open" \
  "line 1: \`\`\`\`" "$(ship_fence_unclosed "$(printf '````\n```\ncode\n')")"

# A ``` line carrying an info string is an opener, never a closer, so a body that
# opens twice and closes once is open.
check "an info string never closes a fence" \
  "line 1: \`\`\`" "$(ship_fence_unclosed "$(printf '```sh\ncode\n```js\nmore\n')")"

check "headings outside fences are listed in order" \
  "$(printf 'Summary\nDeviations from plan\nReview')" \
  "$(ship_body_headings "$(printf 'Closes #1\n\n## Summary\n\ntext\n\n## Deviations from plan\n\nNone\n\n## Review\n')")"

check "a heading inside a fence is example text, not a section" \
  "Summary" \
  "$(ship_body_headings "$(printf '## Summary\n\n```\n## Review\n```\n')")"

check "a deeper heading is not a section" \
  "Summary" "$(ship_body_headings "$(printf '## Summary\n\n### Shape\n')")"

check "a body with no heading lists nothing" \
  "" "$(ship_body_headings "$(printf 'just prose\n')")"

finish
