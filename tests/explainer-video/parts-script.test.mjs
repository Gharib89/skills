// A part's script through the stages: its run folder takes the pack's
// snapshots from the run, and the script gates hold its bridge back to the
// part before and its end's naming of the part after.
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import {
  SCENES,
  check,
  judge,
  line,
  node,
  say,
  sceneFile,
} from "./check-lib.mjs";
import {
  deliver,
  fixture,
  parts,
  plan,
  snapshot,
  writePlan,
} from "./parts-lib.mjs";

const [hook, why, point, recap, bye] = SCENES;
// 15 scenes of 12 s and the 1 s hold: a 3-minute part within 10 percent.
const three = (over = {}) => [
  hook,
  { ...why, ...over.why },
  ...Array.from({ length: 11 }, (_, i) => ({ ...point, id: `p${i}` })),
  recap,
  { ...bye, ...over.bye },
];
// An end of three sentences within the budget that names the next part.
const naming = (title) => ({
  sentences: [
    say(12),
    `${title.toLowerCase()} comes next, ship reads the issue then writes a test. [no-claim]`,
    say(12, "[ex-2, ex-3]"),
  ],
});
const NEXT = { bye: naming("Opening the PR") };
// Two parts of 3 minutes, part 1 delivered when `n` is 2, its folder started
// and its script compiled, judged and ready for the gates.
function partRun(n, scenes) {
  const fx = fixture({ length: 6, excerpts: 6 });
  snapshot(fx, 6);
  writePlan(fx, plan([3, 3], 3));
  assert.equal(parts(fx, "start", "1").code, 0);
  if (n === 2) {
    deliver(fx, "01-claiming-work");
    assert.equal(parts(fx, "start", "2").code, 0);
  }
  const dir = path.join(
    fx.dir,
    "parts",
    fs.readdirSync(path.join(fx.dir, "parts"))[n - 1],
  );
  const part = { tmp: fx.tmp, dir };
  fs.writeFileSync(path.join(dir, "script.md"), sceneFile(scenes));
  const c = node(part, "script/compile.mjs");
  assert.equal(c.code, 0, c.err);
  judge(part);
  return { fx, part };
}

test("a part's cites read word for word in the snapshots of the run it belongs to", () => {
  const { part } = partRun(1, three(NEXT));
  const r = check(part);
  assert.equal(line(r, "cites"), "script cites: pass", r.out);
  fs.writeFileSync(
    path.join(part.dir, "..", "..", "snapshots", "doc.md"),
    "Other words.\nFact number 2.\nFact number 3.",
  );
  assert.match(
    line(check(part), "cites"),
    /^script cites: fail: ex-1 is no longer word for word in line 1$/,
  );
});

test("a part's arc, hook and recap held on its own: a 3-minute part needs no sections", () => {
  const { part } = partRun(1, three(NEXT));
  const r = check(part);
  assert.equal(line(r, "arc"), "script arc: pass", r.out);
  assert.equal(line(r, "budget"), "script budget: pass", r.out);
});

test("each part but the last ends by naming the next part", () => {
  const named = check(partRun(1, three(NEXT)).part);
  assert.equal(line(named, "parts"), "script parts: pass", named.out);
  // a near miss of the title (a longer word, one more word) names nothing
  const near = check(
    partRun(1, three({ bye: naming("Opening the PRs") })).part,
  );
  assert.match(
    line(near, "parts"),
    /^script parts: fail: bye \(end\) does not name/,
  );
  const silent = check(partRun(1, three()).part);
  assert.equal(
    line(silent, "parts"),
    'script parts: fail: bye (end) does not name the next part "Opening the PR"',
  );
  assert.equal(silent.code, 1);
});

test("part two onward's context cites its bridge to the part before, and the last part names no next", () => {
  const bridged = check(partRun(2, three()).part);
  assert.equal(line(bridged, "parts"), "script parts: pass", bridged.out);
  const cut = three({
    why: {
      sentences: [say(12, "[ex-4]"), say(12, "[no-claim]"), say(12, "[ex-5]")],
    },
  });
  const r = check(partRun(2, cut).part);
  assert.equal(
    line(r, "parts"),
    "script parts: fail: why (context) cites none of part 1's excerpts ex-1, ex-2, ex-3: bridge back to the part before",
  );
  assert.equal(r.code, 1);
});

test("a part.json of the wrong shape is refused by file and field, not skipped", () => {
  const { part } = partRun(2, three());
  const own = path.join(part.dir, "part.json");
  const good = JSON.parse(fs.readFileSync(own, "utf8"));
  for (const [body, why] of [
    ["{", /^script: part\.json is not valid JSON: /],
    ["{}", /^script: part\.json: series is not a name$/],
    [{ ...good, n: "2" }, /^script: part\.json: n is not a part number$/],
    [
      { ...good, next: { title: 3 } },
      /^script: part\.json: next\.title is not a title$/,
    ],
    [
      { ...good, bridge: {} },
      /^script: part\.json: bridge\.excerpts is not a list of ids$/,
    ],
    [
      { ...good, bridge: "ex-1" },
      /^script: part\.json: bridge\.excerpts is not a list of ids$/,
    ],
  ]) {
    fs.writeFileSync(
      own,
      typeof body === "string" ? body : JSON.stringify(body),
    );
    const r = check(part);
    assert.equal(r.code, 1, r.out);
    assert.match(r.err.trim(), why);
  }
  fs.writeFileSync(own, JSON.stringify(good));
  assert.equal(line(check(part), "parts"), "script parts: pass");
});

test("a script that is no part's runs no parts gate", () => {
  const fx = fixture({ length: 1, excerpts: 3 });
  snapshot(fx, 3);
  fs.writeFileSync(path.join(fx.dir, "script.md"), sceneFile(SCENES));
  assert.equal(node(fx, "script/compile.mjs").code, 0);
  judge(fx);
  assert.equal(line(check(fx), "parts"), undefined);
});
