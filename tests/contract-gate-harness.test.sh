#!/usr/bin/env bash
# scripts/contract-check.sh checks 7 to 9: the setup-harness catalog format, the
# two profile lines setup-skills parses and the harness schema number's four
# places. Split from tests/contract-gate.test.sh; the shared fixtures are in
# tests/contract-gate-lib.sh.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
source tests/contract-gate-lib.sh

# 7. Every setup-harness catalog entry carries its fixed headings and labels.
# A tree of its own, one valid stack entry and one valid file-kind entry beside
# the real profile template, so each case breaks one rule in one file.
tool_block() { # <tool> <rung> [<hook>]
  printf '### %s\nPublisher: p\nTier: 2: https://example.com\nEvidence: e\nRung: %s\nRun: `t {files}`\nHook: %s\nPin: apt t\nRoute: `apt-get install t`; Blocked: None.\nConstraints: None.\nTraps: None.\n\n' "$1" "$2" "${3:-local}"
}
harness_tree() { # <case-dir>: prints its path
  local d="$fixture/$1"
  rm -rf "$d"; mkdir -p "$d/setup-harness/catalog" "$d/setup-harness/templates" "$d/setup-harness/scripts"
  cp skills/setup-harness/templates/harness-profile.md "$d/setup-harness/templates/"
  cp skills/setup-harness/SKILL.md skills/setup-harness/harness-schema.md "$d/setup-harness/"
  cp skills/setup-harness/scripts/harness-profile-check.sh "$d/setup-harness/scripts/"
  printf '# Catalog\n\n## Signals\n\nNot an entry.\n' > "$d/setup-harness/catalog/README.md"
  { printf '# Py\n\n## Signals\nKind: stack\nManifest: pyproject.toml\nLockfile: uv.lock\nWorkspace: None.\nExtensions: .py\nShebangs: python\nRuntime version: .python-version\nLibrary: `[build-system]` and `[project]` in pyproject.toml\n\n## lint\n'
    tool_block ruff edit
    printf '## typecheck\n'; tool_block mypy turn
  } > "$d/setup-harness/catalog/py.md"
  { printf '# Shell\n\n## Signals\nKind: file kind\nNames: None.\nPaths: None.\nExtensions: .sh\nShebangs: sh\n\n## lint\n'
    tool_block shellcheck edit
  } > "$d/setup-harness/catalog/sh.md"
  printf '%s' "$d"
}

d=$(harness_tree catalog-valid)
run "$inert" "$d"
check_rc "a valid catalog and profile template pass" 0 "$rc"

d=$(harness_tree catalog-label)
sed -i.bak '/^Pin:/d' "$d/setup-harness/catalog/py.md"
run "$inert" "$d"
check_rc "a tool missing a required label fails" 1 "$rc"
check "and the violation names the entry, tool and label" 0 "$(named "catalog $d/setup-harness/catalog/py.md: ### ruff: missing Pin:")"

d=$(harness_tree catalog-signals)
sed -i.bak '/^Lockfile:/d' "$d/setup-harness/catalog/py.md"
run "$inert" "$d"
check "a stack entry missing a Signals label is named" 0 "$(named "catalog $d/setup-harness/catalog/py.md: ## Signals: missing Lockfile:")"

d=$(harness_tree catalog-library)
sed -i.bak '/^Library:/d' "$d/setup-harness/catalog/py.md"
run "$inert" "$d"
check "a stack entry missing its Library: signal is named" 0 "$(named "catalog $d/setup-harness/catalog/py.md: ## Signals: missing Library:")"

d=$(harness_tree catalog-kind-library)
sed -i.bak 's/^Paths: None.$/Paths: None.\nLibrary: None./' "$d/setup-harness/catalog/sh.md"
run "$inert" "$d"
check "a file-kind entry carrying a stack's Library: is named" 0 "$(named "catalog $d/setup-harness/catalog/sh.md: ## Signals: Library: is a stack's")"

d=$(harness_tree catalog-names)
sed -i.bak '/^Names:/d' "$d/setup-harness/catalog/sh.md"
run "$inert" "$d"
check "a file-kind entry missing its Names: label is named" 0 "$(named "catalog $d/setup-harness/catalog/sh.md: ## Signals: missing Names:")"

d=$(harness_tree catalog-paths)
sed -i.bak '/^Paths:/d' "$d/setup-harness/catalog/sh.md"
run "$inert" "$d"
check "a file-kind entry missing its Paths: label is named" 0 "$(named "catalog $d/setup-harness/catalog/sh.md: ## Signals: missing Paths:")"

d=$(harness_tree catalog-stack-paths)
sed -i.bak 's/^Workspace: None.$/Workspace: None.\nPaths: None./' "$d/setup-harness/catalog/py.md"
run "$inert" "$d"
check "a stack entry carrying a file kind's Paths: is named" 0 "$(named "catalog $d/setup-harness/catalog/py.md: ## Signals: Paths: is a file kind's")"

