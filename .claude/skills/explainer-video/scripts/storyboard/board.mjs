// The storyboard stage: one board version per review, from the run's
// compiled, voiced and stilled script, and the human's answers back into it.
//
//   node board.mjs <run-folder> build [--local] [--fix <scene>=<text>]...
//   node board.mjs <run-folder> page [<url>]
//   node board.mjs <run-folder> asset <path>=<url>...
//   node board.mjs <run-folder> apply <answers-file>
//
// The documents are the contract in storyboard/board-data.md. `build` reads
// script.json, script.md, voice.json, stills.json, brief.json, excerpts.json,
// gates.json, manifest.json, timeline.json, composition/ (the stills step writes
// both; the live build and the joined narration come from it) and, once
// delivered, out/, and
// writes the next board/<n>.json (a card is `approved` when the last answers
// approved it and nothing in it changed since), board/keys-<n>.json (the
// content keys that decide that), and the local storyboard.html. A delivered
// run (its MP4 at least as new as stills.json) gets one clip per scene, cut
// into .cache/clips/. With a published page
// (`page <url>`) every media file needs an uploaded URL, recorded by `asset`;
// `--local` builds for storyboard.html alone, the page out of reach.
// `page` with no url writes board/page.html, the file a session publishes
// once; with a url it records the published page in manifest.json. `apply`
// reads the answers (the answers document, or the text the page copies) into
// board/answers-<n>.json and writes edited narration, then each edited kept
// term (in the title, the narration and the screen text), back into script.md.
// stdout: build `board <n>: <kind>, <k> card(s), <o> to answer[, banner: <g> red
//         gate(s)] -> board/<n>.json`, then where the page is; apply one line
//         per card, `board brief: <arg>` per brief change, `board kept: <term>
//         -> <to>` per kept term edited, and `board: approved` or `board: redo
//         <ids>[; brief <args>]`
// writes: <run>/board/, storyboard.html, manifest.json (`board`), script.md
// exit:   0 ok · 1 refused, `board: <why>` on stderr · 2 usage
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { knobOffer, voices } from "../brief/knobs.mjs";
import { estimate, rates } from "../lib/estimate.mjs";
import { scriptHash, stopped } from "../lib/gatestop.mjs";
import { recordAssets, writeIgnore } from "../lib/runfolder.mjs";
import { grammar, loadStyle } from "../lib/style.mjs";
import { loadBackend, skill } from "../lib/tools.mjs";
import { VISUALS } from "../lib/visuals.mjs";
import { esc } from "../render/compose.mjs";
import { liveScript } from "../render/live.mjs";
import { seamPlan } from "../render/seams.mjs";
import { applyAnswers } from "./apply.mjs";
import { cardMenus } from "./menus.mjs";
import { narrationBlocks } from "./script-text.mjs";

const [run, cmd, ...args] = process.argv.slice(2);
const usage = () => {
  console.error(
    "usage: node board.mjs <run-folder> build [--local] [--fix <scene>=<text>]... | page [<url>] | asset <path>=<url>... | apply <answers-file>",
  );
  process.exit(2);
};
// build's flags: `--local` once, `--fix <scene>=<text>` any number of times.
const opts = { local: false, fixes: {} };
if (cmd === "build")
  for (let i = 0; i < args.length; i++) {
    const m = args[i] === "--fix" && args[i + 1]?.match(/^([^=]+)=(.+)$/s);
    if (m) {
      opts.fixes[m[1]] = m[2];
      i++;
    } else if (args[i] === "--local" && !opts.local) opts.local = true;
    else usage();
  }
if (
  !run ||
  !["build", "page", "asset", "apply"].includes(cmd) ||
  (cmd === "page" && args.length > 1) ||
  (cmd === "asset" && !args.length) ||
  (cmd === "apply" && args.length !== 1)
)
  usage();
function fail(why) {
  console.error(`board: ${why}`);
  process.exit(1);
}

const CAP = 15_000_000;
const MB = (n) => `${(n / 1e6).toFixed(1)} MB`;
const at = (...p) => path.join(run, ...p);
const json = (f) => JSON.parse(fs.readFileSync(f, "utf8"));
const maybe = (f) => (fs.existsSync(f) ? json(f) : null);
const write = (f, data) => {
  fs.mkdirSync(path.dirname(f), { recursive: true });
  fs.writeFileSync(f, JSON.stringify(data, null, 2) + "\n");
};
const hash = (...parts) => {
  const h = crypto.createHash("sha256");
  for (const p of parts)
    h.update(
      typeof p === "string" || Buffer.isBuffer(p) ? p : JSON.stringify(p),
    );
  return h.digest("hex").slice(0, 16);
};
// A media file under .cache/, named for its inputs, made once. It is made
// under a partial- name and renamed on success, so a failed or interrupted
// encode never reads as made.
const cached = async (rel, make) => {
  if (fs.existsSync(at(rel))) return rel;
  const part = path.join(
    path.dirname(at(rel)),
    `partial-${path.basename(rel)}`,
  );
  fs.mkdirSync(path.dirname(part), { recursive: true });
  try {
    await make(part);
  } catch (e) {
    fail(e.message);
  }
  fs.renameSync(part, at(rel));
  return rel;
};
const versions = () =>
  fs.existsSync(at("board"))
    ? fs
        .readdirSync(at("board"))
        .map((f) => f.match(/^(\d+)\.json$/)?.[1])
        .filter(Boolean)
        .map(Number)
        .sort((a, b) => a - b)
    : [];
