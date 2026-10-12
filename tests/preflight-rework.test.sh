#!/usr/bin/env bash
# `preflight <n> --rework` admits a Rework run only when the claim is the
# signed-in identity's and exactly one open PR closes the issue, its head the one
# `*-<n>` branch on origin; every other shape is `not reworkable: <detail>`.
# Admitted with no unresolved review thread and no `--feedback` is `no feedback`.
# A plain run's `already claimed`, `existing PR` and `existing branch` stay out of
# a rework run's reasons. Each shape runs under a GitHub origin and an Azure
# DevOps origin: the admission is generic, read through the Host fake
# (tests/host-fake.sh), so the host only changes which adapter detection names.
#
# Origin is a local bare repo holding the issue's branch. The checkout's origin
# URL is a bare path, so a `git` shim answers `remote get-url origin` with the
# host URL detection needs and hands every other call to the real git.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

scripts=$PWD/skills/ship/scripts
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
real_git=$(command -v git)
g() { "$real_git" -c user.name=t -c user.email=t@t -c init.defaultBranch=main "$@"; }
export SHIP_FAKE=$work/fake SHIP_HOST_ADAPTER=$PWD/tests/host-fake.sh
export GIT_ALLOW_PROTOCOL=file
mkdir -p "$work/bin"
{
  g init -q --bare "$work/origin.git"
  g clone -q "$work/origin.git" "$work/repo"
  cd "$work/repo"
  g commit -q --allow-empty -m init && g push -q origin main
  g push -q origin main:feat/y-5
} >/dev/null 2>&1 || { echo "fixture setup failed" >&2; exit 2; }
head=$(git -C "$work/repo" rev-parse HEAD)
cd - >/dev/null || exit 2

shim() { # <origin url>
  cat > "$work/bin/git" <<SHIM
#!/usr/bin/env bash
[ "\$*" = "remote get-url origin" ] && { echo $1; exit 0; }
exec "$real_git" "\$@"
SHIM
  chmod +x "$work/bin/git"
}

# The fixtures of an admitted rework: claimed by `me`, one open closing PR
# whose head is feat/y-5 at the branch's tip, one unresolved thread.
admitted() {
  rm -rf "$SHIP_FAKE"; mkdir -p "$SHIP_FAKE"
  printf 'me\n'   > "$SHIP_FAKE/host_identity.1.json"
  printf 'true\n' > "$SHIP_FAKE/host_can_push.1.json"
  jq -n '{number: 5, state: "open", is_pr: false, labels: ["ready-for-agent"], assignees: ["me"]}' \
    > "$SHIP_FAKE/host_issue_get.1.json"
  jq -n '{closing: [{number: 9, state: "open"}], mentions: []}' > "$SHIP_FAKE/host_issue_linked_prs.1.json"
  jq -n --arg h "$head" '{number: 9, state: "open", head_ref: "feat/y-5", head_sha: $h}' \
    > "$SHIP_FAKE/host_pr_get.1.json"
  jq -n '[{id: "T1", resolved: false, replied: false, author: "r", path: "a", body: "x"},
          {id: "T2", resolved: true, replied: true, author: "r", path: "a", body: "y"}]' \
    > "$SHIP_FAKE/host_pr_threads.1.json"
}
preflight() { ( cd "$work/repo" && PATH="$work/bin:$PATH" bash "$scripts/preflight.sh" "$@" 2>/dev/null ); }
# Reasons a rework decides: the profile and composes reasons a bare fixture
# repo raises are not this test's subject.
rw() { jq -c '[.reasons[] | select(test("^(not reworkable|no feedback|already claimed|existing PR|existing branch|worktree exists)"))]' <<<"$1"; }

