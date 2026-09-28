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
{ printf '# Toy\n\n## Signals\nKind: file kind\nNames: None.\nExtensions: .toy\nShebangs: None.\n\n## lint\n'
  tool lint 'lint {files}'
  tool 'Lax Lint' 'lax {files}'
  printf '## format\n'
  tool fmt 'fmt {files}'
  printf '### gone\nPublisher: p\nTier: 2: https://example.com\nEvidence: e\nRung: edit\nRun: `gone {files}`\nHook: local\nPin: apt gone\nRoute: `false`; Blocked: None.\nConstraints: None.\nUnavailable: no route\nTraps: None.\n'
  printf '### far\nPublisher: p\nTier: 2: https://example.com\nEvidence: e\nRung: edit\nRun: `false {files}`\nHook: local\nPin: apt far\nRoute: `false`; Blocked: None.\nConstraints: None.\nLocal-only: no cloud session runs it\nTraps: None.\n'
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
toy gone: unavailable (no route)
toy far: local-only (no cloud session runs it)" "$out"
check_rc "a tool that misses its planted failure fails the trial" 1 "$rc"
check "every tried tool was installed by its Route, the unavailable and local-only ones not" "installed lint
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

# A file kind claims files by Names: (a basename at any depth) and Paths: (a
# root-relative glob) as well as by extension; a tool's Files: narrows its
# {files} to its own extensions; {version} in Run: is the picked version, and
# {package} the seed's package name, `seed`.
printf '#!/bin/sh\necho 1.2.3\n' > "$root/skills/setup-harness/scripts/pick-version.sh"
printf '#!/bin/sh\nwant=$1; shift; [ "$want" = 1.2.3 ] || [ "$want" = seed ] || exit 1; exec lint "$@"\n' > "$root/bin/arg"
chmod +x "$root/bin/arg"
{ printf '# Kind\n\n## Signals\nKind: file kind\nNames: Kindfile\nPaths: ci/*.yml\nExtensions: .toy .alt\nShebangs: None.\n\n## lint\n'
  tool named 'lint {files}'
  tool narrow 'lint {files}' | sed 's/^Rung: edit$/Rung: edit\nFiles: .toy/'
  tool versioned 'arg {version} {files}' | sed 's/^Pin: apt versioned$/Pin: package npm versioned/'
  tool packaged 'arg {package} {files}'
} > "$root/skills/setup-harness/catalog/kind.md"
seed=$root/tests/fixtures/catalog/kind
mkdir -p "$seed/clean/ci/sub" "$seed/clean/deep" "$seed/bad/named/deep" "$seed/bad/narrow" "$seed/bad/versioned/ci" "$seed/bad/packaged"
echo fine > "$seed/clean/deep/Kindfile"
echo fine > "$seed/clean/ci/a.yml"
echo fine > "$seed/clean/a.toy"
echo BAD > "$seed/clean/other.yml"
echo BAD > "$seed/clean/ci/sub/nested.yml"  # a Paths: `*` stays within one directory
echo BAD > "$seed/clean/b.alt"
echo BAD > "$seed/bad/named/deep/Kindfile"
echo BAD > "$seed/bad/narrow/c.toy"
echo BAD > "$seed/bad/versioned/ci/b.yml"
echo BAD > "$seed/bad/packaged/c.toy"
# A Paths: glob is matched against seed paths, never expanded in the cwd.
mkdir -p "$root/ci" && : > "$root/ci/decoy.yml"
out=$(cd "$root" && PATH="$root/bin:$PATH" bash scripts/catalog-trial.sh kind 2>/dev/null); rc=$?
check "Names:, Paths:, Files:, {version} and {package} each reach the command" "kind named: fail (failed on clean)
kind narrow: pass
kind versioned: fail (failed on clean)
kind packaged: fail (failed on clean)" "$out"
rm "$seed/clean/b.alt"
out=$(cd "$root" && PATH="$root/bin:$PATH" bash scripts/catalog-trial.sh kind 2>/dev/null); rc=$?
check "a file outside Names:, Paths: and Extensions: is never passed, nor one a directory below a Paths: glob" "kind named: pass
kind narrow: pass
kind versioned: pass
kind packaged: pass" "$out"

out=$(cd "$root" && bash scripts/catalog-trial.sh nope 2>/dev/null); rc=$?
check_rc "an entry that does not exist is a usage error" 2 "$rc"

finish
