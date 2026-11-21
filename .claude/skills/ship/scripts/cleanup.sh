#!/usr/bin/env bash
# After the merge: remove the issue's run record, its worktree and force-delete
# its local branch (a squash-merged branch is not an ancestor of the default
# branch). The worktree is found by the branch it has checked out, held to
# isolate's `<type>/<slug>-<issue>` shape, whatever its folder is named: a host
# that made the worktree (T3 names the folder `<slug>-<hex>`) and isolate
# adopted it is removed too. A worktree on a branch without that shape is not
# found and stays; isolate adopts none. Carried files
# stay in the worktree this removes. The record is the
# `ship-<issue>` Run file and `scratch-<issue>` Scratch directory under
# `${XDG_STATE_HOME:-~/.local/state}/ship/<repo key>` that `run-file init`
# made; it goes first, so a worktree that will not come off still leaves the
# run's own files cleaned.
#
#   cleanup <issue|none>
#
# `none` as the issue argument is the task-spec run: it is the literal worktree
# and branch suffix the run used, and the teardown is unchanged, except that no
# record is removed for it: nothing says which run a `none` record belongs to.
#
# stdout: {worktree, branch, worktree_removed, branch_deleted, record}
#   worktree_removed: true when a worktree was found and removed, false when it
#     would not come off, null when the run had no worktree to remove (an
#     in-place run, or one already gone): never true for a worktree not touched
#   record: "removed" when the run's record and scratch directory came off,
#     "none" when there was nothing to remove (the issue is `none`, or no record
#     existed), "failed" when an rm failed or the record root could not be
#     named (cksum failed)
# exit: 0 clean · 1 a step failed (JSON says which) · 2 usage or tooling
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh" || { printf '{"error":"cannot source _lib.sh"}\n'; exit 2; }
usage='usage: cleanup <issue|none>'
ship_help "$usage" "$@"
ship_args "$usage" "issue|none" "$@"
n=$1
[ $# -eq 1 ] || ship_tooling "unknown flag: $2"
root=$(ship_main_checkout) || ship_tooling "not inside a git checkout"

record=none
if [ "$n" != none ]; then
  if records=$(ship_record_root); then
    for r in "$records/ship-$n" "$records/scratch-$n"; do
      [ -e "$r" ] || continue
      rm -rf "$r" && record=removed || { record=failed; break; }
    done
  else record=failed
  fi
fi

wt=null; branch=null; wt_removed=null; br_deleted=true
# isolate's branch shape, the key for both lookups below: a worktree and, for an
# in-place run, a bare branch. It is held to this shape because `branch -D`
# would also take a hand-made branch that merely ends in `-<n>`.
shape=$(ship_branch_shape "$n")
# Prune first: a registered worktree whose folder is already gone would fail
# `worktree remove`, and the branch it held is then found as a bare branch.
git -C "$root" worktree prune >/dev/null 2>&1
list=$(git -C "$root" worktree list --porcelain) || ship_tooling "git worktree list failed"
# The main checkout is never a candidate. Matched with awk on the porcelain
# list, since the folder name is the host's and says nothing about the run.
found=$(awk -v r="$root" -v pat="$shape" '
  /^worktree / { p = substr($0, 10) }
  /^branch refs\/heads\// { b = substr($0, 19); if (p != r && b ~ pat) { print p "\t" b; exit } }' <<<"$list")
if [ -n "$found" ]; then
  wt=${found%%$'\t'*}; branch=${found#*$'\t'}
  git -C "$root" worktree remove --force "$wt" >/dev/null 2>&1 && wt_removed=true || wt_removed=false
fi
# An in-place run has no worktree; its branch still has isolate's
# `<type>/<slug>-<n>` shape. Matched with grep, since a for-each-ref glob's `*`
# stops at a `/`. A branch another linked worktree holds is skipped: the lookup
# above took that worktree, or none held it.
if [ "$branch" = null ]; then
  branch=$(git -C "$root" for-each-ref --format='%(refname:short)%09%(worktreepath)' refs/heads/ \
    | awk -F'\t' -v r="$root" '$2 == "" || $2 == r { print $1 }' | grep -m1 -E "$shape")
  [ -n "$branch" ] || branch=null
fi
if [ "$branch" != null ]; then
  if [ "$(git -C "$root" rev-parse --abbrev-ref HEAD)" = "$branch" ]; then
    br_deleted=false; echo "branch $branch is checked out in the main checkout; switch off it first" >&2
  else
    git -C "$root" branch -D "$branch" >/dev/null 2>&1 || br_deleted=false
  fi
fi
jq -n --arg w "$wt" --arg b "$branch" --argjson wr "$wt_removed" --argjson bd "$br_deleted" --arg rec "$record" \
  '{worktree: (if $w == "null" then null else $w end), branch: (if $b == "null" then null else $b end),
    worktree_removed: $wr, branch_deleted: $bd, record: $rec}'
[ "$wt_removed" != false ] && [ "$br_deleted" = true ] && [ "$record" != failed ]
