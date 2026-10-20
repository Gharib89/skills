// The storyboard board through its process doors, part 1: build, stills, the
// page to publish, and apply of edited narration.
import { after, test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { SCRIPT } from "./scene-file.mjs";
import {
  board,
  calls,
  compile,
  doc,
  fixture,
  ok,
  prep,
  read,
  run,
  stills,
  voice,
} from "./board-lib.mjs";

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

test("a scene showing a rich component is marked past the default on its card", () => {
  const rich = SCRIPT.replace(
    /\{\n {2}"component": "cards"[\s\S]*?\n\}\n/,
    '{ "component": "words", "props": { "lines": [ { "at": 1, "text": "reads the issue", "on": "reads" } ] } }\n',
  );
  const fx = fixture(rich);
  prep(fx);
  ok(board(fx, "build"), "build");
  const d = doc(fx, 1);
  assert.match(
    d.scenes[1].style,
    /^words · past the default · claude-code · am_fenrir$/,
  );
  assert.match(d.scenes[0].style, /^title · claude-code · am_fenrir$/);
});