for origin in https://github.com/owner/repo.git https://dev.azure.com/org/proj/_git/repo; do
  shim "$origin"
  h=${origin#https://}; h=${h%%/*}

  admitted
  out=$(preflight 5 --rework)
  check "$h: admitted" '[]' "$(rw "$out")"
  check "$h: the host the fake was loaded under" "$([ "$h" = github.com ] && echo github || echo ado)" \
    "$(cut -d' ' -f1 "$SHIP_FAKE/loaded")"
  check "$h: rework names the PR, its branch, head and open threads" \
    "$(jq -nc --arg h "$head" '{pr: 9, branch: "feat/y-5", head_sha: $h, worktree: null, threads: ["T1"]}')" \
    "$(jq -c .rework <<<"$out")"

  admitted
  jq '.assignees = []' "$SHIP_FAKE/host_issue_get.1.json" > "$work/i" && mv "$work/i" "$SHIP_FAKE/host_issue_get.1.json"
  check "$h: not claimed" '["not reworkable: not claimed"]' "$(rw "$(preflight 5 --rework)")"

  admitted
  jq '.assignees = ["other"]' "$SHIP_FAKE/host_issue_get.1.json" > "$work/i" && mv "$work/i" "$SHIP_FAKE/host_issue_get.1.json"
  check "$h: claimed by another" '["not reworkable: claimed by other"]' "$(rw "$(preflight 5 --rework)")"

  admitted
  jq -n '{closing: [{number: 9, state: "merged"}], mentions: []}' > "$SHIP_FAKE/host_issue_linked_prs.1.json"
  check "$h: no open PR" '["not reworkable: no open PR"]' "$(rw "$(preflight 5 --rework)")"

  admitted
  jq -n '{closing: [{number: 9, state: "open"}, {number: 11, state: "open"}], mentions: []}' \
    > "$SHIP_FAKE/host_issue_linked_prs.1.json"
  check "$h: several open PRs" '["not reworkable: several open PRs: #9, #11"]' "$(rw "$(preflight 5 --rework)")"

  admitted
  jq '.head_ref = "feat/z-5"' "$SHIP_FAKE/host_pr_get.1.json" > "$work/p" && mv "$work/p" "$SHIP_FAKE/host_pr_get.1.json"
  check "$h: branch mismatch" '["not reworkable: branch mismatch: PR #9 heads feat/z-5, origin has feat/y-5"]' \
    "$(rw "$(preflight 5 --rework)")"

  admitted
  touch "$SHIP_FAKE/host_pr_threads.1.fail"
  check "$h: threads unreadable" '["not reworkable: review threads unreadable"]' "$(rw "$(preflight 5 --rework)")"

  admitted
  touch "$SHIP_FAKE/host_issue_linked_prs.1.fail"
  check "$h: cross-references unreadable" '["not reworkable: cross-references unreadable"]' "$(rw "$(preflight 5 --rework)")"

  admitted
  touch "$SHIP_FAKE/host_pr_get.1.fail"
  check "$h: PR unreadable" '["not reworkable: PR #9 unreadable"]' "$(rw "$(preflight 5 --rework)")"

  # An answer that does not parse is unreadable too, never data.
  for fn in host_issue_linked_prs host_pr_get host_pr_threads; do
    admitted
    printf 'not json\n' > "$SHIP_FAKE/$fn.1.json"
    out=$(preflight 5 --rework)
    check "$h: unparseable $fn is one unreadable reason" 1 \
      "$(jq '[.reasons[] | select(test("^not reworkable: .*unreadable$"))] | length' <<<"$out")"
    check "$h: and admits nothing" 'false null' "$(jq -r '"\(.ok) \(.rework)"' <<<"$out")"
  done

  # No feedback: the claim, the PR and the branch are as they were, since
  # preflight wrote nothing to the host.
  admitted
  jq -n '[{id: "T2", resolved: true, replied: true, author: "r", path: "a", body: "y"}]' \
    > "$SHIP_FAKE/host_pr_threads.1.json"
  check "$h: no unresolved thread and no text is no feedback" '["no feedback"]' "$(rw "$(preflight 5 --rework)")"
  check "$h: no feedback writes nothing to the host" '' \
    "$(cut -f1 "$SHIP_FAKE/calls" | grep -vE '^host_(tooling_reasons|identity|can_push|copilot_login|issue_get|issue_linked_prs|pr_get|pr_threads|pr_for_branch)$')"
  check "$h: no feedback leaves the branch" "$head" "$(git -C "$work/origin.git" rev-parse feat/y-5)"
  check "$h: --feedback admits a PR with no open thread" '[]' "$(rw "$(preflight 5 --rework --feedback)")"
done

# An origin that cannot be listed is one reason, not a plain run's beside a
# branch mismatch.
admitted
cat > "$work/bin/git" <<SHIM
#!/usr/bin/env bash
[ "\$*" = "remote get-url origin" ] && { echo https://github.com/owner/repo.git; exit 0; }
[ "\$1 \$2" = "-C $work/repo" ] && [ "\$3" = ls-remote ] && exit 128
exec "$real_git" "\$@"
SHIM
check "origin unreadable" '["not reworkable: remote unreadable"]' "$(rw "$(preflight 5 --rework)")"

# The plain run's stops are unchanged for the same issue.
shim https://github.com/owner/repo.git
admitted
check "a plain run still stops on the claim, the PR and the branch" \
  '["already claimed: me","existing PR: #9 (open)","existing branch: feat/y-5"]' "$(rw "$(preflight 5)")"

# The worktree an ended attended run left: reused when clean and at the PR head.
admitted
"$real_git" -C "$work/repo" worktree add -q "$work/repo/.claude/worktrees/y-5" feat/y-5 2>/dev/null \
  || "$real_git" -C "$work/repo" worktree add -q -b feat/y-5 "$work/repo/.claude/worktrees/y-5" origin/feat/y-5 2>/dev/null
out=$(preflight 5 --rework)
check "a clean worktree at the PR head is reused" '[]' "$(rw "$out")"
check "rework names the reused worktree" "$work/repo/.claude/worktrees/y-5" "$(jq -r .rework.worktree <<<"$out")"
touch "$work/repo/.claude/worktrees/y-5/dirty"
check "a dirty worktree still stops" "[\"worktree exists: $work/repo/.claude/worktrees/y-5\"]" "$(rw "$(preflight 5 --rework)")"

# --rework has no unattended and no free-text form.
check_rc "--rework --unattended is a usage error" 2 "$(preflight 5 --rework --unattended >/dev/null; echo $?)"
check "--rework --unattended names the usage line" 'usage: preflight <issue|none> [--unattended] | preflight <issue> --rework [--feedback]' \
  "$(preflight 5 --rework --unattended | jq -r .error)"
check_rc "--rework on a free-text run is a usage error" 2 "$(preflight none --rework >/dev/null; echo $?)"
check_rc "--rework with free text in place of the issue is a usage error" 2 \
  "$(preflight "fix the thing" --rework >/dev/null; echo $?)"

finish