d=$(harness_tree catalog-files)
sed -i.bak 's/^Rung: turn$/Rung: turn\nFiles: .py .pyi/' "$d/setup-harness/catalog/py.md"
run "$inert" "$d"
check "a Files: extension outside the entry's Extensions: is named" 0 "$(named "catalog $d/setup-harness/catalog/py.md: ### mypy: Files: .pyi is not in Extensions:")"

d=$(harness_tree catalog-first)
sed -i.bak 's/^## Signals/## Sig/' "$d/setup-harness/catalog/sh.md"
run "$inert" "$d"
check "an entry not opening with ## Signals is named" 0 "$(named "catalog $d/setup-harness/catalog/sh.md: first ## heading is not ## Signals")"

d=$(harness_tree catalog-turn)
{ printf '## format\n'; tool_block shfmt turn; } >> "$d/setup-harness/catalog/sh.md"
run "$inert" "$d"
check_rc "a file-kind entry with a turn rung fails" 1 "$rc"
check "and names the tool" 0 "$(named "catalog $d/setup-harness/catalog/sh.md: ### shfmt: a file kind takes no turn rung")"

d=$(harness_tree catalog-blocked)
sed -i.bak 's/; Blocked: None\.$//' "$d/setup-harness/catalog/py.md"
run "$inert" "$d"
check "a Route line without its Blocked: clause is named" 0 "$(named "catalog $d/setup-harness/catalog/py.md: ### ruff: Route: want \`<install>\`; Blocked: <routes> | None., or None.")"

d=$(harness_tree catalog-role)
{ printf '## typecheck\n'; tool_block shx edit; } >> "$d/setup-harness/catalog/sh.md"
run "$inert" "$d"
check "a file-kind entry with a role beyond lint and format is named" 0 "$(named "catalog $d/setup-harness/catalog/sh.md: ## typecheck: a file kind carries lint and format only")"

d=$(harness_tree catalog-unknown-role)
{ printf '## linting\n'; tool_block x edit; } >> "$d/setup-harness/catalog/py.md"
run "$inert" "$d"
check "a role outside the vocabulary is named" 0 "$(named "catalog $d/setup-harness/catalog/py.md: ## linting: not a role")"

d=$(harness_tree catalog-full-only)
{ printf '## browser\n'; tool_block playwright turn; } >> "$d/setup-harness/catalog/py.md"
run "$inert" "$d"
check "a browser tool off the full rung is named" 0 "$(named "catalog $d/setup-harness/catalog/py.md: ### playwright: browser is full only")"

d=$(harness_tree catalog-rung)
sed -i.bak 's/^Rung: edit/Rung: commit/' "$d/setup-harness/catalog/sh.md"
run "$inert" "$d"
check "a rung outside edit, turn and full is named" 0 "$(named "catalog $d/setup-harness/catalog/sh.md: ### shellcheck: Rung: want edit, turn or full, got commit")"

d=$(harness_tree catalog-lsp)
{ printf '## language server\n'; tool_block pyright None. None.; printf 'Local-only: cloud sessions start no plugin language server\n'; } >> "$d/setup-harness/catalog/py.md"
run "$inert" "$d"
check_rc "a local-only language server with no rung passes" 0 "$rc"

d=$(harness_tree catalog-lsp-rung)
{ printf '## language server\n'; tool_block pyright edit None.; printf 'Local-only: x\n'; } >> "$d/setup-harness/catalog/py.md"
run "$inert" "$d"
check "a language server on a rung is named" 0 "$(named "catalog $d/setup-harness/catalog/py.md: ### pyright: a language server takes Rung: None.")"

d=$(harness_tree catalog-lsp-local)
{ printf '## language server\n'; tool_block pyright None. None.; } >> "$d/setup-harness/catalog/py.md"
run "$inert" "$d"
check "a language server without Local-only: is named" 0 "$(named "catalog $d/setup-harness/catalog/py.md: ### pyright: a language server is Local-only:")"

d=$(harness_tree catalog-rung-none)
sed -i.bak 's/^Rung: edit/Rung: None./' "$d/setup-harness/catalog/sh.md"
run "$inert" "$d"
check "Rung: None. off a language server is named" 0 "$(named "catalog $d/setup-harness/catalog/sh.md: ### shellcheck: Rung: want edit, turn or full, got None.")"

d=$(harness_tree catalog-lsp-hook)
{ printf '## language server\n'; tool_block pyright None. local; printf 'Local-only: x\n'; } >> "$d/setup-harness/catalog/py.md"
run "$inert" "$d"
check "a language server with a hook is named" 0 "$(named "catalog $d/setup-harness/catalog/py.md: ### pyright: a language server takes Hook: None.")"

