# Claude Code as reviewer on GitHub Actions

Scaffold for a repo whose ship profile names Claude Code as a reviewer. Reviews every push, so it maps to the profile as `Trigger: on-push`, `Resolve: None.` (no thread-resolution mechanism; convergence rests on dispositioned threads and a quiet head), `Gating: no` unless the human makes the check required. Replace `__STANDARDS__` with the profile's `## Coding standards` path; the reviewer reads that file, never a copy.

## `.github/workflows/claude-review.yml`

```yaml
name: Claude PR Review

on:
  pull_request:
    types: [opened, synchronize, reopened]

jobs:
  review:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      pull-requests: write
      issues: read
      id-token: write
    steps:
      - uses: actions/checkout@v7
        with:
          fetch-depth: 1

      - uses: anthropics/claude-code-action@v1
        with:
          anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}
          prompt: |
            REPO: ${{ github.repository }}
            PR NUMBER: ${{ github.event.pull_request.number }}

            You are reviewing this pull request. The PR branch is checked out in the
            working directory.

            1. Read the coding standards at `__STANDARDS__` with the Read tool.
            2. Run `gh pr view ${{ github.event.pull_request.number }} --json title,body`
               and find the linked issue (Closes/Fixes/Resolves #N). If one exists, run
               `gh issue view N` and treat it as the spec for this change.
            3. Run `gh pr diff ${{ github.event.pull_request.number }}` and review only
               the changed lines against (a) the standards file and (b) the linked issue.

            Report findings ONLY as GitHub comments:
            - Use `mcp__github_inline_comment__create_inline_comment` (with `confirmed: true`)
              for anything tied to a specific line. One comment per finding. State the
              rule or issue requirement violated and the concrete fix.
            - Use `gh pr comment` only for a finding that cannot be attached to a line
              (for example, the change does not implement what the issue asks).

            If there is nothing actionable, post nothing at all. No "LGTM", summaries,
            praise, or restatements of the diff. Comments are the only output.
          claude_args: |
            --allowedTools "Read,Grep,Glob,mcp__github_inline_comment__create_inline_comment,Bash(gh pr comment:*),Bash(gh pr diff:*),Bash(gh pr view:*),Bash(gh issue view:*)"
            --max-turns 30
```

## Human checklist

1. Settings > Secrets and variables > Actions > New repository secret: `ANTHROPIC_API_KEY`, value from the Claude Console.
2. Settings > Actions > General > Workflow permissions: the job-level `permissions:` block grants what it needs; if the org restricts job-level permissions, an org admin must allow `pull-requests: write` for this repo.
3. Merge the workflow to the default branch; the first review runs on the next PR.
4. Fork PRs never see the secret; leave them unreviewed.
5. For `Gating: yes`: Settings > Branches (or Rules) > require the `review` check to pass before merging.

## Profile block this produces

```markdown
### Claude Code
Login: github-actions[bot]
Trigger: on-push
Request: None.
Cap: None.
Resolve: None.
Gating: no
Instructions: __STANDARDS__
```
