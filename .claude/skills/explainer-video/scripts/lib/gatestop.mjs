// What gates.mjs writes to gates.json and board.mjs reads back for its gate-stop
// banner: one definition each, so the two cannot drift apart.
import crypto from "node:crypto";

// The script a gates record is of: each scene's id and narration.
export const scriptHash = (script) =>
  crypto
    .createHash("sha256")
    .update(JSON.stringify(script.scenes.map((s) => [s.id, s.narration])))
    .digest("hex")
    .slice(0, 16);

// Red on the third render of one script: two fix attempts spent, no video.
export const stopped = (attempts) => attempts >= 3;
