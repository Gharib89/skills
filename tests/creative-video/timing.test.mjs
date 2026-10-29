// The timing stage (render/timing.mjs): the voiced script gridded into a
// timeline and the HyperFrames project's generated files, with the agent's own
// files in project/ left alone.
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import vm from "node:vm";
import { cuesOf } from "../../skills/creative-video/scripts/gates/captions.mjs";
import { HOLD } from "../../skills/creative-video/scripts/lib/length.mjs";
import {
  gridScenes,
  written,
} from "../../skills/creative-video/scripts/render/grid.mjs";
import {
  NO_WORD,
  NO_WORD_RE,
  REPEATED_WORD,
  REPEATED_WORD_RE,
} from "../../skills/creative-video/scripts/render/anchors.mjs";
import { wavSeconds } from "../../skills/creative-video/scripts/render/narration.mjs";
import { SCENES, write } from "./voice-lib.mjs";
import {
  author,
  exec,
  install,
  project,
  read,
  readJson,
  timing,
  voiced,
} from "./timing-lib.mjs";

const r3 = (n) => +n.toFixed(3);
const ids = SCENES.map((s) => s.id);

test("scenes grid back to back from the voice durations, and the timeline carries the voice hash, cues and absolute words", () => {
  const fx = voiced();
  const r = exec(timing, fx);
  assert.equal(r.code, 0, r.out + r.err);
  const voice = readJson(path.join(fx.dir, "voice.json"));
  const grid = gridScenes(
    voice.scenes.map((v) => wavSeconds(fx.dir, v.audio, assert.fail)),
    HOLD,
  );
  const tl = readJson(path.join(fx.dir, "timeline.json"));
  assert.match(tl.voice, /^[0-9a-f]{16}$/);
  assert.equal(tl.total, written(grid.total));
  assert.deepEqual(
    tl.scenes.map((s) => [s.id, s.start, s.duration]),
    ids.map((id, i) => [id, written(grid[i].start), written(grid[i].frames)]),
  );
  const first = voice.scenes[1].words[0];
  assert.equal(
    tl.scenes[1].words[0].start,
    r3(tl.scenes[1].start + first.start),
  );
  assert.deepEqual(
    tl.scenes[1].words.map((w) => w.text),
    voice.scenes[1].words.map((w) => w.text),
  );
  // One cue per narration sentence: every sentence of the fixture is short.
  assert.deepEqual(
    tl.cues.map((c) => c.text),
    SCENES.flatMap((s) => s.narration),
  );
  assert.equal(r.out.split("\n")[0], `timing: 3 scene(s), ${tl.total} s`);
  for (const id of ids)
    assert.ok(r.out.includes(`timing: compositions/${id}.html to author\n`));
});

test("the root lists the scene hosts in order on the grid, then the captions host and the narration", () => {
  const fx = voiced();
  author(fx, ids);
  assert.equal(exec(timing, fx).code, 0);
  const tl = readJson(path.join(fx.dir, "timeline.json"));
  const html = read(project(fx, "index.html"));
  assert.match(
    html,
    new RegExp(
      `<div id="root" data-composition-id="main" data-start="0" data-duration="${tl.total}" data-width="1920" data-height="1080">`,
    ),
  );
  const hosts = [
    ...html.matchAll(
      /<div id="([a-z0-9-]+)" data-composition-id="\1"[^>]*><\/div>/g,
    ),
  ];
  assert.deepEqual(
    hosts.map((m) => m[1]),
    [...ids, "captions"],
  );
  tl.scenes.forEach((s, i) =>
    assert.equal(
      hosts[i][0],
      `<div id="${s.id}" data-composition-id="${s.id}" data-composition-src="compositions/${s.id}.html" data-start="${s.start}" data-duration="${s.duration}" data-track-index="1" data-track-kind="graphics" data-width="1920" data-height="1080"></div>`,
    ),
  );
  assert.equal(
    hosts[3][0],
    `<div id="captions" data-composition-id="captions" data-composition-src="compositions/captions.html" data-start="0" data-duration="${tl.total}" data-track-index="3" data-track-kind="captions" data-width="1920" data-height="1080" style="z-index:10"></div>`,
  );
  assert.ok(
    html.includes(
      `<audio id="narration" class="clip" src="assets/narration.wav" data-start="0" data-duration="${tl.total}" data-volume="1" data-track-index="4"></audio>`,
    ),
  );
  assert.ok(
    html.includes(
      'window.__timelines["main"] = gsap.timeline({ paused: true });',
    ),
  );
  assert.ok(
    html.indexOf("assets/gsap.min.js") < html.indexOf("timing.js") &&
      html.indexOf("timing.js") < html.indexOf("window.__timelines"),
  );
});

