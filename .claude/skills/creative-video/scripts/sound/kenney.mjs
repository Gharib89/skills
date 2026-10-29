// The Kenney word index, setup/kenney-index.json: for each pack the
// sounds:kenney row pins, each file stem's words saying what the sound is,
// beside the words its file name gives, and `loop: true` on a stem whose
// files loop as a bed. Setup refuses a pack holding a stem it lacks, and the
// sha256 pins keep the packs it describes fixed.
import fs from "node:fs";

export const INDEX = JSON.parse(
  fs.readFileSync(
    new URL("../../setup/kenney-index.json", import.meta.url),
    "utf8",
  ),
);

export const AUDIO = /\.(ogg|wav|mp3)$/i;

// A file's stem: its name less its extension and numbering
// (`doorClose_1.ogg` and `jingles_NES07.ogg` give `doorClose` and
// `jingles_NES`).
export const stemOf = (file) =>
  file.replace(/\.\w+$/, "").replace(/[_ -]?\d+$/, "");
