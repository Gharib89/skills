// The storyboard stage: the authored project shown to the person once, before
// the gates and the render (reference/storyboard.md; the documents are in
// board/board-data.md).
//
//   node board.mjs <run-folder> build
//   node board.mjs <run-folder> apply <answers-file>
//
// build reads <run>/timeline.json, voice.json, script.json, storyboard.json,
// directions/<id>.html for each direction not picked, excerpts.json and
// brand.json (both optional) and <run>/project/, takes every scene's in, key and out stills
// (gates/samples.mjs) in one snapshot launch and one frame of each direction not
// picked, and writes the board and its page. A scene is judged by the hash of
// its file and by its narration. After answers that commented on scenes alone,
// every build until the next answers refuses a change to any scene they did not
// name, to the kit, to over.html or to an asset that board had, so a comment on
// one scene re-authors only that scene. A video in chapters (timeline.json's
// `chapters`) is shown while its later chapters are still being authored: a card
// exists for each scene whose file exists, chapter 1's files must all exist, and
// a scene file of a later chapter the answered board did not have is no change.
// With a brand.json, each direction frame not picked and the kit's CSS
// (project/kit/*.css) must each name every colour hex and every face of the
// brand, and the board carries the brand for the page's strip, its logo copied
// into the board folder.
// apply reads an answers file, the answers document as JSON or the answers
// text, and says what it asks: it accepts only answers to the latest board. An
// approval with a brand.json saves the brand to the store (lib/brand.mjs)
// unless it was used once.
// stdout: build, `board: <n> -> board/storyboard.html (<k> scenes, <m> stills,
//         <c> changed)` then `board: files board/files.json`; apply, the
//         lines below, each starting `board: `:
//           brand <name> saved to the store    an approval with a brand.json
//           brand <name> used once, not saved  prints one of these first
//           approved; next: run the gates      only an approval
//           these answers approve nothing and comment on nothing
//           direction <id>
//           look: <text>
//           redo <scene>: <note>               one per noted scene
//           next: re-author <the whole chapter | only <ids>>, then build the board again
// writes: build, board/<n>.json (the board document), board/storyboard.html,
//         page.css, brand.js, page.js, stills/<hash>.png, brand/<hash>.<ext> (the
//         brand's logo), files.json (the Artifact publish's `files` map),
//         .cache/board/ (the frames taken), the run folder's .gitignore and
//         the root again (render/root.mjs); apply, board/answers-<n>.json and
//         the brand store's <name>/ folder for a brand to save
// exit:   0 ok · 1 refused, `board: <why>` on stderr (a missing timeline,
//         scene file, storyboard.json, direction frame or gsap.min.js; a
//         direction frame or the kit's CSS that does not name every colour and
//         face of the brand, a brand logo that is missing, or a malformed
//         brand.json; an
//         invalid storyboard.json; a script.json whose scenes are not the
//         ones timed, in order, or whose narration is not the one voiced; a scene changed, added (but
//         for a later chapter's) or gone, or
//         the kit, over.html or an asset changed or gone, that the comments
//         did not name;
//         answers of an older board, naming an unknown scene or direction or
//         the one in use, cut to fit, or unreadable; an approval of a
//         brand.json changed since the board showed it) · 2 usage
import fs from "node:fs";
import path from "node:path";
import { readBrand, saveBrand } from "../lib/brand.mjs";
import { maybeJson, readJson } from "../lib/json.mjs";
import { mmss } from "../lib/length.mjs";
import { readTimed, writeIgnore } from "../lib/runfolder.mjs";
import { stage } from "../lib/stage.mjs";
import { hyperframesEnv, loadBackend, skill } from "../lib/tools.mjs";
import { sampleTimes } from "../gates/samples.mjs";
import { esc, HEIGHT, host, WIDTH, writeRoot } from "../render/root.mjs";
import { readAnswers } from "./answers.mjs";
import { changedSince, projectHashes, sha, voicedText } from "./approval.mjs";
import { approvedBrand, brandStrip, copyLogo, wearBrand } from "./brand.mjs";

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
// The latest board answered, however many boards were built since it; 0 for none.
const latestAnswered = () =>
  Math.max(
    0,
    ...fs
      .readdirSync(out)
      .map((f) => Number(/^answers-(\d+)\.json$/.exec(f)?.[1] ?? 0)),
  );
const readBoard = (n) =>
  JSON.parse(fs.readFileSync(path.join(out, `${n}.json`), "utf8"));

// storyboard.json held to what the stage relies on beyond its shape; `shown`
// are the timed scenes that have a file, the ones it must have an entry for.
function readStoryboard(shown) {
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
  for (const { id } of shown)
    if (!sb.scenes[id]) fail(`storyboard.json: no entry for scene ${id}`);
  for (const { id } of list.filter((d) => d.id !== picked))
    if (!fs.existsSync(path.join(run, "directions", `${id}.html`)))
      fail(
        `directions/${id}.html is missing: author the frame of the direction not picked`,
      );
  return sb;
}

