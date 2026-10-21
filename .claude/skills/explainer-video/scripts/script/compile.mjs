// The compile stage: the house Markdown scene file to the machine script.
//
//   node compile.mjs <run-folder>
//
// Reads <run>/script.md: a `# <title>` line, `key: value` header lines
// (language, default en; narrator; style), then per scene a
// `## Scene <id> · <title>` heading, an optional `role: <role> · <n> s` line
// (hook, context, section, point, recap or end, and its seconds), a
// `### Narration` list of numbered sentences (an indented line continues the
// one above) and one `### Visual` block of JSON. In a sentence `{written|spoken}` shows the
// written form on screen and voices the spoken one, backticks are
// dropped, and every sentence ends in `[a, b]`, its cites, or `[no-claim]`.
// With <run>/brief.json, language, narrator and style come from the brief, and
// a header key naming another value is refused.
// stdout: `compile: <n> scene(s) -> script.json`
// writes: <run>/script.json, and explainers/.gitignore
// exit:   0 compiled · 1 the file is malformed, `compile: [<scene>: ]<what>`
//         on stderr · 2 usage
import fs from "node:fs";
import path from "node:path";
import { writeIgnore } from "../lib/runfolder.mjs";
import { CUE_CHARS } from "../render/compose.mjs";
import { banReason, cameraReason, seamReason } from "../lib/allowed.mjs";
import { resolveExcerpts } from "../lib/excerpt.mjs";
import { findStyle } from "../lib/style.mjs";
import { checkVisual } from "../lib/visuals.mjs";
import { BRACES, endsLatin, isLatin, keptTerms } from "../lib/terms.mjs";

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

const ROLES = ["hook", "context", "section", "point", "recap", "end"];
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
  } else if (!section && (m = line.match(/^role:\s*(.*?)\s*$/))) {
    const r = m[1].match(/^([a-z]+)\s*·\s*(\d+(?:\.\d+)?)\s*s$/);
    if (!r || !ROLES.includes(r[1]))
      fail(scene.id, `role: ${m[1]} is not <${ROLES.join("|")}> · <n> s`);
    scene.role = r[1];
    scene.seconds = Number(r[2]);
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

// The brief, when the run has one, decides the header.
const briefFile = path.join(run, "brief.json");
if (fs.existsSync(briefFile)) {
  const brief = JSON.parse(fs.readFileSync(briefFile, "utf8"));
  for (const [key, knob] of [
    ["language", "language"],
    ["narrator", "voice"],
    ["style", "style"],
  ]) {
    if (header[key] && header[key] !== brief[knob])
      fail(
        null,
        `header ${key} ${header[key]} differs from the brief's ${knob} ${brief[knob]}`,
      );
    header[key] = brief[knob];
  }
}

const language = header.language ?? "en";

// The components and techniques the run's style profile bans. A malformed
// profile file is refused here; a missing profile or a bad grammar is the
// render stage's.
let style;
try {
  style = findStyle(run, header.style).profile;
} catch (e) {
  fail(null, e.message);
}
const bans = Array.isArray(style?.grammar?.bans) ? style.grammar.bans : [];

// One numbered sentence: its spoken form, its written tokens, each with the
// count of spoken words it covers, and its cites. In Arabic, Latin words in a
// row are one English term and so one token: a token per word would run a
// right-to-left caption's `pull request` as `request pull`. The first word
// may carry an Arabic prefix (`وpull request`).
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
    const text = chunk.replace(BRACES, "$1").replaceAll("`", "");
    said.push(...words);
    const last = captions.at(-1);
    if (language === "ar" && last && isLatin(text) && endsLatin(last.text)) {
      last.text += ` ${text}`;
      last.words += words.length;
    } else captions.push({ text, words: words.length });
  }
  // A cue breaks only between tokens, so a longer one overflows the band.
  for (const { text } of captions)
    if (text.length > CUE_CHARS)
      fail(id, `${text} is longer than a caption's ${CUE_CHARS} characters`);
  return { narration: said.join(" "), captions, cites };
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
  const parts = s.sentences.map((x) => sentence(x, s.id));
  // A custom scene's fragment and an excerpt scene's pack are read beside the
  // scene file, then kept in the script so a later stage plays what was checked.
  const read = (f) => fs.readFileSync(path.join(run, f), "utf8");
  try {
    checkVisual(
      visual,
      parts.map((x) => x.narration),
      { read, language, cites: [...new Set(parts.flatMap((x) => x.cites))] },
    );
  } catch (e) {
    fail(s.id, e.message);
  }
  if (visual.component === "custom")
    visual.props.source = read(visual.props.file);
  if (visual.component === "excerpt")
    visual.props.excerpts = resolveExcerpts(visual.props, read);
  const banned = banReason(
    bans,
    visual.component,
    style?.name,
    visual.props?.source,
  );
  if (banned) fail(s.id, banned);
  const seam = style && seamReason(style, visual.seam);
  if (seam) fail(s.id, seam);
  const camera = style && cameraReason(style, visual);
  if (camera) fail(s.id, camera);
  return {
    id: s.id,
    title: s.title,
    ...(s.role && { role: s.role, seconds: s.seconds }),
    narration: parts.map((x) => x.narration),
    captions: parts.map((x) => x.captions),
    cites: parts.map((x) => x.cites),
    visual,
  };
});

// Sections: a `section` scene opens a group of two to five points with a card of
// 6 to 12 s, and each scene takes the number of its group, the hook and the
// context joining the first and the recap and the end the last, so a render
// can cut the video where a section opens. The arc gate holds the roles' order.
let opened = 0;
compiled.forEach((s, i) => {
  if (s.role === "section") {
    opened++;
    if (s.seconds < 6 || s.seconds > 12)
      fail(s.id, `the section opener is ${s.seconds} s, want 6 to 12 s`);
    let points = 0;
    while (compiled[i + 1 + points]?.role === "point") points++;
    if (points < 2 || points > 5)
      fail(
        s.id,
        `the section holds ${points} point${points === 1 ? "" : "s"}, want 2 to 5`,
      );
  }
  if (opened) s.section = opened;
});
if (opened) for (const s of compiled) s.section ??= 1;

const script = {
  title,
  language,
  ...(header.narrator && { narrator: header.narrator }),
  ...(header.style && { style: header.style }),
  scenes: compiled,
};
if (language === "ar") script.kept = keptTerms(script);
fs.writeFileSync(out, JSON.stringify(script, null, 2) + "\n");
writeIgnore(run);
console.log(`compile: ${compiled.length} scene(s) -> script.json`);
