// The video gates through their process doors, part 4a: the critic's verdicts
// and the contact sheets it reads.
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { checkVerdict } from "../../skills/explainer-video/scripts/gates/verdict.mjs";
import { sheetFrames } from "../../skills/explainer-video/scripts/lib/backend.mjs";
import { CLEAN, critique } from "./critic.mjs";
import { SCRIPT } from "./scene-file.mjs";
import {
  assertGreen,
  calls,
  delivered,
  fixture,
  read,
  record,
  render,
  renderUnjudged,
  stage,
} from "./gates-lib.mjs";

test("a render the critic has not judged is held: critic pending, a contact sheet per scene cut from the MP4, no HyperFrames snapshot, no attempt", () => {
  const fx = fixture();
  const r = renderUnjudged(fx, SCRIPT);
  assert.equal(r.code, 1, r.out + r.err);
  const g = record(fx);
  assert.match(g.gates.critic.sheets, /^\.cache\/critic\/[0-9a-f]{16}$/);
  assert.ok(
    r.out.includes(
      `gate critic: pending: round 1 of 2, 0 of 3 scene(s) judged, contact sheets in ${g.gates.critic.sheets} vs no unreadable or invented content; scores advise\n`,
    ),
    r.out,
  );
  assert.match(
    r.out,
    /^gates: 6 pass, 0 fail, 1 pending; next: run the critic, round 1 of 2$/m,
  );
  assert.equal(g.attempts, 0);
  assert.equal(g.gates.critic.status, "pending");
  assert.ok(!fs.existsSync(delivered(fx)));
  const timeline = JSON.parse(read(fx.dir, "timeline.json"));
  const sheets = calls(fx, "sheet");
  assert.deepEqual(
    sheets.map((c) => [path.basename(c.output), c.start, c.duration]),
    timeline.scenes.map((s) => [`${s.id}.png`, s.start, s.duration]),
  );
  for (const c of sheets) {
    assert.equal(path.basename(c.input), "demo.mp4");
    assert.ok(fs.existsSync(c.output), c.output);
  }
  for (const c of calls(fx, "hyperframes"))
    assert.ok(!c.args.includes("snapshot"), JSON.stringify(c.args));
  // The critic's round, then the render again on its cached video: delivered.
  assert.deepEqual(critique(fx.dir).sort(), ["gate", "hook", "steps"]);
  assertGreen(fx, stage(fx, "render/render.mjs"));
  assert.equal(calls(fx, "sheet").length, 3, "the sheets are cut once");
});

