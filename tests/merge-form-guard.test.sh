#!/usr/bin/env bash
# merge-form-guard, ship-run's PreToolUse hook on Bash: a call to `merge.sh` or
# `run-file.sh gate admit` passes only in the bare form the owner's allow rules
# match, since any other form falls to the auto-mode classifier, which refused
# a third of them (#1419). The refused shapes below are replayed from that
# issue's evidence; each refusal names the bare command to run instead.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

root=$PWD
guard=$root/skills/ship-run/hooks/merge-form-guard.sh
P=.claude/skills/ship-run/scripts
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT

# run <command> [<cwd>]: the hook's stdin as Claude Code sends it; prints the
# exit code, then stderr.
run() {
  jq -n --arg c "$1" --arg d "${2:-/w/tree}" \
    '{hook_event_name: "PreToolUse", tool_name: "Bash", cwd: $d, tool_input: {command: $c}}' \
    | bash "$guard" 2>"$work/err" >/dev/null
  echo "$?"
}
err() { cat "$work/err"; }
has() { grep -qxF -- "  $1" "$work/err" && echo yes || echo no; }

# Refused shapes from the evidence.
check_rc "a variable prefix chained with && is refused" 2 \
  "$(run "S=$P && H=abc123 && \$S/run-file.sh gate admit human --head \$H --issue 1374 && \$S/merge.sh 1396 1374 \$H")"
check "its gate admit comes back bare, variables resolved" yes "$(has "$P/run-file.sh gate admit human --head abc123 --issue 1374")"
check "and its merge too, in order" yes "$(has "$P/merge.sh 1396 1374 abc123")"
check "the message says the allow rule already exists" 1 "$(grep -c 'allow rule already exists' "$work/err")"
check "and that the output needs no trimming" 1 "$(grep -c 'needs no trimming' "$work/err")"

check_rc "\$PWD with a redirect and a pipe is refused" 2 \
  "$(run "$P/merge.sh 1396 1374 abc123 --worktree \$PWD 2>&1 | tail -15" /home/u/wt)"
check "\$PWD becomes the hook's literal cwd, the trim dropped" yes "$(has "$P/merge.sh 1396 1374 abc123 --worktree /home/u/wt")"

check_rc "a leading cd on its own line is refused" 2 \
  "$(run "cd /home/u/wt
$P/merge.sh 1410 1406 abc123 2>&1 | tail -20")"
check "the cd becomes a literal --worktree" yes "$(has "$P/merge.sh 1410 1406 abc123 --worktree /home/u/wt")"

check_rc "the typical ; shape with a ci file is refused" 2 \
  "$(run "S=$P; H=abc; \$S/run-file.sh gate admit clean /s/ci-wait.json --head \$H --issue 5 | tail -3; \$S/merge.sh 7 5 \$H 2>&1 | tail -15")"
check "its admit comes back bare" yes "$(has "$P/run-file.sh gate admit clean /s/ci-wait.json --head abc --issue 5")"

check_rc "a ./ path misses the rule and is refused" 2 "$(run "./$P/merge.sh 1 2 abc")"
check "it comes back without the ./" yes "$(has "$P/merge.sh 1 2 abc")"
check_rc "a bash prefix is refused" 2 "$(run "bash $P/merge.sh 1 2 abc")"
check_rc "a double-quoted ruling holding \$ is refused" 2 \
  "$(run "$P/run-file.sh gate admit waiver --ruling \"cost \$X\" --head abc --issue 5")"
check_rc "an unknown variable is refused" 2 "$(run "$P/merge.sh 1 2 \$HEAD_SHA")"
check "and the message asks for its literal value" 1 "$(grep -c 'literal value' "$work/err")"

# Wrappers, keywords, a trailing separator and a redirect hide no merge call
# (self-review round 1).
for c in "$P/merge.sh 1 2 abc &" "$P/merge.sh 1 2 abc;" "($P/merge.sh 1 2 abc)" \
  "timeout 60 $P/merge.sh 1 2 abc | tail" "env A=b $P/merge.sh 1 2 abc" "nohup $P/merge.sh 1 2 abc" \
  "sudo $P/merge.sh 1 2 abc" "command $P/merge.sh 1 2 abc" "if true; then $P/merge.sh 1 2 abc; fi" \
  "xargs $P/merge.sh 1 2" "$P/merge.sh 1 2 abc >&2" "$P/merge.sh 1 2 abc>/dev/null"; do
  check_rc "refused: $c" 2 "$(run "$c")"
done
# A wrapper taking options hides nothing either (self-review round 2): the call
# is found by its path and arguments wherever it stands.
for c in "timeout -s KILL 60 $P/merge.sh 1 2 abc" "nice -n 5 $P/merge.sh 1 2 abc" \
  "env -i $P/merge.sh 1 2 abc" "sudo -u x $P/merge.sh 1 2 abc" "command -p $P/merge.sh 1 2 abc" \
  "time -p $P/run-file.sh gate admit human --head abc --issue 5" "eval $P/merge.sh 1 2 abc" \
  "stdbuf -oL $P/merge.sh 1 2 abc" "bash -lc '$P/merge.sh 1 2 abc'" "bash -x -c '$P/merge.sh 1 2 abc'" \
  "$P/merge.sh 1 2 \\
abc"; do
  check_rc "refused: $c" 2 "$(run "$c")"
done
check_rc "a cd into the scripts directory and ./merge.sh is refused" 2 \
  "$(run "cd /home/u/wt/$P && ./merge.sh 1 2 abc")"
