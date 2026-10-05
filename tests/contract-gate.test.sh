#!/usr/bin/env bash
# scripts/contract-check.sh: the mechanics' malformed-invocation contract.
# The first case runs the checker against the real `skills/ship/scripts`, and
# every case under it runs it once against a fixture of its own, asserting on
# the exit code and the stdout that one run left behind: the verdict and the
# violation it names are two readings of the same run.
#
# A fixture carries `_lib.sh`, the real host adapters and only the mechanics the
# case's own mutation is read through, rather than a copy of all of them. Checks
# 2, 4 and 5 spawn each mechanic in the directory up to six times, which is
# nearly all of what a full-tree run costs, and on a fixture it is spent
# re-asserting what the first case asserts once against the real tree. The
# guards a fixture does share are the real ones, copied in. Together the two
# take this file from 64 s to 2.5 s.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

fixture=$(mktemp -d); trap 'rm -rf "$fixture"' EXIT

# <case-dir> [<mechanic>...]: a mechanics directory for one case, always
# carrying `_lib.sh` and the real host adapters, plus a real copy of each named
# mechanic for a case that mutates one rather than replacing it.
copy_mechanics() {
  local d="$fixture/$1" m; shift
  rm -rf "$d"; mkdir -p "$d"
  cp skills/ship/scripts/_lib.sh "$d/" || exit 2
  cp -r skills/ship/scripts/host "$d/" || exit 2
  # A mechanic renamed out from under this file would otherwise leave the case
  # appending its mutation to a file holding nothing else, still green.
  for m; do cp "skills/ship/scripts/$m.sh" "$d/" || exit 2; done
  printf '%s' "$d"
}
# <case-dir>: a fresh copy of the whole skills tree, for one Bash 4+ mutation.
copy_skills() { local d="$fixture/$1"; rm -rf "$d"; cp -r skills "$d"; printf '%s' "$d"; }

# Run the checker once and leave its exit code in `rc` and its stdout in `out`,
# which is what every assertion below reads.
run() { out=$(bash scripts/contract-check.sh "$1" "${2:-skills}" 2>/dev/null); rc=$?; }

# 0 when the last run's stdout contains this line, for a fixture that trips more
# than one check and whose whole stdout is therefore not one assertion's
# business.
named() { case $out in *"$1"*) printf 0 ;; *) printf 1 ;; esac; }

# A mechanics directory with no mechanic in it: checks 1, 2, 4 and 5 have
# nothing of their own to read, so the verdict is check 3's alone, which is the
# only check a `copy_skills` fixture mutates.
inert=$(copy_mechanics inert)

# The real mechanics and the real skills tree, so this case holds every check
# against the directory that ships, check 3 included: the tree carries no
# Bash 4+ construct.
run skills/ship/scripts
check_rc "the current tree holds the contract" 0 "$rc"

# A mechanic written with the pre-#62 idiom: bash's own diagnostic on stderr and
# exit 1, where the contract wants one JSON object and exit 2.
d=$(copy_mechanics expansion read-issue)
printf '\nx=${2:?needs a thing}\n' >> "$d/read-issue.sh"
run "$d"
check_rc "a \${N:?} expansion fails the check" 1 "$rc"

# `${N?msg}` fails the same way as `${N:?msg}`: exit 1, bash's diagnostic on
# stderr, no JSON. The ban covers both forms.
d=$(copy_mechanics expansion-no-colon read-issue)
printf '\nx=${2?needs a thing}\n' >> "$d/read-issue.sh"
run "$d"
check_rc "a \${N?} expansion fails the check" 1 "$rc"

# The expansion is banned under the whole directory, host adapters included.
d=$(copy_mechanics expansion-host)
printf '\nx=${1:?needs a thing}\n' >> "$d/host/github.sh"
run "$d"
check_rc "a \${N:?} expansion in a host adapter fails the check" 1 "$rc"

d=$(copy_mechanics exit-one)
cat > "$d/read-issue.sh" <<'EOF'
#!/usr/bin/env bash
echo "read-issue: missing issue" >&2
exit 1
EOF
run "$d"
check_rc "a positional-taking mechanic exiting 1 bare fails the check" 1 "$rc"

