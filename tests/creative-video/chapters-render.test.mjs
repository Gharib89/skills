// The render stage on a video in chapters (render/render.mjs, render/
// chapter-project.mjs): each chapter rendered one at a time from its own
// project folder into a cached part, the whole project's audio pass mastered to
// one mix, the parts and the mix joined with a mark per chapter, and the
// estimate printed before any render. The canned backend stands in for
// HyperFrames and ffmpeg.
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { authored } from "../../skills/creative-video/maintainer/real-render-lib.mjs";
import {
  estimate,
  loadRates,
} from "../../skills/creative-video/scripts/lib/estimate.mjs";
import { mmss } from "../../skills/creative-video/scripts/lib/length.mjs";
import { chapter, chaptered } from "./chapters-lib.mjs";
import { runGates, supported } from "./gates-lib.mjs";
import {
  calls,
  exec,
  project,
  read,
  readJson,
  render,
  timing,
} from "./timing-lib.mjs";
import { cuesOf as cues } from "../../skills/creative-video/scripts/gates/captions.mjs";

const PLAN = [chapter("Why", "a", "b"), chapter("How", "c", "d")];
const SCENES = [
  { id: "a", frames: 1800, html: authored("a", "<h1>Why</h1>") },
  { id: "b", frames: 1800 },
  { id: "c", frames: 1800, html: authored("c", "<h1>How</h1>") },
  { id: "d", frames: 1800 },
];
const rel = (fx, ...p) => path.join(fx.dir, ".cache", "render", ...p);
const parts = (fx, n) =>
  fs
    .readdirSync(rel(fx))
    .filter((f) => new RegExp(`^chapter-${n}-[0-9a-f]{16}\\.mp4$`).test(f));
const renders = (fx) => calls(fx).filter((c) => c.call === "hyperframes");

// A chaptered run folder timed, its gates passed.
function ready() {
  const fx = chaptered(SCENES, { chapters: PLAN });
  supported(fx);
  assert.equal(exec(timing, fx).code, 0);
  const g = runGates(fx);
  assert.equal(g.code, 0, g.out + g.err);
  fs.rmSync(fx.log, { force: true });
  return fx;
}
const timeline = (fx) => readJson(path.join(fx.dir, "timeline.json"));

test("each chapter renders alone, in order, from its own folder, then the whole project's audio at 1 fps, mastered and joined with a mark per chapter", () => {
  const fx = ready();
  const r = exec(render, fx);
  assert.equal(r.code, 0, r.out + r.err);
  const tl = timeline(fx);
  const log = calls(fx);
  const names = log
    .map((c) => c.call)
    .filter((c) =>
      ["hyperframes", "masterAudio", "concat", "mux", "poster"].includes(c),
    );
  assert.deepEqual(names, [
    ...["hyperframes", "hyperframes", "hyperframes"],
    ...["masterAudio", "concat", "mux", "poster"],
  ]);
  const [one, two, audio] = renders(fx);
  for (const [c, n] of [
    [one, 1],
    [two, 2],
  ]) {
    assert.equal(c.cwd, rel(fx, `chapter-${n}`));
    assert.deepEqual(c.args.slice(0, 7), [
      ...["render", "--strict", "--quiet", "--fps", "30"],
      ...["--workers", "3"],
    ]);
    assert.match(
      c.args.at(-1),
      new RegExp(`/chapter-${n}-[0-9a-f]{16}\\.part\\.mp4$`),
    );
  }
  assert.equal(audio.cwd, project(fx));
  assert.deepEqual(audio.args, [
    ...["render", "--strict", "--quiet", "--fps", "1", "--quality", "draft"],
    ...["--workers", "3", "-o", rel(fx, "audio.mp4")],
  ]);
  const master = log.find((c) => c.call === "masterAudio");
  assert.deepEqual(
    [master.input, master.wav, master.lufs, master.peak, master.seconds],
    [rel(fx, "audio.mp4"), rel(fx, "audio.wav"), -14, -1.5, tl.total],
  );
  const mux = log.find((c) => c.call === "mux");
  assert.equal(mux.audio, rel(fx, "audio.wav"));
  assert.equal(mux.output, rel(fx, "out", "demo.mp4"));
  assert.deepEqual(
    mux.chapters,
    tl.chapters.map(({ start, end, title }) => ({ start, end, title })),
  );
  const joined = log.find((c) => c.call === "concat");
  assert.deepEqual(
    joined.parts.map((p) => path.basename(p)),
    [1, 2].map((n) => parts(fx, n)[0]),
  );
  assert.ok(!log.some((c) => c.call === "loudnorm"));
  assert.ok(r.out.includes("delivery chapters: pass\n"), r.out);
  assert.ok(r.out.includes("delivery duration: pass\n"), r.out);
  assert.ok(
    r.out.includes(`render: demo.mp4 ${tl.total.toFixed(2)} s, 4 scene(s)\n`),
  );
  assert.deepEqual(fs.readdirSync(path.join(fx.dir, "out")).sort(), [
    "demo.mp4",
    "demo.srt",
    "poster.png",
  ]);
});