test("invented content on screen fails the critic, delivers nothing, and passes on the fix", () => {
  const fx = fixture();
  renderUnjudged(
    fx,
    SCRIPT.replace('"value": "code"', '"value": "ten times faster"'),
  );
  critique(fx.dir, (id) =>
    id === "steps"
      ? {
          failures: [
            {
              kind: "invented",
              what: 'the card "ten times faster" is in no narration sentence or excerpt',
            },
          ],
          scores: { clarity: 3, legibility: 5, fit: 2, motion: 3 },
          worst: [],
        }
      : CLEAN,
  );
  const r = stage(fx, "render/render.mjs");
  assert.equal(r.code, 1, r.out + r.err);
  assert.match(
    r.out,
    /^gate critic: fail: 1 hard failure\(s\), first: [\d.]+ s steps: invented: the card "ten times faster" .* vs /m,
  );
  assert.match(r.out, /^gates: 6 pass, 1 fail; next: fix attempt 1 of 2$/m);
  assert.ok(!fs.existsSync(path.join(fx.dir, "out")));
  assert.ok(!fs.existsSync(delivered(fx)));
  assert.equal(record(fx).gates.critic.attempts, 1);
  assert.equal(record(fx).attempts, 1);
  assert.match(read(fx.dir, "gates.md"), /^## critic$/m);
  assertGreen(fx, render(fx, SCRIPT));
});

test("low scores with no hard failure pass the critic, the scores in the gates report", () => {
  const fx = fixture();
  renderUnjudged(fx, SCRIPT);
  const steps = JSON.parse(read(fx.dir, "timeline.json")).scenes[1];
  critique(fx.dir, (id) => ({
    failures: [],
    scores: { clarity: 1, legibility: 2, fit: 1, motion: 2 },
    note: "The card says little.",
    worst:
      id === "steps"
        ? [
            {
              at: steps.start + 1,
              what: "The card appears all at once.",
              evidence: "strip frames 4-7",
              fix: "Stagger the reveal.",
            },
          ]
        : [],
  }));
  const r = stage(fx, "render/render.mjs");
  assert.equal(r.code, 0, r.out + r.err);
  assert.match(
    r.out,
    /^gate critic: pass: 0 hard failure\(s\), mean scores clarity 1\.0, legibility 2\.0, fit 1\.0, motion 2\.0, round 1 of 2 vs /m,
  );
  const md = read(fx.dir, "gates.md");
  assert.match(md, /^## Critic scores$/m);
  assert.match(
    md,
    /^\| steps \| 1 \| 2 \| 1 \| 2 \| The card says little\. \|$/m,
  );
  assert.match(md, /^### Worst defects$/m);
  assert.match(
    md,
    new RegExp(
      `^- steps at ${steps.start + 1} s: The card appears all at once\\. \\(strip frames 4-7\\)\\. Fix: Stagger the reveal\\.$`,
      "m",
    ),
  );
});

test("a malformed verdict stops the gates, naming the scene and what is wrong", () => {
  const fx = fixture();
  renderUnjudged(fx, SCRIPT);
  critique(fx.dir);
  const hook = path.join(fx.dir, record(fx).gates.critic.sheets, "hook.json");
  const scores = CLEAN.scores;
  // The hook scene runs from 0 s; a worst entry inside it, then one thing wrong.
  const worst = (n, o = {}) =>
    Array(n).fill({
      at: 0.5,
      what: "The title snaps in.",
      evidence: "strip frames 4-7",
      fix: "Ease the title in.",
      ...o,
    });
  const unmoved = { ...scores, motion: undefined };
  for (const [verdict, why] of [
    ["{", /JSON/],
    [{ scores, worst: [] }, /no failures list/],
    [
      { failures: [{ kind: "ugly", what: "x" }], scores, worst: [] },
      /failure 1 kind "ugly" is not unreadable or invented/,
    ],
    [
      { failures: [{ kind: "invented", what: " " }], scores, worst: [] },
      /failure 1 says nothing/,
    ],
    [
      { failures: [], scores: { ...scores, fit: 4.5 }, worst: [] },
      /score fit is not a whole number 1 to 5/,
    ],
    [
      { failures: [], scores: unmoved, worst: [] },
      /score motion is not a whole number 1 to 5/,
    ],
    [{ failures: [], scores }, /no worst list/],
    [
      { failures: [], scores, worst: worst(4) },
      /worst holds 4 entries, at most 3/,
    ],
    [
      { failures: [], scores, worst: worst(1, { at: 999 }) },
      /worst 1 at 999 is not a time inside the scene/,
    ],
    [{ failures: [], scores, worst: [null] }, /worst 1 is not an object/],
    [
      { failures: [], scores, worst: worst(1, { at: "0.5" }) },
      /worst 1 at 0.5 is not a time inside the scene/,
    ],
    [
      { failures: [], scores, worst: worst(1, { fix: " " }) },
      /worst 1 has no fix/,
    ],
  ]) {
    fs.writeFileSync(
      hook,
      typeof verdict === "string" ? verdict : JSON.stringify(verdict),
    );
    const r = stage(fx, "render/render.mjs");
    assert.equal(r.code, 1, r.out + r.err);
    const line = r.err.match(/^gates: critic verdict hook\.json: (.*)$/m);
    assert.ok(line, r.err);
    assert.match(line[1], why);
  }
});

test("a contact sheet shows the scene's quarter marks and its own last frame, even for a scene starting between frames", () => {
  assert.deepEqual(sheetFrames({ start: 2, duration: 4, fps: 30 }), [
    60,
    [90, 120, 150, 179],
  ]);
  // 28.25 s to 45.9 s at 30 fps: frames 848 to 1376; 1377 is the next scene's.
  assert.deepEqual(sheetFrames({ start: 28.25, duration: 17.65, fps: 30 }), [
    848,
    [980, 1112, 1244, 1376],
  ]);
});

test("a worst moment at a scene's 3-place start is inside it, though the start is truncated", () => {
  // Frame 283 is 9.433333 s, written truncated; a time is read to 3 places.
  const sc = { start: 9.433333, duration: 4.933333 };
  const worst = (at) => ({
    ...CLEAN,
    worst: [{ at, what: "x", evidence: "x", fix: "x" }],
  });
  const refused = (at) => {
    let why = null;
    checkVerdict(worst(at), sc, (w) => (why ??= w));
    return why;
  };
  assert.equal(refused(9.433), null);
  assert.equal(refused(14.367), null);
  assert.match(refused(9.432), /is not a time inside the scene/);
});
