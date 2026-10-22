// The part offer through parts.mjs: no offer within five minutes, a fewest-parts
// proposal with a first-render estimate for both shapes above it, and a decline
// that carries on with sections in one line.
import { test } from "node:test";
import assert from "node:assert/strict";
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
import { skill } from "./board-lib.mjs";

const rates = readJson(skill, "render-rates.json").rates;
// The default look is textured and the default brief scores on, so a video
// second costs base, texture, gates and the synthesised score.
const minutes = (videoSeconds) =>
  (
    Math.round(
      ((videoSeconds *
        (rates.base + rates.texture + rates.gates + rates.score)) /
        60) *
        10,
    ) / 10
  ).toString();

test("a request of five minutes or less gets no offer", () => {
  for (const length of [2, 5]) {
    const fx = fixture({ length });
    const r = parts(fx, "offer");
    assert.equal(r.code, 0, r.err);
    assert.equal(r.out, `parts: no offer, ${length} min is within 5\n`);
    assert.equal(fs.existsSync(path.join(fx.dir, "parts.json")), false);
  }
});

test("a 12-minute request is offered three parts of 4 minutes, with an estimate for parts and for one long video", () => {
  const r = parts(fixture({ length: 12 }), "offer");
  assert.equal(r.code, 0, r.err);
  assert.equal(
    r.out,
    [
      "parts offer: 12 min is over 5: 3 parts of 4 + 4 + 4 min, or one long video in sections",
      `parts estimate: 3 parts ${minutes(720)} min in all, the first after ${minutes(240)} min; one long video ${minutes(720)} min (render, gates and score, not narration)`,
      "",
    ].join("\n"),
  );
});

test("the estimate counts the score the brief asks for: none for off, and for ace-step with no rate it says so", () => {
  const without = (videoSeconds) =>
    (
      Math.round(
        ((videoSeconds * (rates.base + rates.texture + rates.gates)) / 60) * 10,
      ) / 10
    ).toString();
  const line = (score) =>
    parts(fixture({ length: 12, brief: [`score=${score}`] }), "offer").out;
  assert.match(
    line("off"),
    new RegExp(
      `one long video ${without(720)} min \\(render, gates and score, not narration\\)\\n$`,
    ),
  );
  // the shipped table holds no ace-step rate until a machine with the row measures it
  assert.match(
    line("ace-step"),
    new RegExp(
      `one long video ${without(720)} min \\(render, gates and score, not narration; ace-step is not measured, so its score is left out\\)\\n$`,
    ),
  );
});

test("the fewest parts take each at most 5 minutes and at least 2", () => {
  for (const [length, want] of [
    [5.01, "2 parts of 2.5 + 2.5 min"],
    [5.5, "2 parts of 2.8 + 2.7 min"],
    [10, "2 parts of 5 + 5 min"],
    [10.5, "3 parts of 3.5 + 3.5 + 3.5 min"],
    [21, "5 parts of 4.2 + 4.2 + 4.2 + 4.2 + 4.2 min"],
  ]) {
    const r = parts(fixture({ length }), "offer");
    assert.match(
      r.out.split("\n")[0],
      new RegExp(`: ${want.replace(/\+/g, "\\+")}, or `),
      r.out,
    );
  }
});

test("every part the offer proposes is within 2 to 5 minutes and the proposal passes its own check", () => {
  for (const [length, n] of [
    [24.7, 5],
    [29.6, 6],
    [24.75, 5],
    [5.01, 2],
    [13, 3],
    [99.9, 20],
  ]) {
    const fx = fixture({ length, excerpts: n });
    const line = parts(fx, "offer").out.split("\n")[0];
    const got = line.match(/: \d+ parts of ([\d. +]+) min, or /)?.[1];
    assert.ok(got, line);
    const minutes = got.split(" + ").map(Number);
    assert.equal(minutes.length, n, line);
    for (const m of minutes) assert.ok(m >= 2 && m <= 5, `${length}: ${line}`);
    writePlan(fx, plan(minutes, 1));
    const r = parts(fx, "check");
    assert.equal(r.code, 0, `${length}: ${line}\n${r.err}`);
  }
});

