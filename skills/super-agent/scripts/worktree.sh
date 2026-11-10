#!/usr/bin/env bash
# Remove a settled or closed entry's worktree, so finished worktrees do not pile
# up. It removes only a clean one, and never forces: a worktree with uncommitted
# or untracked files, or whose branch has commits on no remote and no merged PR,
# is kept with a named reason for the super agent to report. The branch is left
# alone (deleting branches is the owner's call).
#
#   worktree remove --ledger <file> <key>
#   worktree remove --key <key> --path <worktree> --branch <name> --stage <stage>
#                   --kind <ship|triage> --merged <true|false>
#
# The first form reads the entry's fields from the ledger (`worktree`, `branch`,
# `stage`, `kind`, and `observed.pr.state`, which `reconcile` wrote, for the PR). The
# second takes them as flags and reads no ledger: it is for an entry on a linked
# machine (an `environment_id`), where the script text is sent to a scratch thread
# there as `bash -s -- remove ...`, since that machine has no checkout of this repo.
# `--merged` is whether the entry's PR merged (always false for a `triage` entry). A
# `ship` entry's PR merged when its stage is `settled` or its observed PR state is
# `merged`: `reconcile` settles a ship entry only on a merged PR, while `observed`
# can lag the stage, and the squash-merge deleted the remote branch, so reading
# `observed` alone keeps a merged worktree as `unpushed`.
# The script refuses a stage that is not `settled` or `closed`, so an open entry's
# worktree is never touched, and the main checkout. A path git does not list as a
# worktree of its repository is kept as `not a worktree`, and one whose head is
# not the ledger's branch (another branch, or detached) is kept, since its commits
# are not the ones checked. Removal is `git worktree
# remove <path>` run from the main checkout, then `git worktree prune`.
#
# stdout: {key, removed, kept, reason}: `removed` true when the worktree is gone;
#         `kept` true when it stays on purpose, `reason` then `dirty`, `unpushed`,
#         `not a worktree`, `head is not <branch>`, `branch unreadable` or
#         `remove failed: <git's line>`;
#         a refusal is removed false, kept false, and the reason it names
# exit: 0 removed or kept · 1 refused (an open stage, the main checkout), or a key
#       the ledger does not hold · 2 usage, or an unreadable ledger
set -uo pipefail
usage='usage: worktree remove --ledger <file> <key> | --key <key> --path <worktree> --branch <name> --stage <stage> --kind <ship|triage> --merged <true|false>'
# Self-contained, since the script text travels to a machine with no checkout:
# it cannot source _lib.sh.
fail() { jq -cn --arg e "$1" '{error: $e}'; printf '%s\n' "$1" >&2; exit "${2:-2}"; }
if [ "${1:-}" = --help ] && [ $# -eq 1 ]; then
  printf '%s\n' "$usage"
  awk '/^# stdout:/ { f = 1 } f { if ($0 !~ /^#/ || /^# exit:/) exit; sub(/^# ?/, ""); print }' "${BASH_SOURCE[0]}"
  exit 0
fi
command -v jq >/dev/null || { printf '{"error":"jq not installed"}\n'; exit 2; }
[ "${1:-}" = remove ] || fail "$usage"; shift
ledger='' key='' path='' branch='' stage='' kind='' merged=''
while [ $# -gt 0 ]; do
  case $1 in
    --ledger|--key|--path|--branch|--stage|--kind|--merged)
      case ${2:-} in -*|'') fail "$usage" ;; esac
      case $1 in --ledger) ledger=$2 ;; --key) key=$2 ;; --path) path=$2 ;; --branch) branch=$2 ;; --stage) stage=$2 ;; --kind) kind=$2 ;; --merged) merged=$2 ;; esac
      shift 2 ;;
    -*) fail "$usage" ;;
    *) [ -z "$key" ] || fail "$usage"; key=$1; shift ;;
  esac
done
if [ -n "$ledger" ]; then
  [ -n "$key" ] && [ -z "$path$branch$stage$kind$merged" ] || fail "$usage"
  [ -f "$ledger" ] || fail "$ledger: no such file"
  jq -e '(.entries | type) == "object"' "$ledger" >/dev/null 2>&1 || fail "$ledger: not a ledger"
  jq -e --arg k "$key" '.entries[$k]' "$ledger" >/dev/null || fail "$key is not in the ledger" 1
  eval "$(jq -r --arg k "$key" '.entries[$k] | @sh "path=\(.worktree) branch=\(.branch) stage=\(.stage) kind=\(.kind // "ship") merged=\(if (.kind // "ship") == "ship" and (.stage == "settled" or .observed.pr.state == "merged") then "true" else "false" end)"' "$ledger")"
else
  [ -n "$key" ] && [ -n "$path" ] && [ -n "$branch" ] && [ -n "$stage" ] && [ -n "$kind" ] || fail "$usage"
  case $merged in true|false) ;; *) fail "$usage" ;; esac
fi

answer() { # <removed> <kept> <reason or empty>
  jq -cn --arg k "$key" --argjson r "$1" --argjson p "$2" --arg why "$3" '{key: $k, removed: $r, kept: $p, reason: (if $why == "" then null else $why end)}'
}
case $stage in
  settled|closed) ;;
  *) answer false false "stage $stage: only a settled or closed entry's worktree is removed"; exit 1 ;;
esac
# the worktrees git lists for the repository the path belongs to; the first is the main checkout
real=$(cd "$path" 2>/dev/null && pwd -P) || real=''
listing=$([ -n "$real" ] && git -C "$real" worktree list --porcelain 2>/dev/null </dev/null | sed -n 's/^worktree //p')
mainwt=$(head -1 <<<"$listing")
if [ -z "$real" ] || [ -z "$listing" ] || ! grep -Fxq "$real" <<<"$listing"; then
  answer false true "not a worktree"; exit 0
fi
[ "$real" != "$mainwt" ] || { answer false false "refused: $path is the main checkout"; exit 1; }
if [ -n "$(git -C "$real" status --porcelain 2>/dev/null </dev/null)" ]; then answer false true dirty; exit 0; fi
# the ledger's branch is what the checks below read, so the worktree must be on it: any other head may hold commits they never see
cur=$(git -C "$real" symbolic-ref -q --short HEAD 2>/dev/null </dev/null) || cur=''
[ "$cur" = "$branch" ] || { answer false true "head is not $branch"; exit 0; }
if [ "$merged" != true ]; then
  if ! unpushed=$(git -C "$real" rev-list "refs/heads/$branch" --not --remotes 2>/dev/null </dev/null); then
    answer false true "branch unreadable"; exit 0
  fi
  [ -z "$unpushed" ] || { answer false true unpushed; exit 0; }
fi
if ! err=$(git -C "$mainwt" worktree remove "$real" 2>&1 </dev/null); then
  answer false true "remove failed: $(head -1 <<<"$err")"; exit 0
fi
git -C "$mainwt" worktree prune >/dev/null 2>&1 </dev/null
answer true false ''
