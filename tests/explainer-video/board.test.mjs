// The storyboard stage through its process door: a run folder compiled, voiced
// and stilled with the canned backend, then board.mjs build, page, asset and
// apply, and the revise loop that sends one scene back through voice and stills.
import { after, test } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import crypto from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { judged } from "./critic.mjs";
import { userDirs } from "../../skills/explainer-video/scripts/lib/paths.mjs";
import {
  catalogue,
  dest,
} from "../../skills/explainer-video/scripts/lib/tools.mjs";
import { ARABIC, SCRIPT } from "./scene-file.mjs";

const here = path.dirname(fileURLToPath(import.meta.url));
const skill = path.join(here, "..", "..", "skills", "explainer-video");

const temps = [];
after(() =>
  temps.forEach((t) => fs.rmSync(t, { recursive: true, force: true })),
);

// A temp machine: tool cache and font store as setup leaves them, and a
// project holding explainers/demo/script.md.
function fixture(text = SCRIPT) {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "explainer-board-"));
  temps.push(tmp);
  const env = {
    PATH: process.env.PATH,
    HOME: path.join(tmp, "home"),
    XDG_CONFIG_HOME: path.join(tmp, "config"),
    XDG_DATA_HOME: path.join(tmp, "data"),
    XDG_CACHE_HOME: path.join(tmp, "cache"),
    XDG_VIDEOS_DIR: path.join(tmp, "videos"),
    EXPLAINER_VIDEO_BACKEND: path.join(here, "fake-backend.mjs"),
    EXPLAINER_VIDEO_FAKE_LOG: path.join(tmp, "calls.jsonl"),
  };
  const dirs = userDirs({ platform: "linux", env, home: env.HOME });
  for (const r of catalogue().filter((r) =>
    ["npm", "chrome", "font"].includes(r.kind),
  )) {
    const d = dest(r, dirs);
    fs.mkdirSync(d, { recursive: true });
    fs.writeFileSync(path.join(d, ".stamp"), "");
    for (const f of r.files ?? [])
      fs.writeFileSync(path.join(d, `${f}.woff2`), "woff2");
  }
  const gsap = path.join(dest({ kind: "npm" }, dirs), "node_modules", "gsap");
  fs.mkdirSync(path.join(gsap, "dist"), { recursive: true });
  fs.writeFileSync(path.join(gsap, "dist", "gsap.min.js"), "/* gsap */");
  const dir = path.join(tmp, "proj", "explainers", "demo");
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(path.join(dir, "script.md"), text);
  return { tmp, dir, env, log: env.EXPLAINER_VIDEO_FAKE_LOG };
}

function run(fx, script, args = [], extra = {}) {
  const r = spawnSync(
    process.execPath,
    [path.join(skill, "scripts", script), fx.dir, ...args],
    { env: { ...fx.env, ...extra }, encoding: "utf8" },
  );
  return { code: r.status, out: r.stdout, err: r.stderr };
}
const ok = (r, what) => {
  assert.equal(r.code, 0, `${what}: ${r.out}${r.err}`);
  return r;
};
const compile = (fx) => ok(run(fx, "script/compile.mjs"), "compile");
const voice = (fx) => ok(run(fx, "voice/voice.mjs"), "voice");
const stills = (fx) => ok(run(fx, "render/render.mjs", ["--stills"]), "stills");
const board = (fx, ...args) =>
  run(fx, "storyboard/board.mjs", args, fx.extra ?? {});
const prep = (fx) => {
  compile(fx);
  voice(fx);
  return stills(fx);
};

const read = (...p) => fs.readFileSync(path.join(...p), "utf8");
const doc = (fx, n) => JSON.parse(read(fx.dir, "board", `${n}.json`));
const calls = (fx, name) =>
  fs.existsSync(fx.log)
    ? read(fx.log)
        .trim()
        .split("\n")
        .map((l) => JSON.parse(l))
        .filter((c) => c.call === name)
    : [];

