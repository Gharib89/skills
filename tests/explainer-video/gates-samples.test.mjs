// The sampling pass: layout and reading time judged on the composition's
// samples, before any video exists, so the storyboard can show a red on its card.
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { SCRIPT } from "./scene-file.mjs";
import {
  calls,
  compile,
  fixture,
  ok,
  read,
  run,
  stills,
  voice,
} from "./board-lib.mjs";

const prepared = (text) => {
  const fx = fixture(text);
  compile(fx);
  voice(fx);
  stills(fx);
  return fx;
};
const samples = (fx) => run(fx, "gates/samples.mjs");
const record = (fx) => JSON.parse(read(fx.dir, "samples.json"));

test("samples refuses before the stills step wrote a composition", () => {
  const fx = fixture();
  compile(fx);
  const r = samples(fx);
  assert.equal(r.code, 1);
  assert.match(
    r.err,
    /^samples: no timeline\.json: run node render\.mjs .+ --stills/,
  );
  assert.equal(run(fx, "gates/samples.mjs", ["--x"]).code, 2);
});

test("a clean script samples green: no video made, one record per scene, and the cost line", () => {
  const fx = prepared();
  // `stills` in board-lib ran one pass already.
  const [checks, probes] = [
    calls(fx, "check").length,
    calls(fx, "probe").length,
  ];
  const r = ok(samples(fx), "samples");
  assert.match(r.out, /^samples: 3 scene\(s\), 0 finding\(s\) in \d+\.\d s$/m);
  const rec = record(fx);
  assert.deepEqual(
    rec.scenes.map((s) => [s.id, s.findings]),
    [
      ["hook", []],
      ["steps", []],
      ["gate", []],
    ],
  );
  assert.equal(typeof rec.seconds, "number");
  assert.ok(!fs.existsSync(path.join(fx.dir, "out")));
  // One check and one probe for the whole run, over every scene's samples.
  assert.equal(calls(fx, "check").length, checks + 1);
  assert.equal(calls(fx, "probe").length, probes + 1);
});

test("a probe that finds no text in a scene is a tool error, not a green pass", () => {
  const fx = prepared();
  const r = run(fx, "gates/samples.mjs", [], {
    EXPLAINER_VIDEO_FAKE_BLANK: "1",
  });
  assert.equal(r.code, 1, r.out + r.err);
  assert.match(r.err, /^samples: layout probe: no text in scene hook$/m);
});

test("a clipped title is a layout finding on its scene, and a reading finding is one too; both exit 1", () => {
  const fx = prepared(
    SCRIPT.replace("Issue to pull request", "Issue to clipped request"),
  );
  const r = samples(fx);
  assert.equal(r.code, 1, r.out + r.err);
  assert.match(
    r.out,
    /^sample hook: [\d.]+ s hook: text_box_overflow "Issue to clipped request"/m,
  );
  assert.match(r.out, /^samples: 3 scene\(s\), \d+ finding\(s\) in /m);
  const rec = record(fx);
  assert.ok(rec.scenes[0].findings.length >= 1);
  assert.deepEqual(rec.scenes[1].findings, []);

  // A box that never holds still long enough to read is a reading finding.
  const slow = prepared(
    SCRIPT.replace("Issue to pull request", "Issue to fading request"),
  );
  const f = run(slow, "gates/samples.mjs", [], {
    EXPLAINER_VIDEO_FAKE_FADE_END: "99",
  });
  assert.equal(f.code, 1, f.out + f.err);
  assert.match(
    f.out,
    /^sample hook: .*"Issue to fading request": 0\.0 s readable/m,
  );
});
