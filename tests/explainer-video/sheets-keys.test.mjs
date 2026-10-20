// The critic's per-scene key (gates/sheets.mjs): a verdict stands for every
// input its critic reads, so changing one scene's seam strip alone sends only
// that scene back to the critic.
import { test } from "node:test";
import assert from "node:assert/strict";
import crypto from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { cutSheets } from "../../skills/explainer-video/scripts/gates/sheets.mjs";

const hash = (...parts) => {
  const h = crypto.createHash("sha256");
  for (const p of parts) h.update(JSON.stringify(p) ?? String(p));
  return h.digest("hex").slice(0, 16);
};

// Three scenes of 2 s, the first two handing over at a seam. `seamBytes` is
// what each scene's seam strip holds, by scene id.
async function cut(run, dir, seamBytes) {
  const scenes = ["a", "b", "c"].map((id, i) => ({
    id,
    start: 2 * i,
    duration: 2,
  }));
  const backend = {
    sheet: async (_in, out) => fs.writeFileSync(out, "sheet"),
    strip: async (_in, out) => {
      const id = path.basename(out).split(".")[0];
      fs.writeFileSync(
        out,
        out.endsWith(".seam.png") ? seamBytes[id] : "motion strip",
      );
    },
  };
  fs.mkdirSync(path.join(run, dir), { recursive: true });
  return cutSheets({
    run,
    mp4: "demo.mp4",
    dir,
    plan: scenes.map((sc) => ({
      sc,
      found: {
        fullest: 0,
        motion: { still: false, frame: 10, t: 10 / 30, dead: [] },
      },
    })),
    moves: {
      a: { seams: [[2, 2.2]] },
      b: { seams: [[4, 4.2]] },
      c: { seams: [] },
    },
    seams: [
      [2, 2.2],
      [4, 4.2],
    ],
    backend,
    orFail: (f) => f(),
    script: { scenes: scenes.map(({ id }) => ({ id, visual: {} })) },
    criticRead: [],
    hash,
    format: 4,
    prevSheets: null,
    prevKeys: {},
  });
}

test("changing only one scene's seam strip changes only that scene's key", async () => {
  const run = fs.mkdtempSync(path.join(os.tmpdir(), "explainer-keys-"));
  try {
    const before = await cut(run, "one", { a: "seam a", b: "seam b" });
    const after = await cut(run, "two", { a: "seam a", b: "seam b, moved" });
    assert.equal(after.a, before.a);
    assert.notEqual(after.b, before.b);
    assert.equal(after.c, before.c);
  } finally {
    fs.rmSync(run, { recursive: true, force: true });
  }
});
