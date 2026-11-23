---
status: accepted
---

# A grilling session wakes on a Submit comment

`grill-with-artifact` puts each grilling round on an artifact page, and the human answers there. On Submit the page does two things: it saves the answers to the page's own database, and it posts a comment sent to Claude, anchored on the Submit button. The comment is what starts the session's next turn. The session reads the answers from the database, posts the next round, and then resolves the Submit thread. The platform's own reply in the thread serves as the receipt, so the skill posts no reply of its own.

The comment is a doorbell. A comment sent to Claude is the only thing a page can do that starts a turn in the watching session: database writes and self-republishes notify nothing, and the page's live room can only stage a message for the viewer to send. The comment carries the answers as well, capped at 4 KiB, so a round whose database write failed is still readable.

## Considered options

- The human types "submitted" in the terminal after answering: always works, but it brings back the terminal round trip this skill exists to remove. It remains the fallback when the watch is not armed or the viewer cannot send to Claude.
- The page's live room: it cannot start a turn by itself, and the room's agent peer is off by default.
- The comment alone, with no database write: the 4 KiB cap truncates a round with long comments.
- The database write plus the comment (chosen). First run end to end on 2026-09-30, across rounds 2 to 4 of the design session that produced this skill.

## Amended by #1336

An unarmed send is not inert. With no armed watch in the publishing session (a T3 Code thread, measured 2026-11-23: three Submits, three threads), the Submit comment still reaches Claude: a separate cloud session receives it, replies in the thread without the grilling session's context, and resolves the thread. The page cannot tell this apart from an armed send, since `canSendToClaude()` answers `available` whenever some Claude session would answer. So an unarmed session tells the page: it writes `wake: false` on each document the page shows as open (a round here; a board or a card in `explainer-video` and `creative-video`, whose pages ring the same doorbell). On such a document a Submit saves the answers and sends no comment, and the page's receipt tells the human to type `submitted`, which is then the only bell. The armed path is unchanged.
