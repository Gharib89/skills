// parts.mjs start: a part becomes a run folder of its own under the run, with
// the brief, the pack and the bridge it needs, one part at a time.
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import {
  deliver,
  fixture,
  node,
  parts,
  plan,
  readJson,
  writePlan,
} from "./parts-lib.mjs";

const ready = () => {
  const fx = fixture({ brief: ["avoid=pricing", "must=local gate"] });
  const p = plan([4, 4, 4]);
  p.parts[1].must = ["local gate"];
  writePlan(fx, p);
  return fx;
};

test("part 1 gets a folder of its own with its brief, its excerpts and what comes next", () => {
  const fx = ready();
  const r = parts(fx, "start", "1");
  assert.equal(r.code, 0, r.err);
  assert.equal(
    r.out,
    [
      "parts: part 1 of 3 -> parts/01-claiming-work",
      'parts: next: part 2 "Opening the PR"',
      "",
    ].join("\n"),
  );
  const dir = path.join(fx.dir, "parts", "01-claiming-work");
  const whole = readJson(fx.dir, "brief.json");
  assert.deepEqual(readJson(dir, "brief.json"), {
    ...whole,
    focus: "what happens in step 1",
    length: 4,
    must: [],
  });
  assert.deepEqual(
    readJson(dir, "excerpts.json").excerpts.map((x) => x.id),
    ["ex-1", "ex-2", "ex-3", "ex-4"],
  );
  assert.deepEqual(readJson(dir, "part.json"), {
    series: "demo",
    n: 1,
    of: 3,
    title: "Claiming work",
    focus: "what happens in step 1",
    minutes: 4,
    excerpts: ["ex-1", "ex-2", "ex-3", "ex-4"],
    bridge: null,
    next: { title: "Opening the PR" },
    notes: [],
  });
});

test("a part waits for the one before it to be delivered", () => {
  const fx = ready();
  assert.equal(parts(fx, "start", "1").code, 0);
  const r = parts(fx, "start", "2");
  assert.equal(r.code, 1);
  assert.match(
    r.err,
    /^parts: part 1 is not delivered: finish its render first$/m,
  );
  assert.equal(
    fs.existsSync(path.join(fx.dir, "parts", "02-opening-the-pr")),
    false,
  );
});

test("part 2 bridges back: the previous part's excerpts join its pack, its title and its must items come with it", () => {
  const fx = ready();
  parts(fx, "start", "1");
  deliver(fx, "01-claiming-work");
  const r = parts(fx, "start", "2");
  assert.equal(r.code, 0, r.err);
  assert.equal(
    r.out,
    [
      "parts: part 2 of 3 -> parts/02-opening-the-pr",
      'parts: bridge: part 1 "Claiming work" (ex-1, ex-2, ex-3, ex-4)',
      'parts: next: part 3 "Landing it"',
      "",
    ].join("\n"),
  );
  const dir = path.join(fx.dir, "parts", "02-opening-the-pr");
  assert.deepEqual(
    readJson(dir, "excerpts.json").excerpts.map((x) => x.id),
    ["ex-1", "ex-2", "ex-3", "ex-4", "ex-5", "ex-6", "ex-7", "ex-8"],
  );
  assert.deepEqual(readJson(dir, "brief.json").must, ["local gate"]);
  assert.deepEqual(readJson(dir, "part.json").bridge, {
    title: "Claiming work",
    excerpts: ["ex-1", "ex-2", "ex-3", "ex-4"],
  });
});

test("the last part names no next part, and a part past the plan is refused", () => {
  const fx = ready();
  for (const f of ["01-claiming-work", "02-opening-the-pr"]) {
    const n = f.slice(0, 2);
    assert.equal(parts(fx, "start", String(+n)).code, 0);
    deliver(fx, f);
  }
  const r = parts(fx, "start", "3");
  assert.equal(r.out.includes("parts: next:"), false, r.out);
  assert.equal(
    readJson(fx.dir, "parts", "03-landing-it", "part.json").next,
    null,
  );
  const past = parts(fx, "start", "4");
  assert.equal(past.code, 1);
  assert.match(past.err, /^parts: no part 4, the plan has 3$/m);
});

test("the operator's notes on the previous part reach the next part, from its latest board answers only", () => {
  const fx = ready();
  parts(fx, "start", "1");
  deliver(fx, "01-claiming-work");
  const board = path.join(fx.dir, "parts", "01-claiming-work", "board");
  fs.mkdirSync(board, { recursive: true });
  const answers = (scenes, kept = [], brief = []) =>
    JSON.stringify({ version: 1, scenes, kept, brief });
  fs.writeFileSync(
    path.join(board, "answers-1.json"),
    answers([{ id: "old", choice: "revise", note: "stale note" }]),
  );
  fs.writeFileSync(
    path.join(board, "answers-2.json"),
    answers(
      [
        { id: "hook", choice: "revise", note: "open on the failure" },
        { id: "recap", choice: "approve", note: "" },
      ],
      [{ term: "Ship", to: "Shipp" }],
      ["voice=am_fenrir"],
    ),
  );
  const r = parts(fx, "start", "2");
  assert.equal(r.code, 0, r.err);
  const notes = [
    "hook: open on the failure",
    "kept term Ship -> Shipp",
    "brief voice=am_fenrir",
  ];
  for (const n of notes)
    assert.ok(r.out.includes(`parts: note from part 1, ${n}\n`), r.out);
  assert.deepEqual(
    readJson(fx.dir, "parts", "02-opening-the-pr", "part.json").notes,
    notes,
  );
});

