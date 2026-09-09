---
status: accepted
---

# Ship writes only to the repo it runs in

A Ship run sometimes meets a defect in Ship itself (a missing generic mechanic, wrong prose) while working a repo's issue. It could file that upstream to the skill's source repo, but a derived copy running inside a client's repo has only that host's credentials (an Azure DevOps run cannot reach GitHub), would carry the client run's context into a repo the client does not control, and would have to judge what counts as "about Ship" with no reader in the client repo to catch a misfile. So a Ship defect is a named row in the merge summary, the human carries it upstream, and no mechanic writes outside the repo whose remote the run read.

## Considered options

- A `Source:` line in the ship profile naming the upstream repo, read by `file-issue` for Ship defects: configurable, but every drawback above still holds, and it bumps the profile schema for every repo.
- A fixed upstream target baked into Ship: same drawbacks, and it couples every derived copy to one repo, against the rule that a repo expresses its differences through its own docs.
- Report in the merge summary and let the human carry it upstream (chosen): the human at the merge gate is the only reader who has both the run's context and the right to decide what leaves the repo.

Decided in Gharib89/skills#54, from the smoke run recorded in #51.
