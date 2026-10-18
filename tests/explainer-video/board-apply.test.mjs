// The storyboard board through its process doors, part 2: kept terms, stale
// answers, a reopened red gate and the delivered clips.
import { test } from "node:test";
import assert from "node:assert/strict";
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { judged } from "./critic.mjs";
import { ARABIC } from "./scene-file.mjs";
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

test("kept terms edited together are respelt from the text as it stood, so two can swap", () => {
  const fx = fixture(ARABIC);
  fx.env.GEMINI_API_KEY = "test-key";
  prep(fx);
  ok(board(fx, "build"), "build");
  const file = path.join(fx.tmp, "answers.txt");
  fs.writeFileSync(
    file,
    [
      "explainer-video: board 1 answers (database document answers/board-1)",
      "hook: Approve",
      "steps: Approve",
      "code: Approve",
      "Kept: branch -> merge",
      "Kept: merge -> branch",
    ].join("\n"),
  );
  ok(board(fx, "apply", file), "apply");
  const md = read(fx.dir, "script.md");
  assert.match(md, /الأول بيعمل merge جديد\./);
  assert.match(md, /بيطلب review قبل الـ branch\./);
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
