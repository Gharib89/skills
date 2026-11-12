// The determinism gate: two snapshot launches over every sample time give the
// same pixels, and the backend calls the stage makes to get there.
import { test } from "node:test";
import assert from "node:assert/strict";
import path from "node:path";
import { sampleTimes } from "../../skills/creative-video/scripts/gates/samples.mjs";
import { calls } from "./timing-lib.mjs";
import {
  compose,
  gateLine,
  only,
  runGates,
  timed,
  timeline,
} from "./gates-lib.mjs";

test("a scene left on the wall clock fails determinism at its times, and its frame-driven twin passes", () => {
  for (const clock of ["Date.now()", "performance.now()"]) {
    const fx = timed();
    compose(
      fx,
      "context",
      "<p>a line</p>",
      `tl.set("p", { x: ${clock} % 600 });`,
    );
    const r = runGates(fx);
    assert.equal(r.code, 1, clock);
    only(r, "determinism");
    assert.match(
      gateLine(r, "determinism"),
      /^fail: 3 finding\(s\), first: \d+\.\d\d s context: the frame differs between two launches and between two single-frame re-checks vs the same pixels twice$/,
    );
  }
  const twin = timed();
  compose(twin, "context", "<p>a line</p>", 'tl.set("p", { x: 300 });');
  assert.equal(runGates(twin).code, 0);
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

test("a frame that differs only in a batched launch is re-checked alone, twice, and passes", () => {
  const fx = timed();
  compose(fx, "context", "<p data-flaky>a line</p>", "");
  const r = runGates(fx);
  assert.equal(r.code, 0, r.out);
  assert.match(gateLine(r, "determinism"), /^pass: 0 finding\(s\)/);
  const snaps = calls(fx).filter((c) => c.call === "snapshot");
  const rechecks = snaps.slice(2);
  assert.ok(rechecks.length > 0 && rechecks.length % 2 === 0);
  for (const s of rechecks) assert.equal(s.times.length, 1);
  for (let i = 0; i < rechecks.length; i += 2)
    assert.deepEqual(rechecks[i].times, rechecks[i + 1].times);
  assert.equal(
    new Set(rechecks.map((s) => s.times[0])).size,
    rechecks.length / 2,
  );
  const dirs = rechecks.map((s) => s.outDir);
  assert.equal(new Set(dirs).size, dirs.length);
  for (const d of dirs)
    assert.ok(d.startsWith(path.join(fx.dir, ".cache", "gates", "frames")));
});

test("a re-check that answers no frame stops the stage instead of passing the frame", () => {
  const fx = timed();
  compose(fx, "context", "<p data-flaky data-empty-recheck>a line</p>", "");
  const r = runGates(fx, {}, { critic: false });
  assert.equal(r.code, 1);
  assert.match(r.err, /snapshot gave 0 of 1 frame for a re-check/);
});
