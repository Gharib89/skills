// The part plan through parts.mjs check: the plan the agent writes into
// parts.json held to the brief's length and the source pack.
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fixture, parts, plan, writePlan } from "./parts-lib.mjs";

const refused = (fx, p) => {
  writePlan(fx, p);
  const r = parts(fx, "check");
  assert.equal(r.code, 1, r.out);
  return r.err;
};

test("a plan of three parts of 4 minutes over the 12 excerpts passes, one line a part", () => {
  const fx = fixture();
  writePlan(fx, plan([4, 4, 4]));
  const r = parts(fx, "check");
  assert.equal(r.code, 0, r.err);
  assert.equal(
    r.out,
    [
      "part 1: Claiming work · 4 min · 4 excerpts",
      "part 2: Opening the PR · 4 min · 4 excerpts",
      "part 3: Landing it · 4 min · 4 excerpts",
      "parts: 3 parts, 12 min",
      "",
    ].join("\n"),
  );
});

test("time may shift between parts within the 2 to 5 minute bounds", () => {
  const fx = fixture();
  writePlan(fx, plan([5, 2, 5]));
  assert.equal(parts(fx, "check").code, 0);
});

test("a part outside 2 to 5 minutes is refused, and so is a total that is not the brief's", () => {
  const fx = fixture();
  assert.match(
    refused(fx, plan([6, 2, 4])),
    /^parts: part 1: 6 min is outside 2 to 5$/m,
  );
  assert.match(
    refused(fx, plan([1.5, 5, 5.5])),
    /^parts: part 3: 5.5 min is outside 2 to 5$/m,
  );
  assert.match(
    refused(fx, plan([4, 4, 3])),
    /^parts: the parts run 11 min, the brief asks 12$/m,
  );
});

test("a part with no title, focus or excerpts is refused", () => {
  const fx = fixture();
  const p = plan([4, 4, 4]);
  p.parts[1].title = " ";
  delete p.parts[0].focus;
  p.parts[2].excerpts = [];
  const err = refused(fx, p);
  assert.match(err, /^parts: part 2 has no title$/m);
  assert.match(err, /^parts: part 1 has no focus$/m);
  assert.match(err, /^parts: part 3 has no excerpts$/m);
});

test("an excerpt the pack lacks, or two parts share, is refused", () => {
  const fx = fixture();
  const p = plan([4, 4, 4]);
  p.parts[1].excerpts.push("ex-99");
  assert.match(
    refused(fx, p),
    /^parts: part 2: ex-99 is not in excerpts\.json$/m,
  );
  const q = plan([4, 4, 4]);
  q.parts[1].excerpts.push("ex-2");
  assert.match(refused(fx, q), /^parts: ex-2 is in part 1 and part 2$/m);
});

test("a must item goes to a part and is said there, and each of the brief's lands in one", () => {
  const fx = fixture({ brief: ["must=local gate", "must=merge"] });
  const p = plan([4, 4, 4]);
  p.parts[0].must = ["local gate"];
  p.parts[1].must = ["rebase"];
  const err = refused(fx, p);
  assert.match(
    err,
    /^parts: part 2 must "rebase" is not in the brief's must$/m,
  );
  assert.match(err, /^parts: must "merge" is in no part$/m);
  p.parts[1].must = ["merge"];
  writePlan(fx, p);
  assert.equal(parts(fx, "check").code, 0);
});

test("a plan is refused where the request is within five minutes, absent, or a decline stands", () => {
  const short = fixture({ length: 4 });
  writePlan(short, plan([2, 2]));
  const r = parts(short, "check");
  assert.equal(r.code, 1);
  assert.match(r.err, /^parts: 4 min is within 5, no part plan$/m);
  const none = parts(fixture(), "check");
  assert.equal(none.code, 1);
  assert.match(none.err, /^parts: no part plan: write parts\.json first$/m);
  const fx = fixture();
  assert.equal(parts(fx, "decline").code, 0);
  const d = parts(fx, "check");
  assert.equal(d.code, 0);
  assert.equal(d.out, "parts: declined, one long video in sections\n");
});

test("a parts.json that is not a plan is refused by name, never as a stack trace", () => {
  const fx = fixture();
  const file = path.join(fx.dir, "parts.json");
  for (const [body, why] of [
    ["{not json", /^parts: parts\.json is not valid JSON: /m],
    ["{}", /^parts: parts\.json holds no parts list$/m],
    ['{"parts":"x"}', /^parts: parts\.json holds no parts list$/m],
    ['{"parts":[null]}', /^parts: part 1 is not an object$/m],
    [
      JSON.stringify(plan([4, 4, 4]), (k, v) => (v === 4 ? "4" : v)),
      /^parts: part 1: minutes is not a number$/m,
    ],
    [
      JSON.stringify({
        parts: [{ title: "a", focus: "b", minutes: 4, excerpts: "ex-1" }],
      }),
      /^parts: part 1: excerpts is not a list of ids$/m,
    ],
  ]) {
    fs.writeFileSync(file, body);
    const r = parts(fx, "check");
    assert.equal(r.code, 1, body);
    assert.match(r.err, why, body);
    assert.doesNotMatch(r.err, /\n\s+at /, r.err);
  }
  // valid JSON of the wrong shape in the files the plan is held against
  writePlan(fx, plan([4, 4, 4]));
  const held = (name) => {
    const f = path.join(fx.dir, name);
    const text = fs.readFileSync(f, "utf8");
    return (body) => {
      fs.writeFileSync(f, body);
      const r = parts(fx, "check");
      fs.writeFileSync(f, text);
      return r;
    };
  };
  const pack = held("excerpts.json")('{"x":1}');
  assert.equal(pack.code, 1);
  assert.match(pack.err, /^parts: excerpts\.json holds no excerpts list$/m);
  assert.doesNotMatch(pack.err, /\n\s+at /, pack.err);
  const brief = JSON.parse(
    fs.readFileSync(path.join(fx.dir, "brief.json"), "utf8"),
  );
  const must = held("brief.json")(JSON.stringify({ ...brief, must: "x" }));
  assert.equal(must.code, 1);
  assert.match(must.err, /^parts: brief\.json must is not a list$/m);
  assert.doesNotMatch(must.err, /\n\s+at /, must.err);
  assert.equal(parts(fx, "check").code, 0);
  fs.rmSync(path.join(fx.dir, "excerpts.json"));
  assert.match(
    parts(fx, "check").err,
    /^parts: no excerpts\.json: run pack\.mjs first$/m,
  );
});
