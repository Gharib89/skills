#!/usr/bin/env bash
# scripts/local-gate.sh: what it adds to `check.sh full` and how it grades, rather
# than what any one check does. Each fixture is a throwaway checkout carrying the
# real gate and a stub for every script it calls, so the subject is the gate's
# own wiring: check.sh runs once, as `full`, in the full lane; the small lane
# never runs it and runs the `FULL_ROWS` checks it lists instead; its checks
# become gates by their own names, with no gate of the repo's own duplicating
# one; `version-lines` is handed the base; `secrets` is in every lane. The base cases sit apart: both this gate and the setup-skills
# template refuse a base that is not a commit, before any gate runs. How the
# full lane grades check.sh's answer (a failing check, exit 2 or 3, output
# outside its contract) is the harness template's mapping with check.sh's path
# filled in, and tests/setup-skills-harness-gate.test.sh holds it there.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

fixture=$(mktemp -d); trap 'rm -rf "$fixture"' EXIT
git_() { git -c user.email=t@example.com -c user.name=t -C "$1" "${@:2}"; }

# gitleaks, which the `secrets` gate calls by name, answering clean.
mkdir -p "$fixture/bin"
printf '#!/usr/bin/env bash\nexit 0\n' > "$fixture/bin/gitleaks"; chmod +x "$fixture/bin/gitleaks"
export PATH="$fixture/bin:$PATH"

# A checkout whose base commit carries the gate and its stubs: a check.sh that
# logs how it was called, prints $CHECK_OUT and carries a `FULL_ROWS` block, and
# the scripts those rows and the gate call, each logging its arguments and
# exiting with $TESTS_RC, $DERIVED_RC or $VERSION_RC; prints its path.
repo() {
  local d="$fixture/$1"
  mkdir -p "$d/scripts" "$d/tests" || return 1
  cp scripts/local-gate.sh "$d/scripts/" || return 1
  cat > "$d/scripts/check.sh" <<'STUB'
#!/usr/bin/env bash
echo "check.sh $* deadline=${CHECK_DEADLINE-unset}" >> "$CALLS"
printf '%s' "$CHECK_OUT"
exit "${CHECK_RC:-0}"
# >>> setup-harness configuration
FULL_RUN='prek run --all-files'
LOCAL_ONLY="${STUB_LOCAL_ONLY-}"
FULL_ROWS='tests|tests/run.sh
derived-copies|scripts/derived-copies-check.sh
contract|scripts/contract-check.sh a && scripts/contract-check.sh b
piped|echo "piped row" | cat >> "$CALLS"'
# <<< setup-harness configuration
STUB
  printf '#!/usr/bin/env bash\necho "run.sh${*:+ $*}" >> "$CALLS"\ncat >/dev/null\necho tests log line\nexit "${TESTS_RC:-0}"\n' > "$d/tests/run.sh"
  printf '#!/usr/bin/env bash\necho "version-line-check.sh $*" >> "$CALLS"\necho version log line\nexit "${VERSION_RC:-0}"\n' > "$d/scripts/version-line-check.sh"
  printf '#!/usr/bin/env bash\necho "derived-copies-check.sh" >> "$CALLS"\necho derived log line\nexit "${DERIVED_RC:-0}"\n' > "$d/scripts/derived-copies-check.sh"
  printf '#!/usr/bin/env bash\necho "contract-check.sh $*" >> "$CALLS"\n' > "$d/scripts/contract-check.sh"
  chmod +x "$d/scripts/derived-copies-check.sh" "$d/scripts/contract-check.sh" "$d/scripts/check.sh" "$d/tests/run.sh" "$d/scripts/version-line-check.sh"
  git_ "$d" init -q && git_ "$d" add -A && git_ "$d" commit -qm base && git_ "$d" tag base || return 1
  printf '%s' "$d"
}

# <dir> [gate flags]: run the gate once, leaving `rc`, `out` (stdout), `err` and
# `calls`.
gate() {
  local d=$1; shift
  : > "$d/calls"
  out=$(cd "$d" && CALLS="$d/calls" CHECK_DEADLINE=99 bash scripts/local-gate.sh --base base "$@" 2>"$d/err"); rc=$?
  err=$(cat "$d/err"); calls=$(cat "$d/calls")
}
ALL_GREEN='{"rung":"full","verdict":"pass","checks":{"tests":"pass","derived-copies":"pass","runner":"pass"}}'

d=$(repo full)
CHECK_OUT=$ALL_GREEN gate "$d"
check_rc "full lane, all green: exit 0" 0 "$rc"
check "the gates are check.sh's checks plus secrets and version-lines, each once" \
  '{"verdict":"pass","base":"base","lane":"full","gates":["derived-copies","runner","secrets","tests","version-lines"]}' \
  "$(jq -c '.gates |= keys' <<<"$out")"
check "check.sh runs once, as full, with no CHECK_DEADLINE, and the suite is check.sh's alone" \
  "check.sh full deadline=unset
version-line-check.sh base" "$calls"

