// The determinism gate: two snapshot launches over every sample time give the
// same pixels, and the backend calls the stage makes to get there.
import { test } from "node:test";
import assert from "node:assert/strict";
import path from "node:path";
import { sampleTimes } from "../../skills/creative-video/scripts/gates/samples.mjs";
import { calls } from "./timing-lib.mjs";
import { gateLine, only, runGates, timed, timeline } from "./gates-lib.mjs";

test("a scene drawing from Math.random() fails determinism at its times, and its frame-driven twin passes", () => {
  const r = runGates(timed({ context: "<p>a line</p><!-- Math.random() -->" }));
  assert.equal(r.code, 1);
  only(r, "determinism");
  assert.match(
    gateLine(r, "determinism"),
    /^fail: 3 finding\(s\), first: \d+\.\d\d s context: the frame differs between two launches vs the same pixels twice$/,
  );
  assert.equal(runGates(timed({ context: "<p>a line</p>" })).code, 0);
});

test("the stage asks one check, one probe and two snapshots over every scene's in, key and out times", () => {
  const fx = timed();
  assert.equal(runGates(fx).code, 0);
  const sampled = [
    ...new Set(
      timeline(fx).scenes.flatMap((s) => Object.values(sampleTimes(s))),
    ),
  ].sort((a, b) => a - b);
  const log = calls(fx);
  const [check] = log.filter((c) => c.call === "check");
  assert.deepEqual(check.times, sampled);
  const probes = log.filter((c) => c.call === "probe");
  assert.equal(probes.length, 1);
  for (const t of sampled) assert.ok(probes[0].times.includes(t), String(t));
  const snaps = log.filter((c) => c.call === "snapshot");
  assert.equal(snaps.length, 2);
  assert.deepEqual(
    snaps.map((s) => s.outDir),
    ["a", "b"].map((d) => path.join(fx.dir, ".cache", "gates", "frames", d)),
  );
  for (const s of snaps) assert.deepEqual(s.times, sampled);
});