test("a chapter's folder holds only its scene hosts and cues, every time counted from its first frame, no narration and no over host, linked to the project's files", () => {
  const fx = ready();
  fs.writeFileSync(
    project(fx, "compositions", "over.html"),
    "<template></template>",
  );
  fs.mkdirSync(project(fx, "kit"), { recursive: true });
  fs.writeFileSync(project(fx, "kit", "look.css"), "");
  fs.writeFileSync(project(fx, "kit", "devices.js"), "");
  assert.equal(runGates(fx).code, 0);
  assert.equal(exec(render, fx).code, 0);
  const tl = timeline(fx);
  const dir = rel(fx, "chapter-2");
  const html = read(path.join(dir, "index.html"));
  const hosts = [
    ...html.matchAll(/<div id="([a-z0-9-]+)" data-composition-id="\1"[^>]*>/g),
  ];
  assert.deepEqual(
    hosts.map((m) => m[1]),
    ["c", "d", "captions"],
  );
  assert.ok(!html.includes("<audio"));
  assert.ok(!html.includes("narration"));
  const len = tl.chapters[1].end - tl.chapters[1].start;
  assert.match(
    html,
    new RegExp(
      `data-composition-id="main" data-start="0" data-duration="${len}"`,
    ),
  );
  assert.ok(
    hosts[0][0].includes(
      `data-start="0" data-duration="${tl.scenes[2].duration}"`,
    ),
  );
  assert.ok(
    hosts[1][0].includes(
      `data-start="${(tl.scenes[3].start - tl.chapters[1].start).toFixed(0)}"`,
    ),
  );
  assert.ok(hosts[2][0].includes(`data-start="0" data-duration="${len}"`));
  assert.ok(html.includes('href="kit/look.css"'));
  assert.ok(html.includes('src="kit/devices.js"'));
  assert.ok(html.indexOf("assets/gsap.min.js") < html.indexOf("timing.js"));
  const chapterTiming = {};
  new Function("window", read(path.join(dir, "timing.js")))(chapterTiming);
  assert.equal(chapterTiming.TIMING.total, len);
  assert.deepEqual(Object.keys(chapterTiming.TIMING.scenes), ["c", "d"]);
  assert.equal(chapterTiming.TIMING.scenes.c.start, 0);
  assert.equal(
    chapterTiming.TIMING.scenes.d.start,
    tl.scenes[3].start - tl.chapters[1].start,
  );
  assert.deepEqual(
    chapterTiming.TIMING.scenes.d.words.map((w) => w.text),
    tl.scenes[3].words.map((w) => w.text),
  );
  assert.equal(
    chapterTiming.TIMING.scenes.d.words[0].start,
    tl.scenes[3].words[0].start - tl.scenes[3].start,
  );
  const got = cues(read(path.join(dir, "compositions", "captions.html")));
  const want = tl.cues.filter((c) => c.start >= tl.chapters[1].start);
  assert.deepEqual(
    got.map((c) => c.text),
    want.map((c) => c.text),
  );
  assert.ok(
    Math.abs(got[0].start - (want[0].start - tl.chapters[1].start)) < 1e-3,
  );
  const link = (...p) => fs.lstatSync(path.join(dir, ...p)).isSymbolicLink();
  assert.ok(link("compositions", "c.html"));
  assert.ok(link("compositions", "d.html"));
  assert.ok(link("kit") && link("assets"));
  assert.ok(!fs.existsSync(path.join(dir, "compositions", "over.html")));
  assert.ok(!fs.existsSync(path.join(dir, "compositions", "a.html")));
  assert.equal(
    fs.realpathSync(path.join(dir, "compositions", "c.html")),
    fs.realpathSync(project(fx, "compositions", "c.html")),
  );
});