d=$(copy_mechanics no-json)
cat > "$d/read-issue.sh" <<'EOF'
#!/usr/bin/env bash
echo "usage: read-issue <issue>" >&2
exit 2
EOF
run "$d"
check_rc "exit 2 without a JSON error object fails the check" 1 "$rc"

# The four mechanics that legitimately take no argument are not held to check 2:
# a bare invocation of one is a real run, not a malformed invocation.
d=$(copy_mechanics excluded)
# The stub answers --help because check 5 exempts nobody: without that branch
# the fixture would fail on check 5 and the case would assert the wrong thing.
cat > "$d/base-fresh.sh" <<'EOF'
#!/usr/bin/env bash
[ "${1:-}" = --help ] && { echo "usage: base-fresh"; exit 0; }
printf '{"fresh":true}\n'
exit 0
EOF
run "$d"
check_rc "a mechanic that takes no positional is exempt from check 2" 0 "$rc"

# Check 4: a flag typed where the id belongs. A stub rather than the real
# mechanic with its guard removed, because an unguarded mechanic reaches the
# host and no test here does.
d=$(copy_mechanics dash-as-id)
cat > "$d/read-issue.sh" <<'EOF'
#!/usr/bin/env bash
usage='usage: read-issue <issue>'
[ -n "${1:-}" ] || { printf '{"error":"%s"}\n' "$usage"; exit 2; }
printf '{"number":"%s"}\n' "$1"
EOF
run "$d"
check_rc "a mechanic that reads a leading-dash value as its id fails the check" 1 "$rc"

# Why check 4 invokes three arities: a mechanic with more than one positional
# answers a single `--x` on its missing-second-positional guard, which is the
# usage line for the wrong reason, and passes.
d=$(copy_mechanics dash-as-id-third)
cat > "$d/read-issue.sh" <<'EOF'
#!/usr/bin/env bash
usage='usage: read-issue <issue>'
[ -n "${1:-}" ] && [ -n "${2:-}" ] && [ -n "${3:-}" ] || { printf '{"error":"%s"}\n' "$usage"; exit 2; }
printf '{"number":"%s"}\n' "$1"
EOF
run "$d"
check_rc "a three-positional mechanic is caught only by the third dash" 1 "$rc"

# Check 5: the --help contract. Each stub answers checks 2 and 4 the way a real
# mechanic does, so the one violation in the fixture is the one under test and
# the checker's whole stdout is the line it names.
help_stub() { # <case-dir> <help-branch>
  local d; d=$(copy_mechanics "$1")
  { printf '#!/usr/bin/env bash\n'
    printf "usage='usage: read-issue <issue>'\n"
    [ -n "$2" ] && printf '%s\n' "$2"
    printf 'case ${1:-} in ""|-*) printf %s "$usage"; exit 2 ;; esac\n' "'{\"error\":\"%s\"}\\n'"
    printf 'printf %s "$1"\n' "'{\"number\":\"%s\"}\\n'"
  } > "$d/read-issue.sh"
  printf '%s' "$d"
}

run "$(help_stub help-unanswered '')"
check "a mechanic that does not answer --help is named" \
  'read-issue: --help exited 2, expected 0' "$out"
check_rc "a mechanic that does not answer --help fails the check" 1 "$rc"

run "$(help_stub help-wrong-line '[ "${1:-}" = --help ] && { echo "see the docs"; exit 0; }')"
check "a --help answer that is not the usage line is named" \
  'read-issue: --help did not print its own usage line on stdout' "$out"
check_rc "a --help answer that is not the usage line fails the check" 1 "$rc"

run "$(help_stub help-noisy '[ "${1:-}" = --help ] && { echo "$usage"; echo noise >&2; exit 0; }')"
check "a --help answer that writes to stderr is named" \
  'read-issue: --help wrote to stderr' "$out"
check_rc "a --help answer that writes to stderr fails the check" 1 "$rc"

# The mechanic's name has to end where its own usage line ends it. A prefix
# match alone takes another mechanic's line as this one's.
run "$(help_stub help-name-prefix '[ "${1:-}" = --help ] && { echo "usage: read-issue-other <issue>"; exit 0; }')"
check "a --help answer naming a longer mechanic is named" \
  'read-issue: --help did not print its own usage line on stdout' "$out"