test("build refuses before compile, voice or stills with the documented reason", () => {
  const fx = fixture();
  let r = board(fx, "build");
  assert.equal(r.code, 1);
  assert.match(
    r.err,
    /^board: no script\.json: run the compile stage first \(script\/compile\.mjs\)/,
  );
  compile(fx);
  r = board(fx, "build");
  assert.equal(r.code, 1);
  assert.match(
    r.err,
    /^board: no voice\.json for this script: run the voice stage first \(voice\/voice\.mjs\)/,
  );
  voice(fx);
  r = board(fx, "build");
  assert.equal(r.code, 1);
  assert.match(
    r.err,
    /^board: no still for scene hook: run node render\.mjs .+ --stills/,
  );
  assert.equal(board(fx).code, 2);
});

test("render --stills renders the stills only, and build writes an open board with the script's own narration", () => {
  const fx = fixture();
  const r = prep(fx);
  assert.match(r.out, /^render: stills 0\/3 cached$/m);
  const hf = calls(fx, "hyperframes");
  assert.equal(hf.length, 1);
  assert.ok(hf[0].args.includes("png-sequence"));
  assert.ok(!fs.existsSync(path.join(fx.dir, "out", "demo.mp4")));
  // A delivered run's out/ is left alone: stills again keep its video.
  fs.mkdirSync(path.join(fx.dir, "out"));
  fs.writeFileSync(path.join(fx.dir, "out", "demo.mp4"), "video");
  stills(fx);
  assert.equal(read(fx.dir, "out/demo.mp4"), "video");
  const list = JSON.parse(read(fx.dir, "stills.json"));
  assert.deepEqual(
    list.scenes.map((s) => s.id),
    ["hook", "steps", "gate"],
  );

  const b = ok(board(fx, "build"), "build");
  assert.match(
    b.out,
    /^board 1: review, 3 card\(s\), 3 to answer -> board\/1\.json$/m,
  );
  assert.match(b.out, /^board: local page storyboard\.html$/m);
  const d = doc(fx, 1);
  assert.equal(d.version, 1);
  assert.equal(d.kind, "review");
  assert.deepEqual(
    d.scenes.map((s) => s.status),
    ["open", "open", "open"],
  );
  assert.equal(
    d.scenes[1].narration,
    "1. It reads the issue. [ex-1]\n2. It writes a failing test. [ex-2]\n3. Then the code makes it pass. [ex-5]",
  );
  assert.equal(d.scenes[0].role, undefined);
  assert.match(d.scenes[1].style, /^cards · claude-code · am_fenrir$/);
  for (const c of d.scenes)
    for (const f of [c.still, c.audio])
      assert.ok(fs.existsSync(path.join(fx.dir, f)), f);
  // The asset upload takes video types but no audio type, so each narration
  // card plays an audio-only WebM cut once from the voice WAV.
  for (const c of d.scenes) assert.match(c.audio, /\.webm$/);
  assert.equal(calls(fx, "narration").length, 3);
  assert.ok(!fs.existsSync(path.join(fx.dir, "board", "page.html")));

  const local = read(fx.dir, "storyboard.html");
  // Opened as a file, the page has no skeleton to name its encoding.
  assert.match(local, /^<!doctype html>\n<meta charset="utf-8">\n<title>/);
  const embedded = local.match(
    /<script type="application\/json" id="board">(.*?)<\/script>/s,
  )[1];
  assert.deepEqual(JSON.parse(embedded), d);
  assert.ok(!embedded.includes("<"));
  assert.match(local, /<title>How Ship lands a pull request<\/title>/);

  ok(board(fx, "build"), "build");
  assert.equal(calls(fx, "narration").length, 3);
});

test("page with no url writes the page to publish with its title filled and no board", () => {
  const fx = fixture(
    '# Fish & "chips" <fast>\n' + SCRIPT.split("\n").slice(1).join("\n"),
  );
  assert.equal(board(fx, "page").code, 1);
  compile(fx);
  const r = ok(board(fx, "page"), "page");
  assert.match(r.out, /^board: page board\/page\.html$/m);
  const page = read(fx.dir, "board", "page.html");
  assert.match(
    page,
    /<title>Fish &amp; &quot;chips&quot; &lt;fast&gt;<\/title>/,
  );
  assert.ok(!page.includes("{{TITLE}}"));
  assert.match(page, /id="board">null<\/script>/);
});

