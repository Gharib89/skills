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
