#!/usr/bin/env bash
# ship_body_closes: the closing-keyword test both hosts read.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
source skills/ship/scripts/_lib.sh

says() { ship_body_closes "$1" "$2" && echo yes || echo no; }

check "reads a plain closing line"        yes "$(says 'Closes #76' 76)"
check "reads a multi-issue closing line"  yes "$(says 'Closes #75, #76' 76)"
check "ignores another issue's line"      no  "$(says 'Closes #75' 76)"
check "ignores an inline-code mention"    no  "$(says 'the body carries `Closes #76`' 76)"

# A backtick-fenced example is a mention, not a claim: the behaviour the jq
# strip already had, kept when the fence rule moved to SHIP_AWK_FENCE.
body=$(printf 'An example:\n\n```md\nCloses #76\n```\n')
check "ignores a backtick-fenced example" no "$(says "$body" 76)"

# A tilde fence is a fence too, so host_pr_create no longer reads an example as
# a body that already claims the issue and skips placing the real closing line.
body=$(printf 'An example:\n\n~~~md\nCloses #76\n~~~\n')
check "ignores a tilde-fenced example" no "$(says "$body" 76)"

# The real line below a fenced example still counts.
body=$(printf '~~~md\nCloses #75\n~~~\n\nCloses #76\n')
check "reads a real line under a fenced example" yes "$(says "$body" 76)"

finish
