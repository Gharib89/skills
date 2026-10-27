// Appends one backend call to $CREATIVE_VIDEO_FAKE_LOG as a JSON line.
import fs from "node:fs";

export const log = (call) =>
  fs.appendFileSync(
    process.env.CREATIVE_VIDEO_FAKE_LOG,
    JSON.stringify(call) + "\n",
  );
