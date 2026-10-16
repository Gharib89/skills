// The storyboard stage: one board version per review, from the run's
// compiled, voiced and stilled script, and the human's answers back into it.
//
//   node board.mjs <run-folder> build [--local]
//   node board.mjs <run-folder> page [<url>]
//   node board.mjs <run-folder> asset <path>=<url>...
//   node board.mjs <run-folder> apply <answers-file>
//
// The documents are the contract in storyboard/board-data.md. `build` reads
// script.json, script.md, voice.json, stills.json, brief.json, excerpts.json,
// gates.json, manifest.json and, once delivered, timeline.json and out/, and
// writes the next board/<n>.json (a card is `approved` when the last answers
// approved it and nothing in it changed since), board/keys-<n>.json (the
// content keys that decide that), and the local storyboard.html. A delivered
// run gets one clip per scene, cut into .cache/clips/. With a published page
// (`page <url>`) every media file needs an uploaded URL, recorded by `asset`;
// `--local` builds for storyboard.html alone, the page out of reach.
// `page` with no url writes board/page.html, the file a session publishes
// once; with a url it records the published page in manifest.json. `apply`
// reads the answers (the answers document, or the text the page copies) into
// board/answers-<n>.json and writes edited narration back into script.md.
// stdout: build `board <n>: <kind>, <k> card(s), <o> to answer[, banner: <g> red
//         gate(s)] -> board/<n>.json`, then where the page is; apply one line
//         per card, `board brief: <arg>` per brief change, and `board:
//         approved` or `board: redo <ids>[; brief <args>]`
// writes: <run>/board/, storyboard.html, manifest.json (`board`), script.md
// exit:   0 ok · 1 refused, `board: <why>` on stderr · 2 usage
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { scriptHash, stopped } from "../lib/gatestop.mjs";
import { writeIgnore } from "../lib/runfolder.mjs";
import { loadBackend, skill } from "../lib/tools.mjs";
import { esc } from "../render/compose.mjs";