const template = () =>
  fs.readFileSync(path.join(skill, "storyboard", "page.html"), "utf8");
const filled = (title) => template().replace("{{TITLE}}", () => esc(title));
// The page links its style and scripts by relative path: a publish carries them
// in `files`, and a local copy needs them beside it.
const siblings = [
  "page.css",
  "page-core.js",
  "page-summary.js",
  "page-boot.js",
];
const copySiblings = (dir) => {
  for (const f of siblings)
    fs.copyFileSync(path.join(skill, "storyboard", f), path.join(dir, f));
};

function needScript() {
  if (!fs.existsSync(at("script.json")))
    fail("no script.json: run the compile stage first (script/compile.mjs)");
  return json(at("script.json"));
}

if (cmd === "page") {
  const [url] = args;
  if (!url) {
    const script = needScript();
    fs.mkdirSync(at("board"), { recursive: true });
    fs.writeFileSync(at("board", "page.html"), filled(script.title));
    copySiblings(at("board"));
    console.log("board: page board/page.html");
  } else {
    if (!url.startsWith("https://")) fail(`${url} is not an https:// URL`);
    const file = at("manifest.json");
    write(file, { ...maybe(file), board: url });
    console.log(`board: page ${url} -> manifest.json`);
  }
  process.exit(0);
}

if (cmd === "asset") {
  const file = at("board", "assets.json");
  try {
    write(file, { ...maybe(file), ...recordAssets(run, args) });
  } catch (e) {
    fail(e.message);
  }
  console.log(`board: ${args.length} asset(s) recorded`);
  process.exit(0);
}

if (cmd === "apply") {
  const all = versions();
  if (!all.length) fail("no board yet: run build first");
  const n = all.at(-1);
  applyAnswers(
    run,
    json(at("board", `${n}.json`)),
    n,
    fs.readFileSync(args[0], "utf8"),
    fail,
  );
  process.exit(0);
}

// build
const script = needScript();
writeIgnore(run);
const voice = maybe(at("voice.json"));
if (
  !voice ||
  voice.scenes.length !== script.scenes.length ||
  script.scenes.some((s, i) => voice.scenes[i].id !== s.id)
)
  fail(
    "no voice.json for this script: run the voice stage first (voice/voice.mjs)",
  );
const stills = maybe(at("stills.json"));
for (const s of script.scenes) {
  const f = stills?.scenes.find((x) => x.id === s.id)?.still;
  if (!f || !fs.existsSync(at(f)))
    fail(`no still for scene ${s.id}: run node render.mjs ${run} --stills`);
}
// The stills run writes the timeline and the composition the live build plays.
const timeline = maybe(at("timeline.json"));
if (
  !Array.isArray(timeline?.scenes) ||
  !fs.existsSync(at("composition", "index.html"))
)
  fail(`no composition: run node render.mjs ${run} --stills`);

const slug = path.basename(path.resolve(run));
const manifest = maybe(at("manifest.json")) ?? {};
const mp4 = at("out", `${slug}.mp4`);
// Delivered while the MP4 is at least as new as the stills: a render writes
// the stills first, and `render --stills` after it starts a new review.
const delivered =
  !!manifest.delivered &&
  fs.existsSync(mp4) &&
  fs.statSync(mp4).mtimeMs >= fs.statSync(at("stills.json")).mtimeMs;
const kind = delivered ? "delivered" : "review";
// A review board posts only after the sampling pass ran on these stills, so a
// red it left reaches its card; a delivered one passed every video gate.
const sampled = delivered ? null : maybe(at("samples.json"));
if (!delivered) {
  if (!sampled)
    fail(`no samples.json: run node gates/samples.mjs ${run} first`);
  // One record per script scene, each with a findings list: a missing one
  // would read as a clean scene and recommend Approve.
  const gap = script.scenes.find(
    (s) =>
      !Array.isArray(sampled.scenes?.find?.((x) => x.id === s.id)?.findings),
  );
  if (gap)
    fail(
      `samples.json has no findings for scene ${gap.id}: run node gates/samples.mjs ${run} again`,
    );
  if (
    fs.statSync(at("samples.json")).mtimeMs <
    fs.statSync(at("stills.json")).mtimeMs
  )
    fail(
      `samples.json is older than the stills: run node gates/samples.mjs ${run} again`,
    );
}
const md = fs.readFileSync(at("script.md"), "utf8").split("\n");
const blocks = narrationBlocks(md);
const profile = maybe(at("style.json"))?.name ?? script.style ?? "claude-code";

