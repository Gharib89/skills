// The credits the run's data can write: CREDITS.md's `## Voices` and
// `## Sound` sections.
//
//   node credits.mjs <run-folder>
//
// Voices: each role voice.json voiced some sentence in (the narrator alone
// with no cast.json), its voice id, backend and licence. Sound: the kit's bed
// and each palette sound with its event, source, licence, creator, url and
// attribution, then each sound sounds.mjs dropped. Every other section of
// CREDITS.md (the sources, the faces) is kept as it stands; the file is
// created when absent.
// writes: <run>/CREDITS.md
// exit:   0 written · 1 refused, `credits: <why>` on stderr (no voice.json, a
//         malformed sound.json) · 2 usage
import fs from "node:fs";
import path from "node:path";
import { readJson } from "../lib/json.mjs";
import { kitSounds, soundKit, voicedCast } from "../lib/kit.mjs";
import { stage } from "../lib/stage.mjs";

stage("credits");
const [run, ...rest] = process.argv.slice(2);
if (!run || rest.length) {
  console.error("usage: node credits.mjs <run-folder>");
  process.exit(2);
}
const cast = voicedCast(readJson(run, "voice.json"));
const kit = soundKit(run);
const sections = {
  Voices: Object.entries(cast).map(
    ([role, n]) => `- ${role}: ${n.id} (${n.backend}, ${n.licence})`,
  ),
  Sound: [
    ...kitSounds(kit).map(
      (s) =>
        `- ${s.event}: ${[s.source, s.licence, s.creator && `by ${s.creator}`, s.url, s.attribution].filter(Boolean).join(", ")}`,
    ),
    ...(kit?.dropped ?? []).map((d) => `- ${d.event}: dropped (${d.why})`),
  ],
};
if (!sections.Sound.length) sections.Sound.push("- none but the narration");

const file = path.join(run, "CREDITS.md");
let text = fs.existsSync(file)
  ? fs.readFileSync(file, "utf8")
  : "# Credits\n\n";
for (const [heading, lines] of Object.entries(sections)) {
  const block = `## ${heading}\n\n${lines.join("\n")}\n\n`;
  // The section runs to the next `## ` heading or the end of the file.
  const own = new RegExp(
    `^## ${heading}\\n[\\s\\S]*?(?=^## |(?![\\s\\S]))`,
    "m",
  );
  text = own.test(text)
    ? text.replace(own, () => block)
    : `${text.replace(/\n*$/, "\n\n")}${block}`;
}
fs.writeFileSync(file, text.replace(/\n+$/, "\n"));
