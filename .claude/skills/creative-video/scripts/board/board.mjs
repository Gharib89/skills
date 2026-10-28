// The storyboard stage: the authored project shown to the person once, before
// the gates and the render (reference/storyboard.md; the documents are in
// board/board-data.md).
//
//   node board.mjs <run-folder> build
//   node board.mjs <run-folder> apply <answers-file>
//
// build reads <run>/timeline.json, voice.json, script.json, storyboard.json,
// directions/<id>.html for each direction not picked, excerpts.json (optional)
// and <run>/project/, takes every scene's in, key and out stills
// (gates/samples.mjs) in one snapshot launch and one frame of each direction not
// picked, and writes the board and its page. A scene is judged by the hash of
// its file; after answers that commented on scenes alone, a build refuses a
// change to any scene they did not name, or to the kit, so a comment on one
// scene re-authors only that scene.
// apply reads an answers file, the answers document as JSON or the answers
// text, and says what it asks: it accepts only answers to the latest board.
// stdout: build, `board: <n> -> board/storyboard.html (<k> scenes, <m> stills,
//         <c> changed)` then `board: files board/files.json`; apply, the
//         lines below, each starting `board: `:
//           approved; next: run the gates      only an approval
//           these answers approve nothing and comment on nothing
//           direction <id>
//           look: <text>
//           redo <scene>: <note>               one per noted scene
//           next: re-author <the whole chapter | only <ids>>, then build the board again
// writes: build, board/<n>.json (the board document), board/storyboard.html,
//         page.css, page.js, stills/<hash>.png, files.json (the Artifact
//         publish's `files` map), .cache/board/ (the frames taken), the run
//         folder's .gitignore and the root again (render/root.mjs); apply,
//         board/answers-<n>.json
// exit:   0 ok · 1 refused, `board: <why>` on stderr (a missing timeline,
//         scene file, storyboard.json, direction frame or gsap.min.js; an
//         invalid storyboard.json; a script.json lacking a timed scene; a
//         scene or the kit changed that the comments did not name; answers of
//         an older board, naming an unknown scene or direction or the one in
//         use, cut to fit, or unreadable) · 2 usage
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { maybeJson, readJson } from "../lib/json.mjs";
import { readTimeline, writeIgnore } from "../lib/runfolder.mjs";
import { stage } from "../lib/stage.mjs";
import { hyperframesEnv, loadBackend, skill } from "../lib/tools.mjs";
import { sampleTimes } from "../gates/samples.mjs";
import { esc, HEIGHT, host, WIDTH, writeRoot } from "../render/root.mjs";
import { readAnswers } from "./answers.mjs";

stage("board");
const [run, command, file, ...rest] = process.argv.slice(2);
if (
  !run ||
  rest.length ||
  (command === "apply" ? !file : command !== "build" || file)
) {
  console.error(
    "usage: node board.mjs <run-folder> build | apply <answers-file>",
  );
  process.exit(2);
}
const fail = (why) => {
  throw new Error(why);
};
const out = path.join(path.resolve(run), "board");
const versions = () =>
  fs.existsSync(out)
    ? fs
        .readdirSync(out)
        .flatMap((f) => (/^\d+\.json$/.test(f) ? [parseInt(f, 10)] : []))
    : [];
const readBoard = (n) =>
  JSON.parse(fs.readFileSync(path.join(out, `${n}.json`), "utf8"));

const sha = (bytes) =>
  crypto.createHash("sha256").update(bytes).digest("hex").slice(0, 16);
const mmss = (s) =>
  `${Math.floor(Math.round(s) / 60)}:${String(Math.round(s) % 60).padStart(2, "0")}`;

// Every file under kit/, nested ones too: each one's name and bytes, sorted.
function kitHash(proj) {
  const dir = path.join(proj, "kit");
  const h = crypto.createHash("sha256");
  if (fs.existsSync(dir))
    for (const f of fs.readdirSync(dir, { recursive: true }).sort())
      if (fs.statSync(path.join(dir, f)).isFile())
        h.update(`${f}\0`).update(fs.readFileSync(path.join(dir, f)));
  return h.digest("hex").slice(0, 16);
}

// storyboard.json held to what the stage relies on beyond its shape.
function readStoryboard(timeline) {
  const sb = readJson(run, "storyboard.json");
  const { list, recommended, picked } = sb.directions;
  if (list.length !== 3)
    fail(
      `storyboard.json: directions.list holds ${list.length}, not three directions`,
    );
  for (const d of list)
    if (!/^[a-z0-9-]+$/.test(d.id))
      fail(`storyboard.json: direction id "${d.id}" is not kebab-case`);
  for (const [key, id] of [
    ["recommended", recommended],
    ["picked", picked],
  ])
    if (!list.some((d) => d.id === id))
      fail(
        `storyboard.json: directions.${key} "${id}" is not in directions.list`,
      );
  for (const { id } of timeline.scenes)
    if (!sb.scenes[id]) fail(`storyboard.json: no entry for scene ${id}`);
  for (const { id } of list.filter((d) => d.id !== picked))
    if (!fs.existsSync(path.join(run, "directions", `${id}.html`)))
      fail(
        `directions/${id}.html is missing: author the frame of the direction not picked`,
      );
  return sb;
}

