// The video gates through their process doors, part 3: the attempt count that
// stops a run, tightened floors, cached gates runs and tool errors.
import { after, test } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { findChrome } from "../../skills/explainer-video/scripts/lib/backend.mjs";
import { SCRIPT } from "./scene-file.mjs";
import {
  assertRed,
  calls,
  delivered,
  fixture,
  read,
  record,
  render,
  skill,
  stage,
  temps,
  titled,
} from "./gates-lib.mjs";

test("a gate red three times in a row stops; a changed script starts the count again", () => {
  const fx = fixture();
  const clipped = titled("clipped");
  render(fx, clipped);
  // Each attempt changes the render: a card's value, the title still clipped.
  const second = render(
    fx,
    clipped.replace('"value": "code"', '"value": "the code"'),
  );
  assert.match(
    second.out,
    /^gates: 6 pass, 1 fail, 1 pending; next: fix attempt 2 of 2$/m,
  );
  assert.equal(record(fx).gates.layout.attempts, 2);
  const third = render(
    fx,
    clipped.replace('"value": "code"', '"value": "more code"'),
  );
  assert.equal(third.code, 1);
  assert.match(
    third.out,
    /^gates: 6 pass, 1 fail, 1 pending; stop: red after two fix attempts, no video$/m,
  );
  assert.equal(record(fx).gates.layout.attempts, 3);
  const renarrated = render(
    fx,
    clipped.replace("Here is how.", "Here is why."),
  );
  assert.match(
    renarrated.out,
    /^gates: 6 pass, 1 fail, 1 pending; next: fix attempt 1 of 2$/m,
  );
  assert.equal(record(fx).gates.layout.attempts, 1);
});

test("a red that moves from layout to contrast and back still stops", () => {
  const fx = fixture();
  assertRed(fx, render(fx, titled("clipped")), "layout", "clipped");
  const second = render(fx, titled("dim"));
  assert.match(
    second.out,
    /^gates: 6 pass, 1 fail, 1 pending; next: fix attempt 2 of 2$/m,
  );
  assert.equal(record(fx).gates.layout.attempts, 0);
  assert.equal(record(fx).gates.contrast.attempts, 1);
  const third = render(fx, titled("clipped"));
  assert.equal(third.code, 1);
  assert.match(
    third.out,
    /^gates: 6 pass, 1 fail, 1 pending; stop: red after two fix attempts, no video$/m,
  );
  assert.equal(record(fx).gates.layout.attempts, 1);
  assert.equal(record(fx).attempts, 3);
});

test("the same red render judged again keeps its attempt count", () => {
  const fx = fixture();
  render(fx, titled("clipped"));
  assert.match(record(fx).render, /^[0-9a-f]{16}$/);
  // out/ is emptied on red, so the render stage runs again on its cached video.
  const again = stage(fx, "render/render.mjs");
  assert.equal(again.code, 1, again.out + again.err);
  assert.match(
    again.out,
    /^gates: 6 pass, 1 fail, 1 pending; next: fix attempt 1 of 2$/m,
  );
  assert.equal(record(fx).gates.layout.attempts, 1);
});

test("a tightened floor is the floor applied and printed", () => {
  const fx = fixture();
  const p = JSON.parse(read(skill, "styles", "claude-code.json"));
  const styles = path.join(fx.tmp, "proj", "explainers", ".styles");
  fs.mkdirSync(styles, { recursive: true });
  fs.writeFileSync(
    path.join(styles, "big.json"),
    JSON.stringify({ ...p, gates: { layout: { textPx: 48 } } }),
  );
  const r = render(fx, SCRIPT.replace("style: claude-code", "style: big"));
  assert.equal(r.code, 1, r.out + r.err);
  assert.match(
    r.err,
    /style profile big: scale\.heading 46 is under the 48 px layout floor/,
  );
  fs.writeFileSync(
    path.join(styles, "big.json"),
    JSON.stringify({
      ...p,
      gates: { layout: { textPx: 48 } },
      scale: { heading: 48, body: 48, code: 48, small: 48, label: 48 },
    }),
  );
  const again = render(fx, SCRIPT.replace("style: claude-code", "style: big"));
  assert.match(again.out, /^gate layout: .* text >= 48 px, margin 5%$/m);
});

test("a tightened sfx floor thins the score's cues to it", () => {
  const fx = fixture();
  const p = JSON.parse(read(skill, "styles", "claude-code.json"));
  const styles = path.join(fx.tmp, "proj", "explainers", ".styles");
  fs.mkdirSync(styles, { recursive: true });
  fs.writeFileSync(
    path.join(styles, "calm.json"),
    JSON.stringify({ ...p, gates: { sfx: { perMinute: 1 } } }),
  );
  const r = render(fx, SCRIPT.replace("style: claude-code", "style: calm"));
  assert.equal(r.code, 0, r.out + r.err);
  assert.match(
    r.out,
    /^gate sfx: pass: 1 cue\(s\), at most 1 in a minute vs <= 1 a minute$/m,
  );
});

