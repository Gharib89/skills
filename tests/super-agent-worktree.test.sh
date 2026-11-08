#!/usr/bin/env bash
# super-agent's `worktree`, driven through its command line over a real throwaway
# git repo as the fake worktree (tests/super-agent-fake.sh): a settled or closed
# entry's clean worktree is removed and pruned with its branch left alone; a dirty
# one, or one whose branch has commits on no remote and no merged PR, is kept with a
# named reason and never forced; an open entry's worktree is never touched, and the
# main checkout and a path git does not list are refused.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
source tests/super-agent-fake.sh

s=skills/super-agent/scripts
tmp=$(mktemp -d) || exit 2
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/tools"
for t in bash env jq awk sed grep cat mktemp mv rm mkdir dirname basename tr head tail date timeout sort cut wc diff chmod git readlink ls touch; do
  p=$(command -v $t) && ln -s "$p" "$tmp/tools/$t" 2>/dev/null
done
export PATH="$tmp/tools" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
G() { git -c user.name=t -c user.email=t@t "$@"; }
led=$tmp/ledger.json
W() { bash "$s/worktree.sh" "$@"; }
repo=$tmp/repo; mkdir -p "$repo"; sa_worktree_repo "$repo"
main=$repo/main

# add_wt <name> [--push]: a worktree on branch feat/<name> with one commit; pushed with --push
add_wt() {
  G -C "$main" worktree add -q "$repo/wt-$1" -b "feat/$1" main 2>/dev/null
  G -C "$repo/wt-$1" commit -q --allow-empty -m "work on $1"
  [ "${2:-}" != --push ] || G -C "$repo/wt-$1" push -q origin "feat/$1" 2>/dev/null
}
# entry <name> <stage> [<kind>] [<pr state>]: a ledger entry for that worktree
entry() {
  bash "$s/ledger.sh" --ledger "$led" add --repo acme/w --number "${5:-1}" --thread t --worktree "$repo/wt-$1" --branch "feat/$1" --kind "${3:-ship}" >/dev/null
  bash "$s/ledger.sh" --ledger "$led" set "acme/w#${5:-1}" stage "\"$2\"" >/dev/null
  bash "$s/ledger.sh" --ledger "$led" set "acme/w#${5:-1}" observed "{\"pr\":{\"state\":\"${4:-merged}\",\"number\":7}}" >/dev/null
}
exists() { [ -d "$repo/wt-$1" ] && echo yes || echo no; }
branch_exists() { G -C "$main" rev-parse --verify -q "feat/$1" >/dev/null && echo yes || echo no; }
listed() { G -C "$main" worktree list --porcelain | grep -c "wt-$1\$"; }

# --- the contract every script keeps -----------------------------------------------
out=$(W --help 2>"$tmp/err"); rc=$?
check "--help opens with its usage line" "usage: worktree" "$(sed -n 1p <<<"$out" | cut -d' ' -f1-2)"
check "--help names its stdout fields next" stdout: "$(sed -n 2p <<<"$out" | cut -c1-7)"
check_rc "--help exits 0" 0 "$rc"
check "--help writes nothing on stderr" "" "$(cat "$tmp/err")"
out=$(W --bogus 2>/dev/null); rc=$?
check "a bad flag answers the usage line" "$(sed -n 1p <<<"$(W --help)")" "$(jq -r .error <<<"$out")"
check_rc "a bad flag exits 2" 2 "$rc"
check_rc "no key exits 2" 2 "$(W remove --ledger "$led" >/dev/null 2>&1; echo $?)"

