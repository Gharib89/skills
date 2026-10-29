// The Kenney word index, setup/kenney-index.json. For each pack the
// sounds:kenney row pins, it maps each file stem to `words` saying what the
// sound is, added to its file name's words, and `loop: true` on a stem whose
// every file's loop seam measures clean (the last-to-first sample jump within
// the file's 99th-percentile step, the last and first 50 ms within 3 dB RMS),
// so it loops as a bed; a 5 s length alone is no mark. Setup refuses a pack holding a stem the index lacks, so
// a new pack or sha256 pin lands with its stems indexed.
import fs from "node:fs";
import { parseJson } from "../lib/json.mjs";

const NAME = "setup/kenney-index.json";
let index;
// The index, read on first use, so a malformed one is refused by the stage
// reading it, after its handler is set, never at import.
export const kenneyIndex = () =>
  (index ??= parseJson(
    NAME,
    fs.readFileSync(new URL(`../../${NAME}`, import.meta.url), "utf8"),
  ));

export const AUDIO = /\.(ogg|wav|mp3)$/i;

// A file's stem: its name less its extension and numbering
// (`doorClose_1.ogg` and `jingles_NES07.ogg` give `doorClose` and
// `jingles_NES`).
export const stemOf = (file) =>
  file.replace(/\.\w+$/, "").replace(/[_ -]?\d+$/, "");

// A pack file's index entry: `words`, its name's (camelCase split, lowercased)
// and the index's for its stem, and its stem's `loop`; undefined for a stem
// the index lacks.
export function entryOf(pack, file) {
  const stem = stemOf(file);
  const entry = kenneyIndex()[pack]?.[stem];
  if (!entry) return undefined;
  const name = stem
    .replace(/([a-z])([A-Z])/g, "$1 $2")
    .toLowerCase()
    .match(/[a-z]+/g);
  return { words: [...name, ...entry.words], loop: entry.loop === true };
}
