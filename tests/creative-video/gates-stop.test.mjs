// The gates stage's refusals and its fix-round cap: a red run on one voice is
// one fix attempt, judging the same inputs again is none, a third red stops the
// run, and a pass or a new voice starts the count again.
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { calls, exec, project, timing } from "./timing-lib.mjs";
import { SCENES, run as voice, write } from "./voice-lib.mjs";
import {
  compose,
  gates,
  record,
  runGates,
  supported,
  timed,
} from "./gates-lib.mjs";
import { cited } from "./support-lib.mjs";

const RED = "<p>a clipped line</p>";
const GREEN = "<p>a fitting line</p>";

test("a red run is attempt 1 of 2, the same inputs judged again add none, and changed inputs add one", () => {
  const fx = timed({ context: RED });
  let r = runGates(fx);
  assert.equal(r.code, 1);
  assert.match(r.out, /^gates: 12 pass, 1 fail; next: fix attempt 1 of 2$/m);
  assert.equal(record(fx).attempts, 1);
  r = runGates(fx);
  assert.match(r.out, /; next: fix attempt 1 of 2$/m);
  assert.equal(record(fx).attempts, 1);
  compose(fx, "context", "<p>another clipped line</p>");
  r = runGates(fx);
  assert.match(r.out, /; next: fix attempt 2 of 2$/m);
  compose(fx, "context", "<p>yet another clipped line</p>");
  r = runGates(fx);
  assert.equal(r.code, 1);
  assert.match(
    r.out,
    /^gates: 12 pass, 1 fail; stop: red after two fix attempts, no video$/m,
  );
  assert.equal(record(fx).attempts, 3);
});

test("a pass resets the count, and so does a new voice, but not a script.json edited without one", () => {
  const fx = timed({ context: RED });
  assert.equal(runGates(fx).code, 1);
  compose(fx, "context", "<p>another clipped line</p>");
  assert.equal(runGates(fx).code, 1);
  assert.equal(record(fx).attempts, 2);
  // the narration changes in script.json only: the gates judge the voice, so
  // the count goes on
  const edited = cited(SCENES).map((s) =>
    s.id === "recap" ? { ...s, narration: ["A different closing line."] } : s,
  );
  write(fx, edited);
  compose(fx, "context", "<p>a third clipped line</p>");
  assert.match(runGates(fx).out, /; stop: red after two fix attempts/m);
  // checked, voiced and timed again: a new voice starts at attempt 1
  supported(fx);
  assert.equal(voice(fx).code, 0);
  assert.equal(exec(timing, fx).code, 0);
  compose(fx, "context", "<p>a fourth clipped line</p>");
  const r = runGates(fx);
  assert.match(r.out, /; next: fix attempt 1 of 2$/m);
  compose(fx, "context", GREEN);
  const ok = runGates(fx);
  assert.equal(ok.code, 0, ok.out);
  assert.match(ok.out, /^gates: 13 pass, 0 fail$/m);
  assert.equal(record(fx).attempts, 0);
});

test("a check run on changed inputs prints every gate and the summary but writes no gates.json, so it spends no fix attempt", () => {
  const fx = timed({ context: RED });
  assert.equal(runGates(fx).code, 1);
  const file = path.join(fx.dir, "gates.json");
  const before = fs.readFileSync(file, "utf8");
  compose(fx, "context", "<p>another clipped line</p>");
  const r = runGates(fx, {}, { check: true });
  assert.equal(r.code, 1);
  assert.equal(r.out.match(/^gate [a-z ]+: (pass|fail): /gm).length, 13, r.out);
  assert.match(
    r.out,
    /^gates: 12 pass, 1 fail; check run: gates\.json not written$/m,
  );
  assert.equal(fs.readFileSync(file, "utf8"), before);
  assert.match(runGates(fx).out, /; next: fix attempt 2 of 2$/m);
});

test("a red check run with the critic pending asks for no critic: the failing gates come first", () => {
  const fx = timed({ context: RED });
  const r = runGates(fx, {}, { check: true, critic: false });
  assert.match(
    r.out,
    /^gates: 11 pass, 1 fail, 1 pending; check run: gates\.json not written$/m,
  );
});

