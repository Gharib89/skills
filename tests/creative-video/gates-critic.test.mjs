// The critic gate: each scene's sample stills judged by a critic subagent
// (agents/critic.md), its verdict a stranger's description of every still and
// hard failures of three kinds, never scores. Pending until every scene has a
// verdict; two rounds per voice, unchanged scenes carried, a red second round
// final, a third render carrying the second round.
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { sampleTimes } from "../../skills/creative-video/scripts/gates/samples.mjs";
import {
  compose,
  critics,
  gateLine,
  record,
  runGates,
  timed,
  timeline,
} from "./gates-lib.mjs";

const raw = (fx) => runGates(fx, {}, { critic: false });
const dir = (fx) => path.join(fx.dir, record(fx).gates.critic.stills);
const INVENTED = [
  { kind: "invented", what: 'The card "ten times faster" is in no sentence.' },
];

test("a green project's critic is pending, each scene's sample stills set out, until every scene has a verdict", () => {
  const fx = timed();
  const r = raw(fx);
  assert.equal(r.code, 1, r.out + r.err);
  assert.match(
    gateLine(r, "critic"),
    /^pending: round 1 of 2, 0 of 3 scene\(s\) judged, stills in \.cache\/critic\/[0-9a-f]{16}$/,
  );
  assert.match(
    r.out,
    /^gates: 9 pass, 0 fail, 1 pending; next: run the critic, round 1 of 2$/m,
  );
  const stills = JSON.parse(
    fs.readFileSync(path.join(dir(fx), "stills.json"), "utf8"),
  );
  for (const sc of timeline(fx).scenes) {
    const times = [...new Set(Object.values(sampleTimes(sc)))];
    assert.deepEqual(
      stills[sc.id].map((s) => s.t),
      times,
    );
    for (const s of stills[sc.id])
      assert.ok(fs.existsSync(path.join(dir(fx), s.file)), s.file);
  }
});

test("verdicts with no failure pass, and gates.json keeps each still's description", () => {
  const fx = timed();
  const r = runGates(fx);
  assert.equal(r.code, 0, r.out + r.err);
  assert.match(
    gateLine(r, "critic"),
    /^pass: 0 finding\(s\), round 1 of 2 vs /,
  );
  assert.match(r.out, /^gates: 10 pass, 0 fail$/m);
  const { described } = record(fx).gates.critic;
  assert.deepEqual(
    described.map((d) => d.scene),
    ["hook", "context", "recap"],
  );
  assert.equal(described[0].stills[0].sees, "a frame of hook");
});

test("an invented or unreadable failure fails the critic as one fix attempt, led by the scene's start", () => {
  const fx = timed();
  raw(fx);
  critics(fx, {
    context: [...INVENTED, { kind: "unreadable", what: "Text over text." }],
  });
  const r = raw(fx);
  assert.equal(r.code, 1);
  const start = timeline(fx).scenes[1].start.toFixed(2);
  assert.equal(
    gateLine(r, "critic"),
    `fail: 2 finding(s), first: ${start} s context: invented: The card "ten times faster" is in no sentence., round 1 of 2 vs no unreadable, invented or rtl content`,
  );
  assert.match(r.out, /^gates: 9 pass, 1 fail; next: fix attempt 1 of 2$/m);
});

test("a gates.json whose critic has no rounds is refused by name", () => {
  const fx = timed();
  raw(fx);
  const f = path.join(fx.dir, "gates.json");
  const g = record(fx);
  delete g.gates.critic.rounds;
  fs.writeFileSync(f, JSON.stringify(g));
  const r = raw(fx);
  assert.equal(r.code, 1);
  assert.match(
    r.err,
    /^gates: gates\.json: gates\.critic\.rounds is not a list/,
  );
});

test("a verdict with scores, a kind outside the three, or a still left undescribed is refused by name", () => {
  for (const [bad, why] of [
    [
      { scores: { clarity: 4 } },
      "scores is not part of a verdict: describe each still, never score it",
    ],
    [
      { failures: [{ kind: "ugly", what: "x" }] },
      'failure 1 kind "ugly" is not unreadable, invented or rtl',
    ],
    [{ stills: [] }, "stills holds 0 description(s), one per still: 3"],
  ]) {
    const fx = timed();
    raw(fx);
    critics(fx);
    const f = path.join(dir(fx), "hook.json");
    const v = JSON.parse(fs.readFileSync(f, "utf8"));
    fs.writeFileSync(f, JSON.stringify({ ...v, ...bad }));
    const r = raw(fx);
    assert.equal(r.code, 1);
    assert.equal(r.err.trim(), `gates: critic verdict hook.json: ${why}`);
  }
});

test("a fix re-judges only the changed scene in round 2, and a red second round stops the run", () => {
  const fx = timed();
  raw(fx);
  critics(fx, { context: INVENTED });
  raw(fx);
  compose(fx, "context", "<p>what the narration says</p>");
  let r = raw(fx);
  assert.match(
    gateLine(r, "critic"),
    /^pending: round 2 of 2, 2 of 3 scene\(s\) judged, /,
  );
  critics(fx, { context: INVENTED });
  r = raw(fx);
  assert.equal(r.code, 1);
  assert.match(
    r.out,
    /^gates: 9 pass, 1 fail; stop: the critic's second round is red, no video$/m,
  );
  assert.equal(record(fx).attempts, 3);
});

test("past two rounds a render carries the second round's verdict rather than ask for a third", () => {
  const fx = timed();
  raw(fx);
  critics(fx, { context: INVENTED });
  raw(fx);
  compose(fx, "context", "<p>what the narration says</p>");
  assert.equal(runGates(fx).code, 0);
  compose(fx, "recap", "<p>a recap line</p>");
  const r = raw(fx);
  assert.equal(r.code, 0, r.out);
  assert.match(
    gateLine(r, "critic"),
    /^pass: 0 finding\(s\), round 2 of 2, carried: no third round vs /,
  );
});

test("a new voice starts the critic at round 1", () => {
  const fx = timed();
  raw(fx);
  critics(fx, { context: INVENTED });
  raw(fx);
  compose(fx, "context", "<p>what the narration says</p>");
  assert.equal(runGates(fx).code, 0);
  const rec = record(fx);
  fs.writeFileSync(
    path.join(fx.dir, "gates.json"),
    JSON.stringify({ ...rec, voice: "another" }),
  );
  compose(fx, "recap", "<p>a recap line</p>");
  assert.match(gateLine(raw(fx), "critic"), /^pending: round 1 of 2, 0 of 3 /);
});
