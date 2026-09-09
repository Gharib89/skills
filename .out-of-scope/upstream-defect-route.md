# Upstream route for Ship defects

Ship does not file issues to its own source repo, or to any repo other than the one the run is in. A defect in Ship found during a run is reported in the merge summary's `Ship defects:` row and carried upstream by the human.

## Why this is out of scope

Every Ship write goes through a generic mechanic whose host adapter is chosen from the repo's `origin` remote, with that host's credentials. An upstream route breaks three things at once:

- **Credentials.** A run on an Azure DevOps repo has `az` auth only. The upstream is GitHub. The route would be unavailable in the cloud unattended lane, the one place a human is not present to carry the defect by hand.
- **Confidentiality.** The issue would be written from inside a client repo's run and carry that run's context (PR titles, repo names, gate output) into a repo the client does not control.
- **Classification.** "About Ship" is the agent's call. A repo problem misfiled upstream disappears from the repo's tracker, where the people who can fix it look. Adjacent finds have no cap today because the human reads `Issues filed`; an upstream target has no such reader in the run's repo.

A profile-level `Source:` line makes the target configurable but keeps every drawback and bumps the profile schema for all repos. See `docs/adr/0001-ship-writes-only-to-its-own-repo.md`.

## Prior requests

- #51 (second comment): "a `Source:` line in the profile's `### Ship` block or a fixed `Gharib89/skills` target in `reflect`"
- #54: "adjacent finds about ship itself have no upstream route" (options 1 and 2)
