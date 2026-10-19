// The render stage through its process door, part 3: diagram and code
// components on a scene's paused timeline, sketches and right to left scenes.
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { DIAGRAMS } from "./scene-file.mjs";
import {
  at,
  calls,
  comp,
  fixture,
  near,
  profile,
  profiled,
  read,
  render,
  skill,
  tweens,
} from "./render-lib.mjs";

test("each diagram and code component composes onto its scene's paused timeline, each reveal at its sentence, nothing on the clock", () => {
  const fx = fixture(DIAGRAMS);
  const r = render(fx);
  assert.equal(r.code, 0, r.out + r.err);
  for (const id of ["flow", "sides", "gates", "code", "diff"]) {
    const html = comp(fx, `scenes/${id}.html`);
    assert.doesNotMatch(
      html,
      /transition|animation|@keyframes|setTimeout|setInterval|requestAnimationFrame|Date\.now|performance\.now|Math\.random/,
      id,
    );
    assert.match(html, /gsap\.timeline\(\{ paused: true \}\)/, id);
    assert.ok(tweens(fx, id).length, id);
    // Every scoped line opens a rule: a bare selector swallows the page's
    // next rule, as a clean look's empty sketch CSS once did.
    const style = html.match(/<style>([\s\S]*?)<\/style>/)[1];
    for (const l of style.split("\n").filter((l) => l.trim()))
      assert.match(l, /\{/, `${id}: ${l}`);
  }

  const flow = comp(fx, "scenes/flow.html");
  assert.equal([...flow.matchAll(/class="node /g)].length, 3);
  assert.equal([...flow.matchAll(/class="arrow /g)].length, 2);
  const steps = tweens(fx, "flow").filter(([s]) => /^\.n\d$/.test(s));
  assert.deepEqual(
    steps.map(([s, , , t]) => [s, near(t, at(fx, "flow", +s.slice(2) + 1))]),
    [
      [".n0", true],
      [".n1", true],
      [".n2", true],
    ],
  );
  // draw: the arrow into a step strokes on as that step rises.
  const drawn = tweens(fx, "flow").filter(([, f]) => "strokeDashoffset" in f);
  assert.equal(drawn.length, 2);
  assert.ok(near(drawn[1][3], at(fx, "flow", 3)));

  for (const id of ["flow", "sides", "gates"])
    assert.match(comp(fx, `scenes/${id}.html`), /class="content" dir="ltr"/);

  // Shiki colours each token from the profile's palette; code stays left to
  // right whatever the scene's direction.
  const code = comp(fx, "scenes/code.html");
  // (the critic's round renders a second time)
  assert.deepEqual(
    calls(fx, "highlight")
      .slice(0, 3)
      .map((c) => c.lang),
    ["bash", "js", "js"],
  );
  assert.match(code, /<span style="color:var\(--code-[a-z-]+\)">/);
  assert.match(code, /--code-token-keyword: var\(--accent\);/);
  assert.match(code, /class="code rt" dir="ltr"/);
  const bar = tweens(fx, "code").find(([s]) => s === ".hl0");
  assert.ok(near(bar[3], at(fx, "code", 2)));

  // The diff: the removed line closes and the added one opens at sentence 2,
  // by tweens on the timeline, the kept lines untouched.
  const diff = tweens(fx, "diff");
  const del = diff.filter(([s]) => s.startsWith(".del"));
  const add = diff.filter(([s]) => s.startsWith(".add"));
  assert.equal(del.length, 1);
  assert.equal(add.length, 1);
  assert.equal(del[0][2].height, 0);
  assert.equal(add[0][1].height, 0);
  for (const [, , , t] of [...del, ...add])
    assert.ok(near(t, at(fx, "diff", 2)), String(t));
  const rows = comp(fx, "scenes/diff.html");
  assert.match(rows, /class="ln del del0">.*a - b;/);
  assert.match(rows, /class="ln add add0">.*a \+ b;/);
});

test("a seeded sketch renders identically twice, each outline at its own seed", () => {
  const twice = [0, 1].map(() => {
    const fx = fixture(DIAGRAMS.replace("style: claude-code", "style: rough"));
    profiled(fx, "rough", { grammar: { texture: { surface: "sketch" } } });
    const r = render(fx);
    assert.equal(r.code, 0, r.out + r.err);
    return {
      scenes: ["flow", "sides"].map((id) => comp(fx, `scenes/${id}.html`)),
      seeds: calls(fx, "sketch").flatMap((c) => c.shapes.map((s) => s.seed)),
    };
  });
  assert.deepEqual(twice[0], twice[1]);
  for (const s of twice[0].scenes) assert.match(s, /<svg class="sk"/);
  // three nodes, two arrows and two panels, each at its own seed
  assert.equal(new Set(twice[0].seeds).size, 7);
  assert.ok(twice[0].seeds.every((s) => Number.isInteger(s) && s > 0));
});

test("a right-to-left scene mirrors its flow and keeps its code left to right", async () => {
  process.env.EXPLAINER_VIDEO_FAKE_LOG = path.join(
    fs.mkdtempSync(path.join(os.tmpdir(), "ev-rtl-")),
    "calls.jsonl",
  );
  const { sceneFile } =
    await import("../../skills/explainer-video/scripts/render/compose.mjs");
  const backend = await import("./fake-backend.mjs");
  const profile = JSON.parse(read(skill, "styles", "claude-code.json"));
  const timing = { duration: 6, sentences: [0.2, 2, 4] };
  const scene = (component, props) => ({
    id: component,
    visual: { component, props },
  });
  const flow = await sceneFile(
    scene("flow", {
      steps: [
        { at: 1, label: "Issue" },
        { at: 2, label: "Test" },
      ],
    }),
    timing,
    profile,
    { backend, dir: "rtl" },
  );
  assert.match(flow, /class="content" dir="rtl"/);
  assert.match(
    flow,
    /\[data-composition-id="flow"\] \[dir="rtl"\] \.arrow svg \{ transform: scaleX\(-1\); \}/,
  );
  const code = await sceneFile(
    scene("code", { lang: "js", code: "let a = 1;" }),
    timing,
    profile,
    { backend, dir: "rtl" },
  );
  assert.match(code, /class="content" dir="rtl"/);
  assert.match(code, /class="code rt" dir="ltr"/);
});
