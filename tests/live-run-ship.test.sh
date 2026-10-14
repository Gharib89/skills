#!/usr/bin/env bash
# scripts/live-run-ship.sh: the live run's driver, over stub tools in a
# throwaway state directory. A fake `gh` keeps the fixture's issues, PRs and
# branches as files and clones a local seed repo; a fake `claude` plays one
# scripted outcome per invocation (a Ship that reaches the merge gate, stops
# ambiguous, fails a check, claims a vague issue, hits a cap, or fails to start)
# and writes the Run file and host state that outcome leaves; `npx` is a no-op.
# Asserted: the result line and exit code, which carry the pass rule (one retry
# per path), the caps and the unavailable cases.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

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
# What Ship's in-place isolation meets: the tree's status, then find-docs' ref.
{ git status --porcelain; jq -r '.skills["find-docs"].ref' skills-lock.json; } > "$S/clone"
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
ship_pr() { # claim, push a branch, open a PR closing the issue
  local f=$S/issues/$n.json
  jq '.assignees = [{login: "agent"}]' "$f" > "$S/i" && mv "$S/i" "$f"
  echo "feat/x-$n" >> "$S/branches"
  jq --argjson n "$n" '. + [{number: (100 + $n), state: "open", head: {ref: "feat/x-\($n)"},
    body: "Closes #\($n)\n\n## Why\n\nx\n\n## Attribution\n\nf\n"}]' "$S/pulls.json" > "$S/p" && mv "$S/p" "$S/pulls.json"
}
reply="Done."
case $play in
  happy) phases 8 9 > "$run"; ship_pr ;;
  happy-skips-gate) phases 4 5 > "$run"; ship_pr ;;
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
jq -cn --arg r "$reply" '{subtype: "success", result: $r, total_cost_usd: 1, session_id: "s"}'
CLAUDE

cat > "$T/bin/npx" <<'NPX'
#!/usr/bin/env bash
# `skills add <source> --skill <k> ...`: logs its arguments, then installs <k>
# into the working directory and records <source>'s `#<ref>` in the lock; a
# skill named in $LIVE_STUB/npx-fails fails instead.
S=$LIVE_STUB
printf '%s\n' "$*" >> "$S/npx.log"
[ "$1" != -y ] || shift
src=$3 k=$5
! grep -qxF "$k" "$S/npx-fails" 2>/dev/null || { echo "install of $k failed"; exit 1; }
mkdir -p ".claude/skills/$k" && echo "$src" > ".claude/skills/$k/SKILL.md"
jq --arg k "$k" --arg r "${src##*#}" '.skills[$k] = {ref: $r}' skills-lock.json > lock && mv lock skills-lock.json
NPX
chmod +x "$T/bin/"*
export PATH="$T/bin:$PATH"