test("a media file whose encode failed is made again on the next build, not served from the cache", () => {
  const fx = fixture();
  prep(fx);
  const r = run(fx, "storyboard/board.mjs", ["build"], {
    EXPLAINER_VIDEO_FAKE_NARRATION_FAIL: "1",
  });
  assert.equal(r.code, 1);
  assert.match(r.err, /^board: ffmpeg: encode failed$/m);
  assert.equal(calls(fx, "narration").length, 1);
  ok(board(fx, "build"), "build");
  assert.equal(calls(fx, "narration").length, 4);
  for (const c of doc(fx, 1).scenes)
    assert.notEqual(read(fx.dir, c.audio), "part");
});

test("a published page needs every media file uploaded and recorded before build writes URLs, and --local builds without it", () => {
  const fx = fixture();
  prep(fx);
  let r = board(fx, "page", "http://x/page");
  assert.equal(r.code, 1);
  r = ok(board(fx, "page", "https://claude.ai/artifact/abc"), "page");
  assert.match(r.out, /^board: page https:\/\/claude\.ai\/artifact\/abc/m);
  assert.equal(
    JSON.parse(read(fx.dir, "manifest.json")).board,
    "https://claude.ai/artifact/abc",
  );

  r = board(fx, "build");
  assert.equal(r.code, 1);
  const uploads = r.err.match(/^board: upload .+ \(\d+\.\d MB\)$/gm);
  assert.equal(uploads.length, 6);
  assert.match(
    r.err,
    /board: record each upload with: node board\.mjs .+ asset <path>=<url>/,
  );
  assert.ok(!fs.existsSync(path.join(fx.dir, "board", "1.json")));

  const files = uploads.map((l) => l.match(/upload (\S+) /)[1]);
  assert.equal(board(fx, "asset", `${files[0]}=http://x/a`).code, 1);
  assert.equal(board(fx, "asset", "nope.png=https://x/a").code, 1);
  assert.equal(board(fx, "asset", `${files[0]}=/_blob/../x`).code, 1);
  assert.ok(files.every((f) => !f.endsWith(".wav")));
  // The Artifact upload answers with /_blob/<id>; an https URL is kept too.
  const blob = (i) => `/_blob/${String(i).padStart(32, "0")}`;
  r = ok(
    board(
      fx,
      "asset",
      ...files.map((f, i) =>
        i % 2 ? `${f}=${blob(i)}` : `${f}=https://cdn.x/${i}?a=b`,
      ),
    ),
    "asset",
  );
  assert.match(r.out, /^board: 6 asset\(s\) recorded$/m);

  r = ok(board(fx, "build"), "build");
  assert.match(r.out, /^board: post board\/1\.json to boards\/1$/m);
  const d = doc(fx, 1);
  for (const c of d.scenes) {
    assert.match(c.still, /^(https:\/\/cdn\.x\/|\/_blob\/[0-9a-f]{32}$)/);
    assert.match(c.audio, /^(https:\/\/cdn\.x\/|\/_blob\/[0-9a-f]{32}$)/);
  }
  // storyboard.html is opened from the run folder, so it reads the run's paths.
  const embedded = () =>
    JSON.parse(
      read(fx.dir, "storyboard.html").match(
        /<script type="application\/json" id="board">(.*?)<\/script>/s,
      )[1],
    );
  assert.deepEqual(
    embedded().scenes.map((c) => c.still),
    files.filter((f) => f.endsWith(".png")),
  );

  // The page out of reach: --local builds the next version with no uploads.
  fs.rmSync(path.join(fx.dir, "board", "assets.json"));
  assert.equal(board(fx, "build", "--x").code, 2);
  r = ok(board(fx, "build", "--local"), "build --local");
  assert.match(r.out, /^board: local page storyboard\.html$/m);
  assert.deepEqual(
    doc(fx, 2).scenes.map((c) => c.still),
    embedded().scenes.map((c) => c.still),
  );
  assert.ok(doc(fx, 2).scenes.every((c) => c.still.startsWith(".cache/")));
});