test("a part's board answers or manifest of the wrong shape are refused by file and field, never as a stack trace", () => {
  const fx = ready();
  parts(fx, "start", "1");
  const part = path.join(fx.dir, "parts", "01-claiming-work");
  deliver(fx, "01-claiming-work");
  const board = path.join(part, "board");
  fs.mkdirSync(board, { recursive: true });
  for (const [body, why] of [
    ["[]", /^parts: answers-1\.json is not an object$/m],
    ['{"scenes":"x"}', /^parts: answers-1\.json scenes is not a list$/m],
    ['{"kept":{}}', /^parts: answers-1\.json kept is not a list$/m],
    ...['{"scenes":[null]}', '{"scenes":[{"note":"x"}]}'].map((b) => [
      b,
      /^parts: answers-1\.json scenes entry 1 is not an object with an id$/m,
    ]),
    ...['{"kept":[3]}', '{"kept":[{}]}', '{"kept":[{"term":"a","to":2}]}'].map(
      (b) => [
        b,
        /^parts: answers-1\.json kept entry 1 is not an object with a term and a to$/m,
      ],
    ),
    ['{"brief":[3]}', /^parts: answers-1\.json brief entry 1 is not text$/m],
    [
      '{"scenes":[{"id":"a","note":3}]}',
      /^parts: answers-1\.json scenes entry 1 note is not text$/m,
    ],
  ]) {
    fs.writeFileSync(path.join(board, "answers-1.json"), body);
    const r = parts(fx, "start", "2");
    assert.equal(r.code, 1, body);
    assert.match(r.err, why, body);
    assert.doesNotMatch(r.err, /\n\s+at /, r.err);
  }
  fs.rmSync(board, { recursive: true });
  fs.writeFileSync(path.join(part, "manifest.json"), "null");
  const m = parts(fx, "start", "2");
  assert.equal(m.code, 1);
  assert.match(
    m.err,
    /^parts: part 1 is not delivered: finish its render first$/m,
  );
});

test("starting a part again keeps its scene file, and drops its compiled script only where the brief moved the language, voice or style", () => {
  const fx = ready();
  parts(fx, "start", "1");
  const dir = path.join(fx.dir, "parts", "01-claiming-work");
  fs.writeFileSync(path.join(dir, "script.md"), "# mine\n");
  fs.writeFileSync(path.join(dir, "script.json"), "{}");
  const old = new Date(2020, 0, 1);
  fs.utimesSync(path.join(dir, "excerpts.json"), old, old);
  assert.equal(parts(fx, "start", "1").code, 0);
  assert.equal(fs.existsSync(path.join(dir, "script.json")), true);
  assert.equal(
    fs.statSync(path.join(dir, "excerpts.json")).mtime.getFullYear(),
    2020,
  );
  assert.equal(node(fx, "brief/brief.mjs", ["voice=am_fenrir"]).code, 0);
  assert.equal(parts(fx, "start", "1").code, 0);
  assert.equal(readJson(dir, "brief.json").voice, "am_fenrir");
  assert.equal(fs.existsSync(path.join(dir, "script.json")), false);
  assert.equal(
    fs.readFileSync(path.join(dir, "script.md"), "utf8"),
    "# mine\n",
  );
});

test("a delivered part whose recipe the plan changed is no longer delivered, so the part after it waits for its new render", () => {
  const fx = ready();
  parts(fx, "start", "1");
  deliver(fx, "01-claiming-work");
  const dir = path.join(fx.dir, "parts", "01-claiming-work");
  // starting it again with nothing changed keeps its delivery
  assert.equal(parts(fx, "start", "1").code, 0);
  assert.equal(fs.existsSync(path.join(dir, "manifest.json")), true);
  assert.equal(parts(fx, "start", "2").code, 0);
  fs.rmSync(path.join(fx.dir, "parts", "02-opening-the-pr"), {
    recursive: true,
  });
  // the same title with another focus is another recipe
  const p = plan([4, 4, 4]);
  p.parts[0].focus = "a new angle on step 1";
  p.parts[1].must = ["local gate"];
  writePlan(fx, p);
  const r = parts(fx, "start", "1");
  assert.equal(r.code, 0, r.err);
  assert.match(
    r.out,
    /^parts: part 1 changed since its render: render it again$/m,
  );
  assert.equal(fs.existsSync(path.join(dir, "manifest.json")), false);
  const q = parts(fx, "start", "2");
  assert.equal(q.code, 1);
  assert.match(
    q.err,
    /^parts: part 1 is not delivered: finish its render first$/m,
  );
});

test("a plan that fails its check, a decline or a bad number starts nothing", () => {
  const fx = ready();
  const bad = plan([4, 4, 3]);
  writePlan(fx, bad);
  const r = parts(fx, "start", "1");
  assert.equal(r.code, 1);
  assert.match(r.err, /^parts: the parts run 11 min, the brief asks 12$/m);
  assert.equal(fs.existsSync(path.join(fx.dir, "parts")), false);
  for (const n of ["0", "x"]) {
    const q = parts(ready(), "start", n);
    assert.equal(q.code, 1);
    assert.match(q.err, /^parts: part number is 1 or more, got /m);
  }
  const d = fixture();
  parts(d, "decline");
  const q = parts(d, "start", "1");
  assert.equal(q.code, 1);
  assert.match(
    q.err,
    /^parts: declined, one long video in sections: no parts to start$/m,
  );
});