check_rc "a --help answer naming a longer mechanic fails the check" 1 "$rc"

# The usage line and nothing under it. A case pattern matches across newlines,
# so the prefix arm above passes a mechanic that prints its usage and then talks.
run "$(help_stub help-extra-output '[ "${1:-}" = --help ] && { echo "usage: read-issue <issue>"; echo "and some more"; exit 0; }')"
check "a --help answer with a second line is named" \
  'read-issue: --help printed more than its usage line on stdout' "$out"
check_rc "a --help answer with a second line fails the check" 1 "$rc"

# A guard placed after `ship_load_host` answers --help correctly wherever an
# adapter loads, which is why check 5 runs from a directory with no origin
# remote. This stub answers checks 2 and 4 from a checkout whose origin is on
# GitHub, and only check 5, from there, sees the adapter error where the usage
# line belongs. That checkout is a throwaway rather than this repo, whose clone
# in a cloud session has no origin remote.
d=$(copy_mechanics help-late-guard)
cat > "$d/read-issue.sh" <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh" || { printf '{"error":"cannot source _lib.sh"}\n'; exit 2; }
usage='usage: read-issue <issue>'
ship_load_host
ship_help "$usage" "$@"
case ${1:-} in ""|-*) ship_tooling "$usage" ;; esac
printf '{"number":"%s"}\n' "$1"
EOF
origin=$fixture/github-origin
git init -q "$origin" && git -C "$origin" remote add origin https://github.com/example/repo.git || exit 2
root=$PWD
out=$(cd "$origin" && bash "$root/scripts/contract-check.sh" "$d" "$root/skills" 2>/dev/null); rc=$?
check "a guard after the adapter load is named" \
  'read-issue: --help exited 2, expected 0' "$out"
check_rc "a guard after the adapter load fails the check" 1 "$rc"

# The --help answer and the guards' answer are two paths, and check 4 reads only
# the second. A mechanic that grows a flag and updates one of them leaves the
# other as the run's stale source.
run "$(help_stub help-drift '[ "${1:-}" = --help ] && { echo "usage: read-issue"; exit 0; }')"
check "a --help answer that disagrees with the guard is named" \
  'read-issue: --help and the usage guard print different lines' "$out"
check_rc "a --help answer that disagrees with the guard fails the check" 1 "$rc"

# The drift comparison reaches the mechanics that take no positional too: only
# `base-fresh` and `select` answer a bad call with no usage line at all. The
# call that reaches the guard differs per mechanic, and `file-issue`, which
# carries the longest usage string in the tree, answers the bare call, not
# check 4's three dashes.
d=$(copy_mechanics help-drift-no-positional)
cat > "$d/file-issue.sh" <<'EOF'
#!/usr/bin/env bash
usage='usage: file-issue --title <title> --body-file <path> --label <marker>'
[ "${1:-}" = --help ] && { printf '%s\n' "$usage"; exit 0; }
printf '{"error":"%s [--distinct-from <n>[,<n>]]"}\n' "$usage"
exit 2
EOF
run "$d"
check_rc "a no-positional mechanic whose --help drifts from its guard is named" 0 \
  "$(named 'file-issue: --help and the usage guard print different lines')"
check_rc "a no-positional mechanic whose --help drifts fails the check" 1 "$rc"

# Check 4 takes the usage line and nothing under it, the way check 5 does: the
# regex anchors the start alone. This stub trips check 5's comparison too, so the
# assertion names check 4's own line rather than the whole stdout.
d=$(copy_mechanics dash-usage-extra)
cat > "$d/read-issue.sh" <<'EOF'
#!/usr/bin/env bash
usage='usage: read-issue <issue>'
[ "${1:-}" = --help ] && { printf '%s\n' "$usage"; exit 0; }
case ${1:-} in ""|-*) printf '{"error":"%s\\nand more"}\n' "$usage"; exit 2 ;; esac
printf '{"number":"%s"}\n' "$1"
EOF
run "$d"
check_rc "a usage error with a second line is named by check 4" 0 \
  "$(named 'read-issue: 1 leading-dash positional(s) did not answer with its own usage line')"
check_rc "a usage error with a second line fails the check" 1 "$rc"

