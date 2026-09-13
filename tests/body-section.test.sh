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

# A body that is nothing but the section still keeps its heading.
body=$(printf '## Review\n\nplaceholder\n')
check "replaces a section that is the whole body" \
  "$(printf '## Review\n\nline one\nline two')" \
  "$(ship_body_replace_section "$body" Review "$content")"

finish
