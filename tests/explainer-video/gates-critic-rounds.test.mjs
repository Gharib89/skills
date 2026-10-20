// The video gates through their process doors, part 4b: the critic's two
// rounds of one script.
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { CLEAN, critique } from "./critic.mjs";
import { SCRIPT } from "./scene-file.mjs";
import {
  calls,
  fixture,
  record,
  render,
  renderUnjudged,
  stage,
} from "./gates-lib.mjs";

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

test("a hard failure in the critic's second round stops the run: no third round could judge a fix", () => {
  const fx = fixture();
  const invented = () => ({
    ...CLEAN,
    failures: [{ kind: "invented", what: "a figure no sentence states" }],
  });
  renderUnjudged(fx, SCRIPT);
  critique(fx.dir, invented);
  const r1 = stage(fx, "render/render.mjs");
  assert.match(r1.out, /^gates: 7 pass, 1 fail; next: fix attempt 1 of 2$/m);
  renderUnjudged(fx, SCRIPT.replace('"value": "code"', '"value": "the code"'));
  critique(fx.dir, invented);
  const r2 = stage(fx, "render/render.mjs");
  assert.equal(r2.code, 1, r2.out + r2.err);
  assert.match(r2.out, /^gate critic: fail: .*round 2 of 2 vs /m);
  assert.match(
    r2.out,
    /^gates: 7 pass, 1 fail; stop: the critic's second round is red, no video$/m,
  );
  assert.ok(record(fx).attempts >= 3, "the storyboard reads it as stopped");
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
