// The compile stage: the house Markdown scene file to the machine script.
//
//   node compile.mjs <run-folder>
//
// Reads <run>/script.md: a `# <title>` line, `key: value` header lines
// (language, default en; narrator; style), then per scene a
// `## Scene <id> · <title>` heading, a `### Narration` list of numbered
// sentences (an indented line continues the one above) and one `### Visual`
// block of JSON. In a sentence `{written|spoken}`
// shows the written form on screen and voices the spoken one, backticks are
// dropped, and every sentence ends in `[a, b]`, its cites, or `[no-claim]`.
// stdout: `compile: <n> scene(s) -> script.json`
// writes: <run>/script.json, and explainers/.gitignore
// exit:   0 compiled · 1 the file is malformed, `compile: [<scene>: ]<what>`
//         on stderr · 2 usage
import fs from "node:fs";
import path from "node:path";
import { writeIgnore } from "../lib/runfolder.mjs";

const [run, ...rest] = process.argv.slice(2);
if (!run || rest.length) {
  console.error("usage: node compile.mjs <run-folder>");
  process.exit(2);
}
const out = path.join(run, "script.json");
fs.rmSync(out, { force: true });

function fail(where, what) {
  console.error(`compile: ${where ? `${where}: ` : ""}${what}`);
  process.exit(1);
}

const file = path.join(run, "script.md");
if (!fs.existsSync(file)) fail(null, `no ${file}`);
const lines = fs.readFileSync(file, "utf8").split(/\r?\n/);

let title = null;
const header = {};
const scenes = [];
let scene = null;
let section = null;
let fence = null;
for (const line of lines) {
  if (fence) {
    if (/^```\s*$/.test(line)) {
      scene.visual = fence.join("\n");
      fence = null;
    } else fence.push(line);
    continue;
  }
  let m;
  if (line.startsWith("## ")) {
    m = line.match(/^## Scene\s+([A-Za-z0-9-]+)\s+·\s+(.+?)\s*$/);
    if (!m) fail(null, `not a scene heading: ${line}`);
    if (scenes.some((s) => s.id === m[1])) fail(m[1], "scene id used twice");
    // The composition's own id; a scene of that name would replace it.
    if (m[1] === "main") fail(m[1], "scene id main is reserved");
    scene = { id: m[1], title: m[2], sentences: [], visual: null };
    scenes.push(scene);
    section = null;
  } else if (!scene) {
    if (!title && (m = line.match(/^# (.+?)\s*$/))) title = m[1];
    else if (title && (m = line.match(/^([A-Za-z]+):\s*(.+?)\s*$/))) {
      if (!["language", "narrator", "style"].includes(m[1]))
        fail(null, `unknown header key ${m[1]} (language, narrator, style)`);
      header[m[1]] = m[2];
    }
  } else if (/^### Narration\s*$/.test(line)) section = "narration";
  else if (/^### Visual\s*$/.test(line)) section = "visual";
  else if (section === "narration" && (m = line.match(/^\d+\.\s+(.+)$/)))
    scene.sentences.push(m[1]);
  else if (
    section === "narration" &&
    /^\s+\S/.test(line) &&
    !/^\s+\d+\.\s/.test(line) &&
    scene.sentences.length
  ) {
    if (/\]\s*$/.test(scene.sentences.at(-1)))
      fail(scene.id, `${line.trim()} continues a sentence past its cites`);
    scene.sentences.push(`${scene.sentences.pop()} ${line.trim()}`);
  } else if (section === "narration" && line.trim())
    fail(scene.id, `not a numbered sentence: ${line}`);
  else if (section === "visual" && /^```json\s*$/.test(line)) {
    if (scene.visual !== null) fail(scene.id, "a second ```json visual block");
    fence = [];
  }
}
if (fence) fail(scene.id, "the ```json visual block is never closed");
if (!title) fail(null, "no `# <title>` line");
if (!scenes.length) fail(null, "no `## Scene <id> · <title>` heading");

const BRACES = /\{([^|}]*)\|([^}]*)\}/g;

// One numbered sentence: its spoken form, its written tokens, each with the
// count of spoken words it covers, and its cites.
function sentence(raw, id) {
  const m = raw.match(/^(.*?)\s*\[([^\]]*)\]\s*$/);
  if (!m?.[2].trim()) fail(id, `${raw} ends in no [<cites>] or [no-claim]`);
  const body = m[1];
  const cites = m[2]
    .split(",")
    .map((c) => c.trim())
    .filter((c) => c && c !== "no-claim");
  const said = [];
  const captions = [];
  for (const chunk of body.match(/(?:\{[^}]*\}|\S)+/g) ?? []) {
    const words = chunk
      .replace(BRACES, " $2 ")
      .replaceAll("`", "")
      .split(/\s+/)
      .filter(Boolean);
    if (!words.length) fail(id, `${chunk} has no spoken form`);
    said.push(...words);
    captions.push({
      text: chunk.replace(BRACES, "$1").replaceAll("`", ""),
      words: words.length,
    });
  }
  return { narration: said.join(" "), captions, cites };
}

// What each component's props must hold; `at` names a sentence by number.
function check(visual, n, id) {
  const p = visual.props ?? {};
  const at = (x) => {
    if (!Number.isInteger(x.at) || x.at < 1 || x.at > n)
      fail(id, `at ${x.at} is not a sentence (1 to ${n})`);
  };
  const text = (v, what) => {
    if (typeof v !== "string") fail(id, `${visual.component} needs ${what}`);
  };
  if (visual.component === "title") text(p.title, "a title");
  else if (visual.component === "cards") {
    if (!Array.isArray(p.items) || !p.items.length)
      fail(id, "cards needs items");
    for (const x of p.items) {
      at(x);
      text(x.label, "a label per item");
      text(x.value, "a value per item");
    }
  } else if (visual.component === "terminal") {
    if (!Array.isArray(p.lines) || !p.lines.length)
      fail(id, "terminal needs lines");
    for (const x of p.lines) {
      at(x);
      text(x.text, "a text per line");
    }
  } else fail(id, `unknown component ${visual.component}`);
}

const compiled = scenes.map((s) => {
  if (!s.sentences.length) fail(s.id, "no narration");
  if (s.visual === null) fail(s.id, "no ```json visual block");
  let visual;
  try {
    visual = JSON.parse(s.visual);
  } catch (e) {
    fail(s.id, `visual is not JSON: ${e.message}`);
  }
  check(visual, s.sentences.length, s.id);
  const parts = s.sentences.map((x) => sentence(x, s.id));
  return {
    id: s.id,
    title: s.title,
    narration: parts.map((x) => x.narration),
    captions: parts.map((x) => x.captions),
    cites: parts.map((x) => x.cites),
    visual,
  };
});

fs.writeFileSync(
  out,
  JSON.stringify(
    {
      title,
      language: header.language ?? "en",
      ...(header.narrator && { narrator: header.narrator }),
      ...(header.style && { style: header.style }),
      scenes: compiled,
    },
    null,
    2,
  ) + "\n",
);
writeIgnore(run);
console.log(`compile: ${compiled.length} scene(s) -> script.json`);