// After answers that commented on scenes alone, only those scenes may change.
function guardScenes(n, hashes, kit) {
  const answered = path.join(out, `answers-${n - 1}.json`);
  if (!fs.existsSync(answered)) return;
  const a = JSON.parse(fs.readFileSync(answered, "utf8"));
  if (!a.scenes.length || a.direction || a.look || a.approve) return;
  const prev = readBoard(n - 1);
  const was = new Map(prev.scenes.map((s) => [s.id, s.hash]));
  const named = a.scenes.map((s) => s.id);
  const changed = Object.entries(hashes)
    .filter(([id, h]) => !named.includes(id) && was.get(id) !== h)
    .map(([id]) => id);
  if (kit !== prev.kit) changed.push("the kit");
  if (changed.length)
    fail(
      `${changed.join(", ")} changed, but board ${n - 1}'s comments named only ${named.join(", ")}: re-author only those scenes`,
    );
}

// A direction's frame: its file as the one scene of a 2 s project of its own,
// with no kit, captions or narration, taken at 1 s.
async function directionFrame(backend, env, id, language) {
  const dir = path.join(path.resolve(run), ".cache", "board", "directions", id);
  fs.rmSync(dir, { recursive: true, force: true });
  fs.mkdirSync(path.join(dir, "compositions"), { recursive: true });
  fs.mkdirSync(path.join(dir, "assets"), { recursive: true });
  fs.copyFileSync(
    path.join(run, "directions", `${id}.html`),
    path.join(dir, "compositions", `${id}.html`),
  );
  const gsap = path.join(run, "project", "assets", "gsap.min.js");
  if (!fs.existsSync(gsap))
    fail("project/assets/gsap.min.js is missing: run render/timing.mjs first");
  fs.copyFileSync(gsap, path.join(dir, "assets", "gsap.min.js"));
  fs.writeFileSync(
    path.join(dir, "index.html"),
    `<!doctype html>
<html lang="${language}">
  <head>
    <meta charset="utf-8" />
    <title>${esc(id)}</title>
    <style>
      body {
        margin: 0;
      }
    </style>
    <script src="assets/gsap.min.js"></script>
  </head>
  <body>
    <div id="root" data-composition-id="main" data-start="0" data-duration="2" data-width="${WIDTH}" data-height="${HEIGHT}">
${host(id, 0, 2, 1, "graphics")}
    </div>
    <script>
      window.__timelines["main"] = gsap.timeline({ paused: true });
    </script>
  </body>
</html>
`,
  );
  const [frame] = await backend.snapshot(dir, [1], path.join(dir, "frames"), {
    env,
  });
  return frame.path;
}

