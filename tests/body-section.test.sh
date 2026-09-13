#!/usr/bin/env bash
# ship_body_replace_section: the transformation behind `update-pr-body`.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
source skills/ship/scripts/_lib.sh

content=$(mktemp); trap 'rm -f "$content"' EXIT
printf 'line one\nline two\n' > "$content"

# The section sits between two others: it is replaced wholesale and every other
# line survives, including the `Closes` line above the first heading.
body=$(cat <<'EOF'
Closes #76

## Summary

old summary

## Review

placeholder
more placeholder

## Notes

tail
EOF
)
expected=$(cat <<'EOF'
Closes #76

## Summary

old summary

## Review

line one
line two

## Notes

tail
EOF
)
actual=$(ship_body_replace_section "$body" Review "$content"); rc=$?
check    "replaces a section between two others" "$expected" "$actual"
check_rc "reports replaced, not created"         0 "$rc"

# No such section: it is appended, and the body is untouched.
body=$(cat <<'EOF'
Closes #76

## Summary

old summary
EOF
)
expected=$(cat <<'EOF'
Closes #76

## Summary

old summary

## Review

line one
line two
EOF
)
actual=$(ship_body_replace_section "$body" Review "$content"); rc=$?
check    "appends a section the body lacks" "$expected" "$actual"
check_rc "reports created, not replaced"    1 "$rc"

# Section last: everything after the heading is the section, so all of it goes.
body=$(cat <<'EOF'
## Summary

old summary

## Review

placeholder
EOF
)
expected=$(cat <<'EOF'
## Summary

old summary

## Review

line one
line two
EOF
)
check "replaces a section that runs to the end of the body" \
  "$expected" "$(ship_body_replace_section "$body" Review "$content")"

# Phase 6 places the attribution footer under a heading of its own, after every
# section a later phase rewrites. The rewrite stops at that heading, so the
# footer survives; loose at the end of the last section (the case above) it is
# inside the section and goes with it, which is what dropped it on PR #97.
body=$(cat <<'EOF'
## Review

placeholder

## Attribution

a footer line
EOF
)
expected=$(cat <<'EOF'
## Review

line one
line two

## Attribution

a footer line
EOF
)
check "keeps a footer under a heading placed after the section" \
  "$expected" "$(ship_body_replace_section "$body" Review "$content")"

# A body that is nothing but the section still keeps its heading.
body=$(printf '## Review\n\nplaceholder\n')
check "replaces a section that is the whole body" \
  "$(printf '## Review\n\nline one\nline two')" \
  "$(ship_body_replace_section "$body" Review "$content")"

# A `## <section>` written as an example inside a fence is not a boundary: the
# real section below it is the one that gets replaced. The rule agrees with
# _gh_add_closes, which skips fences when it places the closing line.
body=$(cat <<'EOF'
Closes #76

## Summary

An example of what ship writes:

```md
## Review

copilot: converged
```

## Review

placeholder
EOF
)
expected=$(cat <<'EOF'
Closes #76

## Summary

An example of what ship writes:

```md
## Review

copilot: converged
```

## Review

line one
line two
EOF
)
check "skips a section heading inside a fenced block" \
  "$expected" "$(ship_body_replace_section "$body" Review "$content")"

# The only occurrence is fenced, so there is no section to replace.
body=$(printf '## Summary\n\n```md\n## Review\n```\n')
expected=$(printf '## Summary\n\n```md\n## Review\n```\n\n## Review\n\nline one\nline two')
actual=$(ship_body_replace_section "$body" Review "$content"); rc=$?
check    "appends when the only occurrence is fenced" "$expected" "$actual"
check_rc "reports created for a fenced-only occurrence" 1 "$rc"

# A malformed body carrying the section twice has both replaced. `placed` only
# answers created-or-replaced; it never stops the second match.
body=$(printf '## Review\n\nfirst\n\n## Notes\n\nkeep\n\n## Review\n\nsecond\n')
expected=$(printf '## Review\n\nline one\nline two\n\n## Notes\n\nkeep\n\n## Review\n\nline one\nline two')
actual=$(ship_body_replace_section "$body" Review "$content"); rc=$?
check    "replaces every occurrence of the section" "$expected" "$actual"
check_rc "reports replaced for a body carrying it twice" 0 "$rc"

finish