check_rc "reading merge.sh by its path passes" 0 "$(run "sed -n 1,40p $P/merge.sh | head")"
check_rc "merge.sh --help piped passes: no merge" 0 "$(run "$P/merge.sh --help | head -3")"
check_rc "a bash -c string is read as commands" 2 "$(run "bash -c '$P/merge.sh 1 2 abc'")"
check "and its call comes back bare" yes "$(has "$P/merge.sh 1 2 abc")"
check_rc "a quoted newline in a ruling is refused" 2 \
  "$(run "$P/run-file.sh gate admit waiver --ruling 'a
b' --head abc --issue 5")"
check_rc "a command substitution is refused" 2 "$(run "$P/merge.sh 1 2 \$(git rev-parse HEAD)")"
check "and the message asks for its literal value" 1 "$(grep -c 'literal value' "$work/err")"
# A quoted PR number is still a call, a backslash-newline inside double quotes
# is still a newline, and an ANSI-C bash -c string is still commands; a quoted
# string nothing runs, and a read of the file followed by a number, are not a
# call (self-review round 3).
for c in "cd /x && $P/merge.sh '1' 2 abc" "cd /x && $P/merge.sh \"1\" 2 abc" \
  "$P/merge.sh 1 2 \"abc\\
x\"" "bash -c \$'$P/merge.sh 1 2 abc'" "eval '$P/merge.sh 1 2 abc'"; do
  check_rc "refused: $c" 2 "$(run "$c")"
done
for c in "echo '$P/merge.sh 1 2 abc'" "gh pr comment 1 --body \"run $P/merge.sh 1 2 abc\"" \
  "git commit -m 'teach $P/run-file.sh gate admit human; then merge' && git push" \
  "grep -n foo $P/merge.sh 1"; do
  check_rc "passes: $c" 0 "$(run "$c")"
done
# A quoted script path is still the call; a path another command reads as
# data is not one (codex round 1).
check_rc "a quoted script path piped is refused" 2 "$(run "\"$P/merge.sh\" 1 2 abc | tail")"
for c in "printf '%s\\n' $P/merge.sh 1 2" "grep -n foo $P/merge.sh 1 2" "cat $P/run-file.sh gate admit"; do
  check_rc "passes: $c" 0 "$(run "$c")"
done
check_rc "another tool's merge.sh is not ship's" 0 "$(run "/opt/other/scripts/merge.sh 1 2 | tail")"

# The bare form passes.
check_rc "bare merge passes" 0 "$(run "$P/merge.sh 1396 1374 abc123 --worktree /home/u/wt")"
check_rc "bare gate admit clean passes" 0 "$(run "$P/run-file.sh gate admit clean /s/ci-wait.json --head abc --issue 5")"
check_rc "bare gate admit human passes" 0 "$(run "$P/run-file.sh gate admit human --head abc --issue 5")"
check_rc "a single-quoted ruling holding ; and \$ passes" 0 \
  "$(run "$P/run-file.sh gate admit waiver --ruling 'owner: merge it; \$5 risk is fine && go' --head abc --issue 5")"
check_rc "a double-quoted ruling with no \$ passes" 0 \
  "$(run "$P/run-file.sh gate admit waiver --ruling \"merge it; fine\" --head abc --issue 5")"
check_rc "the absolute path of an install with no project copy passes" 0 \
  "$(run "/home/u/.claude/skills/ship-run/scripts/merge.sh 1 2 abc")"
mkdir -p "$work/wt/$P" && touch "$work/wt/$P/merge.sh"
check_rc "the absolute path of a project copy is refused" 2 \
  "$(run "$work/wt/$P/merge.sh 1 2 abc" "$work/wt")"
check "it comes back relative" yes "$(has "$P/merge.sh 1 2 abc")"
check_rc "a user copy's absolute path beside a project copy is refused" 2 \
  "$(run "/home/u/.claude/skills/ship-run/scripts/merge.sh 1 2 abc" "$work/wt")"
check_rc "surrounding whitespace passes" 0 "$(run "  $P/merge.sh 1 2 abc  ")"

# Everything else passes untouched.
check_rc "an unrelated chained command passes" 0 "$(run "git status && ls | head")"
check_rc "reading merge.sh passes" 0 "$(run "grep -n merge.sh skills/ship-run/reference/merge-gate.md | head")"
check_rc "another run-file verb, piped, passes" 0 "$(run "$P/run-file.sh note X y --issue 5 | jq .")"
check_rc "unreadable input never blocks" 0 "$(printf 'not json' | bash "$guard" 2>/dev/null; echo $?)"

# The frontmatter hook finds the guard from the project copy, else passes.
hook=$(sed -n "s/^ *command: '\(.*\)'\$/\1/p" skills/ship-run/SKILL.md)
check "SKILL.md declares one hook command" 1 "$(grep -c . <<<"$hook")"
mkdir -p "$work/proj/.claude/skills/ship-run/hooks" "$work/home"
cp "$guard" "$work/proj/.claude/skills/ship-run/hooks/"
fire() { # <project dir>
  CLAUDE_PROJECT_DIR=$1 HOME=$work/home CLAUDE_CONFIG_DIR='' bash -c "$hook" >/dev/null 2>&1 \
    <<<"$(jq -n --arg c "cd /x && $P/merge.sh 1 2 abc" '{cwd: "/x", tool_input: {command: $c}}')"
  echo "$?"
}
check_rc "the hook runs the project copy's guard" 2 "$(fire "$work/proj")"
check_rc "with no guard anywhere the hook passes" 0 "$(fire "$work/none")"

finish
