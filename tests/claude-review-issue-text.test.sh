#!/usr/bin/env bash
# The Claude reviewer's `id: issue` step writes the text of the issues a PR
# closes that the round may read as spec, keeping only what an author with push
# access wrote, asked through the collaborator permission route rather than
# `author_association`: an org MEMBER or an outside COLLABORATOR can hold read
# access only. The step's script is lifted from both template shapes and this
# repo's workflow, which must carry it unchanged, and run against a `gh` stub
# that answers each route from a fixture file, applying `--jq` as gh would, and
# fails where no file exists. No call here reaches a host.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

tpl=skills/setup-skills/reviewers/github-claude-review.md
own=.github/workflows/claude-review.yml

# <file> [<nth>]: the `run:` body of the nth `id: issue` step, dedented.
step_script() {
  awk -v want="${2:-1}" '
    /^ *- id: issue$/ { if (++seen == want) s = 1; next }
    s && !r && /^ *run: \|$/ { r = 1; next }
    r { if ($0 == "") { print; next }
        match($0, /^ */)
        if (!ind) ind = RLENGTH
        if (RLENGTH < ind) exit
        print substr($0, ind + 1) }' "$1"
}

script=$(step_script "$tpl" 1)
check "the on-push shape carries the step" "yes" "$([ -n "$script" ] && echo yes || echo no)"
check "the on-request shape carries the same step" "$script" "$(step_script "$tpl" 2)"
check "this repo's workflow carries the same step" "$script" "$(step_script "$own")"

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin" "$work/fix" "$work/tmp"
cat > "$work/bin/gh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FIX/calls"
filter=. pos=()
while [ $# -gt 0 ]; do
  case $1 in
    --jq) filter=$2; shift 2 ;;
    --repo|--json) shift 2 ;;
    -*) shift ;;
    *) pos+=("$1"); shift ;;
  esac
done
case ${pos[0]} in
  pr) route="pr_${pos[2]}" ;;
  api) route=$(printf '%s' "${pos[1]}" | tr '/' '_') ;;
esac
[ -f "$FIX/$route" ] || { echo "gh: Not Found (HTTP 404)" >&2; exit 1; }
jq -r "$filter" "$FIX/$route"
STUB
chmod +x "$work/bin/gh"

# <pr>: runs the step for that PR; prints its exit code.
run_step() {
  rm -f "$work/tmp/linked-issue.md"
  (export PATH="$work/bin:$PATH" FIX="$work/fix" RUNNER_TEMP="$work/tmp" REPO=o/r PR="$1"
   bash -e -o pipefail -c "$script" >/dev/null 2>&1)
  printf '%s' "$?"
}

f=$work/fix
printf '%s\n' '{"closingIssuesReferences":[
  {"number":5,"repository":{"name":"r","owner":{"login":"o"}}},
  {"number":9,"repository":{"name":"other","owner":{"login":"o"}}}]}' > "$f/pr_1"
printf '%s\n' '{"user":{"login":"writer"},"body":"the body"}' > "$f/repos_o_r_issues_5"
printf '[%s]\n' '
  {"user":{"login":"writer"},"body":"a writer comment"},
  {"user":{"login":"reader"},"body":"a reader comment"},
  {"user":{"login":"app[bot]"},"body":"a bot comment"},
  {"user":{"login":"gone"},"body":"a failed lookup comment"},
  {"user":null,"body":"a deleted account comment"}' > "$f/repos_o_r_issues_5_comments"
perm() { printf '{"user":{"permissions":{"push":%s}}}\n' "$2" > "$f/repos_o_r_collaborators_$1_permission"; }
perm writer true; perm reader false; perm 'app%5Bbot%5D' false

check_rc "a PR closing an issue resolves its text" 0 "$(run_step 1)"
check "only the text of an author with push reaches the prompt input" "# Issue #5

the body

# Comment on #5

a writer comment" "$(cat "$work/tmp/linked-issue.md")"
check "another repo's closing issue is not read" "" "$(grep 'issues/9' "$f/calls")"
check "one permission call per distinct author, the login URI-encoded" \
  "api repos/o/r/collaborators/app%5Bbot%5D/permission --jq .user.permissions.push
api repos/o/r/collaborators/gone/permission --jq .user.permissions.push
api repos/o/r/collaborators/reader/permission --jq .user.permissions.push
api repos/o/r/collaborators/writer/permission --jq .user.permissions.push" \
  "$(grep collaborators "$f/calls" | sort)"

printf '{"closingIssuesReferences":[]}\n' > "$f/pr_2"
check_rc "a PR closing no issue is not a failure" 0 "$(run_step 2)"
check "a PR closing no issue leaves the file empty" "0" "$(wc -c < "$work/tmp/linked-issue.md" | tr -d ' ')"

check_rc "a failed read of the PR fails the step" 1 "$(run_step 3)"

finish
