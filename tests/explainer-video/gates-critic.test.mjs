// The video gates through their process doors, part 4: the critic's verdicts,
// its rounds, contact sheets and cached evidence.
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { sheetFrames } from "../../skills/explainer-video/scripts/lib/backend.mjs";
import { CLEAN, critique, judged } from "./critic.mjs";
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

test("the critic judges two rounds of one script at most: a third render carries round two's verdict", () => {
  const fx = fixture();
  const r1 = render(
    fx,
    SCRIPT.replace('"value": "code"', '"value": "the code"'),
  );
  assert.equal(r1.code, 0, r1.out + r1.err);
  const r2 = render(
    fx,
    SCRIPT.replace('"value": "code"', '"value": "some code"'),
  );
  assert.match(r2.out, /^gate critic: pass: .*round 2 of 2 vs /m);
  const r3 = renderUnjudged(fx, SCRIPT);
  assert.equal(r3.code, 0, r3.out + r3.err);
  assert.match(
    r3.out,
    /^gate critic: pass: .*round 2 of 2, carried: no third round vs /m,
  );
  assert.equal(calls(fx, "sheet").length, 6, "no sheets for the third render");
  assert.equal(record(fx).gates.critic.rounds.length, 2);
  // Verdicts that appear for the third render add no third round.
  const g = record(fx);
  assert.ok(!g.gates.critic.rounds.includes(g.gates.critic.key));
  const third = path.join(fx.dir, ".cache", "critic", g.gates.critic.key);
  fs.mkdirSync(third, { recursive: true });
  for (const f of fs.readdirSync(path.join(fx.dir, g.gates.critic.sheets)))
    if (f.endsWith(".png"))
      fs.writeFileSync(
        path.join(third, f.replace(/\.png$/, ".json")),
        JSON.stringify({
          ...CLEAN,
          failures: [{ kind: "invented", what: "x" }],
        }),
      );
  const r3b = stage(fx, "render/render.mjs");
  assert.equal(r3b.code, 0, r3b.out + r3b.err);
  assert.match(r3b.out, /^gate critic: pass: .*carried: no third round vs /m);
  assert.equal(record(fx).gates.critic.rounds.length, 2);
  // New narration is a new script: its critic starts at round 1.
  const r4 = renderUnjudged(fx, SCRIPT.replace("Here is how.", "Here is why."));
  assert.match(r4.out, /^gate critic: pending: round 1 of 2, /m);
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

test("a hard failure in the critic's second round stops the run: no third round could judge a fix", () => {
  const fx = fixture();
  const invented = () => ({
    ...CLEAN,
    failures: [{ kind: "invented", what: "a figure no sentence states" }],
  });
  renderUnjudged(fx, SCRIPT);
  critique(fx.dir, invented);
  const r1 = stage(fx, "render/render.mjs");
  assert.match(r1.out, /^gates: 6 pass, 1 fail; next: fix attempt 1 of 2$/m);
  renderUnjudged(fx, SCRIPT.replace('"value": "code"', '"value": "the code"'));
  critique(fx.dir, invented);
  const r2 = stage(fx, "render/render.mjs");
  assert.equal(r2.code, 1, r2.out + r2.err);
  assert.match(r2.out, /^gate critic: fail: .*round 2 of 2 vs /m);
  assert.match(
    r2.out,
    /^gates: 6 pass, 1 fail; stop: the critic's second round is red, no video$/m,
  );
  assert.ok(record(fx).attempts >= 3, "the storyboard reads it as stopped");
});

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

test("a re-render judges again only the scenes it changed; the rest carry their verdicts into the round", () => {
  const fx = fixture();
  assert.equal(render(fx).code, 0);
  const r = renderUnjudged(
    fx,
    SCRIPT.replace('"value": "code"', '"value": "some code"'),
  );
  assert.equal(r.code, 1, r.out + r.err);
  assert.match(
    r.out,
    /^gate critic: pending: round 2 of 2, 2 of 3 scene\(s\) judged, /m,
  );
  assert.deepEqual(critique(fx.dir), ["steps"]);
  const again = stage(fx, "render/render.mjs");
  assert.equal(again.code, 0, again.out + again.err);
  assert.match(again.out, /^gate critic: pass: .*round 2 of 2 vs /m);
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