async function build() {
  const { timeline } = readTimeline(run, fail);
  const script = readJson(run, "script.json");
  const narrationOf = new Map(script.scenes.map((s) => [s.id, s.narration]));
  for (const { id } of timeline.scenes)
    if (!narrationOf.has(id))
      fail(`script.json has no scene ${id}: voice and time it again first`);
  const sb = readStoryboard(timeline);
  const n = Math.max(0, ...versions()) + 1;
  const proj = path.join(path.resolve(run), "project");
  const hashes = Object.fromEntries(
    timeline.scenes.map((s) => [
      s.id,
      sha(fs.readFileSync(path.join(proj, "compositions", `${s.id}.html`))),
    ]),
  );
  const kit = kitHash(proj);
  if (n > 1) guardScenes(n, hashes, kit);
  writeIgnore(run);
  writeRoot(run);

  const backend = await loadBackend();
  const env = hyperframesEnv();
  const at = Object.fromEntries(
    timeline.scenes.map((s) => [s.id, sampleTimes(s)]),
  );
  const times = [
    ...new Set(Object.values(at).flatMap((t) => Object.values(t))),
  ].sort((a, b) => a - b);
  const frames = path.resolve(run, ".cache", "board", "frames");
  fs.rmSync(frames, { recursive: true, force: true });
  const taken = await backend.snapshot(
    proj,
    times,
    path.join(frames, "scenes"),
    {
      env,
    },
  );
  if (taken.length !== times.length)
    fail(`snapshot gave ${taken.length} of ${times.length} frames`);
  const frameAt = new Map(times.map((t, i) => [t, taken[i].path]));

  // Each still is copied under the hash of its bytes, so a scene that did not
  // change keeps its stills' names from one board to the next.
  fs.mkdirSync(path.join(out, "stills"), { recursive: true });
  const stills = new Set();
  const keep = (from) => {
    const name = `stills/${sha(fs.readFileSync(from))}.png`;
    fs.copyFileSync(from, path.join(out, name));
    stills.add(name);
    return name;
  };

  const prev = n > 1 ? readBoard(n - 1) : null;
  const was = new Map(prev?.scenes.map((s) => [s.id, s.hash]));
  const scenes = timeline.scenes.map((s) => ({
    id: s.id,
    chapter: 1,
    title: sb.scenes[s.id].title,
    timecode: `${mmss(s.start)} to ${mmss(s.start + s.duration)}`,
    narration: narrationOf.get(s.id).join(" "),
    notes: sb.scenes[s.id].notes,
    stills: Object.fromEntries(
      ["in", "key", "out"].map((p) => [p, keep(frameAt.get(at[s.id][p]))]),
    ),
    hash: hashes[s.id],
    changed: prev !== null && was.get(s.id) !== hashes[s.id],
  }));

  const { list, recommended, picked } = sb.directions;
  const directions = [];
  for (const d of list)
    directions.push({
      id: d.id,
      name: d.name,
      kind: d.kind,
      recommended: d.id === recommended,
      picked: d.id === picked,
      frame:
        d.id === picked
          ? scenes[0].stills.key
          : keep(await directionFrame(backend, env, d.id, script.language)),
    });

  const length = mmss(timeline.total);
  const doc = {
    version: n,
    title: sb.title,
    language: script.language,
    length,
    chapters: [{ n: 1, title: sb.title, status: "awaiting" }],
    plan: [
      {
        chapter: 1,
        title: sb.title,
        length,
        focus: sb.focus,
        sources: citedSources(script),
        status: "awaiting",
      },
    ],
    directions,
    kit,
    scenes,
  };
  fs.writeFileSync(
    path.join(out, `${n}.json`),
    JSON.stringify(doc, null, 2) + "\n",
  );

  const board = path.join(skill, "board");
  for (const f of ["page.css", "page.js"])
    fs.copyFileSync(path.join(board, f), path.join(out, f));
  const embedded = JSON.stringify(doc).replaceAll("<", "\\u003c");
  fs.writeFileSync(
    path.join(out, "storyboard.html"),
    fs
      .readFileSync(path.join(board, "page.html"), "utf8")
      .replace("{{TITLE}}", () => esc(sb.title))
      .replace(
        '<script type="application/json" id="board">null</script>',
        () => `<script type="application/json" id="board">${embedded}</script>`,
      ),
  );
  fs.writeFileSync(
    path.join(out, "files.json"),
    JSON.stringify(
      Object.fromEntries(
        ["page.css", "page.js", ...stills].map((f) => [f, path.join(out, f)]),
      ),
      null,
      2,
    ) + "\n",
  );
  console.log(
    `board: ${n} -> board/storyboard.html (${scenes.length} scenes, ${stills.size} stills, ${scenes.filter((s) => s.changed).length} changed)`,
  );
  console.log("board: files board/files.json");
}

// The titles of the sources the script cites, in the order first cited.
function citedSources(script) {
  const pack = maybeJson(run, "excerpts.json");
  if (!pack) return [];
  const source = new Map(pack.excerpts.map((e) => [e.id, e.source]));
  const title = new Map((pack.sources ?? []).map((s) => [s.id, s.title]));
  const titles = script.scenes
    .flatMap((s) => (s.cites ?? []).flat())
    .map((id) => title.get(source.get(id)))
    .filter(Boolean);
  return [...new Set(titles)];
}

// What one answers file asks of the agent.
function apply() {
  const latest = Math.max(0, ...versions());
  if (!latest) fail("no board built yet: run build first");
  if (!fs.existsSync(file)) fail(`${file}: is missing`);
  const a = readAnswers(fs.readFileSync(file, "utf8"));
  if (a.version !== latest)
    fail(
      `these answers are of board ${a.version}, the latest is board ${latest}`,
    );
  const board = readBoard(latest);
  for (const { id } of a.scenes)
    if (!board.scenes.some((s) => s.id === id))
      fail(`no scene ${id} in board ${latest}`);
  const askedDirection = board.directions.find((d) => d.id === a.direction);
  if (a.direction && !askedDirection)
    fail(`no direction ${a.direction} in board ${latest}`);
  if (askedDirection?.picked)
    fail(`direction ${a.direction} is the one in use: pick another, or none`);
  fs.writeFileSync(
    path.join(out, `answers-${latest}.json`),
    JSON.stringify(a, null, 2) + "\n",
  );

  // A text continues on lines indented two spaces, as the answers text does.
  const lines = (t) => t.replaceAll("\n", "\n  ");
  const { direction, look, scenes } = a;
  if (!direction && !look && !scenes.length) {
    console.log(
      a.approve
        ? "board: approved; next: run the gates"
        : "board: these answers approve nothing and comment on nothing",
    );
    return;
  }
  if (direction) console.log(`board: direction ${direction}`);
  if (look) console.log(`board: look: ${lines(look)}`);
  for (const s of scenes) console.log(`board: redo ${s.id}: ${lines(s.note)}`);
  console.log(
    `board: next: re-author ${
      direction || look
        ? "the whole chapter"
        : `only ${scenes.map((s) => s.id).join(", ")}`
    }, then build the board again`,
  );
}

if (command === "build") await build();
else apply();