const [run, cmd, ...args] = process.argv.slice(2);
const usage = () => {
  console.error(
    "usage: node board.mjs <run-folder> build [--local] | page [<url>] | asset <path>=<url>... | apply <answers-file>",
  );
  process.exit(2);
};
if (
  !run ||
  !["build", "page", "asset", "apply"].includes(cmd) ||
  (cmd === "build" && !["", "--local"].includes(args.join(" "))) ||
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
// A media file under .cache/, named for its inputs, made once.
const cached = async (rel, make) => {
  if (fs.existsSync(at(rel))) return rel;
  fs.mkdirSync(path.dirname(at(rel)), { recursive: true });
  try {
    await make(at(rel));
  } catch (e) {
    fail(e.message);
  }
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

function needScript() {
  if (!fs.existsSync(at("script.json")))
    fail("no script.json: run the compile stage first (script/compile.mjs)");
  return json(at("script.json"));
}

// Each scene's narration block in script.md: the lines after `### Narration`
// up to `### Visual`, edge blank lines left out.
function narrationBlocks(lines) {
  const blocks = {};
  let id = null;
  let from = null;
  lines.forEach((line, i) => {
    const m = line.match(/^## Scene\s+([A-Za-z0-9-]+)\s+·\s+(.+?)\s*$/);
    if (m) id = m[1];
    else if (/^### Narration\s*$/.test(line)) from = i + 1;
    else if (/^### Visual\s*$/.test(line) && id && from !== null) {
      let a = from;
      let b = i;
      while (a < b && !lines[a].trim()) a++;
      while (b > a && !lines[b - 1].trim()) b--;
      blocks[id] = { from: a, to: b };
      from = null;
    }
  });
  return blocks;
}

if (cmd === "page") {
  const [url] = args;
  if (!url) {
    const script = needScript();
    fs.mkdirSync(at("board"), { recursive: true });
    fs.writeFileSync(at("board", "page.html"), filled(script.title));
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
  const assets = maybe(file) ?? {};
  const root = path.resolve(run);
  for (const a of args) {
    const i = a.indexOf("=");
    const rel = i < 0 ? "" : a.slice(0, i);
    const url = a.slice(i + 1);
    const abs = path.resolve(root, rel);
    if (
      !rel ||
      !abs.startsWith(root + path.sep) ||
      !fs.existsSync(abs) ||
      !fs.statSync(abs).isFile()
    )
      fail(`${rel || a} is not a file under the run folder`);
    if (!url.startsWith("https://") && !/^\/_blob\/[0-9a-f]{32}$/.test(url))
      fail(`${url} is neither an https:// URL nor /_blob/<id>`);
    assets[path.relative(root, abs)] = url;
  }
  write(file, assets);
  console.log(`board: ${args.length} asset(s) recorded`);
  process.exit(0);
}

if (cmd === "apply") {
  const all = versions();
  if (!all.length) fail("no board yet: run build first");
  const n = all.at(-1);
  const board = json(at("board", `${n}.json`));
  const raw = fs.readFileSync(args[0], "utf8");
  let answers;
  if (raw.trimStart().startsWith("{")) {
    answers = JSON.parse(raw);
  } else {
    const lines = raw.split("\n");
    if (lines.some((l) => l.startsWith("[cut to fit:")))
      fail(
        `the answers were cut to fit a comment: read answers/board-${n} from the database`,
      );
    const head = lines[0].match(/^explainer-video: board (\d+) answers/);
    if (!head) fail("not an answers text: its first line is not the header");
    answers = {
      version: Number(head[1]),
      submittedAt: new Date().toISOString(),
      scenes: [],
      brief: [],
    };
    let card = null;
    let inNarration = false;
    for (const line of lines.slice(1)) {
      let m;
      if ((m = line.match(/^([A-Za-z0-9-]+): (Approve|Revise)$/))) {
        card = {
          id: m[1],
          choice: m[2].toLowerCase(),
          note: "",
          narration: "",
        };
        answers.scenes.push(card);
        inNarration = false;
      } else if (card && (m = line.match(/^ {2}note: (.*)$/))) {
        card.note = m[1];
        inNarration = false;
      } else if (card && line === "  narration:") {
        inNarration = true;
      } else if (inNarration && line.startsWith("    ")) {
        card.narration += (card.narration ? "\n" : "") + line.slice(4);
      } else if ((m = line.match(/^Brief: (.+)$/))) {
        answers.brief.push(m[1]);
        inNarration = false;
      } else if (line.trim()) fail(`cannot read this answers line: ${line}`);
    }
  }
  if (answers.version !== n)
    fail(`answers for board ${answers.version}, the latest is board ${n}`);
  const ids = board.scenes.map((c) => c.id);
  for (const s of answers.scenes)
    if (!ids.includes(s.id)) fail(`the answers name no scene ${s.id}`);
  for (const s of answers.scenes)
    if (!["approve", "revise"].includes(s.choice))
      fail(`scene ${s.id} has no answer`);
  for (const id of ids)
    if (!answers.scenes.some((s) => s.id === id))
      fail(`the answers miss card ${id}`);
  answers.scenes = ids.map((id) => {
    const s = answers.scenes.find((x) => x.id === id);
    return {
      id,
      choice: s.choice,
      note: s.note ?? "",
      narration: s.narration ?? "",
    };
  });
  answers.brief ??= [];
  write(at("board", `answers-${n}.json`), answers);

  const edited = (s) =>
    s.narration.trim() &&
    s.narration !== board.scenes.find((c) => c.id === s.id).narration;
  const edits = answers.scenes.filter(edited);
  if (edits.length) {
    const lines = fs.readFileSync(at("script.md"), "utf8").split("\n");
    const blocks = narrationBlocks(lines);
    for (const s of edits)
      if (!blocks[s.id]) fail(`script.md has no narration block for ${s.id}`);
    for (const s of edits.sort((a, b) => blocks[b.id].from - blocks[a.id].from))
      lines.splice(
        blocks[s.id].from,
        blocks[s.id].to - blocks[s.id].from,
        ...s.narration.split("\n"),
      );
    fs.writeFileSync(at("script.md"), lines.join("\n"));
  }
  for (const s of answers.scenes)
    console.log(
      `board ${s.id}: ${s.choice === "approve" ? "approve" : `revise: ${s.note || "no note"}`}${edited(s) ? ", narration edited" : ""}`,
    );
  for (const a of answers.brief) console.log(`board brief: ${a}`);
  // An approved card whose narration was edited still needs its scene redone.
  const redo = answers.scenes
    .filter((s) => s.choice === "revise" || edited(s))
    .map((s) => s.id);
  console.log(
    !redo.length && !answers.brief.length
      ? "board: approved"
      : `board: redo ${redo.join(",") || "none"}${answers.brief.length ? `; brief ${answers.brief.join(" ")}` : ""}`,
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

const slug = path.basename(path.resolve(run));
const manifest = maybe(at("manifest.json")) ?? {};
const mp4 = at("out", `${slug}.mp4`);
const delivered = !!manifest.delivered && fs.existsSync(mp4);
const kind = delivered ? "delivered" : "review";
const md = fs.readFileSync(at("script.md"), "utf8").split("\n");
const blocks = narrationBlocks(md);
const profile = maybe(at("style.json"))?.name ?? script.style ?? "claude-code";

const cards = script.scenes.map((s, i) => ({
  id: s.id,
  title: s.title,
  ...(s.role && { role: s.role }),
  seconds: Math.round(voice.scenes[i].duration * 10) / 10,
  narration: md.slice(blocks[s.id].from, blocks[s.id].to).join("\n"),
  style: `${s.visual.component} · ${profile} · ${voice.narrator}`,
  still: stills.scenes.find((x) => x.id === s.id).still,
  audio: voice.scenes[i].audio,
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

if (delivered) {
  const timeline = json(at("timeline.json"));
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

const media = cards.flatMap((c) => [c.still, c.audio, c.clip].filter(Boolean));
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
    text: "The video gates stayed red after two fix attempts, so no video was made.",
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
if (banner) {
  for (const [, g] of red)
    for (const e of g.evidence) {
      const id = e.match(/\bs ([A-Za-z0-9-]+):/)?.[1];
      const c = cards.find((x) => x.id === id);
      if (c) c.status = "reopened";
    }
  if (cards.some((c) => c.status === "reopened"))
    banner.text += " Revise the reopened cards.";
}

const brief = maybe(at("brief.json"));
const pack = maybe(at("excerpts.json"));
const doc = {
  version: prev + 1,
  kind,
  title: script.title,
  brief: Object.entries(brief ?? {}).map(([knob, v]) => ({
    knob,
    value: Array.isArray(v) ? v.join("; ") : String(v ?? ""),
  })),
  sources: (pack?.sources ?? []).map((s) => ({
    id: s.id,
    kind: s.kind,
    title: s.title,
    summary: s.summary,
    excerpts: pack.excerpts.filter((e) => e.source === s.id).length,
  })),
  ...(banner && { banner }),
  scenes: cards,
};

// A published page reads uploaded URLs; storyboard.html, opened from the run
// folder, reads the run's paths.
const published = !!manifest.board && args[0] !== "--local";
const assets = maybe(at("board", "assets.json")) ?? {};
if (published && media.some((f) => !assets[f])) {
  for (const f of media.filter((f) => !assets[f]))
    console.error(`board: upload ${f} (${MB(fs.statSync(at(f)).size)})`);
  fail(`record each upload with: node board.mjs ${run} asset <path>=<url>`);
}
fs.writeFileSync(
  at("storyboard.html"),
  filled(script.title).replace(
    '<script type="application/json" id="board">null</script>',
    () =>
      `<script type="application/json" id="board">${JSON.stringify(doc).replaceAll("<", "\\u003c")}</script>`,
  ),
);
if (published)
  for (const c of cards)
    for (const k of ["still", "audio", "clip"]) if (c[k]) c[k] = assets[c[k]];
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