# Check 3: the Bash 3.2 target. A file under skills/ runs in whatever shell a
# consumer machine provides, macOS's system Bash included, and the mechanics
# carry no `set -e`, so a Bash 4 builtin there is a skipped line and a silent
# pass rather than a stop. One case per named construct, because each is its own
# branch of the pattern. The mechanics directory is `inert`.
mechanics=ship/scripts/read-issue.sh

d=$(copy_skills bash4-mapfile)
printf '\nmapfile -t lines < /dev/null\n' >> "$d/$mechanics"
run "$inert" "$d"
check_rc "a mapfile under skills/ fails the check" 1 "$rc"

# A command name ends at any character a name cannot carry, not at whitespace
# alone: `mapfile<f` and `mapfile;` are the same builtin.
d=$(copy_skills bash4-redirect)
printf '\nmapfile</dev/null\n' >> "$d/$mechanics"
run "$inert" "$d"
check_rc "a mapfile delimited by a redirect fails the check" 1 "$rc"

d=$(copy_skills bash4-readarray)
printf '\nreadarray -t lines < /dev/null\n' >> "$d/$mechanics"
run "$inert" "$d"
check_rc "a readarray under skills/ fails the check" 1 "$rc"

d=$(copy_skills bash4-assoc)
printf '\ndeclare -A seen\n' >> "$d/$mechanics"
run "$inert" "$d"
check_rc "a declare -A under skills/ fails the check" 1 "$rc"

# `-A` need not stand alone or come first: every spelling is the same array.
for form in '-r -A' '-A -r' '-Ar'; do
  d=$(copy_skills "bash4-assoc-$(printf '%s' "$form" | tr -d ' -')")
  printf '\ndeclare %s seen\n' "$form" >> "$d/$mechanics"
  run "$inert" "$d"
  check_rc "a declare $form under skills/ fails the check" 1 "$rc"
done

# The lowercase options are Bash 3.2's own and must not be flagged.
d=$(copy_skills bash3-indexed-array)
printf '\ndeclare -ar plain\n' >> "$d/$mechanics"
run "$inert" "$d"
check_rc "a declare -ar does not fail the check" 0 "$rc"

d=$(copy_skills bash4-lowercase)
printf '\nx=${reason,,}\n' >> "$d/$mechanics"
run "$inert" "$d"
check_rc "a \${var,,} under skills/ fails the check" 1 "$rc"

# A positional or `$@` takes the same case modifier, and the pattern covers it:
# `${1,,}` is as absent from Bash 3.2 as `${reason,,}` is.
d=$(copy_skills bash4-positional)
printf '\nx=${1,,}\n' >> "$d/$mechanics"
run "$inert" "$d"
check_rc "a \${1,,} under skills/ fails the check" 1 "$rc"

d=$(copy_skills bash4-uppercase)
printf '\nx=${reason^^}\n' >> "$d/$mechanics"
run "$inert" "$d"
check_rc "a \${var^^} under skills/ fails the check" 1 "$rc"

# A construct named in a comment is prose, not a call: preflight.sh explains in
# one why it uses a read loop instead of mapfile, and that comment must survive.
d=$(copy_skills bash4-comment)
printf '\n# a read loop, not mapfile: the mechanics target Bash 3.2\n' >> "$d/$mechanics"
run "$inert" "$d"
check_rc "a construct named in a comment does not fail the check" 0 "$rc"

# The setup-skills local-gate template is written into consumer repos like the
# rest of skills/, so it is held to Bash 3.2 too, with no exemption.
d=$(copy_skills bash4-template)
printf '\nmapfile -t lines < /dev/null\n' >> "$d/setup-skills/local-gate.sh"
run "$inert" "$d"
check_rc "a Bash 4 construct in the setup-skills local-gate template fails the check" 1 "$rc"

# The comment exclusion reads a field, not the whole line. A violation whose own
# content carries `:N: #` is still a violation.
d=$(copy_skills bash4-shadowed-comment)
printf '\ndeclare -A seen # path:12: # a note\n' >> "$d/$mechanics"
run "$inert" "$d"
check_rc "a violation carrying :N: # in its content still fails" 1 "$rc"