test("apply writes edited narration into script.md only, and the revised scene alone reruns through voice and stills", () => {
  const fx = fixture();
  prep(fx);
  ok(board(fx, "build"), "build");
  const before = read(fx.dir, "script.md").split("\n");
  const file = path.join(fx.tmp, "answers.txt");
  fs.writeFileSync(
    file,
    [
      "explainer-video: board 1 answers (database document answers/board-1)",
      "hook: Approve",
      "steps: Revise",
      "  note: say ticket",
      "  narration:",
      "    1. It reads the ticket. [ex-1]",
      "    2. It writes a failing test. [ex-2]",
      "    3. Then the code makes it pass. [ex-5]",
      "gate: Approve",
    ].join("\n"),
  );
  const r = ok(board(fx, "apply", file), "apply");
  assert.match(r.out, /^board hook: approve$/m);
  assert.match(r.out, /^board steps: revise: say ticket, narration edited$/m);
  assert.match(r.out, /^board: redo steps$/m);
  const after = read(fx.dir, "script.md").split("\n");
  assert.equal(after.length, before.length);
  const changed = before
    .map((l, i) => (l === after[i] ? null : i))
    .filter((i) => i !== null);
  assert.deepEqual(
    changed.map((i) => after[i]),
    ["1. It reads the ticket. [ex-1]"],
  );
  assert.equal(before[changed[0]], "1. It reads the issue. [ex-1]");
  const answers = JSON.parse(read(fx.dir, "board", "answers-1.json"));
  assert.equal(answers.scenes[1].choice, "revise");

  compile(fx);
  const v = voice(fx);
  assert.match(v.out, /^voice hook: cached/m);
  assert.match(v.out, /^voice gate: cached/m);
  assert.match(v.out, /^voice steps: voiced/m);
  assert.match(stills(fx).out, /^render: stills 2\/3 cached$/m);
  const b = ok(board(fx, "build"), "build 2");
  assert.match(b.out, /^board 2: review, 3 card\(s\), 1 to answer/m);
  assert.deepEqual(
    doc(fx, 2).scenes.map((s) => [s.id, s.status]),
    [
      ["hook", "approved"],
      ["steps", "open"],
      ["gate", "approved"],
    ],
  );
});

test("apply redoes an approved card whose narration was edited", () => {
  const fx = fixture();
  prep(fx);
  ok(board(fx, "build"), "build");
  const file = path.join(fx.tmp, "answers.txt");
  fs.writeFileSync(
    file,
    [
      "explainer-video: board 1 answers (database document answers/board-1)",
      "hook: Approve",
      "steps: Approve",
      "  narration:",
      "    1. It reads the ticket. [ex-1]",
      "    2. It writes a failing test. [ex-2]",
      "    3. Then the code makes it pass. [ex-5]",
      "gate: Approve",
    ].join("\n"),
  );
  const r = ok(board(fx, "apply", file), "apply");
  assert.match(r.out, /^board steps: approve, narration edited$/m);
  assert.match(r.out, /^board: redo steps$/m);
});

test("an Arabic board lists its kept terms, and one edited changes speech, screen and captions alike", () => {
  // A spoken form spelt for the old term goes with it.
  const fx = fixture(
    ARABIC.replace("1. الـ CI بيشغل", "1. الـ {CI|سي آي} بيشغل"),
  );
  fx.env.GEMINI_API_KEY = "test-key";
  prep(fx);
  ok(board(fx, "build"), "build");
  assert.deepEqual(doc(fx, 1).kept, [
    "Ship",
    "issue",
    "pull request",
    "merge",
    "branch",
    "CI",
    "review",
  ]);
  const file = path.join(fx.tmp, "answers.txt");
  const answers = (kept) =>
    [
      "explainer-video: board 1 answers (database document answers/board-1)",
      "hook: Approve",
      "steps: Approve",
      "code: Approve",
      kept,
    ].join("\n");
  fs.writeFileSync(file, answers("Kept: shell -> سكريبت"));
  assert.match(
    board(fx, "apply", file).err,
    /^board: the answers edit shell, which board 1 does not keep$/m,
  );
  fs.writeFileSync(file, answers("Kept: CI -> GitHub Actions"));
  const r = ok(board(fx, "apply", file), "apply");
  assert.match(r.out, /^board kept: CI -> GitHub Actions$/m);
  assert.match(r.out, /^board: redo steps,code$/m);
  const md = read(fx.dir, "script.md");
  assert.doesNotMatch(md, /\bCI\b/);
  assert.match(md, /بيشغل الـ GitHub Actions على الـ branch\. \[ex-3\]/);
  assert.match(md, /1\. الـ GitHub Actions بيشغل الأمر/);
  // Code stays as written.
  assert.match(md, /scripts\/local-gate\.sh\\ngh pr create/);

  compile(fx);
  const script = JSON.parse(read(fx.dir, "script.json"));
  const steps = script.scenes.find((s) => s.id === "steps");
  assert.equal(steps.visual.props.steps[1].label, "GitHub Actions");
  assert.ok(
    steps.captions.flat().some((c) => c.text === "GitHub Actions"),
    JSON.stringify(steps.captions),
  );
  assert.ok(script.kept.includes("GitHub Actions"));
  assert.ok(!script.kept.includes("CI"));
  const before = calls(fx, "synthesize").length;
  voice(fx);
  const said = calls(fx, "synthesize")
    .slice(before)
    .map((c) => c.text);
  assert.ok(
    said.some((t) => /الـ GitHub Actions بيشغل/.test(t)),
    said,
  );
  assert.ok(!said.some((t) => t.includes("سي آي")), said);
});

