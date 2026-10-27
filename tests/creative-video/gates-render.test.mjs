// The render's side of the gates: it refuses a project the gates have not
// passed for its current inputs, and checks the delivered captions against the
// composition's cues, not only their count.
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { calls, project, read, render, exec } from "./timing-lib.mjs";
import { compose, runGates, timed } from "./gates-lib.mjs";

const REFUSED =
  /^render: the gates have not passed on this project: run gates\/gates\.mjs/;
const rendered = (fx) => calls(fx).some((c) => c.call === "hyperframes");

test("a render with no gates.json, or after the project changed, or on a red record is refused before any render", () => {
  const fx = timed();
  let r = exec(render, fx);
  assert.equal(r.code, 1);
  assert.match(r.err, REFUSED);
  assert.equal(runGates(fx).code, 0);
  compose(fx, "hook", "<p>changed after the gates</p>");
  r = exec(render, fx);
  assert.equal(r.code, 1);
  assert.match(r.err, REFUSED);
  compose(fx, "hook", "<p>a clipped line</p>");
  assert.equal(runGates(fx).code, 1);
  r = exec(render, fx);
  assert.equal(r.code, 1);
  assert.match(r.err, REFUSED);
  assert.ok(!rendered(fx));
});

test("a gates.json that is not JSON, or lacks its gates, is refused by name before any render", () => {
  const fx = timed();
  const record = path.join(fx.dir, "gates.json");
  fs.writeFileSync(record, "{ not json");
  let r = exec(render, fx);
  assert.equal(r.code, 1);
  assert.match(r.err, /^render: gates\.json: is not valid JSON \(/);
  fs.writeFileSync(
    record,
    JSON.stringify({ inputs: "0123456789abcdef", script: "0123456789abcdef" }),
  );
  r = exec(render, fx);
  assert.equal(r.code, 1);
  assert.match(r.err, /^render: gates\.json: gates is not an object/);
  assert.ok(!rendered(fx));
});

test("a kit file added after the gates passed also makes them stale", () => {
  const fx = timed();
  assert.equal(runGates(fx).code, 0);
  fs.mkdirSync(project(fx, "kit"), { recursive: true });
  fs.writeFileSync(project(fx, "kit", "look.css"), "");
  assert.match(exec(render, fx).err, REFUSED);
});

test("a file reached through a symlink, to a file or a folder, changed after the gates passed makes them stale", () => {
  for (const link of ["file", "dir"]) {
    const fx = timed();
    const outside = path.join(fx.dir, "outside");
    fs.mkdirSync(outside);
    fs.writeFileSync(path.join(outside, "look.css"), "a {}");
    if (link === "file")
      fs.symlinkSync(path.join(outside, "look.css"), project(fx, "look.css"));
    else fs.symlinkSync(outside, project(fx, "kit"));
    assert.equal(runGates(fx).code, 0);
    fs.writeFileSync(path.join(outside, "look.css"), "b {}");
    assert.match(exec(render, fx).err, REFUSED, link);
  }
});

test("a render after the gates passed delivers, and its captions check names its findings against the composition's cues", () => {
  const fx = timed();
  assert.equal(runGates(fx).code, 0);
  const ok = exec(render, fx);
  assert.equal(ok.code, 0, ok.out + ok.err);
  assert.ok(ok.out.includes("delivery captions: pass\n"));
  assert.ok(!ok.out.includes("delivery srt"));

  // a cue the composition draws that the timeline does not hold
  const file = project(fx, "compositions", "captions.html");
  fs.writeFileSync(file, read(file).replace(/Ship/, "Shop"));
  assert.equal(runGates(fx).code, 0);
  const bad = exec(render, fx);
  assert.equal(bad.code, 1);
  assert.match(
    bad.out,
    /^delivery captions: fail: 1 finding\(s\), first: SRT cue 1 reads "Ship drives .*", the composition "Shop drives .*" vs none$/m,
  );
  assert.ok(!fs.existsSync(path.join(fx.dir, "out")));
});