# SHIP_HOST_ADAPTER swaps the host adapter for the test suite's Host fake, so
# `ship_load_host` in `_lib.sh` is its one reader. The untouched copy carries
# that reader and passes; a mechanic that reads it fails, named.
d=$(copy_skills host-adapter-lib)
run "$inert" "$d"
check_rc "the one reader in _lib.sh passes" 0 "$rc"

d=$(copy_skills host-adapter-mechanic)
printf '\nadapter=${SHIP_HOST_ADAPTER:-}\n' >> "$d/ship/scripts/read-issue.sh"
run "$inert" "$d"
check_rc "a mechanic reading SHIP_HOST_ADAPTER fails" 1 "$rc"
check "and the violation names the mechanic" 0 "$(named "$d/ship/scripts/read-issue.sh:")"

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

d=$(harness_tree catalog-settings)
{ printf '## language server\n'; tool_block pyright None. None.; printf 'Local-only: x\nSettings: `{}`\n'; } >> "$d/setup-harness/catalog/py.md"
run "$inert" "$d"
check_rc "a language server with Settings: passes" 0 "$rc"

d=$(harness_tree catalog-settings-off)
sed -i.bak 's/^Rung: edit$/Rung: edit\nSettings: `{}`/' "$d/setup-harness/catalog/sh.md"
run "$inert" "$d"
check "Settings: off a language server is named" 0 "$(named "catalog $d/setup-harness/catalog/sh.md: ### shellcheck: Settings: is for a language server only")"

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

# 10. Two rules ship's prose states that nothing else enforces. Each case
# rewrites the governed sentence to its opposite, which every word a looser grep
# would look for still appears in, so a check that passes it proves nothing.
d=$(copy_skills phase4-negated)
sed -i.bak "s/JSON and never runs/JSON and also runs/" "$d/ship/SKILL.md"
run "$inert" "$d"
check_rc "a phase 4 that tells the axes to run the suite too fails" 1 "$rc"
check "and names the file and the rule" 0 "$(named "$d/ship/SKILL.md: phase 4 must tell each axis the Local gate runs later, so it reads the gate's JSON and never runs check.sh full or the suite")"

d=$(copy_skills phase4-absent)
sed -i.bak "/^gate runs later in the run,/d" "$d/ship/SKILL.md"
run "$inert" "$d"
check_rc "a phase 4 missing a line of the sentence fails" 1 "$rc"

d=$(copy_skills discipline-negated)
sed -i.bak 's/Read one reference file per call\./Read several reference files per call./' "$d/ship/reference/context-discipline.md"
run "$inert" "$d"
check_rc "a context discipline that reads several files per call fails" 1 "$rc"
check "and names the file and the rule" 0 "$(named "$d/ship/reference/context-discipline.md: must say to read one reference file per call")"

# 11 to 14 read a mechanic's usage line against its header, its flag guards, a
# failing host and the prose that names it. `flag_stub` is a read-issue that
# answers every call checks 2, 4 and 5 make with its usage line, so the one
# violation in a fixture is the one under test and the checker's whole stdout is
# the line it names. Its header and usage line are the case's own, and its arm
# is what it does with the flags after the positional.
flag_stub() { # <case-dir> <header-lines> <usage-line> <arm>
  local d; d=$(copy_mechanics "$1")
  { printf '#!/usr/bin/env bash\n%s\n#\n' "$2"
    printf "usage='%s'\n" "$3"
    cat <<'EOF'
fail() { jq -n --arg e "$usage" '{error: $e}'; exit 2; }
[ "${1:-}" = --help ] && { printf '%s\n' "$usage"; exit 0; }
case ${1:-} in ""|-*) fail ;; esac
shift
EOF
    printf '%s\n' "$4"
  } > "$d/read-issue.sh"
  printf '%s' "$d"
}
guarded='while [ $# -gt 0 ]; do case $1 in --title) case ${2:-} in ""|-*) fail ;; esac; shift 2 ;; *) fail ;; esac; done'
unguarded='while [ $# -gt 0 ]; do case $1 in --title) [ -n "${2:-}" ] || fail; shift 2 ;; *) fail ;; esac; done'
title_usage='usage: read-issue <issue> --title "<t>"'
title_header='#   read-issue <issue> --title "<t>"'

