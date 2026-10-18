// Appends one backend call to $EXPLAINER_VIDEO_FAKE_LOG as a JSON line.
import fs from "node:fs";

export const log = (call) =>
  fs.appendFileSync(
    process.env.EXPLAINER_VIDEO_FAKE_LOG,
    JSON.stringify(call) + "\n",
  );
