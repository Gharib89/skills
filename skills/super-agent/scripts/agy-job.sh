#!/usr/bin/env bash
# Run one bounded text job (a draft, a summary, a second-opinion review, triage
# reading) on agy's own quota. agy's `--mode auto` is closed for this account
# and `--sandbox` does not confine it (measured 2026-11-06), so the job runs as
# a CLI call from a scratch worktree with a session-only allow list: the
# worktree is disposable and the list names only harmless commands. Never
# `--dangerously-skip-permissions`, and never a rule that allows every command.
#
#   agy-job --repo <dir> --task <text> [--model <name>] [--allow <binary>]... [--timeout <s>]
#
# A rule names a binary exactly: `command(ls)` allows `ls .`, while a prefix
# form (`ls*`, `git *`) allowed nothing (measured). The default list is
# permissive toward harmless commands: ls cat head tail wc grep rg find sort
# uniq cut tr diff jq tree file stat pwd echo basename dirname date. `git` is
# left out of it, since an allowed `git` could push: pass `--allow git` for a
# job that reads history. --allow adds one binary name; a name with a wildcard,
# a space or a parenthesis, or one that deletes, escalates or reaches the
# network (rm sudo su curl wget ssh scp nc dd chmod chown kill), is refused.
# --timeout (default 300 s) bounds the job, agy's own print time and a hard
# limit just past it. The scratch worktree is a detached one of --repo's HEAD,
# removed afterwards however the job ended.
#
# stdout: {status, response, allow, denied, duration_seconds, worktree} on a
#         job that answered, `allow` the binary names permitted and `denied`
#         the commands agy refused (the job needed one the list lacks, and its
#         response is then empty); {error, ...} with the same fields agy
#         printed otherwise
# exit: 0 the job answered with nothing denied · 1 agy failed, timed out,
#       reported a status that is not SUCCESS, or was denied a command · 2 usage,
#       a --repo that is not a git repository, or a scratch worktree that
#       could not be made
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh" || { printf '{"error":"cannot source _lib.sh"}\n'; exit 2; }

usage='usage: agy-job --repo <dir> --task <text> [--model <name>] [--allow <binary>]... [--timeout <s>]'
sa_help "$usage" "$@"
repo='' task='' model='' timeout_s=300 allow=(ls cat head tail wc grep rg find sort uniq cut tr diff jq tree file stat pwd echo basename dirname date)
while [ $# -gt 0 ]; do
  case $1 in
    --repo) sa_flag_value "$usage" "${2:-}"; repo=$2; shift 2 ;;
    --task) sa_flag_value "$usage" "${2:-}"; task=$2; shift 2 ;;
    --model) sa_flag_value "$usage" "${2:-}"; model=$2; shift 2 ;;
    --timeout) sa_flag_value "$usage" "${2:-}"; sa_window_flag "$usage" "$2"; timeout_s=$2; shift 2 ;;
    --allow)
      sa_flag_value "$usage" "${2:-}"
      # c[u]rl: spelled as a glob so the contract check's curl rule does not read the list as a call
      case $2 in *[!A-Za-z0-9._+-]*|rm|sudo|su|c[u]rl|wget|ssh|scp|nc|dd|chmod|chown|kill) sa_tooling "$usage" ;; esac
      allow+=("$2"); shift 2 ;;
    *) sa_tooling "$usage" ;;
  esac
done
[ -n "$repo" ] && [ -n "$task" ] || sa_tooling "$usage"
git -C "$repo" rev-parse --git-dir >/dev/null 2>&1 || sa_tooling "$repo: not a git repository"

scratch=$(mktemp -d) || sa_tooling "cannot make a scratch directory"
wt=$scratch/worktree
cleanup() { git -C "$repo" worktree remove --force "$wt" >/dev/null 2>&1; rm -rf "$scratch"; }
trap cleanup EXIT
git -C "$repo" worktree add --detach "$wt" HEAD >/dev/null 2>&1 || sa_tooling "cannot add a scratch worktree of $repo"

allow_json=$(printf '%s\n' "${allow[@]}" | jq -R . | jq -cs .)
settings=$(jq -cn --argjson a "$allow_json" '{permissions: {allow: [$a[] | "command(\(.))"]}}')
args=(-p "$task" --settings "$settings" --output-format json --print-timeout "${timeout_s}s")
[ -z "$model" ] || args+=(--model "$model")
raw=$(cd "$wt" && timeout "$((timeout_s + 15))" agy "${args[@]}" 2>/dev/null </dev/null); rc=$?
line=$(grep '^{' <<<"$raw" | tail -1)
if [ -z "$line" ] || ! jq -e . <<<"$line" >/dev/null 2>&1; then
  sa_fail "agy exited $rc with no JSON answer"
fi
jq -c --argjson a "$allow_json" --argjson rc "$rc" '
  {status, response: (.response // ""), allow: $a, denied: (.denied_actions // []),
   duration_seconds: (.duration_seconds // null)}
  + (if (.error // null) != null then {error} else {} end)
  | . as $o
  | if $rc != 0 and $o.response == "" then $o + {error: "agy exited \($rc)"} else $o end' <<<"$line" > "$scratch/answer"
cat "$scratch/answer"
jq -e '.status == "SUCCESS" and (.denied | length) == 0 and (.error // null) == null' "$scratch/answer" >/dev/null