test("a chapter starting between milliseconds keeps its opening cue, which the timeline rounds to the millisecond", () => {
  const fx = chaptered([{ ...SCENES[0], frames: 1801 }, ...SCENES.slice(1)], {
    chapters: PLAN,
  });
  supported(fx);
  assert.equal(exec(timing, fx).code, 0);
  assert.equal(runGates(fx).code, 0);
  assert.equal(exec(render, fx).code, 0);
  const tl = timeline(fx);
  const opening = tl.scenes[2].words.map((w) => w.text).join(" ");
  const cue = tl.cues.find((c) => c.text === opening);
  assert.ok(cue.start < tl.chapters[1].start);
  const text = (n) =>
    cues(read(rel(fx, `chapter-${n}`, "compositions", "captions.html"))).map(
      (c) => c.text,
    );
  assert.ok(text(2).includes(opening));
  assert.ok(!text(1).includes(opening));
});

test("the estimate is printed before any render, from the chapters not cached and the rates table", () => {
  const fx = ready();
  const rates = loadRates().rates;
  const tl = timeline(fx);
  const line = (k) => {
    const { seconds, budget } = estimate(k ? tl.total : 0, tl.total, rates);
    return `render: ${k} of 2 chapter(s) to render, estimate ${mmss(seconds)}, budget ${mmss(budget)}\n`;
  };
  const r = exec(render, fx);
  assert.equal(r.code, 0, r.out + r.err);
  assert.ok(r.out.startsWith(line(2)), r.out);
  const again = exec(render, fx);
  assert.ok(again.out.startsWith(line(0)), again.out);
  assert.match(
    again.out,
    /^render: 0 of 2 chapter\(s\) to render, estimate \d+:\d\d, budget \d+:\d\d\n/,
  );
});

test("a chapter unchanged since its part was rendered is not rendered again; an edit to one scene renders its chapter alone and removes its stale part", () => {
  const fx = ready();
  assert.equal(exec(render, fx).code, 0);
  const [first1, first2] = [1, 2].map((n) => parts(fx, n)[0]);
  fs.rmSync(fx.log);
  const second = exec(render, fx);
  assert.equal(second.code, 0, second.out + second.err);
  assert.deepEqual(
    renders(fx).map((c) => c.cwd),
    [project(fx)],
  );
  assert.deepEqual(
    [1, 2].map((n) => parts(fx, n)),
    [[first1], [first2]],
  );

  fs.appendFileSync(project(fx, "compositions", "b.html"), "<!-- edit -->");
  assert.equal(runGates(fx).code, 0);
  fs.rmSync(fx.log);
  const edited = exec(render, fx);
  assert.equal(edited.code, 0, edited.out + edited.err);
  assert.match(edited.out, /^render: 1 of 2 chapter\(s\) to render/);
  assert.deepEqual(
    renders(fx).map((c) => c.cwd),
    [rel(fx, "chapter-1"), project(fx)],
  );
  assert.equal(parts(fx, 1).length, 1);
  assert.notEqual(parts(fx, 1)[0], first1);
  assert.deepEqual(parts(fx, 2), [first2]);
  assert.deepEqual(
    fs
      .readdirSync(rel(fx))
      .filter((f) => f.endsWith(".mp4"))
      .sort(),
    [parts(fx, 1)[0], parts(fx, 2)[0], "audio.mp4"].sort(),
  );
});

test("a kit file changes every chapter's key, so every chapter renders again", () => {
  const fx = ready();
  assert.equal(exec(render, fx).code, 0);
  fs.mkdirSync(project(fx, "kit"), { recursive: true });
  fs.writeFileSync(project(fx, "kit", "look.css"), "a { color: red }");
  assert.equal(runGates(fx).code, 0);
  const r = exec(render, fx);
  assert.match(r.out, /^render: 2 of 2 chapter\(s\) to render/);
});

