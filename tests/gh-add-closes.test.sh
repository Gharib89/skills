#!/usr/bin/env bash
# _gh_add_closes: the GitHub adapter's closing-line placement.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
# The adapter reads these at source time; no call in this file reaches a host.
SHIP_OWNER=owner SHIP_REPO=repo
source skills/ship/scripts/_lib.sh
source skills/ship/scripts/host/github.sh

# Above the first heading, where a later section rewrite cannot reach it.
body=$(cat <<'EOF'
Some intro

## Summary

text
EOF
)
expected=$(cat <<'EOF'
Some intro

Closes #76

## Summary

text
EOF
)
check "puts the closing line above the first heading" "$expected" "$(_gh_add_closes "$body" 76)"

# Two headings, one closing line.
body=$(printf '## Summary\n\ntext\n\n## Notes\n\nmore\n')
expected=$(printf 'Closes #76\n\n## Summary\n\ntext\n\n## Notes\n\nmore')
check "adds the closing line once, at the first heading" "$expected" "$(_gh_add_closes "$body" 76)"

# No heading: nothing to fall inside, so it keeps the append.
check "appends to a body with no heading" \
  "$(printf 'Just a body\n\nCloses #76')" \
  "$(_gh_add_closes "$(printf 'Just a body')" 76)"

# A `## ` inside a fence is example text, not a section boundary.
body=$(cat <<'EOF'
Intro

```md
## Not a heading
```

## Real heading

text
EOF
)
expected=$(cat <<'EOF'
Intro

```md
## Not a heading
```

Closes #76

## Real heading

text
EOF
)
check "skips a heading inside a fenced block" "$expected" "$(_gh_add_closes "$body" 76)"

# A tilde fence hides a heading the same way.
body=$(cat <<'EOF'
Intro

~~~md
## Not a heading
~~~

## Real heading

text
EOF
)
expected=$(cat <<'EOF'
Intro

~~~md
## Not a heading
~~~

Closes #76

## Real heading

text
EOF
)
check "skips a heading inside a tilde fence" "$expected" "$(_gh_add_closes "$body" 76)"

# A four-backtick fence holding a triple-backtick line: the inner run is not a
# close, so the heading between them is still example text.
body=$(cat <<'EOF'
Intro

````md
```
## Not a heading
```
````

## Real heading

text
EOF
)
expected=$(cat <<'EOF'
Intro

````md
```
## Not a heading
```
````

Closes #76

## Real heading

text
EOF
)
check "skips a heading inside a four-backtick fence holding a triple-backtick line" \
  "$expected" "$(_gh_add_closes "$body" 76)"

# A host serves a body back with CRLF line endings, so a closing fence carries a
# trailing CR. Reading that CR as an info string would leave the fence open and
# swallow the real heading below it, appending the closing line at the end.
body=$(printf 'Intro\r\n\r\n```md\r\n## Not a heading\r\n```\r\n\r\n## Real heading\r\n\r\ntext\r\n')
expected=$(printf 'Intro\r\n\r\n```md\r\n## Not a heading\r\n```\r\n\r\nCloses #76\n\n## Real heading\r\n\r\ntext\r')
check "closes a fence whose line ends in CRLF" "$expected" "$(_gh_add_closes "$body" 76)"

finish