test("an over.html adds the over host on track 2, and the kit's files load sorted", () => {
  const fx = voiced();
  author(fx, ids);
  assert.equal(exec(timing, fx).code, 0);
  const bare = read(project(fx, "index.html"));
  assert.ok(!bare.includes('id="over"'));
  assert.ok(!bare.includes("kit/"));
  author(fx, ["over"]);
  for (const f of ["b.js", "a.css", "a.js", "b.css"]) {
    fs.mkdirSync(project(fx, "kit"), { recursive: true });
    fs.writeFileSync(project(fx, "kit", f), "");
  }
  assert.equal(exec(timing, fx).code, 0);
  const html = read(project(fx, "index.html"));
  const tl = readJson(path.join(fx.dir, "timeline.json"));
  assert.ok(
    html.includes(
      `<div id="over" data-composition-id="over" data-composition-src="compositions/over.html" data-start="0" data-duration="${tl.total}" data-track-index="2" data-track-kind="graphics" data-width="1920" data-height="1080"></div>`,
    ),
  );
  const at = (s) => html.indexOf(s);
  assert.ok(at('href="kit/a.css"') < at('href="kit/b.css"'));
  assert.ok(at('src="kit/a.js"') < at('src="kit/b.js"'));
  assert.ok(
    at('id="context"') < at('id="over"') &&
      at('id="over"') < at('id="captions"'),
  );
});

test("timing.js answers at() with the local start of the nth matching word and throws on an unknown one", () => {
  const fx = voiced();
  assert.equal(exec(timing, fx).code, 0);
  const voice = readJson(path.join(fx.dir, "voice.json"));
  const window = {};
  vm.runInNewContext(read(project(fx, "timing.js")), { window });
  const tl = readJson(path.join(fx.dir, "timeline.json"));
  assert.equal(window.TIMING.total, tl.total);
  assert.equal(window.TIMING.scenes.context.duration, tl.scenes[1].duration);
  assert.equal(window.TIMING.scenes.context.start, tl.scenes[1].start);
  const words = voice.scenes[1].words; // It reads the profile first. Then it claims ...
  // The context is another realm's: its objects compare by JSON.
  assert.deepEqual(
    JSON.parse(JSON.stringify(window.TIMING.scenes.context.words[3])),
    {
      text: "profile",
      start: r3(words[3].start),
      end: r3(words[3].end),
    },
  );
  assert.equal(window.at("context", "profile"), r3(words[3].start));
  // Case and punctuation do not count: "first." is "FIRST".
  assert.equal(window.at("context", "FIRST"), r3(words[4].start));
  // "it" is words 1, 7 and 13 ("Then it claims", "takes it").
  assert.equal(window.at("context", "it", 1), r3(words[0].start));
  assert.equal(window.at("context", "it", 2), r3(words[6].start));
  assert.throws(() => window.at("context", "nowhere"), {
    message: 'at: no word "nowhere" (1) in scene context',
  });
  assert.throws(() => window.at("context", "it", 4), /no word "it" \(4\)/);
  assert.throws(() => window.at("nope", "it"), /in scene nope/);
});

test("the message at() throws in timing.js is the one the gates stage's anchors pattern reads back", () => {
  const fx = voiced();
  assert.equal(exec(timing, fx).code, 0);
  const window = {};
  vm.runInNewContext(read(project(fx, "timing.js")), { window });
  let message;
  try {
    window.at("context", "nowhere", 2);
  } catch (e) {
    message = e.message;
  }
  assert.ok(message.startsWith(NO_WORD), message);
  assert.deepEqual(message.match(NO_WORD_RE).slice(1), ["nowhere", "context"]);
});

test("at() with no nth on a word its scene repeats throws the occurrences the anchors pattern reads back; a single word or an explicit nth answers", () => {
  const fx = voiced();
  assert.equal(exec(timing, fx).code, 0);
  const words = readJson(path.join(fx.dir, "voice.json")).scenes[1].words;
  const window = {};
  vm.runInNewContext(read(project(fx, "timing.js")), { window });
  // "It reads the profile first. Then it claims the issue so no other run takes
  // it.": "it" is words[0], [6] and [15]; "profile" is said once.
  assert.equal(window.at("context", "profile"), r3(words[3].start));
  assert.equal(window.at("context", "it", 1), r3(words[0].start));
  assert.equal(window.at("context", "It", 2), r3(words[6].start));
  let message;
  try {
    window.at("context", "It");
  } catch (e) {
    message = e.message;
  }
  assert.ok(message?.startsWith(REPEATED_WORD), message);
  const times = [0, 6, 15].map((i) => `${r3(words[i].start).toFixed(2)} s`);
  assert.deepEqual(message.match(REPEATED_WORD_RE).slice(1), [
    "It",
    "context",
    times.join(", "),
  ]);
});

