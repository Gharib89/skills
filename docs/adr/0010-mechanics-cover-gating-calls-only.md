---
status: accepted
---

# Mechanics cover gating calls only, and a Ship defect never holds the gate

Before this decision, every host write and every gating read in a Ship run had to go through a generic mechanic, any gap was a Ship defect with a drafted issue, and a clean gate required that no Ship defect was met. So a write nothing depends on, like retitling an issue after phase 1 narrowed it (#666), either grew a new mechanic or stopped an unattended merge whose CI, review and criteria were all green.

Now only a **gating call**, a host read or write that a later phase, a stop row, the merge or the release depends on, must go through a mechanic. Any other host call is a **direct call**: the run makes it itself through the host's REST form (`gh api`, `az rest`) and logs it in the Run file's `## Direct calls`. REST, because the cloud sandbox's proxy refuses GitHub GraphQL, which commands like `gh issue edit` use: its 403 reads "GitHub GraphQL is not available from Claude Code sessions; use the REST API" (measured on unattended fires, #254). A direct call made in two runs is raised as a Ship note, the signal that it may earn a mechanic. A Ship defect is a gap that broke or misled the run, it is still reported with a drafted issue, and it never holds a clean gate on its own: when a defect really breaks a gating step, the gate already fails on that step's evidence. Friction the run worked around is a **Ship note**, one line on the merge summary and in the PR body, with no draft, so a retro can find it after the run's files are gone.

The line sits at gating because that is where a mechanic's guarantees (a read-back after every write, the host's status on a failure, the same verdict from the same host state on both hosts) protect something: a wrong PR title becomes a wrong squash subject and a wrong release grade, while a wrong issue title misleads nobody downstream.

## Considered options

- Keep every write behind a mechanic: each new write the agent needs costs a mechanic, both host adapters and tests, or a Ship defect.
- Only gating reads and the merge behind mechanics: the PR title and body lose their read-back, and they feed the squash subject and the merge gate.
- No rule at all: Azure DevOps parity and the cloud sandbox's refusal of GitHub GraphQL stop being handled anywhere.
- Gating calls only (chosen). Settled in the #666 triage grilling.