# Their stubs are named like the real read-issue, so the real prose that
# invokes `read-issue <issue>` would be held to the stubs' flags by check 14; an
# empty skills tree keeps these cases to the check under test.
nodocs=$fixture/nodocs; mkdir -p "$nodocs"
runs() { run "$1" "$nodocs"; }

# 11. The header synopsis and the --help usage line are two spellings of one
# interface; the run reads the second, a maintainer the first.
runs "$(flag_stub synopsis-agrees "$title_header" "$title_usage" "$guarded")"
check_rc "a header and a usage line that agree pass checks 11 and 12" 0 "$rc"
check "and print nothing" "" "$out"

runs "$(flag_stub synopsis-flag '#   read-issue <issue> [--since <iso>]' 'usage: read-issue <issue>' 'exit 0')"
check_rc "a header flag the usage line lacks fails" 1 "$rc"
check "and the violation names the flags" \
  'read-issue: header synopsis and --help usage line disagree: flags (header: --since; usage: none)' "$out"

runs "$(flag_stub synopsis-slot '#   read-issue <issue>' 'usage: read-issue <issue|none>' 'exit 0')"
check "a leading slot spelled differently is named" \
  'read-issue: header synopsis and --help usage line disagree: leading slots (header: <issue>; usage: <issue|none>)' "$out"

# The block runs to the next line that is exactly `#`, so a second synopsis line
# and a flag in it count; prose after the blank does not.
runs "$(flag_stub synopsis-block '#   read-issue <issue> --title "<t>"
#   read-issue <issue> --title "<t>" [--since <iso>]
#
# a note that mentions --other' "$title_usage" "$guarded")"
check "a flag on a second synopsis line is read and prose after the block is not" \
  'read-issue: header synopsis and --help usage line disagree: flags (header: --since --title; usage: --title)' "$out"

# 12. A flag that takes a value refuses a leading-dash one with the usage line:
# `--title --x` reads the next flag as the title otherwise.
runs "$(flag_stub dash-value "$title_header" "$title_usage" "$unguarded")"
check_rc "a flag that reads a leading-dash value as its value fails" 1 "$rc"
check "and the violation names the flag" \
  'read-issue: --title took a leading-dash value; guard it with ship_flag_value so it answers the usage line and exit 2' "$out"

runs "$(flag_stub dash-value-optional '#   read-issue <issue> [--title "<t>"]' 'usage: read-issue <issue> [--title "<t>"]' "$unguarded")"
check "an optional flag is held to the same rule" \
  'read-issue: --title took a leading-dash value; guard it with ship_flag_value so it answers the usage line and exit 2' "$out"

# 13. A failure through the Host fake prints one JSON object. The mechanic is
# real code against the real `_lib.sh`; only its tail differs per case.
host_stub() { # <case-dir> <tail>
  local d; d=$(copy_mechanics "$1")
  cat > "$d/read-issue.sh" <<EOF
#!/usr/bin/env bash
set -uo pipefail
source "\$(dirname "\${BASH_SOURCE[0]}")/_lib.sh" || { printf '{"error":"cannot source _lib.sh"}\n'; exit 2; }
usage='usage: read-issue <issue>'
ship_help "\$usage" "\$@"
ship_args "\$usage" issue "\$@"
ship_load_host
$2
EOF
  printf '%s' "$d"
}
runs "$(host_stub host-failure-json 'host_issue_get "$1" || ship_fail "cannot read issue $1"')"
check_rc "a host failure that prints one JSON object passes" 0 "$rc"
check "and prints nothing" "" "$out"

runs "$(host_stub host-failure-bare 'host_issue_get "$1" || exit 1')"
check_rc "a host failure that prints nothing fails" 1 "$rc"
check "and the violation gives the count and the call" \
  'read-issue: with every host_* failing in the Host fake, `read-issue 1` printed 0 JSON values on stdout; want exactly one object' "$out"

runs "$(host_stub host-failure-two 'host_issue_get "$1" || { echo "{\"note\":1}"; ship_fail "cannot read issue $1"; }')"
check "a host failure that prints two objects is counted" \
  'read-issue: with every host_* failing in the Host fake, `read-issue 1` printed 2 JSON values on stdout; want exactly one object' "$out"

