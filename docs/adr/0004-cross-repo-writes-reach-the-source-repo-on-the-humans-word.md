---
status: accepted
---

# Cross-repo writes reach the source repo on the human's word

Supersedes 0001. Two writes now leave the repo a run works in, and both go to the source repo (`Gharib89/skills`), never to a third repo:

- A **Ship defect** met in a consumer repo. Ship drafts the source-repo issue, names it on the merge summary's `Ship defects:` row, and files it through `file-issue --repo` only when the human says so at the merge gate. A profile defect stays in the consumer repo as an adjacent find.
- **Upstream drift** found by `update-skills`: one open issue in the source repo, rewritten in place on each run and closed by the source repo's own refresh. Its body holds skill names and refs, no consumer context.

0001's reasons still hold, so each is answered rather than dropped. The source repo is public, and a defect's text can carry a client run's context: the human at the merge gate reads the draft before it leaves, so the decision stays with the only reader who has the context and the right. An Azure DevOps run has no GitHub credentials: where the source repo's host is unreachable, the mechanic prints the exact command instead of filing. The misfile risk is the ship-versus-profile split, which the same human confirms.

`update-skills` also calls Ship's generic mechanics by path (`isolate`, `open-pr`, `file-issue`) rather than through the Skill tool, the one skill that does. It installs those scripts, so it cannot run against a Ship other than the one it just refreshed.

## Considered options

- Ship files source-repo issues on its own: removes the toil, but publishes client context with no reader, and fails on every ADO run.
- Keep 0001 and let the human re-type each defect upstream (the old decision): safe, but the toil meant defects went unfiled.
- Draft, then file on the human's word, printing the command when the host is unreachable (chosen).
- For `update-skills`' PR: raw `gh`/`az` calls (duplicates both host adapters), or filing a refresh issue and running `/ship` on it (the run would refresh the Ship it is executing).
