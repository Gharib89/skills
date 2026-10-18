#!/usr/bin/env bash
# scripts/contract-check.sh checks 11 to 16: usage line against header, flag
# guards, a failing host, prose invocations and the shell habits grep holds.
# Split from tests/contract-gate.test.sh; the shared fixtures are in
# tests/contract-gate-lib.sh.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
source tests/contract-gate-lib.sh

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
[ "${1:-}" = --help ] && { printf '%s\nstdout: {number}\n' "$usage"; exit 0; }
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
# stdout: {number}
# exit: 0
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

# A wait mechanic retries a failing host once per --interval, so check 13 passes
# the shortest one: at ci-wait's and poll-pr's defaults the check slept 100 s.
d=$(copy_mechanics host-interval)
cat > "$d/read-issue.sh" <<'EOF'
#!/usr/bin/env bash
# stdout: {number}
# exit: 0
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh" || { printf '{"error":"cannot source _lib.sh"}\n'; exit 2; }
usage='usage: read-issue <issue> [--interval <s>]'
ship_help "$usage" "$@"
ship_args "$usage" issue "$@"
ship_load_host
[ -z "${SHIP_FAKE:-}" ] || printf '%s\n' "$*" > "$ARGS_LOG"
ship_fail "cannot read issue $1"
EOF
ARGS_LOG=$fixture/host-interval.args runs "$d"
check "a mechanic that takes --interval is driven at --interval 1" \
  '1 --interval 1' "$(cat "$fixture/host-interval.args" 2>/dev/null)"

# A tree that cannot drive the check is a failure, never a pass: a checker copy
# whose Host fake lists no host_* function, and one whose root lacks the profile
# the throwaway checkout is seeded from.
stage_root() { # <case> <fake-sed>: a root with the checker and a Host fake, no profile
  local r="$fixture/$1"
  mkdir -p "$r/scripts" "$r/tests"
  cp -r scripts/contract-check.sh scripts/contract-check.d "$r/scripts/" && sed "$2" tests/host-fake.sh > "$r/tests/host-fake.sh" || exit 2
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

# 15. Four shell rules grep can hold. One fixture per violation, each asserting
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

# A pipe into a quiet grep in a script that sets pipefail: grep -q exits at its
# first match, the writer dies of SIGPIPE, and the pipeline reads as no match
# (#758). Each spelling of the quiet flag, and the continued-line form, fails.
# The check scans this directory too, so a fixture writes PIPE for the pipe and
# `pipes` turns it back; a literal one here would be a violation of its own.
pipes() { printf '%s' "${1//PIPE/|}"; }
pipe_msg='a pipe into a quiet grep under pipefail fails open on SIGPIPE; read the writer'"'"'s output into a variable and use grep -q PATTERN <<<"$var"'
pipe_case() { # <name> <line>: a pipefail script whose line 3 is <line>, which fails
  shell_run "pipe-$1" "$(pipes "#!/usr/bin/env bash
set -uo pipefail
$2")"
  check_rc "a pipe into a quiet grep ($1) under pipefail fails" 1 "$rc"
  check "and is named at its line" "$sk/zz/bad.sh:3: $pipe_msg" "$out"
}
pipe_case short 'printf x PIPE grep -q x'
pipe_case bundled 'printf x PIPE grep -Eq x'
pipe_case reordered 'printf x PIPE grep -qE x'
pipe_case apart 'printf x PIPE grep -E -q x'
pipe_case after-pattern 'printf x PIPE grep -e x -q'
pipe_case long 'printf x PIPE grep --quiet x'
pipe_case silent 'printf x PIPE grep --silent x'
pipe_case egrep 'printf x PIPE egrep -q x'
pipe_case stderr-too 'printf x PIPE& grep -q x'
pipe_case after-and 'true && printf x PIPE grep -q x'
pipe_case env-assignment 'printf x PIPE LC_ALL=C grep -q x'
pipe_case env-command 'printf x PIPE env LC_ALL=C grep -q x'
pipe_case command-prefix 'printf x PIPE command grep -q x'
pipe_case grep-path 'printf x PIPE /usr/bin/grep -q x'
# A trailing pipe or a backslash continues the command; the line named is its first.
pipe_case trailing-pipe 'printf x PIPE
  grep -q x'
pipe_case trailing-pipe-stderr 'printf x PIPE&
  grep -q x'
pipe_case backslash 'printf x PIPE \
  grep -q x'

# Its here-string form passes, and so does everything that only looks like it.
shell_run pipe-grep-near-misses "$(pipes '#!/usr/bin/env bash
set -uo pipefail
# printf x PIPE grep -q x is prose
grep -q x <<<"$v"
printf x PIPE grep x
printf x PIPE grep -c q
cmd PIPEPIPE grep -q x "$f"
grep -q x "$f"
printf x PIPE grep x && grep -q y "$f"
printf x PIPE grep -e x -- -q
printf x PIPE LC_ALL=C grep x
printf x PIPE env LC_ALL=C sort')"
check_rc "a here-string grep -q and near misses pass under pipefail" 0 "$rc"
check "and print nothing" "" "$out"

# Without pipefail the pipeline status is grep's own, so the shape is harmless.
shell_run pipe-grep-no-pipefail "$(pipes '#!/usr/bin/env bash
printf x PIPE grep -q x')"
check_rc "a pipe into grep -q in a script that sets no pipefail passes" 0 "$rc"

# An <extra-dir> is scanned like the skills tree: the repo's own scripts, tests
# and hooks set pipefail too.
d=$fixture/extra; mkdir -p "$d"
pipes '#!/usr/bin/env bash
set -uo pipefail
printf x PIPE grep -q x
' > "$d/gate.sh"
out=$(bash scripts/contract-check.sh "$inert" skills "$d" 2>/dev/null); rc=$?
check_rc "a pipe into grep -q under an extra directory fails" 1 "$rc"
check "and is named at its line" "$d/gate.sh:3: $pipe_msg" "$out"
out=$(bash scripts/contract-check.sh "$inert" skills "$fixture/absent" 2>/dev/null); rc=$?
check_rc "an absent extra directory is tooling, not a pass" 2 "$rc"
# An awk that fails on the scan leaves the file looking clean, so it is tooling
# too: a stub awk refuses the check-16 program (the one naming --silent).
real_awk=$(command -v awk)
mkdir -p "$fixture/bin"
printf '#!/bin/sh\ncase "$*" in *--silent*) exit 2 ;; esac\nexec %s "$@"\n' "$real_awk" > "$fixture/bin/awk"
chmod +x "$fixture/bin/awk"
out=$(PATH="$fixture/bin:$PATH" bash scripts/contract-check.sh "$inert" skills "$d" 2>/dev/null); rc=$?
check_rc "a scan awk fails on is tooling, not a pass" 2 "$rc"
if [ "$(id -u)" -ne 0 ]; then
  mkdir -p "$d/sealed"; chmod 000 "$d/sealed"
  out=$(bash scripts/contract-check.sh "$inert" skills "$d" 2>/dev/null); rc=$?
  chmod 755 "$d/sealed"
  check_rc "an extra directory the search cannot read is tooling, not a pass" 2 "$rc"
else
  skipped "an extra directory the search cannot read is tooling, not a pass"
fi

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