test("apply refuses answers for a stale version and a text cut to fit a comment", () => {
  const fx = fixture();
  prep(fx);
  ok(board(fx, "build"), "build");
  const file = path.join(fx.tmp, "answers.txt");
  const lines = (n) => [
    `explainer-video: board ${n} answers (database document answers/board-${n})`,
    "hook: Approve",
    "steps: Approve",
    "gate: Approve",
  ];
  fs.writeFileSync(file, lines(2).join("\n"));
  let r = board(fx, "apply", file);
  assert.equal(r.code, 1);
  assert.match(r.err, /^board: answers for board 2, the latest is board 1/);
  fs.writeFileSync(
    file,
    [...lines(1), "[cut to fit: read answers/board-1]"].join("\n"),
  );
  r = board(fx, "apply", file);
  assert.equal(r.code, 1);
  assert.match(
    r.err,
    /^board: the answers were cut to fit a comment: read answers\/board-1 from the database/,
  );
  fs.writeFileSync(file, lines(1).slice(0, 3).join("\n"));
  assert.equal(board(fx, "apply", file).code, 1);
  fs.writeFileSync(file, lines(1).join("\n"));
  const ok1 = board(fx, "apply", file);
  assert.equal(ok1.code, 0);
  assert.match(ok1.out, /^board: approved$/m);
});

