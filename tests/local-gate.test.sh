#!/usr/bin/env bash
# scripts/local-gate.sh: what it runs itself and what it leaves to CI, rather
# than what any one check does. Each fixture is a throwaway checkout carrying the
# real gate and a stub for every script it calls, so the subject is the gate's
# own wiring: in both lanes it runs `secrets` and `version-lines` (handed the
# base) and nothing else, and reports every check `check.sh full` would report,
# named from check.sh's configuration block, as `deferred-to-ci` unrun, so a
# failing check no longer fails it while a failing `secrets` or `version-lines`
# still does. The base cases sit apart: both this gate and the setup-skills
# template refuse a base that is not a commit, before any gate runs.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

fixture=$(mktemp -d); trap 'rm -rf "$fixture"' EXIT
git_() { git -c user.email=t@example.com -c user.name=t -C "$1" "${@:2}"; }

# gitleaks, which the `secrets` gate calls by name, exiting $SECRETS_RC.
mkdir -p "$fixture/bin"
printf '#!/usr/bin/env bash\nexit "${SECRETS_RC:-0}"\n' > "$fixture/bin/gitleaks"; chmod +x "$fixture/bin/gitleaks"
export PATH="$fixture/bin:$PATH"

# A checkout whose base commit carries the gate and its stubs: a check.sh that
# logs how it was called, prints $CHECK_OUT and carries a configuration block
# (`alpha` has typecheck and tests on `full`, `beta` affected tests alone), and
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
TURN_ROWS='a/|alpha|*.js|tsc|npm test|
b/|beta|*.mjs|||run {files}'
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
  # A warning, not a gate: its exit status, here a tooling 2, grades nothing.
  printf '#!/usr/bin/env bash\nexit 2\n' > "$d/scripts/glossary-warn.sh"
  # The same for the context report, which prints $CONTEXT_LINE when a case sets it.
  printf '#!/usr/bin/env bash\n[ -z "${CONTEXT_LINE-}" ] || echo "$CONTEXT_LINE"\nexit 2\n' > "$d/scripts/context-report.sh"
  chmod +x "$d/scripts/derived-copies-check.sh" "$d/scripts/contract-check.sh" "$d/scripts/check.sh" "$d/tests/run.sh" "$d/scripts/version-line-check.sh" "$d/scripts/glossary-warn.sh" "$d/scripts/context-report.sh"
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
FAILING='{"rung":"full","verdict":"fail","checks":{"tests":"fail","runner":"fail"}}'
DEFERRED='{"contract":"deferred-to-ci","derived-copies":"deferred-to-ci","piped":"deferred-to-ci","runner":"deferred-to-ci","secrets":"pass","tests":"deferred-to-ci","tests:alpha":"deferred-to-ci","typecheck:alpha":"deferred-to-ci","version-lines":"pass"}'
sorted='.gates |= (to_entries | sort_by(.key) | from_entries)'

d=$(repo full)
for lane in full small; do
  flags=(); [ "$lane" = full ] || flags=(--small docs/note.md)
  CHECK_OUT=$FAILING CHECK_RC=1 TESTS_RC=1 DERIVED_RC=1 gate "$d" "${flags[@]}"
  check_rc "$lane lane, every check.sh check failing: exit 0" 0 "$rc"
  check "$lane lane: each check check.sh full reports is deferred-to-ci, secrets and version-lines pass" \
    "{\"verdict\":\"pass\",\"base\":\"base\",\"lane\":\"$lane\",\"gates\":$DEFERRED}" "$(jq -c "$sorted" <<<"$out")"
  check "$lane lane: version-lines is the only script it runs, handed the base" "version-line-check.sh base" "$calls"

  SECRETS_RC=1 gate "$d" "${flags[@]}"
  check "$lane lane: a failing secrets fails the verdict" "1 fail fail" "$rc $(jq -r '"\(.verdict) \(.gates.secrets)"' <<<"$out")"

  VERSION_RC=1 gate "$d" "${flags[@]}"
  check_rc "$lane lane: a failing version-lines fails the verdict" 1 "$rc"
  check "$lane lane: version-lines failing is graded fail and its log reaches stderr" "fail version log line" \
    "$(jq -r '.gates["version-lines"]' <<<"$out") $err"
