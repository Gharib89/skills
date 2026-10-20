// A number in a `diagram` node's label or note is a claim: the script gate
// holds it to an excerpt the scene cites, as it holds a timeline's.
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { SCENES, check, edit, fixture, line } from "./check-lib.mjs";

const FACTS = "The local gate runs 1,200 checks in 40 ms, 0.5 percent flaky.";
function gated(visual) {
  const fx = fixture({ scenes: edit(SCENES, 2, { visual }) });
  // No snapshot to re-check the excerpt against: the pack's text stands.
  fs.rmSync(path.join(fx.dir, "snapshots"), { recursive: true });
  const file = path.join(fx.dir, "excerpts.json");
  const pack = JSON.parse(fs.readFileSync(file, "utf8"));
  pack.excerpts[1].text = FACTS;
  fs.writeFileSync(file, JSON.stringify(pack));
  return line(check(fx), "cites");
}
const diagram = (a, b) => ({
  component: "diagram",
  props: {
    nodes: [a, b].map(([label, note], i) => ({
      id: `n${i}`,
      at: 1,
      label,
      ...(note && { note }),
    })),
    links: [{ from: "n0", to: "n1", at: 1 }],
  },
});

test("a diagram's numbers in a label or note stand in a cited excerpt", () => {
  assert.equal(
    gated(diagram(["Gate", "1,200 checks"], ["Runner", "40 ms"])),
    "script cites: pass",
  );
  assert.match(
    gated(diagram(["3 workers"], ["Runner"])),
    /on-screen number "3"/,
  );
  assert.match(
    gated(diagram(["Gate"], ["Runner", "200 checks"])),
    /on-screen number "200"/,
  );
});