# The seed carries every skill on ship's composes line at its pin, but OFF_PIN,
# which its lock records at another ref.
composes=$(sed -n 's/^  composes: //p' skills/ship/SKILL.md)
seed() {
  local entry k ref lock='{"version": 1, "skills": {}}'
  for entry in $composes; do
    k=${entry##*:} ref=${entry%:*}; ref=${ref##*#}
    [ "$k" != "${OFF_PIN:-}" ] || ref=522c4db000000000000000000000000000000000
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
  bash scripts/live-run-ship.sh "$PWD" 2>/dev/null | jq -c 'del(.runs)'
  printf 'rc=%s\n' "${PIPESTATUS[0]}"
}

check "both paths passing is a pass" '{"result":"pass","failed":[],"retried":[]}
rc=0' "$(drive happy ambiguous)"
check "every claude run carries the budget cap" "2" "$(grep -c -- '--max-budget-usd 2.50 ' "$LIVE_STUB/claude.log")"
check "the vague issue is filed ready for an agent" '["ready-for-agent"]' \
  "$(jq -sc '[.[] | select(.title == "Fix calc.sh the way we discussed") | .labels[].name]' "$LIVE_STUB"/issues/*.json)"
check "every run's issue is closed after it" "[]" "$(jq -sc '[.[] | select(.state == "open") | .number]' "$LIVE_STUB"/issues/*.json)"

check "an in-sync seed installs ship alone" "1" "$(wc -l < "$LIVE_STUB/npx.log")"

off=$(tr ' ' '\n' <<<"$composes" | grep ':find-docs$')
check "a composed skill off its pin in the seed is installed at its pin" '{"result":"pass","failed":[],"retried":[]}
rc=0
skills add '"${off%:*} --skill find-docs --agent claude-code -y" \
  "$(OFF_PIN=find-docs drive happy ambiguous; tail -n +2 "$LIVE_STUB/npx.log")"
pin=${off%:*}
check "Ship meets a clean clone with the installed pin" "${pin#*#}" "$(cat "$LIVE_STUB/clone")"
check "a failed composed-skill install is unavailable" \
  '{"result":"unavailable","reason":"composed skill install failed: find-docs"}
rc=2' "$(OFF_PIN=find-docs NPX_FAILS=find-docs drive happy ambiguous)"

check "a pass on the retry is a pass that names the first failure" \
  '{"result":"pass","failed":[],"retried":["happy: phase 5: not closed","happy: phase 6: not closed","happy: phase 7: not closed","happy: phase 8: not closed","happy: merge gate: not reached"]}
rc=0' "$(drive happy-skips-gate happy ambiguous)"

check "a retry does not hide the first attempt's cleanup failure" \
  '["happy: cleanup: left PR #101 open"]
rc=1' "$(PR_CLOSE_FAILS=1 drive happy-skips-gate happy ambiguous | { read -r line; jq -c .failed <<<"$line"; cat; })"

check "an ambiguous path that claims and opens a PR twice fails" \
  '{"result":"fail","failed":["ambiguous: stop: the reply does not name ambiguous","ambiguous: phase 1: closed","ambiguous: phase 2: opened","ambiguous: issue: claimed","ambiguous: pr: 1 open PRs close #3, want 0","ambiguous: branch: feat/x-3 pushed"],"retried":["ambiguous: stop: the reply does not name ambiguous","ambiguous: phase 1: closed","ambiguous: phase 2: opened","ambiguous: issue: claimed","ambiguous: pr: 1 open PRs close #2, want 0","ambiguous: branch: feat/x-2 pushed"]}
rc=1' "$(drive happy ambiguous-claims ambiguous-claims)"
check "the PRs and branches of a failed run are cleaned up" "[] " \
  "$(jq -c '[.[] | select(.state == "open")]' "$LIVE_STUB/pulls.json") $(cat "$LIVE_STUB/branches")"

check "the budget cap is a fail" '{"result":"fail","failed":["happy: cap: budget $2.50"],"retried":["happy: cap: budget $2.50"]}
rc=1' "$(drive budget budget ambiguous)"

check "the wall-clock cap is a fail" '{"result":"fail","failed":["happy: cap: wall clock 1 s"],"retried":["happy: cap: wall clock 1 s"]}
rc=1' "$(LIVE_RUN_WALL_S=1 drive slow slow ambiguous)"

check "an unreachable fixture repo is unavailable" '{"result":"unavailable","reason":"cannot clone Gharib89/ship-fixture"}
rc=2' "$(CLONE_FAILS=1 drive happy ambiguous)"

check "a claude killed before the wall clock is not the cap" '{"result":"unavailable","reason":"claude -p failed"}
rc=2' "$(drive killed)"
check "claude output that is not JSON is unavailable" '{"result":"unavailable","reason":"claude -p output unreadable"}
rc=2' "$(drive happy garbled)"
check "claude exiting 0 with no output is unavailable" '{"result":"unavailable","reason":"claude -p output unreadable"}
rc=2' "$(drive happy silent)"
check "an empty reply is judged, not unavailable" '{"result":"fail","failed":["ambiguous: stop: the reply does not name ambiguous"],"retried":["ambiguous: stop: the reply does not name ambiguous"]}
rc=1' "$(drive happy no-reply no-reply)"

check "claude failing to run is unavailable" '{"result":"unavailable","reason":"claude -p failed"}
rc=2' "$(drive auth)"
check "an unavailable run still closes its issue" "[]" \
  "$(jq -sc '[.[] | select(.state == "open") | .number]' "$LIVE_STUB"/issues/*.json)"

finish