d=$(harness_tree catalog-hook-none)
sed -i.bak 's/^Hook: local/Hook: None./' "$d/setup-harness/catalog/sh.md"
run "$inert" "$d"
check "Hook: None. off a language server is named" 0 "$(named "catalog $d/setup-harness/catalog/sh.md: ### shellcheck: Hook: None. is for a language server only")"

d=$(harness_tree catalog-lsp-reason)
{ printf '## language server\n'; tool_block pyright None. None.; printf 'Local-only:\n'; } >> "$d/setup-harness/catalog/py.md"
run "$inert" "$d"
check "a Local-only: with no reason is named" 0 "$(named "catalog $d/setup-harness/catalog/py.md: ### pyright: Local-only: wants its reason")"

# 8. The two profile lines setup-skills parses are frozen in the template.
d=$(harness_tree frozen-location)
sed -i.bak 's/^Location:/Path:/' "$d/setup-harness/templates/harness-profile.md"
run "$inert" "$d"
check_rc "a profile template without Location: fails" 1 "$rc"
check "and names the frozen line" 0 "$(named "harness profile template: ## Check entry point has no Location: line")"

d=$(harness_tree frozen-setup)
sed -i.bak 's/^## Cloud$/## Remote/' "$d/setup-harness/templates/harness-profile.md"
run "$inert" "$d"
check "a renamed ## Cloud loses its Setup: line, named" 0 "$(named "harness profile template: ## Cloud has no Setup: line")"

# 9. The harness schema number agrees in its four places. Each case moves one
# of them, because any one moving alone is the drift a Schema bump invites.
d=$(harness_tree schema-agrees)
run "$inert" "$d"
check_rc "a harness tree whose four schema places agree passes" 0 "$rc"

d=$(harness_tree schema-metadata)
sed -i.bak 's/^  harness-schema: .*/  harness-schema: 9/' "$d/setup-harness/SKILL.md"
run "$inert" "$d"
check_rc "a moved metadata.harness-schema fails" 1 "$rc"
check "and names all four places" 0 "$(named "harness schema disagrees: SKILL.md metadata.harness-schema 9, templates/harness-profile.md Schema: 3, scripts/harness-profile-check.sh schema=3, harness-schema.md entry '## Schema 9' missing")"

d=$(harness_tree schema-template)
sed -i.bak 's/^Schema: .*/Schema: 9/' "$d/setup-harness/templates/harness-profile.md"
run "$inert" "$d"
check "a moved template Schema: line is named" 0 "$(named "templates/harness-profile.md Schema: 9,")"

d=$(harness_tree schema-checker)
sed -i.bak 's/^schema=.*/schema=9/' "$d/setup-harness/scripts/harness-profile-check.sh"
run "$inert" "$d"
check "a moved checker literal is named" 0 "$(named "scripts/harness-profile-check.sh schema=9,")"

d=$(harness_tree schema-entry)
sed -i.bak 's/^## Schema 3$/## Schema three/' "$d/setup-harness/harness-schema.md"
run "$inert" "$d"
check "a missing harness-schema.md entry is named" 0 "$(named "harness-schema.md entry '## Schema 3' missing")"

d=$(harness_tree schema-missing)
sed -i.bak '/^schema=/d' "$d/setup-harness/scripts/harness-profile-check.sh"
run "$inert" "$d"
check "a checker with no literal is named as disagreeing" 0 "$(named "scripts/harness-profile-check.sh schema=none,")"

# Only the first value counts: a later line that looks like one (an example in
# the template's prose, a second assignment in the checker) is not a second value.
d=$(harness_tree schema-second-template)
printf '\nSchema: 9\n' >> "$d/setup-harness/templates/harness-profile.md"
run "$inert" "$d"
check_rc "a Schema: line below the first heading is not read" 0 "$rc"

d=$(harness_tree schema-second-checker)
printf '\nschema=9\n' >> "$d/setup-harness/scripts/harness-profile-check.sh"
run "$inert" "$d"
check_rc "a second schema= assignment is not read" 0 "$rc"

d=$(harness_tree schema-second-skill)
printf '\n  harness-schema: 9\n' >> "$d/setup-harness/SKILL.md"
run "$inert" "$d"
check_rc "a harness-schema: line below the frontmatter is not read" 0 "$rc"

# A place the check cannot read is tooling, not a drift about a file nobody
# read. A missing file is the case check 9 alone meets: an unreadable one trips
# the tree-wide grep of checks 3 and 6 first.
d=$(harness_tree schema-no-doc)
rm "$d/setup-harness/harness-schema.md"
run "$inert" "$d"
check_rc "a missing harness-schema.md is tooling" 2 "$rc"


finish