// After answers that commented on scenes, with no look or direction, only those
// scenes may change: notes beside an approval win over it, as apply prints.
// `now` is the project's projectHashes, `voiced` each scene's narration;
// `chapterOf` maps each timed id to its chapter.
function guardScenes(now, voiced, chapterOf) {
  const k = latestAnswered();
  if (!k) return;
  const a = JSON.parse(
    fs.readFileSync(path.join(out, `answers-${k}.json`), "utf8"),
  );
  if (!a.scenes.length || a.direction || a.look) return;
  const named = a.scenes.map((s) => s.id);
  const changed = changedSince(readBoard(k), now, voiced, chapterOf, named);
  if (changed.length)
    fail(
      `${changed.join(", ")} changed, but board ${k}'s comments named only ${named.join(", ")}: re-author only those scenes`,
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
  const { timeline, voice } = readTimed(run, fail);
  const proj = path.join(path.resolve(run), "project");
  const has = (id) =>
    fs.existsSync(path.join(proj, "compositions", `${id}.html`));
  // A video with no chapters is one.
  const chapters = timeline.chapters ?? [
    {
      n: 1,
      title: null,
      start: 0,
      end: timeline.total,
      scenes: timeline.scenes.map((s) => s.id),
    },
  ];
  const missing = chapters[0].scenes
    .filter((id) => !has(id))
    .map((id) => `compositions/${id}.html`);
  if (missing.length) fail(`no ${missing.join(", ")}: author each scene file`);
  const shown = timeline.scenes.filter((s) => has(s.id));
  const chapterOf = Object.fromEntries(
    chapters.flatMap((c) => c.scenes.map((id) => [id, c.n])),
  );
  const script = readJson(run, "script.json");
  // The board shows script.json's narration beside stills timed to voice.json:
  // a script edited after timing (a scene added, gone or moved, or its words
  // changed) is not what the board would show.
  const timed = timeline.scenes.map((s) => s.id).join(", ");
  if (script.scenes.map((s) => s.id).join(", ") !== timed)
    fail(
      `script.json's scenes are not the scenes timed (${timed}): voice and time it again first`,
    );
  const narrationOf = new Map(script.scenes.map((s) => [s.id, s.narration]));
  const voiced = voicedText(voice);
  for (const { id } of timeline.scenes)
    if (narrationOf.get(id).join(" ") !== voiced.get(id))
      fail(
        `script.json's scene ${id} is not the narration voiced: voice and time it again first`,
      );
  const sb = readStoryboard(shown);
  const brand = readBrand(run);
  if (brand) wearBrand(run, brand, sb.directions, fail);
  const strip = brandStrip(run, brand, sha, fail);
  const n = Math.max(0, ...versions()) + 1;
  const now = projectHashes(
    proj,
    shown.map((s) => s.id),
  );
  const { hashes, kit, over, assets } = now;
  if (n > 1) guardScenes(now, voiced, chapterOf);
  writeIgnore(run);
  writeRoot(run);

  const backend = await loadBackend();
  const env = hyperframesEnv();
  const at = Object.fromEntries(shown.map((s) => [s.id, sampleTimes(s)]));
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

  // `changed` is against the board the person last answered: a board built
  // again with no Submit still shows what their comments changed.
  const prev = n > 1 ? readBoard(latestAnswered() || n - 1) : null;
  const was = new Map(prev?.scenes.map((s) => [s.id, s.hash]));
  const scenes = shown.map((s) => ({
    id: s.id,
    chapter: chapterOf[s.id],
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

  const logo = copyLogo(run, out, brand, strip);
  // A chapter some of whose scene files are missing is being authored.
  const status = (c) => (c.scenes.every(has) ? "awaiting" : "authoring");
  const doc = {
    version: n,
    title: sb.title,
    language: script.language,
    length: mmss(timeline.total),
    chapters: chapters.map((c) => ({
      n: c.n,
      title: c.title ?? sb.title,
      status: status(c),
    })),
    plan: chapters.map((c) => ({
      chapter: c.n,
      title: c.title ?? sb.title,
      length: mmss(c.end - c.start),
      focus: script.chapters?.[c.n - 1]?.focus ?? sb.focus,
      sources: citedSources(script, c.scenes),
      status: status(c),
    })),
    directions,
    brand: strip,
    kit,
    over,
    assets,
    scenes,
  };
  fs.writeFileSync(
    path.join(out, `${n}.json`),
    JSON.stringify(doc, null, 2) + "\n",
  );

  const board = path.join(skill, "board");
  for (const f of ["page.css", "brand.js", "page.js"])
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
        ["page.css", "brand.js", "page.js", ...stills, ...logo].map((f) => [
          f,
          path.join(out, f),
        ]),
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

// The titles of the sources the script's scenes `ids` cite, in the order first cited.
function citedSources(script, ids) {
  const pack = maybeJson(run, "excerpts.json");
  if (!pack) return [];
  const source = new Map(pack.excerpts.map((e) => [e.id, e.source]));
  const title = new Map((pack.sources ?? []).map((s) => [s.id, s.title]));
  const titles = script.scenes
    .filter((s) => ids.includes(s.id))
    .flatMap((s) => (s.cites ?? []).flat())
    .map((id) => title.get(source.get(id)))
    .filter(Boolean);
  return [...new Set(titles)];
}

// What one answers file asks of the agent.
async function apply() {
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
    const brand =
      a.approve && approvedBrand(run, board.brand, latest, sha, fail);
    if (brand) {
      const { name, saved } = await saveBrand(run, brand);
      console.log(
        `board: brand ${name} ${saved ? "saved to the store" : "used once, not saved"}`,
      );
    }
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
else await apply();