runs "$(host_stub host-failure-garbage 'host_issue_get "$1" || { echo "{not json"; exit 1; }')"
check "a host failure that prints unparseable output says so" \
  'read-issue: with every host_* failing in the Host fake, `read-issue 1` printed unparseable output on stdout; want exactly one object' "$out"

# A tree that cannot drive the check is a failure, never a pass: a checker copy
# whose Host fake lists no host_* function, and one whose root lacks the profile
# the throwaway checkout is seeded from.
stage_root() { # <case> <fake-sed>: a root with the checker and a Host fake, no profile
  local r="$fixture/$1"
  mkdir -p "$r/scripts" "$r/tests"
  cp scripts/contract-check.sh "$r/scripts/" && sed "$2" tests/host-fake.sh > "$r/tests/host-fake.sh" || exit 2
  printf '%s' "$r"
}
d=$(host_stub host-setup 'host_issue_get "$1" || ship_fail "cannot read issue $1"')
r=$(stage_root host-fake-empty 's/^for _fn in/for _fx in/')
out=$(bash "$r/scripts/contract-check.sh" "$d" "$nodocs" 2>/dev/null); rc=$?
check_rc "a Host fake that lists no host function fails" 1 "$rc"
check "and the violation names the fake" \
  "$r/tests/host-fake.sh: no host_* function on its \`for _fn in\` line; check 13 has nothing to fail" "$out"

r=$(stage_root host-profile-missing 's/^//')
out=$(bash "$r/scripts/contract-check.sh" "$d" "$nodocs" 2>/dev/null); rc=$?
check_rc "a root with no ship profile to copy fails" 1 "$rc"
check "and the violation names the step" \
  'read-issue: check 13 setup failed: cannot copy docs/agents/ship.md' "$out"

# 14. Prose invoking a mechanic carries its required flags, outside fences. One
# doc per violation, so the output is the one line under test, and a passing doc
# alone.
docmech=$(copy_mechanics doc-flag comment-issue update-pr-body)
doc_run() { # <case> <doc>: leaves the doc's path in `zz`
  local sk; sk=$(copy_skills "doc-$1"); mkdir -p "$sk/zz"
  printf '%s\n' "$2" > "$sk/zz/zz.md"; zz=$sk/zz/zz.md
  run "$docmech" "$sk"
}
doc_run lacks-body 'Post it with `comment-issue 5` now.'
check_rc "a Markdown invocation without a required flag fails" 1 "$rc"
check "and the lacking span is named" \
  "$zz:1: \`comment-issue 5\` lacks --body-file from comment-issue's usage line" "$out"

doc_run lacks-group 'An `update-pr-body --body-file b` names neither.'
check_rc "an invocation without either flag of a group fails" 1 "$rc"
check "and the group is named as an either-or" \
  "$zz:1: \`update-pr-body --body-file b\` lacks --section or --preamble from update-pr-body's usage line" "$out"

doc_run lacks-section 'An `update-pr-body --section` for it.'
check_rc "an invocation that leaves out the body file fails" 1 "$rc"
check "and the missing flag is named" \
  "$zz:1: \`update-pr-body --section\` lacks --body-file from update-pr-body's usage line" "$out"

doc_run complete 'Post it with `comment-issue 5 --body-file b.md` now.
And `update-pr-body 5 --preamble --body-file b` too.
```
`comment-issue 5` inside a fence is a sample, not an instruction.
```'
check_rc "invocations with their required flags, and a fenced sample, pass" 0 "$rc"
check "and print nothing" "" "$out"

# 15. Three shell rules grep can hold. One fixture per violation, each asserting
# the exit code and the one printed reason, and a passing fixture of near misses
# alone.
shell_run() { # <case> <file-content>: leaves the fixture's path in `sk`
  sk=$(copy_skills "shell-$1"); mkdir -p "$sk/zz"
  printf '%s\n' "$2" > "$sk/zz/bad.sh"
  run "$inert" "$sk"
}
shell_run curl '#!/usr/bin/env bash
curl -fsSL "$url" > out'
check_rc "a curl with no --max-time fails" 1 "$rc"
check "and is named at its line" \
  "$sk/zz/bad.sh:2: curl without --max-time; a hung download hangs the caller with it" "$out"

shell_run sh-c '#!/usr/bin/env bash
while read -r row; do
  sh -c "true"
done <<EOT
$rows
EOT'
check_rc "an unredirected sh -c in a heredoc-fed read loop fails" 1 "$rc"
check "and is named at its line" \
  "$sk/zz/bad.sh:3: sh -c inside a while-read loop over redirected input reads the loop's stdin; give it </dev/null" "$out"

shell_run eval '#!/usr/bin/env bash
while read -r row; do
  eval "$row"
done <<EOT
$rows
EOT'
check_rc "an unredirected eval in a heredoc-fed read loop fails" 1 "$rc"
check "and is named at its line" \
  "$sk/zz/bad.sh:3: eval inside a while-read loop over redirected input reads the loop's stdin; give it </dev/null" "$out"

shell_run eval-file '#!/usr/bin/env bash
while read -r row; do
  eval "$row"
done < "$f"'
check_rc "an unredirected eval in a file-fed read loop fails" 1 "$rc"
check "and is named at its line" \
  "$sk/zz/bad.sh:3: eval inside a while-read loop over redirected input reads the loop's stdin; give it </dev/null" "$out"

# A here-string inside a command substitution redirects the substitution's
# command, not the eval.
shell_run eval-subst '#!/usr/bin/env bash
while read -r row; do
  eval "$(jq -r .a <<<"$row")"
done <<EOT
$rows
EOT'
check_rc "an eval whose only < is a here-string inside a substitution fails" 1 "$rc"
check "and is named at its line" \
  "$sk/zz/bad.sh:3: eval inside a while-read loop over redirected input reads the loop's stdin; give it </dev/null" "$out"

shell_run fence '#!/usr/bin/env bash
grep -c '"'"'```'"'"' "$f"'
check_rc "a hand-rolled fence pattern fails" 1 "$rc"
check "and is named at its line" \
  "$sk/zz/bad.sh:2: a hand-rolled fence pattern; use SHIP_AWK_FENCE from _lib.sh" "$out"

# _lib.sh is exempt on the SHIP_AWK_FENCE definition alone.
shell_run lib-fence 'true'
lib=$sk/ship/scripts/_lib.sh
n=$(($(wc -l < "$lib") + 1))
printf 'x=%s\n' "'"'```'"'" >> "$lib"
rm "$sk/zz/bad.sh"
run "$inert" "$sk"
check_rc "a hand-rolled fence elsewhere in _lib.sh fails" 1 "$rc"
check "and is named at its line" \
  "$lib:$n: a hand-rolled fence pattern; use SHIP_AWK_FENCE from _lib.sh" "$out"

shell_run near-misses '#!/usr/bin/env bash
# curl -fsSL "$url" is prose, and so is a ``` fence in a comment
command -v curl >/dev/null || exit 2
_curl() { curl -fsSL --max-time 30 "$@"; }
curl -fsSL \
  --connect-timeout 30 --max-time 600 "$url"
while read -r row; do
  bash -c "cat" </dev/null
  bash -c "cat" < "$f"
  eval "$row" </dev/null
  bash -c "cat" <<< "$row"
done <<EOT
$rows
EOT
'
sed -i.bak '/^readonly SHIP_AWK_FENCE=/a\
  x = "```"' "$sk/ship/scripts/_lib.sh"
rm "$sk/ship/scripts/_lib.sh.bak"
run "$inert" "$sk"
check_rc "near misses, and a fence pattern inside the SHIP_AWK_FENCE definition, pass" 0 "$rc"
check "and print nothing" "" "$out"

# A tree the check cannot read is tooling, exit 2, never a pass: an unsearchable
# skills tree reported as clean is the silent pass the rule exists to prevent.
# Two ways it can be unreadable, and the second is the one the grep status owns.
run "$inert" "$fixture/absent"
check_rc "an absent skills tree is tooling, not a pass" 2 "$rc"

# Root reads through a 000 directory, so there the search would succeed and the
# case would assert the wrong thing.
if [ "$(id -u)" -ne 0 ]; then
  d=$(copy_skills grep-failure)
  chmod 000 "$d/ship"
  run "$inert" "$d"
  chmod 755 "$d/ship"
  check_rc "a search the tree refuses is tooling, not a pass" 2 "$rc"
else
  skipped "a search the tree refuses is tooling, not a pass"
fi

finish