test("a bed in the sound kit renders no chapter again: it plays in the whole project's mix alone", () => {
  const fx = ready();
  assert.equal(exec(render, fx).code, 0);
  fs.mkdirSync(project(fx, "assets", "sounds"), { recursive: true });
  fs.writeFileSync(project(fx, "assets", "sounds", "bed-1.mp3"), "bed");
  fs.mkdirSync(project(fx, "kit"), { recursive: true });
  fs.writeFileSync(
    project(fx, "kit", "sound.json"),
    JSON.stringify({
      bed: {
        query: "room tone",
        level: -28,
        source: "openverse:bed-1",
        file: "assets/sounds/bed-1.mp3",
        licence: "CC0-1.0",
      },
    }),
  );
  const g = runGates(fx);
  assert.equal(g.code, 0, g.out + g.err);
  const r = exec(render, fx);
  assert.equal(r.code, 0, r.out + r.err);
  assert.match(r.out, /^render: 0 of 2 chapter\(s\) to render/);
  assert.match(read(project(fx, "index.html")), /<audio id="bed"/);
});

test("a new asset changes the key of only the chapters whose files name it; one no file names, as a name built at run time, changes every chapter's", () => {
  const fx = ready();
  assert.equal(exec(render, fx).code, 0);
  const again = () => {
    assert.equal(runGates(fx).code, 0);
    fs.rmSync(fx.log, { force: true });
    const r = exec(render, fx);
    assert.equal(r.code, 0, r.out + r.err);
    return r;
  };
  fs.writeFileSync(project(fx, "assets", "photo.png"), "one");
  fs.appendFileSync(
    project(fx, "compositions", "d.html"),
    '<img src="assets/photo.png">',
  );
  assert.match(again().out, /^render: 1 of 2 chapter\(s\) to render/);
  assert.deepEqual(
    renders(fx).map((c) => c.cwd),
    [rel(fx, "chapter-2"), project(fx)],
  );
  fs.writeFileSync(project(fx, "assets", "photo.png"), "two");
  assert.match(again().out, /^render: 1 of 2 chapter\(s\) to render/);
  assert.deepEqual(
    renders(fx).map((c) => c.cwd),
    [rel(fx, "chapter-2"), project(fx)],
  );
  fs.writeFileSync(project(fx, "assets", "ding.wav"), "built");
  assert.match(again().out, /^render: 2 of 2 chapter\(s\) to render/);
});

test("--estimate prints the estimate line alone, renders nothing, leaves out/ as it was and needs no passed gates", () => {
  const fx = chaptered(SCENES, { chapters: PLAN });
  supported(fx);
  assert.equal(exec(timing, fx).code, 0);
  fs.mkdirSync(path.join(fx.dir, "out"));
  fs.writeFileSync(path.join(fx.dir, "out", "old.mp4"), "old");
  const r = exec(render, fx, [fx.dir, "--estimate"]);
  assert.equal(r.code, 0, r.out + r.err);
  assert.match(
    r.out,
    /^render: 2 of 2 chapter\(s\) to render, estimate \d+:\d\d, budget \d+:\d\d\n$/,
  );
  assert.ok(!calls(fx).some((c) => c.call === "hyperframes"));
  assert.equal(read(path.join(fx.dir, "out", "old.mp4")), "old");
});

test("--estimate on a video that is not in chapters is refused", () => {
  const fx = chaptered(SCENES, {});
  supported(fx);
  assert.equal(exec(timing, fx).code, 0);
  const r = exec(render, fx, [fx.dir, "--estimate"]);
  assert.equal(r.code, 1);
  assert.match(r.err, /^render: --estimate is for a video in chapters/);
});

test("chapter marks the file does not carry fail the chapters check, deliver nothing and exit 1", () => {
  const fx = ready();
  const r = exec(render, fx, [fx.dir], {
    CREATIVE_VIDEO_FAKE_PROBE: JSON.stringify({
      chapters: [{ start: 0, end: 10, title: "Wrong" }],
    }),
  });
  assert.equal(r.code, 1);
  assert.match(
    r.out,
    /^delivery chapters: fail: 1 chapters \(0\.00 s Wrong\) vs 2 \(/m,
  );
  assert.ok(!fs.existsSync(path.join(fx.dir, "out")));
});

test("a stray argument is usage", () => {
  const fx = ready();
  assert.equal(exec(render, fx, [fx.dir, "--nope"]).code, 2);
});
