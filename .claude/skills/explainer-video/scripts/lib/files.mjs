// What setup says about a file: its checksum and its size in words.
import crypto from "node:crypto";
import fs from "node:fs";

// A file's sha256, hashed as a stream: a checkpoint can pass the 2 GiB a file
// read takes.
export async function sha256(file) {
  const hash = crypto.createHash("sha256");
  for await (const chunk of fs.createReadStream(file)) hash.update(chunk);
  return hash.digest("hex");
}

export const formatSize = (n) =>
  n >= 1e9
    ? `${(n / 1e9).toFixed(1)} GB`
    : n >= 1e6
      ? `${Math.round(n / 1e6)} MB`
      : `${Math.max(1, Math.round(n / 1e3))} KB`;
