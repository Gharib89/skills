---
status: accepted
---

# Clean-gate evidence covers the head

Before this decision, the clean gate compared heads only for the Local gate record and CI. A reviewer's `Stop: <reviewer>: tree unchanged` line and a Verification's `pass` named no head. So a change the human asked for at the merge gate, a fix pushed after the review loop ended, or a base merge after `stale-base` could merge under `Merge: on-clean-gate` with no reviewer having read the new diff and no Verification having proved it. Now each piece of evidence names the head it was recorded on, and the gate holds unless that head is a **covered head**.

Two rules decide coverage, and both were weighed against strict SHA equality.

- **Clean base merges keep coverage.** In a supervised batch the base moves after every merge, so each PR still open gets a base merge before its own merge. Under strict SHA equality every one of those PRs would lose its reviewer stops and Verification results, and auto-merge would end for the batch. A base merge that `git merge-tree --write-tree` reproduces exactly adds nothing the PR's author wrote: the base was reviewed in its own PR. A merge that resolved a conflict holds new code, so it breaks coverage. So does a merge whose second parent is not on the base, or any ordinary commit.
- **Verifications are keyed by path, and reviewers are not.** A Verification proves one real-world path, so a later change that touches none of its files leaves its proof standing. Its profile entry can say which files those are with an optional `Paths:` line of git glob pathspecs. Without `Paths:`, any break in coverage holds the gate. A reviewer reads the whole diff, so a reviewer stop has no paths to key on: any break holds it.

The Local gate record stays strict, because re-running the gate on the final head is cheap and the merge gate already does it.

## Considered options

- Strict SHA equality for every piece of evidence: simplest, but it ends auto-merge in supervised batches.
- Re-requesting a review from the merge gate when the head moved: it adds polling and spends review quota for a lint fix. Holding the gate and letting the human say "merge" costs one reply.
- Coverage by clean base merge, plus `Paths:` for Verifications (chosen). Settled in the #637 triage grilling.
