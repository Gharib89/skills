#!/usr/bin/env bash
# scripts/catalog-trial.sh: the entry trial. The subject is its verdict per
# tool: installed by `Route:`, its `Run:` passing on the clean seed tree
# without changing a file, and failing (or changing a file) once the tool's
# planted-bad files are laid over it. The case root is a throwaway copy of the
# repo layout the script reads, holding one fixture entry whose tools are stub
# commands pinned by apt, so no registry is asked for a version.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

fixture=$(mktemp -d); trap 'rm -rf "$fixture"' EXIT
root=$fixture/root
mkdir -p "$root/scripts" "$root/skills/setup-harness/catalog" "$root/bin"
cp scripts/catalog-trial.sh "$root/scripts/"
cp -r skills/setup-harness/scripts "$root/skills/setup-harness/"

# lint fails on a file holding BAD; fmt rewrites UGLY; lax passes everything.
printf '#!/bin/sh\nrc=0; for f; do grep -q BAD "$f" && rc=1; done; exit $rc\n' > "$root/bin/lint"
printf '#!/bin/sh\nfor f; do sed "s/UGLY/pretty/" "$f" > "$f.t" && mv "$f.t" "$f"; done\n' > "$root/bin/fmt"
printf '#!/bin/sh\nexit 0\n' > "$root/bin/lax"
chmod +x "$root/bin/"*

tool() { # <name> <run> [<route>]
  printf '### %s\nPublisher: p\nTier: 2: https://example.com\nEvidence: e\nRung: edit\nRun: `%s`\nHook: local\nPin: apt %s\nRoute: `%s`; Blocked: None.\nConstraints: None.\nTraps: None.\n\n' \
    "$1" "$2" "$1" "${3:-echo installed $1 >> $fixture/installs}"
}
{ printf '# Toy\n\n## Signals\nKind: file kind\nExtensions: .toy\nShebangs: None.\n\n## lint\n'
  tool lint 'lint {files}'
  tool 'Lax Lint' 'lax {files}'
  printf '## format\n'
  tool fmt 'fmt {files}'
  printf '### gone\nPublisher: p\nTier: 2: https://example.com\nEvidence: e\nRung: edit\nRun: `gone {files}`\nHook: local\nPin: apt gone\nRoute: `false`; Blocked: None.\nConstraints: None.\nUnavailable: no route\nTraps: None.\n'
} > "$root/skills/setup-harness/catalog/toy.md"

seed=$root/tests/fixtures/catalog/toy
mkdir -p "$seed/clean/src" "$seed/bad/lint" "$seed/bad/lax-lint" "$seed/bad/fmt"
echo fine > "$seed/clean/src/a.toy"
echo 'not covered' > "$seed/clean/notes.txt"
echo BAD > "$seed/bad/lint/b.toy"
echo BAD > "$seed/bad/lax-lint/b.toy"
echo UGLY > "$seed/bad/fmt/c.toy"

out=$(cd "$root" && PATH="$root/bin:$PATH" bash scripts/catalog-trial.sh toy 2>/dev/null); rc=$?
check "each tool gets one verdict line" "toy lint: pass
toy lax-lint: fail (passed on bad/lax-lint)
toy fmt: pass
toy gone: unavailable (no route)" "$out"
check_rc "a tool that misses its planted failure fails the trial" 1 "$rc"
check "every tried tool was installed by its Route, the unavailable one not" "installed lint
installed Lax Lint
installed fmt" "$(cat "$fixture/installs")"
check "the seed tree itself is left untouched" fine "$(cat "$seed/clean/src/a.toy")"

rm -rf "$seed/bad/lax-lint"
sed -i.bak '/^### Lax Lint/,/^$/d' "$root/skills/setup-harness/catalog/toy.md"
out=$(cd "$root" && PATH="$root/bin:$PATH" bash scripts/catalog-trial.sh all 2>/dev/null); rc=$?
check_rc "all passes when every tool catches its planted failure" 0 "$rc"

echo BAD > "$seed/clean/src/a.toy"
out=$(cd "$root" && PATH="$root/bin:$PATH" bash scripts/catalog-trial.sh toy 2>/dev/null)
check "a tool failing on the clean tree is named" "toy lint: fail (failed on clean)" "$(printf '%s\n' "$out" | head -n 1)"

out=$(cd "$root" && bash scripts/catalog-trial.sh nope 2>/dev/null); rc=$?
check_rc "an entry that does not exist is a usage error" 2 "$rc"

finish