test("a decline carries on with sections, prints one line with the estimate and records itself", () => {
  const fx = fixture({ length: 12 });
  const r = parts(fx, "decline");
  assert.equal(r.code, 0, r.err);
  assert.equal(
    r.out,
    `parts: declined, one long video in sections, first render about ${minutes(720)} min\n`,
  );
  assert.deepEqual(readJson(fx.dir, "parts.json"), {
    declined: true,
    length: 12,
  });
  // asked again, the offer is not made twice
  assert.equal(
    parts(fx, "offer").out,
    "parts: declined earlier, one long video in sections\n",
  );
});

test("a decline holds for the length it was made at: a changed brief is offered again", () => {
  const fx = fixture({ length: 12 });
  assert.equal(parts(fx, "decline").code, 0);
  assert.equal(
    parts(fx, "offer").out,
    "parts: declined earlier, one long video in sections\n",
  );
  assert.equal(node(fx, "brief/brief.mjs", ["length=8"]).code, 0);
  const again = parts(fx, "offer");
  assert.match(
    again.out,
    /^parts offer: 8 min is over 5: 2 parts of 4 \+ 4 min/,
  );
  // the stale decline is no plan: nothing starts, and the refusal says so
  const start = parts(fx, "start", "1");
  assert.equal(start.code, 1);
  assert.match(start.err, /^parts: no part plan: write parts\.json first$/m);
});

test("a request within five minutes has nothing to decline", () => {
  const r = parts(fixture({ length: 3 }), "decline");
  assert.equal(r.code, 1);
  assert.match(r.err, /^parts: 3 min is within 5, nothing to decline$/m);
});

test("a run with no brief is refused with the stage to run first", () => {
  const fx = fixture();
  fs.rmSync(path.join(fx.dir, "brief.json"));
  const r = parts(fx, "offer");
  assert.equal(r.code, 1);
  assert.match(r.err, /^parts: no brief\.json: run brief\.mjs first$/m);
});

test("a style no store holds is refused as a parts line, never a stack trace", () => {
  const fx = fixture();
  const file = path.join(fx.dir, "brief.json");
  const brief = JSON.parse(fs.readFileSync(file, "utf8"));
  fs.writeFileSync(file, JSON.stringify({ ...brief, style: "nope" }));
  for (const cmd of ["offer", "decline"]) {
    const r = parts(fx, cmd);
    assert.equal(r.code, 1, cmd);
    assert.match(r.err, /^parts: no style profile nope in /m, cmd);
    assert.doesNotMatch(r.err, /\n\s+at /, r.err);
  }
  assert.equal(fs.existsSync(path.join(fx.dir, "parts.json")), false);
});

test("a brief.json of the wrong shape is refused by file and field, whichever command reads it", () => {
  const fx = fixture();
  const file = path.join(fx.dir, "brief.json");
  const good = fs.readFileSync(file, "utf8");
  for (const [body, why] of [
    ["null", /^parts: brief\.json is not an object$/m],
    ["[]", /^parts: brief\.json is not an object$/m],
    ["{}", /^parts: brief\.json length is not a number$/m],
    ['{"length":"12"}', /^parts: brief\.json length is not a number$/m],
    [
      JSON.stringify({ ...JSON.parse(good), style: 3 }),
      /^parts: brief\.json style is not a name$/m,
    ],
  ])
    for (const cmd of ["offer", "decline", "check"]) {
      fs.writeFileSync(file, body);
      const r = parts(fx, cmd);
      assert.equal(r.code, 1, `${cmd} ${body}`);
      assert.match(r.err, why, `${cmd} ${body}`);
      assert.doesNotMatch(r.err, /\n\s+at /, r.err);
    }
});