test("captions.html reads back through the caption gate's cuesOf as the timeline's cues", () => {
  const fx = voiced();
  assert.equal(exec(timing, fx).code, 0);
  const tl = readJson(path.join(fx.dir, "timeline.json"));
  const html = read(project(fx, "compositions", "captions.html"));
  const cues = cuesOf(html);
  assert.equal(cues.length, tl.cues.length);
  cues.forEach((c, i) => {
    assert.equal(c.text, tl.cues[i].text);
    assert.ok(Math.abs(c.start - tl.cues[i].start) < 1e-6);
    assert.ok(Math.abs(c.end - tl.cues[i].end) < 1e-3);
  });
  assert.match(html, /<template[^>]*>[\s\S]*<\/template>/);
  assert.ok(
    html.includes(
      '<div id="root" data-composition-id="captions" data-width="1920" data-height="1080">',
    ),
  );
  assert.ok(html.includes('id="cue-1"'));
  assert.ok(
    html.includes(
      'window.__timelines["captions"] = gsap.timeline({ paused: true });',
    ),
  );
});

test("a run keeps the agent's files, builds the assets, and lists only the scene files not yet authored", () => {
  const fx = voiced();
  author(fx, ["hook"]);
  fs.mkdirSync(project(fx, "kit"), { recursive: true });
  fs.writeFileSync(project(fx, "kit", "mine.txt"), "mine");
  const r = exec(timing, fx);
  assert.equal(r.code, 0, r.out + r.err);
  assert.ok(!r.out.includes("compositions/hook.html to author"));
  assert.ok(r.out.includes("compositions/context.html to author"));
  assert.equal(read(project(fx, "compositions", "hook.html")), "<!-- hook -->");
  assert.equal(read(project(fx, "kit", "mine.txt")), "mine");
  assert.equal(read(project(fx, "assets", "gsap.min.js")), "/* gsap */");
  const wav = fs.readFileSync(project(fx, "assets", "narration.wav"));
  assert.equal(wav.toString("ascii", 0, 4), "RIFF");
  const tl = readJson(path.join(fx.dir, "timeline.json"));
  assert.ok(
    Math.abs(wav.readUInt32LE(40) / 2 / wav.readUInt32LE(24) - tl.total) < 1e-3,
  );
  const ignore = read(path.join(path.dirname(fx.dir), ".gitignore"));
  for (const f of [
    "timeline.json",
    "project/index.html",
    "project/timing.js",
    "project/compositions/captions.html",
    "project/assets/narration.wav",
    "project/assets/gsap.min.js",
    "project/.hyperframes/",
  ])
    assert.match(
      ignore,
      new RegExp(`^\\*/${f.replaceAll(".", "\\.")}$`, "m"),
      f,
    );
});

test("a voice.json that no longer matches the script is refused", () => {
  const fx = voiced();
  write(fx, [
    ...SCENES.slice(0, 2),
    { id: "recap", narration: ["A different closing line."] },
  ]);
  const r = exec(timing, fx);
  assert.equal(r.code, 1);
  assert.match(
    r.err,
    /^timing: voice\.json does not match scene recap: run the voice stage again/,
  );
  assert.ok(!fs.existsSync(path.join(fx.dir, "timeline.json")));
  write(fx, SCENES, "en", { narrator: "am_fenrir" });
  const n = exec(timing, fx);
  assert.equal(n.code, 1);
  assert.match(
    n.err,
    /voice\.json holds narrator af_heart, the script asks for am_fenrir/,
  );
});

test("a scene id that is reserved or not lower-case letters, digits and hyphens is refused", () => {
  for (const id of ["main", "captions", "over", "narration", "Hook_1"]) {
    const fx = voiced([{ id, narration: ["One short line."] }]);
    const r = exec(timing, fx);
    assert.equal(r.code, 1, id);
    assert.match(r.err, new RegExp(`^timing: scene id ${id}`), id);
  }
});

test("a missing script, voice.json or npm install is refused, and a stray argument is usage", () => {
  const fx = voiced();
  fs.rmSync(path.join(fx.dir, "voice.json"));
  assert.match(exec(timing, fx).err, /^timing: voice\.json: is missing/);
  fs.rmSync(path.join(fx.dir, "script.json"));
  assert.match(exec(timing, fx).err, /^timing: script\.json: is missing/);
  const bare = voiced();
  fs.rmSync(path.join(bare.tmp, "cache", "creative-video", "node"), {
    recursive: true,
  });
  const r = exec(timing, bare);
  assert.equal(r.code, 1);
  assert.match(
    r.err,
    /^timing: npm-packages is not installed: run \/creative-video setup/,
  );
  install(bare);
  const u = exec(timing, bare, []);
  assert.equal(u.code, 2);
  assert.match(u.err, /^usage: node timing\.mjs <run-folder>/);
  assert.equal(exec(timing, bare, [bare.dir, "x"]).code, 2);
});
