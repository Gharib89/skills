# Claude Code as reviewer on GitHub Actions

Scaffold for a repo whose ship profile names Claude Code as a reviewer. It comes in two shapes, and a repo takes exactly one:

- **The on-push shape.** The repo has no other reviewer. Claude reviews every push to an open PR, so it is the whole second pair of eyes, and its job lands a check run on the PR head.
- **The on-request fallback shape.** The repo already has a reviewer (Copilot, CodeRabbit) and this one stands in for it on the month its quota runs out. A PR comment is the trigger, so nothing fires while the primary is healthy. See [ADR 0002](https://github.com/Gharib89/skills/blob/main/docs/adr/0002-fallback-reviewer-is-on-request-and-conditional.md) for why a fallback is on-request and never on-push.

What both shapes do the same way, because ship reads a round off the host and never off the workflow's logs:

- **One formal pull request review per round**, submitted in a single call, with every inline finding attached to it, and a body of exactly `no findings` when the PR is clean. A reviewer that stays silent on a clean PR cannot be told apart from one that failed, and the run waits out its whole poll window either way.
- **`--model claude-opus-5`.** A review is judgment work: a cheaper tier reads the diff and misses the standards violation in it.
- **`claude_code_oauth_token`** from the `CLAUDE_CODE_OAUTH_TOKEN` secret, minted by `claude setup-token`, so the review is billed to a Claude subscription rather than to API credit.
- **`actions/checkout` before the action.** The action does not clone the repo, and it runs `git diff --name-only -z --relative --ignore-submodules HEAD --` in the workspace of its own accord, before the prompt runs. With no checkout that fails the job outright, `Action failed with error: ... warning: Not a git repository.`, and the prompt is never reached: no review, no findings, and nothing on the PR to say why. Observed on run 34847733490 of this repo. Step 1 of the prompt needs it a second time, to read the instructions file off the filesystem.

Replace `__INSTRUCTIONS__` with the profile's `Instructions:` path for this reviewer: the repo's reviewer brief where it has one (a repo with Copilot keeps it at `.github/copilot-instructions.md`), else the `## Coding standards` path. The reviewer reads that file, never a copy of it. Where `__INSTRUCTIONS__` is the standards path itself, delete `Read the standards file it points at as well.` from the prompt.

The two YAML blocks below are each complete on purpose: a consumer copies one of them whole, and a shared block plus a list of substitutions is where a workflow that fails on indentation comes from.

Two human steps belong to both shapes, so each checklist below carries only what is its own:

1. Settings > Secrets and variables > Actions > New repository secret: `CLAUDE_CODE_OAUTH_TOKEN`, from `claude setup-token` on your own machine. The token expires: a reviewer that stops arriving with no change to the workflow is an expired token, re-minted the same way.
2. Settings > Actions > General > Workflow permissions: the job-level `permissions:` block grants what the job needs; where the org restricts job-level permissions, an org admin must allow `pull-requests: write` for this repo.

## The on-push shape

A `pull_request` event from a fork never sees the secret, so a fork PR draws no round. Leave those unreviewed; nothing in the profile changes.

### `.github/workflows/claude-review.yml`

```yaml
name: Claude PR Review

# On-push: every push to an open PR draws a fresh round, which is what
# `Trigger: on-push` in the profile means, and convergence needs this reviewer
# quiet on the current head. The job lands a check run on the PR head, so it is
# a CI leg as well as a reviewer: name it on `## CI`'s `Legs:` line, or
# `ci-wait` will not wait for it.
on:
  pull_request:
    types: [opened, synchronize, reopened]

permissions:
  contents: read
  pull-requests: write
  issues: read
  id-token: write

jobs:
  review:
    runs-on: ubuntu-latest
    steps:
      # Not optional: the action runs `git diff ... HEAD` in the workspace
      # before the prompt runs, and fails the whole job with "Not a git
      # repository" when there is nothing checked out. A `pull_request`
      # checkout is the PR's merge ref, so the instructions file read here is
      # the PR's own version of it.
      - uses: actions/checkout@v6
        with:
          fetch-depth: 1

      - uses: anthropics/claude-code-action@v1
        with:
          claude_code_oauth_token: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
          prompt: |
            REPO: ${{ github.repository }}
            PR NUMBER: ${{ github.event.pull_request.number }}

            You are reviewing this pull request. The PR branch is checked out in
            the working directory.

            1. Read `__INSTRUCTIONS__` with the Read tool. It is your brief: it names the
               coding standards to review against and the things that are not
               findings in this repo. Read the standards file it points at as well.
            2. Run `gh pr view ${{ github.event.pull_request.number }} --json title,body`
               and find the linked issue (Closes/Fixes/Resolves #N). If one exists,
               run `gh issue view N` and treat it as the spec for this change.
            3. Run `gh pr diff ${{ github.event.pull_request.number }}` and review
               only the changed lines against (a) the brief and the standards it
               names and (b) the linked issue.

            Report the round as ONE formal pull request review, submitted in a
            single call, with every inline finding attached to it:

                gh api --method POST \
                  repos/${{ github.repository }}/pulls/${{ github.event.pull_request.number }}/reviews \
                  --input -

            reading this JSON on stdin:

                {"event": "COMMENT",
                 "body": "<the round's text, or exactly `no findings`>",
                 "comments": [{"path": "<file>", "line": <line in the new file>,
                               "side": "RIGHT", "body": "<one finding>"}]}

            One entry in `comments` per finding tied to a line, each naming the
            rule or issue requirement broken and the concrete fix. A finding you
            cannot anchor to a line in the diff goes in `body`, never in
            `comments`: GitHub rejects the entire call when one `comments` entry
            names a line outside the diff, and a rejected call is a round the run
            never sees.

            Submit exactly one review, even when you found nothing: a reviewer
            that stays silent on a clean PR cannot be told apart from one that
            failed, and the run waits out its whole poll window either way. With
            nothing actionable, send `body` of exactly `no findings` and an empty
            `comments` list. No LGTM, no praise, no summary of the diff.
          claude_args: |
            --model claude-opus-5
            --max-turns 30
            --allowedTools "Read,Grep,Glob,Bash(gh api:*),Bash(gh pr diff:*),Bash(gh pr view:*),Bash(gh issue view:*)"
```

### Human checklist

Both shared steps above, then:

1. Merge the workflow to the default branch. A `pull_request` event runs the workflow from the PR's own merge ref, so the PR that adds this file is reviewed by it, unlike the fallback shape.
2. Add the job to `## CI`'s `Legs:` in `docs/agents/ship.md`. It lands a check run on the PR head, and `Legs:` is where a run reads what that check proves.
3. For `Gating: yes`: Settings > Branches (or Rules) > require the `review` check to pass before merging.

### Profile block this produces

```markdown
### Claude Code
Login: github-actions[bot]
Trigger: on-push
Request: None.
Cap: <step 4's answer; recommend 3>
Resolve: resolve-thread
Gating: no
Fallback-for: None.
Instructions: __INSTRUCTIONS__
```

## The on-request fallback shape

Replace `__PHRASE__` with the phrase that triggers a round, `@claude` unless something else in the repo already answers to it, and `__PRIMARY__` with the `### <name>` of the reviewer this one stands in for, exactly as the profile spells it. The two must agree with the profile: ship posts `__PHRASE__` as a PR comment and nothing else starts a round, and it requests this reviewer only when `__PRIMARY__` exits degraded. The `if:` tests for the phrase anywhere in a comment body, so any comment that merely mentions it, a quote of an earlier request included, spends a round: pick a phrase nobody types in passing.

### `.github/workflows/claude-review.yml`

```yaml
name: Claude PR Review

# On-request: one round per request, and the request is a PR comment carrying
# `__PHRASE__`, which is what `Request: comment __PHRASE__` in the profile asks
# for. There is deliberately no `pull_request` trigger: it would fire on every
# push, and a reviewer that cannot be withheld cannot be a fallback. It also
# keeps this workflow off the PR head, so it lands no check run and is not a
# CI leg.
on:
  issue_comment:
    types: [created]

permissions:
  contents: read
  pull-requests: write
  issues: read
  id-token: write

jobs:
  review:
    # An issue_comment fires on issues too, so the PR test comes first. A run
    # that starts and finds nothing to review still costs minutes and still
    # shows up in the Actions tab as a review that happened. No commenter test:
    # the identity a run requests a round under has to pass whatever this `if:`
    # says, and a reviewer that silently declines to fire is the failure a
    # fallback exists to prevent. The checklist's "Decide who may spend the
    # token" step is where that is narrowed on purpose.
    if: >-
      github.event.issue.pull_request != null &&
      contains(github.event.comment.body, '__PHRASE__')
    runs-on: ubuntu-latest
    steps:
      # Not optional: the action runs `git diff ... HEAD` in the workspace
      # before the prompt runs, and fails the whole job with "Not a git
      # repository" when there is nothing checked out. An issue_comment
      # checkout is the default branch, never the PR head, and that is the
      # right instructions file to review against: the canonical one, not the
      # version the PR under review proposes. The reviewed diff comes from
      # `gh pr diff`, so the PR head is never needed on disk.
      - uses: actions/checkout@v6
        with:
          fetch-depth: 1

      - uses: anthropics/claude-code-action@v1
        with:
          claude_code_oauth_token: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
          prompt: |
            REPO: ${{ github.repository }}
            PR NUMBER: ${{ github.event.issue.number }}

            You are reviewing this pull request.

            1. Read `__INSTRUCTIONS__` with the Read tool. It is your brief: it names the
               coding standards to review against and the things that are not
               findings in this repo. Read the standards file it points at as well.
            2. Run `gh pr view ${{ github.event.issue.number }} --json title,body`
               and find the linked issue (Closes/Fixes/Resolves #N). If one exists,
               run `gh issue view N` and treat it as the spec for this change.
            3. Run `gh pr diff ${{ github.event.issue.number }}` and review only
               the changed lines against (a) the brief and the standards it names
               and (b) the linked issue.

            Report the round as ONE formal pull request review, submitted in a
            single call, with every inline finding attached to it:

                gh api --method POST \
                  repos/${{ github.repository }}/pulls/${{ github.event.issue.number }}/reviews \
                  --input -

            reading this JSON on stdin:

                {"event": "COMMENT",
                 "body": "<the round's text, or exactly `no findings`>",
                 "comments": [{"path": "<file>", "line": <line in the new file>,
                               "side": "RIGHT", "body": "<one finding>"}]}

            One entry in `comments` per finding tied to a line, each naming the
            rule or issue requirement broken and the concrete fix. A finding you
            cannot anchor to a line in the diff goes in `body`, never in
            `comments`: GitHub rejects the entire call when one `comments` entry
            names a line outside the diff, and a rejected call is a round the run
            never sees.

            Submit exactly one review, even when you found nothing: a fallback
            reviewer that stays silent on a clean PR cannot be told apart from one
            that failed, and the run waits out its whole poll window either way.
            With nothing actionable, send `body` of exactly `no findings` and an
            empty `comments` list. No LGTM, no praise, no summary of the diff.
          claude_args: |
            --model claude-opus-5
            --max-turns 30
            --allowedTools "Read,Grep,Glob,Bash(gh api:*),Bash(gh pr diff:*),Bash(gh pr view:*),Bash(gh issue view:*)"
```

### Human checklist

Both shared steps above, then:

1. **Merge the workflow to the default branch before expecting a round.** GitHub dispatches an `issue_comment` workflow from the default branch only, so this file reviews nothing while it is still on a branch: the PR that adds it cannot be reviewed by it, and the first round is on the next PR.
2. Nothing to configure as a check or a policy. The job lands no check run on the PR head, so `## CI` names no leg for it and `No-checks legal:` is unaffected.
3. Post `__PHRASE__` on an open PR by hand once, after the merge, and confirm one formal review comes back. That proves the secret, the permissions and the trigger phrase in one go, and it is the only proof before a degraded primary needs this reviewer for real.
4. Decide who may spend the token. The `if:` above fires for any commenter, a drive-by on a public repo included. To narrow it, replace the whole `if:` with this one:

   ```yaml
    if: >-
      github.event.issue.pull_request != null &&
      contains(github.event.comment.body, '__PHRASE__') &&
      contains(fromJSON('["OWNER", "MEMBER", "COLLABORATOR"]'), github.event.comment.author_association)
   ```

   Weigh it first: whatever identity a ship run requests a round under must fall inside that list, and an unattended run whose identity does not gets no review and no error, the silent failure a fallback exists to prevent. A private repo where every commenter can already push needs no clause.

### Profile block this produces

```markdown
### Claude Code
Login: github-actions[bot]
Trigger: on-request
Request: comment __PHRASE__
Cap: <step 4's answer; recommend 2>
Resolve: None.
Gating: no
Fallback-for: __PRIMARY__
Instructions: __INSTRUCTIONS__
```

`Login:` is `github-actions[bot]` in both shapes because a workflow reviews under the Actions identity, not under a bot account of its own. `Resolve:` is `None.` here and `resolve-thread` in the on-push shape: the label is an on-push field, and an on-request round is answered on the review rather than resolved thread by thread.
