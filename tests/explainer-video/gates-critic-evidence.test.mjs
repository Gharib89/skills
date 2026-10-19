// The video gates through their process doors, part 4c: the cached evidence a
// verdict stands on, and what sends a scene back to the critic.
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { CLEAN, critique } from "./critic.mjs";
import { SCRIPT } from "./scene-file.mjs";
import {
  fixture,
  read,
  record,
  render,
  renderUnjudged,
  stage,
} from "./gates-lib.mjs";

test("a verdict stands only for the evidence it read: new cites or a changed cited excerpt is judged again", () => {
  const fx = fixture();
  const excerpts = (text) =>
    fs.writeFileSync(
      path.join(fx.dir, "excerpts.json"),
      JSON.stringify({ excerpts: [{ id: "ex-1", text }] }),
    );
  excerpts("Ship reads the issue first.");
  assert.equal(render(fx).code, 0);
  excerpts("Ship reads the issue and its comments.");
  const r1 = stage(fx, "render/render.mjs");
  assert.equal(r1.code, 1, r1.out + r1.err);
  assert.match(r1.out, /^gate critic: pending: round 2 of 2, /m);
  const fresh = fixture();
  assert.equal(render(fresh).code, 0);
  const r2 = renderUnjudged(
    fresh,
    SCRIPT.replace("It reads the issue. [ex-1]", "It reads the issue. [ex-2]"),
  );
  assert.equal(r2.code, 1, r2.out + r2.err);
  assert.match(r2.out, /^gate critic: pending: round 2 of 2, /m);
});

test("a changed cite or cited excerpt's text sends every scene back to the critic, though no sheet changed, since each critic reads every excerpt", () => {
  const excerpts = (fx, text) =>
    fs.writeFileSync(
      path.join(fx.dir, "excerpts.json"),
      JSON.stringify({ excerpts: [{ id: "ex-1", text }] }),
    );
  const fx = fixture();
  excerpts(fx, "Ship reads the issue first.");
  assert.equal(render(fx).code, 0);
  excerpts(fx, "Ship reads the issue and its comments.");
  const r1 = stage(fx, "render/render.mjs");
  assert.match(
    r1.out,
    /^gate critic: pending: .*, 0 of 3 scene\(s\) judged, /m,
  );
  assert.deepEqual(critique(fx.dir).sort(), ["gate", "hook", "steps"]);
  const fresh = fixture();
  assert.equal(render(fresh).code, 0);
  const r2 = renderUnjudged(
    fresh,
    SCRIPT.replace("It reads the issue. [ex-1]", "It reads the issue. [ex-2]"),
  );
  assert.match(
    r2.out,
    /^gate critic: pending: .*, 0 of 3 scene\(s\) judged, /m,
  );
  assert.deepEqual(critique(fresh.dir).sort(), ["gate", "hook", "steps"]);
});

test("a scene whose visual changed is judged again though its sheet did not, since its critic reads the visual", () => {
  const fx = fixture();
  assert.equal(render(fx).code, 0);
  fs.writeFileSync(
    path.join(fx.dir, "script.md"),
    SCRIPT.replace('"value": "code"', '"value": "some code"'),
  );
  for (const s of ["script/compile.mjs", "voice/voice.mjs"])
    assert.equal(stage(fx, s).code, 0, s);
  // A prop no component draws: the gate scene's HTML, so its sheet, stays.
  const file = path.join(fx.dir, "script.json");
  const script = JSON.parse(fs.readFileSync(file, "utf8"));
  script.scenes.find((s) => s.id === "gate").visual.props.aside = "moved";
  fs.writeFileSync(file, JSON.stringify(script, null, 2));
  const r = stage(fx, "render/render.mjs");
  assert.match(
    r.out,
    /^gate critic: pending: round 2 of 2, 1 of 3 scene\(s\) judged, /m,
  );
  assert.deepEqual(critique(fx.dir).sort(), ["gate", "steps"]);
});

test("a malformed keys.json in the previous sheets folder stops the gates, naming it", () => {
  const fx = fixture();
  assert.equal(render(fx).code, 0);
  const keys = path.join(fx.dir, record(fx).gates.critic.sheets, "keys.json");
  for (const body of ["{", "null", "[]"]) {
    fs.writeFileSync(keys, body);
    const r = renderUnjudged(
      fx,
      SCRIPT.replace('"value": "code"', '"value": "some code"'),
    );
    assert.equal(r.code, 1, r.out + r.err);
    assert.match(
      r.err,
      /^gates: critic keys \.cache\/critic\/[0-9a-f]{16}\/keys\.json: .*; delete it to judge every scene again$/m,
    );
  }
});

test("a scene shifted by an earlier scene's new length is judged again, its old verdict not carried", () => {
  const fx = fixture();
  assert.equal(renderUnjudged(fx, SCRIPT).code, 1);
  const before = JSON.parse(read(fx.dir, "timeline.json")).scenes[2];
  // A worst moment at the scene's old start, which the shift moves outside it.
  critique(fx.dir, (id) => ({
    ...CLEAN,
    worst:
      id === "gate"
        ? [{ at: before.start, what: "x", evidence: "x", fix: "x" }]
        : [],
  }));
  assert.equal(stage(fx, "render/render.mjs").code, 0);
  const voice = JSON.parse(read(fx.dir, "voice.json"));
  // The scene's WAV, 2 s longer: render sizes a scene from its WAV.
  const file = path.join(fx.dir, voice.scenes[1].audio);
  const wav = fs.readFileSync(file);
  const more = Buffer.alloc(2 * wav.readUInt32LE(24) * 2);
  wav.writeUInt32LE(wav.readUInt32LE(40) + more.length, 40);
  wav.writeUInt32LE(wav.readUInt32LE(4) + more.length, 4);
  fs.writeFileSync(file, Buffer.concat([wav, more]));
  voice.scenes[1].duration += 2;
  fs.writeFileSync(path.join(fx.dir, "voice.json"), JSON.stringify(voice));
  const r = stage(fx, "render/render.mjs");
  assert.ok(!/critic verdict/.test(r.err), r.err);
  assert.equal(r.code, 1, r.out + r.err);
  assert.equal(
    JSON.parse(read(fx.dir, "timeline.json")).scenes[2].start,
    before.start + 2,
  );
  assert.match(r.out, /^gate critic: pending: .*, 1 of 3 scene\(s\) judged, /m);
  assert.deepEqual(critique(fx.dir).sort(), ["gate", "steps"]);
});