test("a red gate record of this script at its third attempt reopens the scenes its evidence names, asks for no revision when it names none, and is spent once answered", () => {
  const fx = fixture();
  prep(fx);
  const script = JSON.parse(read(fx.dir, "script.json"));
  const hash = crypto
    .createHash("sha256")
    .update(JSON.stringify(script.scenes.map((s) => [s.id, s.narration])))
    .digest("hex")
    .slice(0, 16);
  const record = (attempts) =>
    fs.writeFileSync(
      path.join(fx.dir, "gates.json"),
      JSON.stringify({
        script: hash,
        render: "x",
        attempts,
        gates: {
          layout: {
            status: "fail",
            measured:
              "1 finding(s), first: 1.5 s steps: text 12 px under 18 px",
            floor: "none, text >= 18 px, margin 5%",
            attempts,
            evidence: ["1.5 s steps: text 12 px under 18 px"],
          },
          loudness: {
            status: "pass",
            measured: "-14.0 LUFS",
            floor: "-14",
            attempts: 0,
            evidence: [],
          },
        },
      }),
    );
  record(1);
  let r = ok(board(fx, "build"), "build");
  assert.ok(!("banner" in doc(fx, 1)));
  assert.ok(!/banner/.test(r.out));

  record(3);
  r = ok(board(fx, "build"), "build");
  assert.match(r.out, /, banner: 1 red gate\(s\) -> board\/2\.json$/m);
  const d = doc(fx, 2);
  assert.match(
    d.banner.text,
    /^The video gates stayed red with no fix attempt left/,
  );
  assert.deepEqual(d.banner.gates, [
    "gate layout: fail: 1 finding(s), first: 1.5 s steps: text 12 px under 18 px vs none, text >= 18 px, margin 5%",
  ]);
  assert.deepEqual(
    d.scenes.map((s) => s.status),
    ["open", "reopened", "open"],
  );

  // Answered, the same red record is spent: the revision's build posts no
  // banner and reopens nothing until a render writes a new record.
  const file = path.join(fx.tmp, "answers.txt");
  fs.writeFileSync(
    file,
    [
      "explainer-video: board 2 answers (database document answers/board-2)",
      "hook: Approve",
      "steps: Revise",
      "  note: larger text",
      "gate: Approve",
    ].join("\n"),
  );
  ok(board(fx, "apply", file), "apply");
  r = ok(board(fx, "build"), "build");
  assert.ok(!("banner" in doc(fx, 3)));
  assert.deepEqual(
    doc(fx, 3).scenes.map((s) => s.status),
    ["approved", "open", "approved"],
  );
  record(4);
  ok(board(fx, "build"), "build");
  assert.ok("banner" in doc(fx, 4));
  assert.match(doc(fx, 4).banner.text, /Revise the reopened cards\.$/);

  // A red gate naming no scene reopens no card, so the banner asks for none.
  const g = JSON.parse(read(fx.dir, "gates.json"));
  g.gates.layout.evidence = ["integrated loudness -9.0 LUFS"];
  fs.writeFileSync(path.join(fx.dir, "gates.json"), JSON.stringify(g));
  ok(board(fx, "build"), "build");
  assert.ok(!doc(fx, 5).scenes.some((s) => s.status === "reopened"));
  assert.doesNotMatch(doc(fx, 5).banner.text, /Revise/);
});

test("a delivered run builds a clip per scene once, from the timeline, refuses a clip over the asset cap, and reviews again after new stills", () => {
  const fx = fixture();
  compile(fx);
  voice(fx);
  ok(
    judged(fx.dir, () => run(fx, "render/render.mjs")),
    "render",
  );
  const timeline = JSON.parse(read(fx.dir, "timeline.json")).scenes;
  let r = ok(board(fx, "build"), "build");
  assert.match(r.out, /^board 1: delivered, 3 card\(s\), 0 to answer/m);
  const d = doc(fx, 1);
  assert.equal(d.kind, "delivered");
  assert.deepEqual(
    d.scenes.map((s) => s.status),
    ["approved", "approved", "approved"],
  );
  for (const c of d.scenes) assert.ok(fs.existsSync(path.join(fx.dir, c.clip)));
  const cut = calls(fx, "clip");
  assert.equal(cut.length, 3);
  assert.deepEqual(
    cut.map((c) => [c.start, c.duration]),
    timeline.map((t) => [t.start, t.duration]),
  );
  ok(board(fx, "build"), "build again");
  assert.equal(calls(fx, "clip").length, 3);
  // New stills start a review: the delivered MP4 is of an earlier script.
  stills(fx);
  r = ok(board(fx, "build"), "build after stills");
  assert.match(r.out, /^board 3: review, /m);
  assert.ok(fs.existsSync(path.join(fx.dir, "out", "demo.mp4")));

  const big = fixture();
  compile(big);
  voice(big);
  ok(
    judged(big.dir, () => run(big, "render/render.mjs")),
    "render",
  );
  r = run(big, "storyboard/board.mjs", ["build"], {
    EXPLAINER_VIDEO_FAKE_CLIP_BYTES: "16000000",
  });
  assert.equal(r.code, 1);
  assert.match(r.err, /^board: .+\.mp4 is 16\.0 MB, over the 15 MB asset cap/);
});

test("a still over the asset cap is refused with its size", () => {
  const fx = fixture();
  prep(fx);
  const still = JSON.parse(read(fx.dir, "stills.json")).scenes[0].still;
  fs.truncateSync(path.join(fx.dir, still), 16_000_000);
  const r = board(fx, "build");
  assert.equal(r.code, 1);
  assert.equal(
    r.err.trim(),
    `board: ${still} is 16.0 MB, over the 15 MB asset cap`,
  );
});
