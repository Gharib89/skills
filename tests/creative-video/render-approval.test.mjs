// The render's hold on the storyboard (#1046): an attended run renders only
// the look the board approved, an unattended run its recorded direction, and
// what changed after the approval is named on stdout for DELIVERY.md.
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { calls, exec, project, readJson, render } from "./timing-lib.mjs";
import { compose, runGates } from "./gates-lib.mjs";
import { answersText, apply, build, ok, ready } from "./board-lib.mjs";

// A run folder ready for its board and attended: no unattended record.
function attended(bodies) {
  const fx = ready({ bodies });
  fs.rmSync(path.join(fx.dir, "unattended.json"));
  return fx;
}

// Board `n` built, then answered with `lines`.
function answer(fx, n, ...lines) {
  ok(build(fx));
  ok(apply(fx, answersText(n, ...lines)));
}

function renders(fx) {
  ok(runGates(fx));
  const r = exec(render, fx);
  assert.equal(r.code, 0, r.out + r.err);
  return r.out;
}

const REFUSED =
  /^render: no approval of the look: run the storyboard until `board apply` prints `board: approved`/;

function refused(fx, reason, what = "") {
  ok(runGates(fx));
  const r = exec(render, fx);
  assert.equal(r.code, 1, `${what} ${r.out}${r.err}`);
  assert.match(r.err, reason, what && `${what}: ${r.err}`);
}

test("an attended run with no approval is refused before any render, out/ left as it was", () => {
  const fx = attended();
  ok(runGates(fx));
  fs.mkdirSync(path.join(fx.dir, "out"));
  fs.writeFileSync(path.join(fx.dir, "out", "old.mp4"), "old");
  const r = exec(render, fx);
  assert.equal(r.code, 1);
  assert.match(r.err, REFUSED);
  assert.equal(r.out, "");
  assert.deepEqual(fs.readdirSync(path.join(fx.dir, "out")), ["old.mp4"]);
  assert.ok(!calls(fx).some((c) => c.call === "hyperframes"));
});

test("answers that only comment on a scene are no approval", () => {
  const fx = attended();
  answer(fx, 1, "hook: slower");
  refused(fx, REFUSED);
});

test("the board's approval lets the render go ahead, naming nothing when nothing changed", () => {
  const fx = attended();
  answer(fx, 1, "Approved: the look");
  const out = renders(fx);
  assert.ok(!/approval:|unattended/.test(out), out);
});

test("a direction or a look asked after the approval cancels it", () => {
  for (const asked of ["Direction: kitchen", "Look: warmer"]) {
    const fx = attended();
    answer(fx, 1, "Approved: the look");
    answer(fx, 2, asked);
    refused(fx, REFUSED, asked);
  }
});

test("a later approval leaves the first standing, and one after a direction or a look takes over", () => {
  const fx = attended();
  answer(fx, 1, "Approved: the look");
  answer(fx, 2, "hook: slower");
  compose(fx, "hook", "<p>hook, slower</p>");
  answer(fx, 3, "Approved: the look");
  assert.ok(
    renders(fx).includes("render: changed after board 1's approval: hook\n"),
  );
  answer(fx, 4, "Look: warmer");
  answer(fx, 5, "Approved: the look");
  const out = renders(fx);
  assert.ok(!out.includes("approval:"), out);
});

test("scene notes after the approval do not cancel it, and the scenes they changed are named", () => {
  const fx = attended();
  answer(fx, 1, "Approved: the look");
  answer(fx, 2, "hook: slower");
  compose(fx, "hook", "<p>hook, slower</p>");
  assert.ok(
    renders(fx).includes("render: changed after board 1's approval: hook\n"),
  );
});

test("an approved scene, the kit and an asset changed after the approval still render, each named on one line", () => {
  const fx = attended();
  fs.mkdirSync(project(fx, "assets"), { recursive: true });
  fs.writeFileSync(project(fx, "assets", "logo.svg"), "<svg/>");
  answer(fx, 1, "Approved: the look");
  compose(fx, "context", "<p>context, moved by a gate fix</p>");
  fs.mkdirSync(project(fx, "kit"), { recursive: true });
  fs.writeFileSync(project(fx, "kit", "look.css"), "p { color: red }");
  fs.writeFileSync(project(fx, "assets", "logo.svg"), "<svg></svg>");
  assert.ok(
    renders(fx).includes(
      "render: changed after board 1's approval: context, the kit, assets/logo.svg\n",
    ),
  );
});

test("a scene the approved board did not show is not named, in chapter 1 too", () => {
  const fx = attended();
  answer(fx, 1, "Approved: the look");
  // As if recap were scripted after the approval.
  const bfile = path.join(fx.dir, "board", "1.json");
  const board = readJson(bfile);
  board.scenes = board.scenes.filter((s) => s.id !== "recap");
  fs.writeFileSync(bfile, JSON.stringify(board));
  const out = renders(fx);
  assert.ok(!out.includes("approval:"), out);
});

test("a later chapter's scene the approved board did not have is not named", () => {
  // Each chapter's first frame draws its title.
  const fx = attended({ hook: "<p>The loop: hook line</p>" });
  const plan = [
    { title: "The loop", focus: "what a loop is", scenes: ["hook", "context"] },
    { title: "The wrap", focus: "how it ends", scenes: ["recap"] },
  ];
  const sfile = path.join(fx.dir, "script.json");
  fs.writeFileSync(
    sfile,
    JSON.stringify({ ...readJson(sfile), chapters: plan }),
  );
  const tfile = path.join(fx.dir, "timeline.json");
  const tl = readJson(tfile);
  const at = (id) => tl.scenes.find((s) => s.id === id);
  tl.chapters = plan.map((c, i) => ({
    n: i + 1,
    title: c.title,
    start: at(c.scenes[0]).start,
    end: at(c.scenes.at(-1)).start + at(c.scenes.at(-1)).duration,
    scenes: c.scenes,
  }));
  fs.writeFileSync(tfile, JSON.stringify(tl));
  const recap = project(fx, "compositions", "recap.html");
  fs.rmSync(recap);
  answer(fx, 1, "Approved: the look");
  compose(fx, "recap", "<p>The wrap: recap line</p>");
  const out = renders(fx);
  assert.ok(!out.includes("approval:"), out);
});

test("an unattended run's recorded direction lets the render go ahead, and its output says the run is unattended", () => {
  const fx = ready();
  const out = renders(fx);
  assert.ok(
    out.includes("render: unattended run, no approval: direction switch\n"),
    out,
  );
});

test("an answers or board file of the wrong shape is refused by name", () => {
  for (const [f, edit, reason] of [
    [
      "answers-1.json",
      (a) => delete a.scenes,
      /^render: board\/answers-1\.json: scenes is not a list/,
    ],
    [
      "1.json",
      (b) => delete b.assets,
      /^render: board\/1\.json: assets is not an object/,
    ],
  ]) {
    const fx = attended();
    answer(fx, 1, "Approved: the look");
    const file = path.join(fx.dir, "board", f);
    const doc = readJson(file);
    edit(doc);
    fs.writeFileSync(file, JSON.stringify(doc));
    refused(fx, reason, f);
  }
});

test("an unattended record of the wrong shape is refused by name", () => {
  const fx = ready();
  fs.writeFileSync(path.join(fx.dir, "unattended.json"), "{}");
  refused(fx, /^render: unattended\.json: direction is not text/);
});
