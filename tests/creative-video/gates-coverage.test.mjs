// The anchors gate (an at() naming a word the narration lacks) and the must and
// avoid gate (the brief's words, said in the narration or shown on screen).
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { compose, gateLine, only, runGates, timed } from "./gates-lib.mjs";

// A project whose context scene cues an event at `word` of its own narration.
function anchored(word) {
  const fx = timed();
  compose(
    fx,
    "context",
    "<p>context line</p>",
    `tl.from("p", { opacity: 0 }, at("context", "${word}"));`,
  );
  return fx;
}

test("an at() naming a word the scene lacks fails anchors by scene and word, and a real word passes", () => {
  const r = runGates(anchored("nosuchword"));
  assert.equal(r.code, 1);
  only(r, "anchors");
  assert.match(
    gateLine(r, "anchors"),
    /^fail: 1 finding\(s\), first: \d+\.\d\d s context: at: no word "nosuchword" vs every anchor names an aligned word$/,
  );
  assert.equal(runGates(anchored("profile")).code, 0);
});

test("a scene whose script throws fails script errors by scene and message, not anchors, and a script that runs passes", () => {
  const fx = timed();
  compose(
    fx,
    "context",
    "<p>context line</p>",
    'throw new Error("no such element");',
  );
  const r = runGates(fx);
  assert.equal(r.code, 1);
  only(r, "script errors");
  assert.match(
    gateLine(r, "script errors"),
    /^fail: 1 finding\(s\), first: context: Error: no such element vs every scene's script runs$/,
  );
  assert.equal(
    runGates(anchored("profile")).code,
    0,
    "a script that runs passes",
  );
});

test("a scene that never registers its timeline fails script errors though no error is reported", () => {
  const fx = timed();
  compose(fx, "context", "<p>context line</p>", "// no-timeline");
  const r = runGates(fx);
  assert.equal(r.code, 1);
  only(r, "script errors");
  assert.match(
    gateLine(r, "script errors"),
    /^fail: 1 finding\(s\), first: context: no timeline registered as window\.__timelines\["context"\], so its script stopped vs /,
  );
});

const BRIEF = (extra) => ({ brief: { length: 0.2, ...extra } });

test("a must word said or shown passes, one neither said nor shown fails", () => {
  // said: "pull request" is in the hook's narration
  const said = runGates(timed({}, BRIEF({ must: ["Pull Request"] })));
  assert.equal(said.code, 0, said.out);
  // shown: a word the narration lacks, drawn in a scene
  const shown = runGates(
    timed({ recap: "<p>quantum leap</p>" }, BRIEF({ must: ["quantum"] })),
  );
  assert.equal(shown.code, 0, shown.out);
  const missing = runGates(timed({}, BRIEF({ must: ["quantum"] })));
  assert.equal(missing.code, 1);
  only(missing, "must and avoid");
  assert.match(
    gateLine(missing, "must and avoid"),
    /^fail: 1 finding\(s\), first: must "quantum" is not said or shown vs /,
  );
});

test("an avoid word said or shown fails naming the scenes, and matches whole words only", () => {
  const said = runGates(timed({}, BRIEF({ avoid: ["profile"] })));
  assert.equal(said.code, 1);
  only(said, "must and avoid");
  assert.match(
    gateLine(said, "must and avoid"),
    /first: avoid "profile" is in context vs /,
  );
  const shown = runGates(
    timed({ hook: "<p>secret plan</p>" }, BRIEF({ avoid: ["secret"] })),
  );
  assert.match(gateLine(shown, "must and avoid"), /avoid "secret" is in hook/);
  // "prof" is inside "profile"; "request" is a whole word of two scenes
  assert.equal(runGates(timed({}, BRIEF({ avoid: ["prof"] }))).code, 0);
  const whole = runGates(timed({}, BRIEF({ avoid: ["request"] })));
  assert.match(
    gateLine(whole, "must and avoid"),
    /avoid "request" is in hook, recap/,
  );
});

test("must and avoid judge the voiced words, not a script.json edited after timing", () => {
  const edit = (fx, change) => {
    const file = path.join(fx.dir, "script.json");
    const script = JSON.parse(fs.readFileSync(file, "utf8"));
    for (const s of script.scenes) s.narration = s.narration.map(change);
    fs.writeFileSync(file, JSON.stringify(script));
  };
  const added = timed({}, BRIEF({ must: ["quantum"] }));
  edit(added, (n) => `${n} quantum`);
  const r = runGates(added);
  assert.equal(r.code, 1, r.out);
  assert.match(gateLine(r, "must and avoid"), /must "quantum" is not said/);
  const removed = timed({}, BRIEF({ avoid: ["profile"] }));
  edit(removed, (n) => n.replace(/profile/gi, "outline"));
  assert.match(
    gateLine(runGates(removed), "must and avoid"),
    /avoid "profile" is in context/,
  );
});

test("text drawn at opacity 0 is not shown, for must or for avoid", () => {
  const must = runGates(
    timed({ recap: "<p>quantum hidden</p>" }, BRIEF({ must: ["quantum"] })),
  );
  assert.equal(must.code, 1, must.out);
  assert.match(gateLine(must, "must and avoid"), /must "quantum" is not said/);
  const avoid = runGates(
    timed({ hook: "<p>secret hidden</p>" }, BRIEF({ avoid: ["secret"] })),
  );
  assert.match(gateLine(avoid, "must and avoid"), /^pass: /, avoid.out);
});

test("a brief with no must and no avoid passes the gate, and a list that is not text is refused", () => {
  const r = runGates(timed({}, BRIEF({})));
  assert.equal(r.code, 0, r.out);
  assert.match(gateLine(r, "must and avoid"), /^pass: /);
  const fx = timed({}, BRIEF({}));
  fs.writeFileSync(
    path.join(fx.dir, "brief.json"),
    JSON.stringify({ length: 0.2, must: "quantum" }),
  );
  const bad = runGates(fx);
  assert.equal(bad.code, 1);
  assert.match(bad.err, /^gates: brief\.json: must is not a list/);
});

test("a must or avoid entry with no letter or digit is refused, since it would match everywhere", () => {
  for (const [key, entry] of [
    ["must", ""],
    ["avoid", "..."],
  ]) {
    const fx = timed({}, BRIEF({}));
    fs.writeFileSync(
      path.join(fx.dir, "brief.json"),
      JSON.stringify({ length: 0.2, [key]: ["real", entry] }),
    );
    const r = runGates(fx);
    assert.equal(r.code, 1);
    assert.match(
      r.err,
      new RegExp(`^gates: brief\\.json: ${key}\\[1\\] has no letter or digit`),
    );
  }
});
