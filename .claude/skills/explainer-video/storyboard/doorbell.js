/* The Submit's doorbell, shared by the storyboard page and the style card page. A classic script,
   loaded after the page's core file, whose latest(S) it reads: the board or the card on show. */

// An unarmed session writes `wake: false` on its board or card: with no watch, a send wakes a cloud
// session that replies without this session's context and resolves the thread, so the page only saves
// and the human types `submitted` in the chat.
const armed = (S) => latest(S).wake !== false;
async function ring(S, comments, anchor, text) {
  if (!armed(S)) return "unarmed";
  if (!comments || !anchor) return false;
  try {
    // `available` means some Claude session answers the send, not that this one watches.
    if ((await comments.canSendToClaude()) !== "available") return false;
    await comments.sendToClaude({ anchor, text });
    return true;
  } catch (e) {
    return false;
  }
}
// A failed save leaves the comment as the only copy, so it counts as sent only when it held the whole answers.
const outcome = (saved, woke, whole) =>
  woke === "unarmed"
    ? saved
      ? "unarmed"
      : "neither"
    : woke && (saved || whole)
      ? "sent"
      : saved
        ? "saved"
        : "neither";
