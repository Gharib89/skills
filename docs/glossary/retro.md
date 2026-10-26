### Retro

**Retro run**:
One scheduled cloud run that reads the git host's record of a week's merged PRs, finds the classes of mistake that recurred across two or more of them and were never filed before, and files them as one grouped issue for triage. It never changes code or instructions itself: the human re-enters at triage, and Ship builds what triage accepts.
_Avoid_: retrospective (the attended `/retro`, which reads one session's local logs), fire (one `cloud-ship` run), weekly retro
