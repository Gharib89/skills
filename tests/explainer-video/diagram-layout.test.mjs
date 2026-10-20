// The composer lays a diagram out: columns along the reading direction, each
// node a box inside the content area, no two boxes overlapping, for every grid
// a frame holds; right to left, the layout mirrors.
import { test } from "node:test";
import assert from "node:assert/strict";
import { FIXTURE } from "../../skills/explainer-video/maintainer/real-render-fixture.mjs";
import { DIAGRAM } from "../../skills/explainer-video/scripts/lib/diagram.mjs";
import { checkVisual } from "../../skills/explainer-video/scripts/lib/visuals.mjs";
import { contentBox } from "../../skills/explainer-video/scripts/render/compose.mjs";
import { diagramLayout } from "../../skills/explainer-video/scripts/render/diagram.mjs";

// A diagram whose columns hold `heights[c]` nodes each: every node of a column
// linked from the first node of the column before.
function grid(heights) {
  const nodes = [];
  const links = [];
  heights.forEach((h, c) => {
    for (let r = 0; r < h; r++) {
      nodes.push({ id: `c${c}r${r}`, at: 1, label: `Node ${c}.${r}` });
      if (c) links.push({ from: `c${c - 1}r0`, to: `c${c}r${r}`, at: 1 });
    }
  });
  return { nodes, links };
}
// Every list of 1 to DIAGRAM.columns column heights, each 1 to DIAGRAM.rows.
function* shapes(prefix = []) {
  if (prefix.length) yield prefix;
  if (prefix.length === DIAGRAM.columns) return;
  for (let h = 1; h <= DIAGRAM.rows; h++) yield* shapes([...prefix, h]);
}
const overlap = (a, b) =>
  a.left < b.left + b.w &&
  b.left < a.left + a.w &&
  a.top < b.top + b.h &&
  b.top < a.top + a.h;
// Each node box inside `box`, and no two overlapping; `what` names the case.
function contained(nodes, box, what) {
  for (const a of nodes) {
    assert.ok(
      a.left >= 0 &&
        a.top >= 0 &&
        a.left + a.w <= box.width &&
        a.top + a.h <= box.height,
      `${what}: ${JSON.stringify(a)} outside ${box.width}x${box.height}`,
    );
    for (const b of nodes)
      if (a !== b) assert.ok(!overlap(a, b), `${what}: boxes overlap`);
  }
}

test("every node of every grid a frame holds sits inside the content area, and no two overlap", () => {
  let n = 0;
  for (const layout of ["open", "bands"]) {
    const box = contentBox(layout);
    for (const heights of shapes()) {
      const { nodes } = diagramLayout(grid(heights), box, false);
      contained(nodes, box, `${layout} ${heights}`);
      n++;
    }
  }
  // 3 + 9 + 27 + 81 + 243 grids, under each layout
  assert.equal(n, 726);
});

test("the real-render fixture's diagrams compile, and lay out inside the content area with no two nodes overlapping", () => {
  const diagrams = FIXTURE.filter(
    (p) => p.scene.visual.component === "diagram",
  );
  assert.equal(diagrams.length, 2);
  for (const { scene, dir } of diagrams) {
    checkVisual(scene.visual, scene.narration);
    for (const layout of ["open", "bands"]) {
      const box = contentBox(layout);
      const { nodes } = diagramLayout(scene.visual.props, box, dir === "rtl");
      contained(nodes, box, `${scene.id} ${layout}`);
    }
  }
});

test("columns run along the reading direction: left to right, mirrored right to left", () => {
  const box = contentBox("open");
  const d = grid([1, 2]);
  const ltr = diagramLayout(d, box, false).nodes;
  const rtl = diagramLayout(d, box, true).nodes;
  // the first column's node stands at the reading start
  assert.ok(ltr[0].left < ltr[1].left);
  assert.ok(rtl[0].left > rtl[1].left);
  for (const [i, a] of ltr.entries()) {
    assert.equal(rtl[i].left, box.width - a.left - a.w);
    assert.equal(rtl[i].top, a.top);
  }
  // a column's nodes stack in the order written
  assert.ok(ltr[1].top < ltr[2].top);
  assert.equal(ltr[1].left, ltr[2].left);
});
