/* The Submit's doorbell of creative-video's storyboard page, a classic script loaded before page.js,
   which calls armed, ring and outcome. Split from page.js to keep each file within the token limit. */

// The Submit's doorbell. An unarmed session writes `wake: false` on its board: with no watch, a send
// wakes a cloud session that replies without this session's context and resolves the thread, so the
// page only saves and the human types `submitted` in the chat.
const armed = (S) => S.board.wake !== false;
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