# --- a settled entry's clean worktree is removed and pruned, its branch kept ----------------
add_wt clean --push; entry clean settled ship merged 1
out=$(W remove --ledger "$led" acme/w#1); rc=$?
check_rc "a clean settled worktree is removed, exit 0" 0 "$rc"
check "the answer says so, with no reason" '{"key":"acme/w#1","removed":true,"kept":false,"reason":null}' "$(jq -c . <<<"$out")"
check "the directory is gone" no "$(exists clean)"
check "and git no longer lists it" 0 "$(listed clean)"
check "the branch is left alone" yes "$(branch_exists clean)"

# --- merged work needs no push; a closed entry is treated like a settled one --------------
add_wt merged-unpushed; entry merged-unpushed settled ship merged 2
check "commits on no remote are safe once the PR merged" true "$(W remove --ledger "$led" acme/w#2 | jq .removed)"
add_wt closed1 --push; entry closed1 closed ship closed 3
check "a closed entry's clean, pushed worktree is removed" true "$(W remove --ledger "$led" acme/w#3 | jq .removed)"

# --- a dirty worktree is kept, whatever else is true -----------------------------------------
add_wt dirty --push; entry dirty settled ship merged 4
printf 'x\n' > "$repo/wt-dirty/new.txt"
out=$(W remove --ledger "$led" acme/w#4); rc=$?
check_rc "a dirty worktree is kept, exit 0" 0 "$rc"
check "with the reason dirty (an untracked file counts)" 'false true dirty' "$(jq -r '"\(.removed) \(.kept) \(.reason)"' <<<"$out")"
check "and is still there, still listed" 'yes 1' "$(exists dirty) $(listed dirty)"
printf 'x\n' > "$repo/wt-dirty/new2.txt"
rm -f "$repo/wt-dirty/new.txt" "$repo/wt-dirty/new2.txt"
echo >> "$repo/wt-dirty/.gitignore"
check "an untracked file is enough" dirty "$(W remove --ledger "$led" acme/w#4 | jq -r .reason)"
rm -f "$repo/wt-dirty/.gitignore"

# --- unpushed commits with no merged PR keep the worktree -------------------------------------
add_wt unpushed; entry unpushed settled ship closed 5
out=$(W remove --ledger "$led" acme/w#5)
check "commits on no remote and no merged PR: kept as unpushed" 'false true unpushed' "$(jq -r '"\(.removed) \(.kept) \(.reason)"' <<<"$out")"
check "the worktree and branch stand" 'yes yes' "$(exists unpushed) $(branch_exists unpushed)"
add_wt tri; entry tri settled triage none 6
check "a triage entry has no PR, so unpushed commits keep it" unpushed "$(W remove --ledger "$led" acme/w#6 | jq -r .reason)"
add_wt tri-pushed --push; entry tri-pushed settled triage none 7
check "a triage entry whose commits are pushed is removed" true "$(W remove --ledger "$led" acme/w#7 | jq .removed)"

# --- an open entry's worktree is never touched --------------------------------------------------
add_wt open --push; entry open launched ship open 8
for st in launched running at-rest merged; do
  bash "$s/ledger.sh" --ledger "$led" set acme/w#8 stage "\"$st\"" >/dev/null
  out=$(W remove --ledger "$led" acme/w#8); rc=$?
  check_rc "stage $st is refused, exit 1" 1 "$rc"
  check "stage $st: removed false, kept false, named" 'false false' "$(jq -r '"\(.removed) \(.kept)"' <<<"$out")"
  check "stage $st: the worktree is untouched" 'yes 1' "$(exists open) $(listed open)"
done

# --- refusals: the main checkout, and a path git does not list ------------------------------
bash "$s/ledger.sh" --ledger "$led" add --repo acme/w --number 9 --thread t --worktree "$main" --branch main >/dev/null
bash "$s/ledger.sh" --ledger "$led" set acme/w#9 stage '"settled"' >/dev/null
out=$(W remove --ledger "$led" acme/w#9); rc=$?
check_rc "the main checkout is refused, exit 1" 1 "$rc"
check "named, and still there" 'false false yes' "$(jq -r '"\(.removed) \(.kept)"' <<<"$out") $([ -d "$main/.git" ] && echo yes)"
bash "$s/ledger.sh" --ledger "$led" add --repo acme/w --number 10 --thread t --worktree "$tmp/nowhere" --branch gone >/dev/null
bash "$s/ledger.sh" --ledger "$led" set acme/w#10 stage '"settled"' >/dev/null
check "a path that is no worktree is kept as not a worktree" 'false true not a worktree' "$(W remove --ledger "$led" acme/w#10 | jq -r '"\(.removed) \(.kept) \(.reason)"')"
mkdir -p "$tmp/plain"
bash "$s/ledger.sh" --ledger "$led" set acme/w#10 worktree "\"$tmp/plain\"" >/dev/null
check "a plain directory is no worktree either, and is left" 'not a worktree yes' "$(W remove --ledger "$led" acme/w#10 | jq -r .reason) $([ -d "$tmp/plain" ] && echo yes)"
check "a key the ledger does not hold exits 1" 1 "$(W remove --ledger "$led" acme/w#99 >/dev/null 2>&1; echo $?)"

# --- the self-contained form a remote entry takes: the entry's fields as flags ---------------------
add_wt remote --push
out=$(W remove --key acme/w#11 --path "$repo/wt-remote" --branch feat/remote --stage settled --kind ship --merged true)
check "flags in place of the ledger remove the same way" 'true yes' "$(jq -r .removed <<<"$out") $(branch_exists remote)"
add_wt remote2
out=$(W remove --key acme/w#12 --path "$repo/wt-remote2" --branch feat/remote2 --stage settled --kind ship --merged false)
check "the flag form keeps unpushed work with no merged PR" unpushed "$(jq -r .reason <<<"$out")"
out=$(W remove --key acme/w#12 --path "$repo/wt-remote2" --branch feat/remote2 --stage running --kind ship --merged true 2>/dev/null); rc=$?
check_rc "the flag form refuses an open stage too" 1 "$rc"
check_rc "flags with no --path exit 2" 2 "$(W remove --key k --branch b --stage settled --kind ship --merged true >/dev/null 2>&1; echo $?)"
check "the script sources nothing, so it can travel to a machine with no checkout" 0 "$(grep -c '^source\|^\. ' "$s/worktree.sh")"

# --- the worktree must be on the ledger's branch: any other head may hold commits nobody checked ---------
add_wt other --push; entry other settled ship merged 13
G -C "$repo/wt-other" checkout -q --detach
G -C "$repo/wt-other" commit -q --allow-empty -m "detached work"
out=$(W remove --ledger "$led" acme/w#13); rc=$?
check_rc "a detached head is kept, exit 0" 0 "$rc"
check "with the reason naming the branch it is not on" "head is not feat/other" "$(jq -r .reason <<<"$out")"
check "and the directory is still there" yes "$(exists other)"

# --- the key may come before --ledger ------------------------------------------------------------------
add_wt order --push; entry order settled ship merged 14
check "a key before --ledger removes the same" true "$(W remove acme/w#14 --ledger "$led" | jq -r .removed)"

# --- nothing is ever forced ---------------------------------------------------------------------
check "the script holds no --force and no branch delete" 0 "$(grep -cE -- '--force|branch -[dD]|branch --delete' "$s/worktree.sh")"

finish