test("more sound effects in a minute than the floor fails sfx", () => {
  const fx = fixture();
  assert.equal(render(fx).code, 0);
  const cues = Array.from({ length: 25 }, (_, i) => ({ type: "whoosh", t: i }));
  fs.writeFileSync(
    path.join(fx.dir, "score.json"),
    JSON.stringify({ score: "on", cues }),
  );
  const r = stage(fx, "gates/gates.mjs");
  assert.equal(r.code, 1, r.out + r.err);
  assert.match(
    r.out,
    /^gate sfx: fail: 25 cue\(s\), at most 25 in a minute vs <= 24 a minute$/m,
  );
  assert.deepEqual(record(fx).gates.sfx.evidence, [
    "25 cues in the minute from 0.00 s, over 24",
  ]);
});

test("a second gates run with nothing changed calls neither check nor probe, yet measures loudness and captions", () => {
  const fx = fixture();
  assert.equal(render(fx).code, 0);
  const r = stage(fx, "gates/gates.mjs");
  assert.equal(r.code, 0, r.out + r.err);
  assert.equal(calls(fx, "check").length, 1);
  assert.equal(calls(fx, "probe").length, 1);
  // The render, its critic round's render again, and this run.
  assert.equal(calls(fx, "loudness").length, 3);
  assert.match(r.out, /^gate captions: pass: /m);
});

test("one changed scene re-gates only that scene's samples", () => {
  const fx = fixture();
  assert.equal(render(fx).code, 0);
  const r = render(
    fx,
    SCRIPT.replace('"value": "code"', '"value": "the code"'),
  );
  assert.equal(r.code, 0, r.out + r.err);
  const [first, again] = calls(fx, "probe");
  const steps = JSON.parse(read(fx.dir, "timeline.json")).scenes[1];
  assert.ok(again.times.length > 1);
  assert.deepEqual(
    again.times,
    first.times.filter(
      (t) => t >= steps.start && t < steps.start + steps.duration,
    ),
  );
  assert.deepEqual(calls(fx, "check")[1].times, again.times);
});

test("the gates stage before a render says which stage to run", () => {
  const fx = fixture();
  assert.equal(stage(fx, "script/compile.mjs").code, 0);
  const r = stage(fx, "gates/gates.mjs");
  assert.equal(r.code, 1, r.out + r.err);
  assert.match(
    r.err,
    /^gates: no timeline\.json: run the render stage first$/m,
  );
  const usage = spawnSync(process.execPath, [
    path.join(skill, "scripts", "gates", "gates.mjs"),
  ]);
  assert.equal(usage.status, 2);
});

test("a probe that finds no text in a scene stops the gates as a tool error, not a pass", () => {
  const fx = fixture();
  const r = render(fx, SCRIPT, { EXPLAINER_VIDEO_FAKE_BLANK: "1" });
  assert.equal(r.code, 1, r.out + r.err);
  assert.match(r.err, /^gates: layout probe: no text in scene hook$/m);
  assert.match(r.err, /^render: the gates did not pass: nothing delivered$/m);
  assert.ok(!/^gate layout: pass/m.test(r.out), r.out);
  assert.ok(!fs.existsSync(path.join(fx.tmp, "videos")));
});

test("a scene drawing no text of its own stops the gates, though captions show over it", () => {
  const fx = fixture();
  const r = render(
    fx,
    SCRIPT.replace(
      '"props": { "kicker": "Ship", "title": "Issue to pull request", "subtitle": "One run, one merge" }',
      '"props": { "title": "" }',
    ),
  );
  assert.equal(r.code, 1, r.out + r.err);
  assert.match(r.err, /^gates: layout probe: no text in scene hook$/m);
  assert.ok(!fs.existsSync(path.join(fx.tmp, "videos")));
});

test("findChrome finds Windows' chrome-headless-shell.exe", () => {
  const home = fs.mkdtempSync(path.join(os.tmpdir(), "explainer-chrome-"));
  temps.push(home);
  const dir = path.join(
    home,
    ...[".cache", "hyperframes", "chrome", "win64-x"],
    "chrome-headless-shell-win64",
  );
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(path.join(dir, "chrome-headless-shell.exe"), "");
  assert.equal(findChrome(home), path.join(dir, "chrome-headless-shell.exe"));
});

test("a check that never reached the browser stops the gates as a tool error, not a pass", () => {
  const fx = fixture();
  const r = render(fx, SCRIPT, {
    EXPLAINER_VIDEO_FAKE_CHECK: '{"ok":false,"error":"Command failed"}',
  });
  assert.equal(r.code, 1, r.out + r.err);
  assert.match(r.err, /^gates: hyperframes check: Command failed$/m);
  assert.ok(!/^gate layout: pass/m.test(r.out), r.out);
  assert.ok(!fs.existsSync(path.join(fx.tmp, "videos")));
});
