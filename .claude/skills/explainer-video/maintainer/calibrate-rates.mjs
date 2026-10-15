// Maintainer only: measure each narrator's speaking rate on a fixed text and
// write it into narrators.json, where the script stage budgets scene words.
//
//   node maintainer/calibrate-rates.mjs <language> [narrators.json]
//
// Needs the voice rows installed (`node scripts/setup.mjs install`). The rate
// is words per second over the aligned span, from the first word's start to
// the last word's end, so leading and trailing silence does not count.
// stdout: `calibrate <id>: <rate> words/s` per narrator of that language
// exit:   0 written · 1 synthesis or alignment failed · 2 usage
import fs from "node:fs";
import path from "node:path";
import { loadBackend, skill, toolPaths } from "../scripts/lib/tools.mjs";
import { align } from "../scripts/voice/align.mjs";

// Explainer narration in the house register, numbers spelled out.
const TEXTS = {
  en:
    "Every pull request starts as an issue that someone wrote down. " +
    "The agent reads the issue, checks out a fresh branch, and writes the change with its tests. " +
    "Then it runs the gate, opens the pull request, and waits for review. " +
    "When the checks pass and the reviewers agree, the change merges, and the issue closes on its own.",
};

const [language, file = path.join(skill, "narrators.json"), ...rest] =
  process.argv.slice(2);
if (!TEXTS[language] || rest.length) {
  console.error(
    `usage: node calibrate-rates.mjs <${Object.keys(TEXTS).join("|")}> [narrators.json]`,
  );
  process.exit(2);
}

const doc = JSON.parse(fs.readFileSync(file, "utf8"));
const tools = toolPaths();
const backend = await loadBackend();
const ctc = await backend.aligner({ language, tools });
const words = TEXTS[language].split(/\s+/);
try {
  for (const n of doc.narrators.filter((n) => n.language === language)) {
    const { samples, sampleRate } = await backend.synthesize({
      text: TEXTS[language],
      narrator: n,
      language,
      tools,
    });
    const timed = (await align(samples, sampleRate, words, ctc)).words;
    n.rate = +(words.length / (timed.at(-1).end - timed[0].start)).toFixed(2);
    console.log(`calibrate ${n.id}: ${n.rate} words/s`);
  }
} catch (e) {
  console.error(`calibrate: ${e.message}`);
  process.exit(1);
}
fs.writeFileSync(file, JSON.stringify(doc, null, 2) + "\n");
