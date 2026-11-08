#!/usr/bin/env bash
# Fixture shared by tests/live-run-ship.test.sh and tests/live-run-paths.test.sh, sourced
# after tests/lib.sh from the repo root: the fake gh, claude and npx, the seed, and drive.
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
mkdir "$T/bin"
export LIVE_STUB=$T/stub

cat > "$T/bin/gh" <<'GH'
#!/usr/bin/env bash
# The fixture's host: issues/<n>.json, pulls.json, branches (one per line).
S=$LIVE_STUB
if [ "$1 $2" = "repo clone" ]; then
  [ ! -e "$S/clone-fails" ] || exit 1
  d=$4
  git init -q "$d" && mkdir -p "$d/.github" && cp -a "$S/seed/." "$d/"
  printf 'Closes #\n\n## Why\n\n## Attribution\n' > "$d/.github/pull_request_template.md"
  git -C "$d" add -A && git -C "$d" -c user.name=t -c user.email=t@t commit -qm seed
  git -C "$d" tag seed && git -C "$d" update-ref refs/remotes/origin/main HEAD
  git init -q --bare "$S/origin.git" && git -C "$d" remote add origin "$S/origin.git"
  exit 0
fi
shift # api
method=GET expr=. path="" body="" title="" labels=""
while [ $# -gt 0 ]; do
  case $1 in
    --paginate) ;;
    -X) method=$2; shift ;;
    --jq) expr=$2; shift ;;
    -f) case $2 in body=*) body=${2#body=} ;; title=*) title=${2#title=} ;; 'labels[]='*) labels=${2#labels[]=} ;; esac
        [ "$method" != GET ] || method=POST; shift ;;
    *) path=${1#repos/*/*/}; path=${path%%\?*} ;;
  esac
  shift
done
out() { jq -r "$expr"; }
case "$method $path" in
  "GET pulls") jq '[.[] | select(.state == "open")]' "$S/pulls.json" | out ;;
  "PATCH pulls/"*) n=${path#pulls/}
    # One close refused, then the host answers again.
    [ ! -e "$S/pr-close-fails" ] || { rm "$S/pr-close-fails"; exit 1; }
    jq --argjson n "$n" 'map(if .number == $n then .state = "closed" else . end)' "$S/pulls.json" > "$S/p" \
      && mv "$S/p" "$S/pulls.json" ;;
  "GET branches") jq -R '{name: .}' "$S/branches" | jq -s . | out ;;
  "DELETE git/refs/heads/"*) b=${path#git/refs/heads/}
    grep -vxF "${b//%2F//}" "$S/branches" > "$S/b"; mv "$S/b" "$S/branches" ;;
  "POST issues") n=$(( $(ls "$S/issues" | wc -l) + 1 ))
    jq -n --argjson n "$n" --arg t "$title" --arg b "$body" --arg l "$labels" \
      '{number: $n, title: $t, body: $b, labels: [{name: $l}], state: "open", assignees: []}' > "$S/issues/$n.json"
    out < "$S/issues/$n.json" ;;
  "GET issues") jq -s '[.[] | select(.state == "open")] | sort_by(-.number)' "$S"/issues/*.json | out ;;
  "GET issues/"*) out < "$S/issues/${path#issues/}.json" ;;
  "PATCH issues/"*) f=$S/issues/${path#issues/}.json
    jq '.state = "closed"' "$f" > "$S/i" && mv "$S/i" "$f" ;;
  *) echo "fake gh: no route for $method $path" >&2; exit 1 ;;
esac
GH

cat > "$T/bin/claude" <<'CLAUDE'
#!/usr/bin/env bash
# Plays the next line of $LIVE_STUB/script against the issue in its prompt.
S=$LIVE_STUB
printf '%s\n' "$*" >> "$S/claude.log"
# What Ship's in-place isolation meets: the tree's status, untracked files shown
# whatever the config says, then find-docs' ref.
{ git status --porcelain --untracked-files=normal; jq -r '.skills["find-docs"].ref' skills-lock.json; } > "$S/clone"
n=${*: -1}; n=${n#/ship }; n=${n%% *}
play=$(head -n 1 "$S/script"); tail -n +2 "$S/script" > "$S/s"; mv "$S/s" "$S/script"
run=$XDG_STATE_HOME/ship/key/ship-$n/run.md
mkdir -p "${run%/*}"
phases() { # <last closed phase> <open phase>
  local p
  echo "# ship run · $n"; echo
  for p in 0 1 2 3 4 5 6 7 8 9; do
    if [ "$p" -le "$1" ]; then echo "- [x] $p · Phase: x (10:0$p→10:0$p)"
    elif [ "$p" -eq "$2" ]; then echo "- [ ] $p · Phase: x in_progress (10:0$p→)"
    else echo "- [ ] $p · Phase: x"; fi
  done
}
push_pr() { # <number> <branch> <calc.sh, empty for none> <body>: push the branch as refs/pull/<number>/head, open the PR
  git worktree add -q -b "$2" "$S/wt-$1" || return
  [ -z "$3" ] || { echo "$3" > "$S/wt-$1/calc.sh" && git -C "$S/wt-$1" add calc.sh; }
  git -C "$S/wt-$1" -c user.name=t -c user.email=t@t commit -q --allow-empty -m pr \
    && { [ -n "${UNPUSHED:-}" ] || git -C "$S/wt-$1" push -q origin "HEAD:refs/pull/$1/head"; }
  echo "$2" >> "$S/branches"
  jq --argjson m "$1" --arg b "$2" --arg body "$4" '. + [{number: $m, state: "open", head: {ref: $b}, body: $body}]' \
    "$S/pulls.json" > "$S/p" && mv "$S/p" "$S/pulls.json"
}
ship_pr() { # [<calc.sh>]: claim, open a PR closing the issue whose outline names calc.sh's sub()
  local f=$S/issues/$n.json
  jq '.assignees = [{login: "agent"}]' "$f" > "$S/i" && mv "$S/i" "$f"
  push_pr $(( 100 + n )) "feat/x-$n" "${1-sub() { :; \}}" \
    "Closes #$n"$'\n\n## Why\n\nx\n\n## Change outline\n\n```diff\n+calc.sh\n+  sub()\n```\n\n## Attribution\n\nf\n'
}
reply="Done."
case $play in
  happy) phases 8 9 > "$run"; ship_pr ;;
  happy-unpushed) phases 8 9 > "$run"; UNPUSHED=1 ship_pr ;;
  # A second run PR, listed first, whose head has the sub() the closing PR's head lacks.
  happy-decoy) phases 8 9 > "$run"; push_pr $(( 200 + n )) "fix/y-$n" 'sub() { :; }' x; ship_pr '' ;;
  happy-skips-gate) phases 4 5 > "$run"; ship_pr ;;
  # The seeded-defect path: criterion 1 met on the unrelated proof, or held.
  defect-accepts) { phases 8 9; echo 'Criterion 1: met: stat README.md exits 0'; } > "$run"; ship_pr ;;
  defect-holds) { phases 8 9; echo 'Criterion 1: not met: stat README.md says nothing of mul'; } > "$run"; ship_pr ;;
  # The red path: a stop past the tests, or a green run toward the merge gate.
  red-stops) phases 4 5 > "$run"; reply='Stopped `red-after-retry`: test.sh fails after the change.' ;;
  red-merges) phases 8 9 > "$run"; ship_pr ;;
  ambiguous) rmdir "${run%/*}"; reply='Stopped `ambiguous` on the issue, with no claim taken.' ;;
  ambiguous-claims) phases 1 2 > "$run"; ship_pr ;;
  budget) echo '{"subtype": "error_max_budget_usd", "is_error": true, "total_cost_usd": 2.6}'; exit 1 ;;
  slow) sleep 5 ;;
  auth) echo 'Invalid API key' >&2; exit 1 ;;
  killed) kill -9 $$ ;;
  garbled) echo 'not json'; exit 0 ;;
  silent) exit 0 ;;
  no-reply) reply="" ;;
esac
# STUB_USAGE=1: the usage fields a real result carries, two models (a parent
# and a child agent's); unset, a result without them.
# USAGE_ONCE=1: only the first run reports it.
if [ -n "${STUB_USAGE:-}" ] && { [ -z "${USAGE_ONCE:-}" ] || [ ! -e "$S/usage-given" ]; }; then
  touch "$S/usage-given"
  jq -cn --arg r "$reply" '{subtype: "success", result: $r, total_cost_usd: 1, session_id: "s", num_turns: 3,
    subagent_stats: {spawned: 1},
    modelUsage: {a: {inputTokens: 10, outputTokens: 20, cacheReadInputTokens: 30, cacheCreationInputTokens: 40},
                 b: {inputTokens: 1, outputTokens: 2, cacheReadInputTokens: 3, cacheCreationInputTokens: 0}}}
    | if env.USAGE_PARTIAL then del(.modelUsage.b.cacheCreationInputTokens) else . end
    | if env.USAGE_MALFORMED then .modelUsage.b = 3 else . end'
else
  jq -cn --arg r "$reply" '{subtype: "success", result: $r, total_cost_usd: 1, session_id: "s"}'
fi
CLAUDE

cat > "$T/bin/npx" <<'NPX'
#!/usr/bin/env bash
# `skills add <source> --skill <k> ...`: logs its arguments, then installs <k>
# into the working directory and records <source>'s `#<ref>` in the lock; a
# skill named in $LIVE_STUB/npx-fails fails instead, and one in
# $LIVE_STUB/npx-noop exits 0 having installed nothing; with
# $LIVE_STUB/npx-locks it leaves the index locked, as a crashed git would.
S=$LIVE_STUB
printf '%s\n' "$*" >> "$S/npx.log"
[ "$1" != -y ] || shift
src=$3 k=$5
! grep -qxF "$k" "$S/npx-fails" 2>/dev/null || { echo "install of $k failed"; exit 1; }
! grep -qxF "$k" "$S/npx-noop" 2>/dev/null || exit 0
mkdir -p ".claude/skills/$k" && echo "$src" > ".claude/skills/$k/SKILL.md"
jq --arg k "$k" --arg r "${src##*#}" '.skills[$k] = {ref: $r}' skills-lock.json > lock && mv lock skills-lock.json
[ ! -e "$S/npx-locks" ] || touch .git/index.lock
NPX
chmod +x "$T/bin/"*
export PATH="$T/bin:$PATH"

# The seed carries every skill on ship's composes line at its pin, but OFF_PIN,
# which its lock records at another ref, and MISSING, which it lacks.
read -ra composes <<<"$(sed -n 's/^  composes: //p' skills/ship/SKILL.md)"
off_ref=522c4db000000000000000000000000000000000
seed() {
  local entry k ref lock='{"version": 1, "skills": {}}'
  for entry in "${composes[@]}"; do
    k=${entry##*:} ref=${entry%:*}; ref=${ref##*#}
    [ "$k" != "${MISSING:-}" ] || continue
    [ "$k" != "${OFF_PIN:-}" ] || ref=$off_ref
    mkdir -p "$LIVE_STUB/seed/.claude/skills/$k" && echo seed > "$LIVE_STUB/seed/.claude/skills/$k/SKILL.md"
    lock=$(jq --arg k "$k" --arg r "$ref" '.skills[$k] = {ref: $r}' <<<"$lock")
  done
  printf '%s\n' "$lock" > "$LIVE_STUB/seed/skills-lock.json"
}

# <script lines...>: one driver run on a fresh fixture; its JSON line with the
# per-run fields dropped, then its exit code.
drive() {
  rm -rf "$LIVE_STUB"; mkdir -p "$LIVE_STUB/issues"; seed
  echo '[]' > "$LIVE_STUB/pulls.json"; : > "$LIVE_STUB/branches"
  printf '%s\n' "$@" > "$LIVE_STUB/script"
  [ -z "${CLONE_FAILS:-}" ] || touch "$LIVE_STUB/clone-fails"
  [ -z "${PR_CLOSE_FAILS:-}" ] || touch "$LIVE_STUB/pr-close-fails"
  [ -z "${NPX_FAILS:-}" ] || echo "$NPX_FAILS" > "$LIVE_STUB/npx-fails"
  [ -z "${NPX_NOOP:-}" ] || echo "$NPX_NOOP" > "$LIVE_STUB/npx-noop"
  [ -z "${NPX_LOCKS:-}" ] || touch "$LIVE_STUB/npx-locks"
  # The default paths of these cases are happy and ambiguous; PATHS names others,
  # DEFAULT_PATHS leaves the script's own default.
  if [ -n "${DEFAULT_PATHS:-}" ]; then unset LIVE_RUN_PATHS; else export LIVE_RUN_PATHS=${PATHS:-happy,ambiguous}; fi
  bash scripts/live-run-ship.sh "${SRC:-$PWD}" 2>/dev/null | jq -c "${DRIVE_KEEP:-del(.runs, .per_path)}"
  printf 'rc=%s\n' "${PIPESTATUS[0]}"
}

