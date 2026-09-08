# Issue tracker: Azure DevOps

Issues and specs for this repo live as Azure Boards work items. Use the `az` CLI with the `azure-devops` extension (`az extension add --name azure-devops`) for all operations; where `az boards` has no subcommand, call the REST API through `az devops invoke` with the same credential.

**Work item type: Issue.** _(Set to the type your process uses for a plain ticket: `Issue` in the Basic process, `User Story` or `Bug` in Agile, `Product Backlog Item` in Scrum. Every "create" below uses it.)_

**Closed state: Done.** _(Basic uses `Done`; Agile and CMMI use `Closed`; Scrum uses `Done`. Every "close" below uses it.)_

## Conventions

- **Auth**: `az login` (Microsoft Entra), or a PAT in `AZURE_DEVOPS_EXT_PAT` for non-interactive shells. `az devops` auto-detects the organization, project and repository from the clone's remote (`dev.azure.com/<org>/<project>/_git/<repo>` or `<org>.visualstudio.com/...`); set them once with `az devops configure --defaults organization=https://dev.azure.com/<org> project=<project>` when running outside a clone.
- **Create an issue**: `az boards work-item create --type "<Work item type>" --title "..." --description "..."`. The description is HTML; wrap Markdown in `<pre>` or convert. Use a heredoc via `--description "$(cat <<'EOF' ... EOF)"` for multi-line bodies.
- **Read an issue**: `az boards work-item show --id <n> --expand all -o json` (fields, tags, assignee, relations). Comments are a separate resource: `az devops invoke --area wit --resource comments --route-parameters project=<project> workItemId=<n> --api-version 7.1-preview.4 -o json`.
- **List issues**: WIQL through `az boards query --wiql "SELECT [System.Id], [System.Title], [System.State], [System.Tags], [System.AssignedTo] FROM WorkItems WHERE [System.TeamProject] = @project AND [System.State] <> '<Closed state>' AND [System.Tags] CONTAINS 'needs-triage' ORDER BY [System.CreatedDate] ASC" -o json`. Flat queries only.
- **Comment on an issue**: `az boards work-item update --id <n> --discussion "..."`.
- **Apply / remove labels**: labels are **tags** (`System.Tags`), a single `;`-separated string that `update` replaces wholesale. Read the current value first, then write the full set: `az boards work-item update --id <n> --fields "System.Tags=needs-triage; ready-for-agent"`.
- **Assign**: `az boards work-item update --id <n> --assigned-to "<email>"`. The field is one identity; unassigned items match `[System.AssignedTo] = ''` in WIQL.
- **Close**: `az boards work-item update --id <n> --state "<Closed state>" --discussion "..."`.
- **Pull requests**: `az repos pr create --title "..." --description "..." --work-items <n>` (links the work item; add `--transition-work-items true` on `az repos pr update --status completed` so completion moves it to the closed state), `az repos pr show --id <id>`, `az repos pr list --status active`. PR comment threads have no `az repos pr` subcommand: `az devops invoke --area git --resource pullRequestThreads --route-parameters project=<project> repositoryId=<repo> pullRequestId=<id> --api-version 7.1 -o json`, and `--http-method POST --in-file body.json` to post one.

Azure DevOps numbers work items per organization and pull requests per organization in separate spaces, so `#42` is a work item unless the maintainer says PR. Commit messages and PR descriptions can mention `#42` to link the work item.

## Pull requests as a triage surface

**PRs as a request surface: no.** _(Set to `yes` if this repo treats external PRs as feature requests; `/triage` reads this flag.)_

When set to `yes`, PRs run through the same tags and states as work items, using the `az repos pr` equivalents:

- **Read a PR**: `az repos pr show --id <id> -o json` plus the threads call above; `git diff <target>...<source>` after `az repos pr checkout --id <id>` for the diff.
- **List external PRs for triage**: `az repos pr list --status active -o json`, then keep only PRs whose `createdBy` is not a project member (Azure DevOps has no author-association field; compare against `az devops security group membership list` or the team roster).
- **Comment / label / close**: post a thread via `az devops invoke` (see above), `az repos pr update --id <id> --labels`, `az repos pr update --id <id> --status abandoned`.

## When a skill says "publish to the issue tracker"

Create a work item of the configured type.

## When a skill says "fetch the relevant ticket"

Run `az boards work-item show --id <n> --expand all -o json` and the comments call.

## Wayfinding operations

Used by `/wayfinder`. The **map** is a single work item with **child** work items as tickets.

- **Map**: a work item tagged `wayfinder:map`, holding the Notes / Decisions-so-far / Fog body: `az boards work-item create --type "<Work item type>" --title "..." --description "..." --fields "System.Tags=wayfinder:map"`. (An Epic or Feature may hold the map where the process has one; a tagged work item works in every process.)
- **Child ticket**: a work item linked to the map with a **Parent** link: `az boards work-item relation add --id <child> --relation-type parent --target-id <map>`. Tag it `wayfinder:<type>` (`research`/`prototype`/`grilling`/`task`) and put `Part of #<map>` at the top of its description. Once claimed, the ticket is assigned to the driving dev.
- **Blocking**: Azure Boards' **Predecessor / Successor** dependency link (`System.LinkTypes.Dependency`), the UI-visible representation. On the blocked ticket add a Predecessor link to its blocker: `az boards work-item relation add --id <child> --relation-type predecessor --target-id <blocker>` (if the CLI rejects the name, `az boards work-item relation list-type` prints the accepted names; the reference name is `System.LinkTypes.Dependency-Reverse`). A ticket is unblocked when every predecessor is in the closed state.
- **Frontier query**: WIQL for the map's children that are open and unassigned (`[System.Parent] = <map> AND [System.State] <> '<Closed state>' AND [System.AssignedTo] = ''`), then drop any whose `--expand relations` shows an open predecessor; first in map order wins.
- **Claim**: `az boards work-item update --id <n> --assigned-to "<your email>"`, the session's first write.
- **Resolve**: `az boards work-item update --id <n> --discussion "<answer>"`, then `--state "<Closed state>"`, then append a context pointer (gist + link) to the map's Decisions-so-far.
