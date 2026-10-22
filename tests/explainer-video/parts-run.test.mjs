// A part's folder is a run folder of its own: the explainers folder's style
// store and `.gitignore` reach it, and its video lands as one numbered file in
// the videos folder its series shares.
import { test } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import {
  fixture,
  node,
  parts,
  plan,
  readJson,
  writePlan,
} from "./parts-lib.mjs";
import {
  fixture as machine,
  profile,
  put,
  read,
  render,
  skill,
  unstyled,
} from "./render-lib.mjs";

const git = (cwd, ...args) =>
  spawnSync("git", args, { cwd, encoding: "utf8" }).status;

test("a part's files follow the ignore rules of its explainers folder: the recipe is committed, what a stage rebuilds is not", () => {
  const fx = fixture();
  git(fx.tmp, "init", "-q");
  writePlan(fx, plan([4, 4, 4]));
  assert.equal(parts(fx, "start", "1").code, 0);
  const dir = path.join(fx.dir, "parts", "01-claiming-work");
  assert.equal(fs.existsSync(path.join(fx.dir, "parts", ".gitignore")), false);
  for (const f of ["script.json", "voice.json", "out/demo.mp4", "board/1.json"])
    (fs.mkdirSync(path.dirname(path.join(dir, f)), { recursive: true }),
      fs.writeFileSync(path.join(dir, f), "x"));
  for (const [f, ignored] of [
    ["script.json", true],
    ["voice.json", true],
    ["out/demo.mp4", true],
    ["board/1.json", true],
    ["script.md", false],
    ["brief.json", false],
    ["part.json", false],
  ])
    assert.equal(
      git(fx.tmp, "check-ignore", "-q", path.join(dir, f)) === 0,
      ignored,
      f,
    );
  assert.notEqual(
    git(fx.tmp, "check-ignore", "-q", path.join(fx.dir, "parts.json")),
    0,
  );
});

test("a brief change in a part sees the project style store of its explainers folder, and its menu lists those styles", async () => {
  const fx = fixture();
  writePlan(fx, plan([4, 4, 4]));
  assert.equal(parts(fx, "start", "1").code, 0);
  const dir = path.join(fx.dir, "parts", "01-claiming-work");
  const store = path.join(fx.tmp, "explainers", ".styles");
  put(store, "mine.json", profile("Mine"));
  const r = node({ ...fx, dir }, "brief/brief.mjs", ["style=mine"]);
  assert.equal(r.code, 0, r.err);
  assert.equal(readJson(dir, "brief.json").style, "mine");
  const { knobOffer } = await import(
    path.join(skill, "scripts", "brief", "knobs.mjs")
  );
  assert.ok(knobOffer("style", dir, {}).options.includes("mine"));
});

// A part folder under the render fixture's project, its scene file moved in.
function partOf() {
  const fx = machine();
  const dir = path.join(fx.dir, "parts", "01-intro");
  fs.mkdirSync(dir, { recursive: true });
  fs.renameSync(path.join(fx.dir, "script.md"), path.join(dir, "script.md"));
  fs.writeFileSync(
    path.join(dir, "part.json"),
    JSON.stringify({ series: "demo", n: 1, of: 2, title: "Intro" }),
  );
  return { ...fx, series: fx.dir, dir };
}

test("a part takes its style from the store of the explainers folder it sits in", () => {
  const fx = partOf();
  fs.writeFileSync(path.join(fx.dir, "script.md"), unstyled);
  const store = path.join(fx.series, "..", ".styles");
  put(store, "default", "mine");
  put(store, "mine.json", profile("Mine"));
  const r = render(fx);
  assert.equal(r.code, 0, r.out + r.err);
  assert.equal(JSON.parse(read(fx.dir, "style.json")).name, "mine");
});

test("a part's video is delivered under its number into the series' folder, with its caption file and poster", () => {
  const fx = partOf();
  const r = render(fx);
  assert.equal(r.code, 0, r.out + r.err);
  const where = path.join(fx.tmp, "videos", "explainer-video", "proj", "demo");
  assert.match(r.out, new RegExp(`^delivered: ${where}$`, "m"));
  assert.deepEqual(fs.readdirSync(where).sort(), [
    "01-intro.mp4",
    "01-intro.png",
    "01-intro.srt",
  ]);
  assert.equal(readJson(fx.dir, "manifest.json").delivered, where);
  // the run's own out folder keeps the names a render always gave
  assert.deepEqual(fs.readdirSync(path.join(fx.dir, "out")).sort(), [
    "01-intro.mp4",
    "01-intro.srt",
    "poster.png",
  ]);
});

test("a video that is no part's is delivered as it was, with its poster named poster.png", () => {
  const fx = machine();
  const r = render(fx);
  assert.equal(r.code, 0, r.out + r.err);
  const where = path.join(fx.tmp, "videos", "explainer-video", "proj", "demo");
  assert.deepEqual(fs.readdirSync(where).sort(), [
    "demo.mp4",
    "demo.srt",
    "poster.png",
  ]);
});
