// The code that draws, measures and judges a scene, read for the gates cache
// key: a change to any of these files invalidates what the gates cached.
import fs from "node:fs";
import { fileURLToPath } from "node:url";

export const source = [
  "../render/compose.mjs",
  "gates.mjs",
  "source.mjs",
  "captions.mjs",
  "events.mjs",
  "reading.mjs",
  "scene.mjs",
  "sheets.mjs",
  "verdict.mjs",
  "../lib/backend.mjs",
  "../lib/backend/common.mjs",
  "../lib/backend/browser.mjs",
  "../lib/backend/media.mjs",
  "../lib/backend/voice.mjs",
  "../lib/backend/source.mjs",
  "../lib/layout.mjs",
  "../lib/motion.mjs",
  "../lib/terms.mjs",
  "../lib/style.mjs",
].map((f) =>
  fs.readFileSync(fileURLToPath(new URL(f, import.meta.url)), "utf8"),
);
