// The `creative-videos/` folder every run folder sits in. Its `.gitignore`
// keeps a run's recipe (excerpts.json, outline.md, manifest.json, brief.json,
// script.json) committed and everything a stage can rebuild out of git.
import fs from "node:fs";
import path from "node:path";

const BEGIN = "# creative-video: begin";
const END = "# creative-video: end";
const REBUILDABLE = ["voice.json", "snapshots/", ".cache/", "out/"];
const BLOCK = `${BEGIN} (each run folder commits its recipe only)
${REBUILDABLE.map((f) => `*/${f}`).join("\n")}
${END}
`;

// The `creative-videos/` folder holding `run`: where the `.gitignore` is.
export const creativeVideosDir = (run) => path.dirname(path.resolve(run));

// Writes the skill's block between its markers, leaving every other line of
// the file as the user wrote it.
export function writeIgnore(run) {
  const file = path.join(creativeVideosDir(run), ".gitignore");
  const old = fs.existsSync(file) ? fs.readFileSync(file, "utf8") : "";
  const i = old.indexOf(BEGIN);
  const j = old.indexOf(`${END}\n`, i);
  const next =
    i >= 0 && j > i
      ? old.slice(0, i) + BLOCK + old.slice(j + END.length + 1)
      : old + (old && !old.endsWith("\n") ? "\n" : "") + BLOCK;
  if (next !== old) fs.writeFileSync(file, next);
}