test("gates.json records the inputs, the voice, each gate's verdict with its evidence, and the warnings", () => {
  const fx = timed({ context: RED });
  runGates(fx);
  const rec = record(fx);
  assert.match(rec.inputs, /^[0-9a-f]{16}$/);
  assert.match(rec.voice, /^[0-9a-f]{16}$/);
  assert.deepEqual(Object.keys(rec.gates), [
    "determinism",
    "layout",
    "contrast",
    "reading",
    "caption band",
    "anchors",
    "script errors",
    "sounds",
    "licence",
    "bed level",
    "must and avoid",
    "support",
    "critic",
  ]);
  assert.equal(rec.gates.layout.status, "fail");
  assert.equal(rec.gates.layout.floor, "none, text >= 18 px, margin 5%");
  assert.equal(rec.gates.layout.evidence.length, 1);
  assert.equal(rec.gates.contrast.status, "pass");
  assert.deepEqual(rec.gates.contrast.evidence, []);
  assert.ok(rec.warnings.some((w) => w.startsWith("pacing: ")));
  const before = rec.inputs;
  fs.mkdirSync(project(fx, "kit"), { recursive: true });
  fs.writeFileSync(project(fx, "kit", "look.css"), "");
  runGates(fx);
  assert.notEqual(record(fx).inputs, before);
});

test("a gates.json that is not JSON, or whose gates are not an object, is refused by name before any backend call", () => {
  const fx = timed();
  const record = path.join(fx.dir, "gates.json");
  fs.writeFileSync(record, "{ not json");
  let r = runGates(fx);
  assert.equal(r.code, 1);
  assert.match(r.err, /^gates: gates\.json: is not valid JSON \(/);
  fs.writeFileSync(
    record,
    JSON.stringify({ inputs: "x", voice: "x", gates: [] }),
  );
  r = runGates(fx);
  assert.equal(r.code, 1);
  assert.match(r.err, /^gates: gates\.json: gates is not an object/);
  assert.deepEqual(
    calls(fx).filter((c) => ["check", "probe", "snapshot"].includes(c.call)),
    [],
  );
});

test("a project missing its timeline, with a stale one, or short of a scene file is refused before any backend call", () => {
  const fx = timed();
  fs.rmSync(path.join(fx.dir, "timeline.json"));
  let r = runGates(fx);
  assert.equal(r.code, 1);
  assert.match(
    r.err,
    /^gates: timeline\.json is missing: run render\/timing\.mjs first/,
  );
  assert.equal(exec(timing, fx).code, 0);
  fs.appendFileSync(path.join(fx.dir, "voice.json"), "\n");
  r = runGates(fx);
  assert.equal(r.code, 1);
  assert.match(
    r.err,
    /^gates: timeline\.json is from an older voice\.json: run render\/timing\.mjs again/,
  );
  assert.equal(exec(timing, fx).code, 0);
  fs.rmSync(project(fx, "compositions", "hook.html"));
  r = runGates(fx);
  assert.equal(r.code, 1);
  assert.match(
    r.err,
    /^gates: no compositions\/hook\.html: author each scene file/,
  );
  assert.deepEqual(
    calls(fx).filter((c) => ["check", "probe", "snapshot"].includes(c.call)),
    [],
  );
  assert.equal(exec(gates, fx, []).code, 2);
});

test("a check that never reached the browser names its error, a string or HyperFrames 0.8.216's {code, message}", () => {
  let r = runGates(
    timed({ hook: '<p data-check-error="Command failed">a line</p>' }),
  );
  assert.equal(r.code, 1);
  assert.equal(r.err, "gates: hyperframes check: Command failed\n");
  r = runGates(
    timed({
      hook: '<p data-check-error="No composition found" data-check-code="runtime_error">a line</p>',
    }),
  );
  assert.equal(r.code, 1);
  assert.equal(
    r.err,
    "gates: hyperframes check: No composition found (runtime_error)\n",
  );
});
