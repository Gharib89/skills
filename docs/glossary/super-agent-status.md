### Super agent: the status block and needs

**Status block**:
The one report the owner reads, printed by every reconcile from the ledger alone and posted as printed in chat: the needs-you message first, then the rows `Merged`, `Running`, `Yours`, `Waiting` and `Reviewer limit`, an empty row left out, each ticket a link and each task or adopted entry marked as one, ending on the provider instance the super agent itself runs on. A wake that changed nothing and raised no need posts none, and nothing is pushed; a digest prints the whole block on the owner's "status", at the morning report and when the waiting list empties.
_Avoid_: report (prose written fresh on each wake), summary, dashboard

**Needs-you message**:
The opening of the status block: every open need printed in full, blocking needs first, each its question with its ticket linked, a `Why:` line and its options numbered from 1 with the recommended one first (or where to answer it), at most 6 lines a need. It prints when the needs change or one is raised, and the owner answers `88 1`.
_Avoid_: Needs you row, push

**Blocking need**:
A need whose thread or the queue is stopped until the owner acts (a held call, a merge-gate hold, a scope fork, a stall at the cap), set by its reason word. It prints bold, before the offers, and is raised once more after 4 working hours open, never again.
_Avoid_: urgent need

**Offer**:
A need nothing waits on (a daily offer, an unqueued issue, an ask-first fix), set by its reason word. It prints behind `Offer:` and is never reminded.
_Avoid_: suggestion, optional need

**Acknowledge mark**:
A ledger mark (`ledger ack <key> --reason <word>`) that quiets an escalate row needing nothing of the owner yet, with no need and no line in the block. It lapses when the entry's stage changes.
_Avoid_: "Nothing yet" need, snooze
