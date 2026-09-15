#!/usr/bin/env bash
# ship_body_replace_section: the transformation behind `update-pr-body`.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
source skills/ship/scripts/_lib.sh

content=$(mktemp)
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

# A tilde fence is a fence too (CommonMark), so the example inside it is not a
# boundary either. Recognising backticks only put the real section below it out
# of reach.
body=$(cat <<'EOF'
## Summary

An example of what ship writes:

~~~md
## Review

copilot: converged
~~~

## Review

placeholder
EOF
)
expected=$(cat <<'EOF'
## Summary

An example of what ship writes:

~~~md
## Review

copilot: converged
~~~

## Review

line one
line two
EOF
)
check "skips a section heading inside a tilde fence" \
  "$expected" "$(ship_body_replace_section "$body" Review "$content")"

# A fence longer than three characters legally contains a shorter run of the
# same character. Closing on that inner run inverted the state for the rest of
# the body, so the example was replaced and the real section survived.
body=$(cat <<'EOF'
## Summary

````md
```
## Review
```
````

## Review

placeholder
EOF
)
expected=$(cat <<'EOF'
## Summary

````md
```
## Review
```
````

## Review

line one
line two
EOF
)
check "skips a heading inside a four-backtick fence holding a triple-backtick line" \
  "$expected" "$(ship_body_replace_section "$body" Review "$content")"

# A closing fence carries no info string, so a ```js line inside a ``` fence is
# content, not the close. Closing on it would leave the heading below exposed.
body=$(cat <<'EOF'
## Summary

```
an example
```js
## Review
```

## Review

placeholder
EOF
)
expected=$(cat <<'EOF'
## Summary

```
an example
```js
## Review
```

## Review

line one
line two
EOF
)
check "does not close a fence on a run carrying an info string" \
  "$expected" "$(ship_body_replace_section "$body" Review "$content")"

# A backtick opener may carry no backtick in its info string (CommonMark 4.5),
# so the line is paragraph text and the heading below it is a real boundary.
body=$(cat <<'EOF'
## Summary

```js`example

## Review

placeholder
EOF
)
expected=$(cat <<'EOF'
## Summary

```js`example

## Review

line one
line two
EOF
)
check "does not open a fence on a backtick opener carrying a backtick" \
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

# Phase 7 hands the mechanic the section's CONTENT. A file that repeats the
# heading anyway yields one heading, not two: the duplicate is what no mechanic
# could then repair, because every `## <sec>` line matches and a later clean
# write placed the content under both.
heading=$(mktemp); trap 'rm -f "$content" "$heading" "$other"' EXIT
printf '## Review\n\nline one\nline two\n' > "$heading"
body=$(printf '## Review\n\nplaceholder\n\n## Attribution\n\na footer line\n')
expected=$(printf '## Review\n\nline one\nline two\n\n## Attribution\n\na footer line')
actual=$(ship_body_replace_section "$body" Review "$heading"); rc=$?
check    "strips a leading heading the body file repeats" "$expected" "$actual"
check_rc "reports replaced for a file carrying the heading" 0 "$rc"

# Any other leading line is content, `## Other` included: only the section's own
# heading is the mechanic's to write.
other=$(mktemp)
printf '## Other\n\nline one\n' > "$other"
body=$(printf '## Review\n\nplaceholder\n')
check "keeps a leading heading that is not the section" \
  "$(printf '## Review\n\n## Other\n\nline one')" \
  "$(ship_body_replace_section "$body" Review "$other")"

# A body already carrying the duplicate is repaired by one ordinary write: the
# repeat sits inside the section just placed, so it is swallowed rather than
# given a second copy of the content. Every other section survives.
body=$(cat <<'BODY'
## Summary

keep

## Review

## Review

placeholder

## Attribution

a footer line
BODY
)
expected=$(cat <<'BODY'
## Summary

keep

## Review

line one
line two

## Attribution

a footer line
BODY
)
actual=$(ship_body_replace_section "$body" Review "$content"); rc=$?
check    "collapses a duplicate heading the body already carries" "$expected" "$actual"
check_rc "reports replaced for a body carrying the duplicate"     0 "$rc"

# Writing the same file twice gives the same body: the repair is not a one-shot.
check "is idempotent over the repaired body" \
  "$expected" "$(ship_body_replace_section "$expected" Review "$content")"

finish