CHECK_OUT=$ALL_GREEN VERSION_RC=1 gate "$d"
check_rc "version-lines failing fails the verdict" 1 "$rc"
check "version-lines failing is graded fail and its log reaches stderr" "fail version log line" \
  "$(jq -r '.gates["version-lines"]' <<<"$out") $err"

CHECK_OUT=$ALL_GREEN gate "$d" --small docs/note.md
check_rc "--small, all green: exit 0" 0 "$rc"
check "--small runs check.sh's FULL_ROWS by name, never its runner" '{"lane":"small","gates":["contract","derived-copies","piped","secrets","tests","version-lines"]}' \
  "$(jq -c '{lane, gates: (.gates | keys)}' <<<"$out")"
check "--small: the calls are the rows in order, a row's && and | commands in full, then version-lines" "run.sh
derived-copies-check.sh
contract-check.sh a
contract-check.sh b
piped row
version-line-check.sh base" "$calls"

TESTS_RC=1 gate "$d" --small docs/note.md
check_rc "--small, a failing suite fails the verdict" 1 "$rc"
check "--small, a failing suite: its log tail reaches stderr" "tests log line" "$err"

DERIVED_RC=1 gate "$d" --small docs/note.md
check "--small, derived copies that differ fail the verdict" "fail fail" "$(jq -r '"\(.verdict) \(.gates["derived-copies"])"' <<<"$out")"

DERIVED_RC=127 gate "$d" --small docs/note.md
check_rc "--small, a row whose tool is missing (127) is tooling" 2 "$rc"
check "--small, a row whose tool is missing (127) grades unavailable" "unavailable" "$(jq -r '.gates["derived-copies"]' <<<"$out")"

STUB_LOCAL_ONLY=contract CLAUDE_CODE_REMOTE=true gate "$d" --small docs/note.md
check "--small, a LOCAL_ONLY row in a cloud session is skipped and read as pass" "pass 4" \
  "$(jq -r '.gates.contract' <<<"$out") $(grep -c . <<<"$calls")"
STUB_LOCAL_ONLY=contract gate "$d" --small docs/note.md
check "--small, a LOCAL_ONLY row outside a cloud session still runs" "6" "$(grep -c . <<<"$calls")"

# A row runs under pipefail, as check.sh runs it: a failing head of a pipe fails
# the row, where a bare `bash -c` would read the last command's status alone.
d=$(repo pipefail)
sed -i.bak "s/^piped|.*/piped|false | cat'/" "$d/scripts/check.sh"
gate "$d" --small docs/note.md
check "--small, a row failing at the head of a pipe fails (pipefail)" "fail" "$(jq -r '.gates.piped' <<<"$out")"

d=$(repo no-rows)
sed -i.bak '/setup-harness configuration/d' "$d/scripts/check.sh"
gate "$d" --small docs/note.md
check_rc "--small, a check.sh with no configuration block is tooling" 2 "$rc"
check "--small, a check.sh with no configuration block grades one check: unavailable" "unavailable" "$(jq -r '.gates.check' <<<"$out")"
d=$fixture/full

# A base that names no commit is tooling, before any gate runs: gitleaks given a
# range it cannot resolve scans nothing and still exits 0, so `secrets` would pass.
gate "$d" --base no-such-ref
check_rc "a base that is not a commit: exit 2" 2 "$rc"
check "a base that is not a commit: the error names it, and no gate ran" "true true" \
  "$(jq -r '.error | contains("no-such-ref")' <<<"$out") $([ -z "$calls" ] && echo true || echo false)"

# The setup-skills template holds the same line: its placeholders stubbed, a
# base that is not a commit stops it as tooling and a real one still passes.
d=$fixture/template; mkdir -p "$d"
sed 's/__DEPS__/true/; s/__RUNNER__/true/' skills/setup-skills/local-gate.sh > "$d/local-gate.sh"
git_ "$d" init -q && git_ "$d" add -A && git_ "$d" commit -qm base && git_ "$d" tag base
out=$(cd "$d" && bash local-gate.sh --base no-such-ref 2>/dev/null); rc=$?
check_rc "template, a base that is not a commit: exit 2" 2 "$rc"
check "template, a base that is not a commit: the error names it" "true" "$(jq -r '.error | contains("no-such-ref")' <<<"$out")"
out=$(cd "$d" && bash local-gate.sh --base base 2>/dev/null); rc=$?
check_rc "template, a real base: exit 0" 0 "$rc"
check "template, a real base: secrets passes" "pass" "$(jq -r '.gates.secrets' <<<"$out")"

# `--help` and `-h` answer the header's usage line, exit 0, before any check
# runs, in this repo's gate and in both templates setup-skills lands.
for f in scripts/local-gate.sh skills/setup-skills/local-gate.sh skills/setup-skills/local-gate-harness.sh; do
  for flag in --help -h; do
    out=$(cd "$fixture" && bash "$OLDPWD/$f" "$flag" 2>&1); rc=$?
    check_rc "$f $flag: exit 0" 0 "$rc"
    check "$f $flag: the usage line, and nothing else" \
      "usage: scripts/local-gate.sh [--small <node>] [--base <ref>]" "$out"
  done
done

finish
