# Claude Code as reviewer on Azure Pipelines

Scaffold for an Azure DevOps repo whose ship profile names Claude Code as a reviewer. A build validation policy runs the pipeline on every PR update (Azure Repos Git has no YAML `pr:` trigger; the policy is the trigger), Claude emits findings as JSON, the pipeline posts each as a PR thread and fails the build on a `critical` finding. Maps to the profile as `Trigger: on-push`, `Gating: yes` when the policy is required: a declined critical is `converged, override needed`. Threads are Azure DevOps PR threads with `fixed | closed` status. Replace `__STANDARDS__` with the profile's `## Coding standards` path.

## `azure-pipelines-claude-review.yml`

```yaml
# Runs through a Build Validation branch policy, never from a push.
trigger: none

pool:
  vmImage: ubuntu-latest

variables:
  STANDARDS_PATH: __STANDARDS__

steps:
- checkout: self
  fetchDepth: 0   # PR builds check out the merge commit; HEAD^1 is the target branch, HEAD^2 the PR tip

- script: npm install -g @anthropic-ai/claude-code
  displayName: Install Claude Code

- bash: |
    set -euo pipefail
    SCHEMA='{"type":"object","properties":{"findings":{"type":"array","items":{"type":"object","properties":{"severity":{"type":"string","enum":["critical","major","minor"]},"file":{"type":"string"},"line":{"type":"integer"},"message":{"type":"string"}},"required":["severity","file","message"]}}},"required":["findings"]}'
    PROMPT="You are reviewing Azure Repos pull request $(System.PullRequest.PullRequestId).
    HEAD is the PR merge commit; HEAD^1 is the target branch.
    1. Read the coding standards at $STANDARDS_PATH.
    2. Run 'git diff HEAD^1 HEAD' and review only the changed lines against the standards.
    3. Run 'git log --format=%B HEAD^2 -n 20' and, if a work item is referenced (#1234 or AB#1234),
       treat its intent as the spec for this change.
    Return ONLY findings that require a code change. Severity: critical = must fix before merge
    (correctness, security, data loss, a MUST rule in the standards); major = a standards rule;
    minor = style. file is repo-relative, line is the line in the new file.
    If nothing is actionable, return {\"findings\": []}. No praise, no summaries."
    claude --bare -p "$PROMPT" \
      --output-format json \
      --json-schema "$SCHEMA" \
      --allowedTools "Read,Grep,Glob,Bash(git diff *),Bash(git log *)" \
      --permission-mode dontAsk \
      --max-turns 30 \
      --max-budget-usd 5 \
      | jq '.structured_output' > "$(Build.ArtifactStagingDirectory)/findings.json"
    cat "$(Build.ArtifactStagingDirectory)/findings.json"
  displayName: Claude review (JSON findings)
  condition: eq(variables['Build.Reason'], 'PullRequest')
  env:
    ANTHROPIC_API_KEY: $(ANTHROPIC_API_KEY)   # secret variables reach scripts only through an explicit env mapping

- bash: |
    set -euo pipefail
    F="$(Build.ArtifactStagingDirectory)/findings.json"
    URL="$(System.CollectionUri)$(System.TeamProjectId)/_apis/git/repositories/$(Build.Repository.ID)/pullRequests/$(System.PullRequest.PullRequestId)/threads?api-version=7.1"
    jq -c '.findings[]' "$F" | while read -r f; do
      body=$(jq -n --argjson f "$f" '
        { comments: [{ parentCommentId: 0, commentType: 1,
                       content: ("**" + ($f.severity|ascii_upcase) + "** " + $f.message) }],
          status: 1 }
        + (if $f.line then
            { threadContext: {
                filePath: ("/" + ($f.file|ltrimstr("/"))),
                rightFileStart: { line: $f.line, offset: 1 },
                rightFileEnd:   { line: $f.line, offset: 1 } } }
           else {} end)')
      curl -sS --fail -X POST "$URL" \
        -H "Authorization: Bearer $SYSTEM_ACCESSTOKEN" \
        -H "Content-Type: application/json" \
        -d "$body" > /dev/null
    done
    crit=$(jq '[.findings[] | select(.severity=="critical")] | length' "$F")
    echo "critical findings: $crit"
    [ "$crit" -eq 0 ] || exit 1
  displayName: Post PR threads, fail on critical
  condition: eq(variables['Build.Reason'], 'PullRequest')
  env:
    SYSTEM_ACCESSTOKEN: $(System.AccessToken)   # the YAML form of "allow scripts to access the OAuth token"
```

Known gap, to settle on the first real run: the threads API documents `pullRequestThreadContext.changeTrackingId` as required for line anchoring on PRs with iterations. If threads land at PR level instead of on the line, look the id up from the PR iterations API and add it to the body.

## Human checklist

1. Pipelines > New pipeline > Azure Repos Git > this repo > Existing Azure Pipelines YAML file > `azure-pipelines-claude-review.yml` > Save (not Run). Note the `definitionId` in the URL.
2. That pipeline > Edit > Variables > New variable `ANTHROPIC_API_KEY`, "Keep this value secret" > Save.
3. Project Settings > Repositories > this repo > Security > `<Project> Build Service (<Org>)` (or `Project Collection Build Service (<Org>)` when the job authorization scope is collection) > **Contribute to pull requests**: Allow. A `TF401027 ... PullRequestContribute` 403 on the POST means this step was missed.
4. Branch policy on the default branch (Project Administrator):
   ```sh
   az repos policy build create \
     --org https://dev.azure.com/<org> --project <project> \
     --repository-id <repoGuid> --branch main --branch-match-type exact \
     --build-definition-id <definitionId> --display-name "Claude PR review" \
     --blocking true --enabled true \
     --manual-queue-only false --queue-on-source-update-only true --valid-duration 0
   ```
   `--blocking true` is what makes the reviewer gating; `false` gives `Gating: no`.

## Profile block this produces

```markdown
### Claude Code
Login: <Project> Build Service (<Org>)
Trigger: on-push
Request: None.
Cap: None.
Resolve: threads are set to `fixed` once a finding is dispositioned; the build re-runs on the next push
Gating: yes
Instructions: __STANDARDS__
```