// A card's place in the build: where its scene starts and how long its slot is.
const loop = (id) => {
  const t = timeline.scenes.find((x) => x.id === id);
  if (!Number.isFinite(t?.start) || !Number.isFinite(t?.slot))
    fail(
      `timeline.json has no start and slot for scene ${id}: run node render.mjs ${run} --stills`,
    );
  return { start: t.start, slot: t.slot };
};
const rich = (s) => !!VISUALS[s.visual.component]?.ownCamera;
const style = loadStyle(run, script.style);
const plan = seamPlan(script.scenes, style);
const cards = script.scenes.map((s, i) => ({
  id: s.id,
  title: s.title,
  ...(s.role && { role: s.role }),
  seconds: Math.round(voice.scenes[i].duration * 10) / 10,
  narration: md.slice(blocks[s.id].from, blocks[s.id].to).join("\n"),
  // A rich component moves the frame itself, which the human weighs at the
  // card, so it is marked past the default.
  style: `${s.visual.component}${rich(s) ? " · past the default" : ""} · ${profile} · ${voice.narrator}`,
  rich: rich(s),
  // A custom scene's own line of what it shows, so the card says what the
  // frame is meant to do.
  ...(s.visual.component === "custom" && { intent: s.visual.props.intent }),
  menus: cardMenus(s, style, plan[i].out, i === script.scenes.length - 1),
  still: stills.scenes.find((x) => x.id === s.id).still,
  audio: voice.scenes[i].audio,
  // The slot is the scene's voiced length plus its exit seam: a card's loop.
  ...loop(s.id),
  status: "open",
}));

const backend = await loadBackend();
// The voice WAV's name is its content hash, so the WebM cut from it is too.
for (const c of cards) {
  const name = `${path.basename(c.audio, ".wav")}.webm`;
  c.audio = await cached(path.join(".cache", "board-audio", name), (out) =>
    backend.narration(at(c.audio), out),
  );
}

// The live build and the joined narration the animatic plays it over. Both
// are named for their content, so a build of the same composition is made once.
let live;
try {
  live = liveScript(at("composition"));
} catch (e) {
  fail(`${e.message}: run node render.mjs ${run} --stills`);
}
const build = await cached(
  path.join(".cache", "board-build", `${hash(live)}.js`),
  (out) => fs.writeFileSync(out, live),
);
const joined = at("composition", "narration.wav");
const narration = await cached(
  path.join(".cache", "board-audio", `${hash(fs.readFileSync(joined))}.webm`),
  (out) => backend.narration(joined, out),
);

if (delivered) {
  const sha = crypto
    .createHash("sha256")
    .update(fs.readFileSync(mp4))
    .digest("hex");
  for (const c of cards) {
    const t = timeline.scenes.find((x) => x.id === c.id);
    const name = `${hash(sha, c.id, t.start, t.duration)}.mp4`;
    c.clip = await cached(path.join(".cache", "clips", name), (out) =>
      backend.clip(mp4, out, { start: t.start, duration: t.duration }),
    );
  }
}

const media = [
  build,
  narration,
  ...cards.flatMap((c) => [c.still, c.audio, c.clip].filter(Boolean)),
];
for (const f of media) {
  const size = fs.statSync(at(f)).size;
  if (size > CAP) fail(`${f} is ${MB(size)}, over the 15 MB asset cap`);
}

const key = (c, s) => hash(c.narration, s.visual, c.still, c.audio);
const keys = Object.fromEntries(
  cards.map((c, i) => [c.id, key(c, script.scenes[i])]),
);

const all = versions();
const prev = all.at(-1) ?? 0;
const answersFile = at("board", `answers-${prev}.json`);
const answered = maybe(answersFile);

// Gate stop: the gates record's script hash says it is of this script; its
// evidence names the scenes to reopen. Answers written after the record
// spent it: the revision's board waits for the next render's record.
const gates = delivered ? null : maybe(at("gates.json"));
const red = Object.entries(gates?.gates ?? {}).filter(
  ([, g]) => g.status === "fail",
);
let banner;
if (
  gates &&
  gates.script === scriptHash(script) &&
  stopped(gates.attempts) &&
  red.length &&
  !(
    answered &&
    fs.statSync(answersFile).mtimeMs >= fs.statSync(at("gates.json")).mtimeMs
  )
) {
  banner = {
    text: "The video gates stayed red with no fix attempt left, so no video was made.",
    gates: red.map(
      ([name, g]) => `gate ${name}: fail: ${g.measured} vs ${g.floor}`,
    ),
  };
}

