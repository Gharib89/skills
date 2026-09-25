#!/usr/bin/env bash
# scripts/local-gate.sh: how it runs its gates, rather than what any one gate
# checks. Each fixture is a throwaway checkout carrying the real gate and a stub
# for every script it calls, so the subject is the gate's own scheduling and
# grading: `tests` and `shellcheck` run concurrently, each gate's log tail is its
# own, and `--small` leaves `shellcheck` out when the diff touches no `*.sh`.
# The stubs prove concurrency by rendezvous: under `AWAIT`, each of the two
# waits up to 5 s for the other to start and fails if it never does, which is
# what a gate running them one after another produces.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

fixture=$(mktemp -d); trap 'rm -rf "$fixture"' EXIT
git_() { git -c user.email=t@example.com -c user.name=t -C "$1" "${@:2}"; }

# gitleaks, which the `secrets` gate calls by name, answering clean.
mkdir -p "$fixture/bin"
printf '#!/usr/bin/env bash\nexit 0\n' > "$fixture/bin/gitleaks"; chmod +x "$fixture/bin/gitleaks"
export PATH="$fixture/bin:$PATH"

# <path> <name> <peer> <rc-var>: a check that logs its name, marks that it
# started, under AWAIT waits for <peer> to start, and exits with $<rc-var>.
# Under HANG it forks a long sleep and waits on it, recording both pids, so the
# interrupt case sees a grandchild of the gate the way a real test file is one.
stub() {
  cat > "$1" <<EOF
#!/usr/bin/env bash
echo "$2 log line"
: > "\$MARKS/$2"
[ -z "\${HANG:-}" ] || { sleep 30 & echo \$! > "\$MARKS/$2.child.pid"; echo \$\$ > "\$MARKS/$2.pid"; wait; }
if [ -n "\${AWAIT:-}" ]; then
  for _ in \$(seq 50); do [ -e "\$MARKS/$3" ] && break; sleep 0.1; done
  [ -e "\$MARKS/$3" ] || { echo "$2 ran without $3"; exit 1; }
fi
exit "\${$4:-0}"
EOF
  chmod +x "$1"
}

# <case> <changed-file>: a checkout whose base commit carries the gate and its
# stubs, with <changed-file> committed on top; prints its path.
repo() {
  local d="$fixture/$1" s f
  mkdir -p "$d/scripts" "$d/tests" || return 1
  for s in ship cloud-ship setup-skills; do mkdir -p "$d/skills/$s" "$d/.claude/skills/$s"; done
  cp scripts/local-gate.sh "$d/scripts/" || return 1
  for f in version-line house-style prose-budget stray-file contract profile-schema; do
    printf '#!/usr/bin/env bash\nexit 0\n' > "$d/scripts/$f-check.sh"; chmod +x "$d/scripts/$f-check.sh"
  done
  stub "$d/tests/run.sh" tests shellcheck TESTS_RC
  stub "$d/scripts/shellcheck-check.sh" shellcheck tests SHELLCHECK_RC
  echo '{"skills":{"ship":{},"cloud-ship":{},"setup-skills":{}}}' > "$d/skills-lock.json"
  git_ "$d" init -q && git_ "$d" add -A && git_ "$d" commit -qm base && git_ "$d" tag base || return 1
  mkdir -p "$d/$(dirname "$2")"; echo change > "$d/$2"
  git_ "$d" add -A && git_ "$d" commit -qm change || return 1
  printf '%s' "$d"
}

# <dir> [gate flags]: run the gate once, leaving `rc`, `out` (stdout) and `err`.
gate() {
  local d=$1; shift
  rm -rf "$d/marks"; mkdir "$d/marks"
  out=$(cd "$d" && MARKS="$d/marks" bash scripts/local-gate.sh --base base "$@" 2>"$d/err"); rc=$?
  err=$(cat "$d/err")
}

d=$(repo full docs/note.md)
gate "$d"
check_rc "full lane, all green: exit 0" 0 "$rc"
check "the verdict shape is unchanged" \
  '{"verdict":"pass","base":"base","lane":"full","gates":["contract","derived-copies","house-style","prose-budget","secrets","shellcheck","stray-files","tests","version-lines"]}' \
  "$(jq -c '.gates |= keys' <<<"$out")"

AWAIT=1 gate "$d"
check "tests and shellcheck run concurrently" '{"tests":"pass","shellcheck":"pass"}' \
  "$(jq -c '{tests: .gates.tests, shellcheck: .gates.shellcheck}' <<<"$out")"

TESTS_RC=1 gate "$d"
check_rc "a failing tests gate fails the verdict" 1 "$rc"
check "the failing gate is graded fail" "fail pass" "$(jq -r '"\(.gates.tests) \(.gates.shellcheck)"' <<<"$out")"
check "stderr carries the failing gate's own log" "tests log line" "$err"

SHELLCHECK_RC=2 gate "$d"
check_rc "shellcheck's exit 2 is tooling" 2 "$rc"
check "shellcheck's exit 2 grades unavailable" "unavailable unavailable" "$(jq -r '"\(.verdict) \(.gates.shellcheck)"' <<<"$out")"

gate "$d" --small docs/note.md
check "--small, no *.sh in the diff: shellcheck is left out" "small false pass" \
  "$(jq -r '"\(.lane) \(.gates | has("shellcheck")) \(.gates.secrets)"' <<<"$out")"
check "--small, no *.sh in the diff: shellcheck never ran" "absent" "$([ -e "$d/marks/shellcheck" ] && echo ran || echo absent)"

d=$(repo small-sh skills/ship/scripts/x.sh)
gate "$d" --small skills/ship/scripts/x.sh
check "--small, a *.sh in the diff: shellcheck runs" "pass" "$(jq -r '.gates.shellcheck' <<<"$out")"

# An interrupted gate stops its background gates rather than orphaning them.
rm -rf "$d/marks"; mkdir "$d/marks"
(cd "$d" && HANG=1 MARKS="$d/marks" exec bash scripts/local-gate.sh --base base >/dev/null 2>&1) &
gpid=$!
for _ in $(seq 50); do [ -s "$d/marks/tests.pid" ] && [ -s "$d/marks/shellcheck.pid" ] && break; sleep 0.1; done
kill -TERM "$gpid"; wait "$gpid" 2>/dev/null
left=""
for g in tests tests.child shellcheck shellcheck.child; do
  p=$(cat "$d/marks/$g.pid" 2>/dev/null) || { left+=" $g(never started)"; continue; }
  for _ in $(seq 20); do kill -0 "$p" 2>/dev/null || break; sleep 0.1; done
  if kill -0 "$p" 2>/dev/null; then left+=" $g"; kill "$p"; fi
done
check "a killed gate leaves no background gate or its child running" "" "$left"

# git C-quotes a path carrying a non-ASCII byte, so a name-matching skip misses it.
d=$(repo small-quoted "skills/caf$(printf '\303\251').sh")
gate "$d" --small docs/note.md
check "--small, a C-quoted *.sh in the diff: shellcheck runs" "pass" "$(jq -r '.gates.shellcheck' <<<"$out")"

# A diff git cannot compute fails closed: shellcheck runs rather than being skipped.
gate "$d" --small docs/note.md --base no-such-ref
check "--small, a base git cannot diff: shellcheck runs" "true" "$(jq -r '.gates | has("shellcheck")' <<<"$out")"

finish
