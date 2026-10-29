// Canned sound sources: Openverse's search, the Kenney zips and the short-term
// loudness the bed level gate reads.
//   CREATIVE_VIDEO_FAKE_OPENVERSE  JSON: a query's answers, one per call in
//                                  order, the last repeated: `"timeout"`
//                                  throws as the real search does, a list is
//                                  its results; a query not named finds none
//   CREATIVE_VIDEO_FAKE_LOUD       JSON: a file's short-term loudness (LUFS) by
//                                  its name, else narration.wav -16, any
//                                  other file -20
import fs from "node:fs";
import path from "node:path";
import { log } from "./fake-backend-log.mjs";

const INDEX = JSON.parse(
  fs.readFileSync(
    new URL(
      "../../skills/creative-video/setup/kenney-index.json",
      import.meta.url,
    ),
    "utf8",
  ),
);

const asked = (call, query) =>
  fs
    .readFileSync(process.env.CREATIVE_VIDEO_FAKE_LOG, "utf8")
    .trim()
    .split("\n")
    .map((l) => JSON.parse(l))
    .filter((c) => c.call === call && c.query === query).length;

export async function openverse(query, { medium }) {
  log({ call: "openverse", query, medium });
  const answers =
    JSON.parse(process.env.CREATIVE_VIDEO_FAKE_OPENVERSE ?? "{}")[query] ?? [];
  const a = answers[Math.min(asked("openverse", query), answers.length) - 1];
  if (a === "timeout") throw new Error("timed out after 30 s");
  return a ?? [];
}

// A pack unpacks to its licence and one sound, of the first stem the word
// index lists for it.
export async function unzipSounds(zip, dir) {
  log({ call: "unzipSounds", zip, dir });
  const [stem] = Object.keys(INDEX[path.basename(dir)]);
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(path.join(dir, "License.txt"), "CC0");
  fs.writeFileSync(path.join(dir, `${stem}_001.ogg`), "ogg");
}

// A constant level every 0.1 s over `seconds`.
export async function shortTerm(file, seconds) {
  log({ call: "shortTerm", file: path.basename(file), seconds });
  const name = path.basename(file);
  const lufs =
    JSON.parse(process.env.CREATIVE_VIDEO_FAKE_LOUD ?? "{}")[name] ??
    (name === "narration.wav" ? -16 : -20);
  const out = [];
  for (let i = 1; i <= Math.round(seconds * 10); i++)
    out.push([+(i / 10).toFixed(3), lufs]);
  return out;
}