done

CONTEXT_LINE='total: 1 chars' gate "$d"
check_rc "the context report's tooling exit 2 grades nothing" 0 "$rc"
check "the context report's lines reach stderr" "total: 1 chars" "$err"
check "the report adds no gate status and leaves the verdict JSON as it was" \
  "{\"verdict\":\"pass\",\"base\":\"base\",\"lane\":\"full\",\"gates\":$DEFERRED}" "$(jq -c "$sorted" <<<"$out")"

d=$(repo no-runner)
sed -i.bak "s/^FULL_RUN=.*/FULL_RUN=''/" "$d/scripts/check.sh"
gate "$d"
check "a check.sh with no FULL_RUN defers no runner" "null pass" "$(jq -r '"\(.gates.runner) \(.verdict)"' <<<"$out")"

d=$(repo no-rows)
sed -i.bak '/setup-harness configuration/d' "$d/scripts/check.sh"
gate "$d"
check_rc "a check.sh with no configuration block is tooling" 2 "$rc"
check "a check.sh with no configuration block grades one check: unavailable" "unavailable" "$(jq -r '.gates.check' <<<"$out")"
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

# With no harness there is no bootstrap to name, so a missing scanner names the
# install command setup-skills filled. The PATH holds only what the gate calls,
# so a gitleaks on this machine cannot reach it.
nb=$fixture/noscan; mkdir -p "$nb"
for t in bash git jq mktemp rm tail; do ln -s "$(command -v "$t")" "$nb/$t"; done
sed 's/__DEPS__/true/; s/__RUNNER__/true/; s/__SCANNER_INSTALL__/sudo apt-get install -y gitleaks/' \
  skills/setup-skills/local-gate.sh > "$d/local-gate.sh"
out=$(cd "$d" && PATH=$nb bash local-gate.sh --base base 2>"$fixture/err"); rc=$?
check_rc "template, no scanner: exit 2" 2 "$rc"
check "template, no scanner: secrets is unavailable, the rest as before" \
  '{"verdict":"unavailable","base":"base","lane":"full","gates":{"secrets":"unavailable","deps":"pass","tests":"pass"}}' "$out"
check "template, no scanner: stderr names the filled install" \
  "secrets: gitleaks not on PATH; sudo apt-get install -y gitleaks installs it" "$(cat "$fixture/err")"

# The template grades its own gates: a failing gate is exit 1, an unavailable one
# exit 2, and fail wins over unavailable. Each case fills the gates block the way
# a consumer might: a placeholder with a failing command, or a `mark`. A gate
# written twice keeps the worse status, so a later write cannot mask a failure.
for c in "false|true|run deps  __DEPS__|1 fail fail|a failing gate" \
  "true|true|mark deps unavailable|2 unavailable unavailable|an unavailable gate" \
  "true|false|mark deps unavailable|1 fail unavailable|a failing gate beside an unavailable one" \
  "true|true|run deps false; mark deps deferred-to-ci|1 fail fail|a later mark over a failing gate" \
  "true|true|mark deps unavailable; run deps true|2 unavailable unavailable|a later pass over an unavailable gate"; do
  IFS='|' read -r deps runner line want name <<<"$c"
  sed "s/^run deps  __DEPS__.*/$line/; s/__DEPS__/$deps/; s/__RUNNER__/$runner/" skills/setup-skills/local-gate.sh > "$d/local-gate.sh"
  out=$(cd "$d" && bash local-gate.sh --base base 2>/dev/null); rc=$?
  check "template, $name: exit, verdict and the deps gate" "$want" "$rc $(jq -r '"\(.verdict) \(.gates.deps)"' <<<"$out")"
done

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