const before = maybe(at("board", `keys-${prev}.json`));
for (const c of cards) {
  if (delivered) c.status = "approved";
  else if (
    answered?.scenes.some((a) => a.id === c.id && a.choice === "approve") &&
    before?.[c.id] === keys[c.id]
  )
    c.status = "approved";
}
// A card's findings: the reds the sampling pass left, then the gate stop's
// evidence naming it.
const found = new Map(
  cards.map((c) => [
    c.id,
    [...(sampled?.scenes.find((x) => x.id === c.id)?.findings ?? [])],
  ]),
);
if (banner) {
  for (const [, g] of red)
    for (const e of g.evidence) {
      const id = e.match(/\bs ([A-Za-z0-9-]+):/)?.[1];
      const c = cards.find((x) => x.id === id);
      if (c) {
        c.status = "reopened";
        found.get(id).push(e);
      }
    }
  if (cards.some((c) => c.status === "reopened"))
    banner.text += " Revise the reopened cards.";
}
// A card with a finding arrives recommended Revise, unless an earlier board's
// approval of it still stands.
for (const c of cards) {
  const lines = found.get(c.id);
  if (lines.length) c.finding = lines.join("\n");
  c.recommendation =
    lines.length && c.status !== "approved" ? "revise" : "approve";
}
for (const id of Object.keys(opts.fixes)) {
  const c = cards.find((x) => x.id === id);
  if (!c?.finding) fail(`--fix names no card with a finding: ${id}`);
  c.fix = opts.fixes[id];
}

// The first-render estimate: it warns on the page, and never refuses a board.
const table = rates();
const estimated = estimate(
  cards.map((c, i) => ({
    id: c.id,
    seconds: c.seconds,
    webgl: !!VISUALS[script.scenes[i].visual.component].webgl,
  })),
  table.rates,
  { textured: grammar(style).texture.overlays.length > 0 },
);
for (const c of cards) if (c.rich) c.adds = estimated.adds[c.id];

const brief = maybe(at("brief.json"));
const pack = maybe(at("excerpts.json"));
const doc = {
  version: prev + 1,
  kind,
  title: script.title,
  build,
  narration,
  estimate: {
    seconds: estimated.seconds,
    budget: estimated.budget,
    over: estimated.over,
    hyperframes: table.hyperframes,
  },
  brief: Object.entries(brief ?? {}).map(([knob, v]) => ({
    knob,
    value: Array.isArray(v) ? v.join("; ") : String(v ?? ""),
    ...knobOffer(knob, run, brief),
  })),
  voices: voices(brief),
  sources: (pack?.sources ?? []).map((s) => ({
    id: s.id,
    kind: s.kind,
    title: s.title,
    summary: s.summary,
    excerpts: pack.excerpts.filter((e) => e.source === s.id).length,
  })),
  ...(script.kept && { kept: script.kept }),
  ...(banner && { banner }),
  scenes: cards,
};

// A published page reads uploaded URLs; storyboard.html, opened from the run
// folder, reads the run's paths.
const published = !!manifest.board && !opts.local;
const assets = maybe(at("board", "assets.json")) ?? {};
if (published && media.some((f) => !assets[f])) {
  for (const f of media.filter((f) => !assets[f]))
    console.error(`board: upload ${f} (${MB(fs.statSync(at(f)).size)})`);
  fail(`record each upload with: node board.mjs ${run} asset <path>=<url>`);
}
// The local copy declares its encoding: no publish wraps it in a skeleton.
copySiblings(run);
fs.writeFileSync(
  at("storyboard.html"),
  '<!doctype html>\n<meta charset="utf-8">\n' +
    filled(script.title).replace(
      '<script type="application/json" id="board">null</script>',
      () =>
        `<script type="application/json" id="board">${JSON.stringify(doc).replaceAll("<", "\\u003c")}</script>`,
    ),
);
if (published) {
  doc.build = assets[build];
  doc.narration = assets[narration];
  for (const c of cards)
    for (const k of ["still", "audio", "clip"]) if (c[k]) c[k] = assets[c[k]];
}
write(at("board", `${doc.version}.json`), doc);
write(at("board", `keys-${doc.version}.json`), keys);
const open = cards.filter((c) => c.status !== "approved").length;
console.log(
  `board ${doc.version}: ${kind}, ${cards.length} card(s), ${open} to answer${banner ? `, banner: ${red.length} red gate(s)` : ""} -> board/${doc.version}.json`,
);
console.log(
  published
    ? `board: post board/${doc.version}.json to boards/${doc.version}`
    : "board: local page storyboard.html",
);
