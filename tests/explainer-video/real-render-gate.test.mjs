// real-render.mjs runs the product's determinism gate through
// maintainer/real-render-gate.mjs: the gate's own function per scene, the
// frame from the scene's section on that section's clock, and a row naming the
// scenes that differ (#937). A stub backend answers where the real one renders.
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import {
  determinismGate,
  gateRow,
} from "../../skills/explainer-video/maintainer/real-render-gate.mjs";
import { loadStyle } from "../../skills/explainer-video/scripts/lib/style.mjs";

const run = fs.mkdtempSync(path.join(os.tmpdir(), "real-render-gate-"));
const profile = loadStyle(run, "claude-code");
const scene = (id, component = "title") => ({ id, visual: { component } });
const timeline = [
  { id: "one", start: 0, duration: 1 },
  { id: "two", start: 4, duration: 1 },
];

// bandMotion peaks at diff 3; `frame` writes a file per call, whose pixels are
// the same twice unless `differ` names the scene's comp.
function stub(differ = null) {
  const calls = { frame: [], bandMotion: [] };
  let n = 0;
  return {
    calls,
    events: async () => ({}),
    bandMotion: async (mp4, opts) => {
      calls.bandMotion.push({ mp4, ...opts });
      return Array.from({ length: 29 }, (_, k) => (k === 3 ? 9 : 0));
    },
    frame: async (comp, t, out, opts) => {
      calls.frame.push({ comp, t, out, ...opts });
      fs.writeFileSync(out, `${comp}@${differ === comp ? n++ : t}`);
    },
    framePixels: async (file) => fs.readFileSync(file, "utf8"),
  };
}

const gate = (backend, extra = {}) =>
  determinismGate({
    scenes: [scene("one"), scene("two", "stack3d")],
    timeline,
    run,
    mp4: path.join(run, "joined.mp4"),
    comp: "/whole",
    raw: {},
    backend,
    env: {},
    profile,
    ...extra,
  });

test("the gate reads each scene's peak off the video and renders its frame twice from the composition", async () => {
  const backend = stub();
  const plan = await gate(backend);
  assert.equal(plan.length, 2);
  assert.ok(
    backend.calls.bandMotion.every(
      (c) => c.mp4 === path.join(run, "joined.mp4"),
    ),
  );
  const [a, b] = backend.calls.frame.slice(0, 2);
  assert.equal(a.comp, "/whole");
  assert.equal(a.t, b.t);
  assert.notEqual(a.out, b.out);
  assert.ok(a.out.startsWith(path.join(run, ".cache", "gates", "frames")));
});

test("a scene that draws WebGL has its two frames rendered on SwiftShader, the others not", async () => {
  const backend = stub();
  await gate(backend);
  const [one, two] = [backend.calls.frame[0], backend.calls.frame[2]];
  assert.ok(!one.software);
  assert.equal(two.software, true);
});

test("in a video in sections the frame comes from the scene's section, on its own clock", async () => {
  const backend = stub();
  await gate(backend, {
    section: (id) => (id === "two" ? { dir: "/section-2", base: 4 } : null),
  });
  const [one, two] = [backend.calls.frame[0], backend.calls.frame[2]];
  assert.equal(one.comp, "/whole");
  assert.equal(two.comp, "/section-2");
  assert.ok(
    two.t < 1,
    `${two.t} is the scene's frame less its section's start`,
  );
});

test("the row passes when every scene's two renders match and names the scene that differs", async () => {
  const rows = [];
  const check = (name, ok, detail) => rows.push({ name, ok, detail });
  gateRow("gate determinism", await gate(stub()), check);
  gateRow("gate determinism", await gate(stub("/whole")), check);
  assert.equal(rows[0].ok, true);
  assert.match(rows[0].detail, /^0 of 2 scene\(s\) differ/);
  assert.equal(rows[1].ok, false);
  assert.match(
    rows[1].detail,
    /first: 0\.00 s one: frame \d+ .* renders differently twice/,
  );
});
