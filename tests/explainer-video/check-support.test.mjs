// The script check stage through its process door, part 2: kept verdicts, must
// include and avoid items, reading time and style rules.
import { after, test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { sentences } from "../../skills/explainer-video/scripts/lib/length.mjs";
import { VISUALS } from "../../skills/explainer-video/scripts/lib/visuals.mjs";
import {
  SCENES,
  check,
  edit,
  fixture,
  judge,
  line,
  reword,
  say,
  sceneFile,
} from "./check-lib.mjs";

// #725: a recap sentence passed one support check and failed the next with its
// words and cites unchanged, and the fail counted as a fix attempt.
test("a sentence whose words, cites and cited excerpts are unchanged keeps its earlier verdict, and a different one is drift", () => {
  const fx = fixture();
  assert.equal(check(fx).code, 0);
  judge(fx, { "recap 1": "unsupported" });
  let r = check(fx);
  assert.equal(r.code, 0, r.out);
  assert.equal(
    line(r, "support"),
    "script support: warn: recap 1 drift: judged unsupported on unchanged words, kept supported",
  );
  assert.match(r.out, /^script: 7 pass, 0 fail, 1 warn$/m);

  // A kept failure stays one fix attempt, however the next check judges it.
  reword(fx, "steps 1");
  judge(fx, { "steps 1": "unsupported" });
  assert.match(check(fx).out, /; next: fix attempt 1 of 2$/m);
  judge(fx);
  r = check(fx);
  assert.equal(
    line(r, "support"),
    "script support: fail: steps 1 unsupported: fixture; steps 1 drift: judged supported on unchanged words, kept unsupported",
  );
  assert.match(r.out, /; next: fix attempt 1 of 2$/m);

  // New words behind a cited excerpt are a new sentence to judge.
  const file = path.join(fx.dir, "excerpts.json");
  const pack = JSON.parse(fs.readFileSync(file, "utf8"));
  pack.excerpts[0].text = "Ship reads";
  fs.writeFileSync(file, JSON.stringify(pack));
  judge(fx);
  assert.equal(line(check(fx), "support"), "script support: pass");
});

test("a verdict for another wording of the sentence is not a verdict for this one", () => {
  const fx = fixture();
  const file = path.join(fx.dir, "support.json");
  const s = JSON.parse(fs.readFileSync(file, "utf8"));
  s.sentences[0].text = "an older wording.";
  fs.writeFileSync(file, JSON.stringify(s));
  const r = check(fx);
  assert.equal(
    line(r, "support"),
    "script support: fail: hook 1 not judged: run the support check",
  );
  assert.doesNotMatch(r.out, /attempt/);
});

test("the stop holds while support.json is missing or older than the pack", () => {
  const fx = fixture();
  for (const k of ["hook 1", "steps 1", "steps 2"]) {
    reword(fx, k);
    judge(fx, { [k]: "unsupported" });
    check(fx);
  }
  const stop = /; stop: unsupported claims after two fix attempts$/m;
  fs.rmSync(path.join(fx.dir, "support.json"));
  check(fx);
  judge(fx, { "why 1": "unsupported" });
  assert.match(check(fx).out, stop);

  const later = new Date(Date.now() + 60_000);
  fs.utimesSync(path.join(fx.dir, "excerpts.json"), later, later);
  check(fx);
  judge(fx, { "hook 1": "unsupported" });
  fs.utimesSync(path.join(fx.dir, "support.json"), later, later);
  assert.match(check(fx).out, stop);
});

test("a fix that changes only a sentence's cites is a fix attempt", () => {
  const fx = fixture();
  judge(fx, { "steps 1": "unsupported" });
  assert.match(check(fx).out, /; next: fix attempt 1 of 2$/m);
  const file = path.join(fx.dir, "script.json");
  const s = JSON.parse(fs.readFileSync(file, "utf8"));
  s.scenes.find((sc) => sc.id === "steps").cites[0] = ["ex-3"];
  fs.writeFileSync(file, JSON.stringify(s));
  judge(fx, { "steps 1": "unsupported" });
  assert.match(check(fx).out, /; next: fix attempt 2 of 2$/m);
});

test("a verdict on other cites, or older than the source pack, is not a verdict", () => {
  const fx = fixture();
  const file = path.join(fx.dir, "support.json");
  const s = JSON.parse(fs.readFileSync(file, "utf8"));
  s.sentences[0].cites = ["ex-2"];
  fs.writeFileSync(file, JSON.stringify(s));
  assert.equal(
    line(check(fx), "support"),
    "script support: fail: hook 1 not judged: run the support check",
  );

  judge(fx);
  const later = new Date(Date.now() + 60_000);
  fs.utimesSync(path.join(fx.dir, "excerpts.json"), later, later);
  assert.equal(
    line(check(fx), "support"),
    "script support: fail: support.json predates excerpts.json: run the support check",
  );
});

test("every must-include item is said or shown and no avoid item is", () => {
  let r = check(
    fixture({ brief: ["length=1", "must=local gate", "must=Codex"] }),
  );
  assert.equal(
    line(r, "coverage"),
    'script coverage: fail: must "Codex" is not said or shown',
  );
  r = check(fixture({ brief: ["length=1", "avoid=FAILING test"] }));
  assert.match(
    line(r, "coverage"),
    /^script coverage: fail: avoid "FAILING test" is in hook/,
  );
  // Whole words only: "ai" inside "failing" and "read" inside "reads" match
  // nothing.
  r = check(fixture({ brief: ["length=1", "must=read", "avoid=ai"] }));
  assert.equal(
    line(r, "coverage"),
    'script coverage: fail: must "read" is not said or shown',
  );
});

test("a visual item stays on screen long enough to read: 0.8 s a label, 0.3 s a word and 1.2 s at least for longer text", () => {
  const cards = {
    component: "cards",
    props: {
      items: [
        { at: 1, label: "Input", value: "issue" },
        {
          at: 3,
          label: "Then",
          value: "the code that makes the failing test pass",
        },
      ],
    },
  };
  const r = check(
    fixture({
      scenes: edit(SCENES, 2, {
        sentences: [say(17), say(18, "[no-claim]"), say(2)],
        visual: cards,
      }),
    }),
  );
  assert.equal(r.code, 1);
  assert.equal(
    line(r, "reading"),
    "script reading: fail: steps item 2: 0.6 s on screen vs 3.2 s to read",
  );
});

test("an item cued on a phrase is on screen from that phrase, not from its sentence", () => {
  const steps = (on) => ({
    component: "cards",
    props: {
      items: [
        { at: 1, label: "Input", value: "issue" },
        {
          at: 2,
          label: "Then",
          value: "the code that makes the failing test pass",
          ...(on && { on }),
        },
      ],
    },
  });
  const run = (on) =>
    check(
      fixture({
        scenes: edit(SCENES, 2, {
          sentences: [say(17), say(18, "[no-claim]"), say(2)],
          visual: steps(on),
        }),
      }),
    );
  assert.equal(line(run(), "reading"), "script reading: pass");
  // `review` is the sentence's 18th and last word: 3 of 37 words remain.
  assert.equal(
    line(run("review"), "reading"),
    "script reading: fail: steps item 2: 1.0 s on screen vs 3.2 s to read",
  );
});

test("a code diff's reader reads the lines the render adds, a moved line among them", () => {
  const [, [, at, added]] = VISUALS.codediff.items({
    lang: "js",
    before: "one();\ntwo();",
    after: "two();\none();",
    at: 2,
  });
  assert.equal(at, 2);
  assert.deepEqual(added, ["two();"]);
});

test("an em or en dash anywhere in the scene file fails, and a sentence over 25 words warns", () => {
  const md = sceneFile(SCENES).replace(
    "# How Ship lands",
    `# How Ship ${String.fromCharCode(0x2014)} lands`,
  );
  let r = check(fixture({ md }));
  assert.equal(r.code, 1);
  assert.equal(line(r, "dashes"), "script dashes: fail: line 1 has an em dash");
  r = check(
    fixture({
      md: sceneFile(SCENES).replace(
        "# How Ship lands",
        `# How Ship ${String.fromCharCode(0x2013)} lands`,
      ),
    }),
  );
  assert.equal(line(r, "dashes"), "script dashes: fail: line 1 has an en dash");

  r = check(
    fixture({
      scenes: edit(SCENES, 0, {
        sentences: [say(26), say(5, "[no-claim]"), say(5)],
      }),
    }),
  );
  assert.equal(r.code, 0, r.out);
  assert.equal(
    line(r, "sentences"),
    "script sentences: warn: hook 1 has 26 words (over 25)",
  );
  assert.match(r.out, /^script: 7 pass, 0 fail, 1 warn$/m);
});

test("a run folder missing what the gates read names the stage to run first", () => {
  for (const [file, why] of [
    ["script.json", /^script: no script\.json: compile first$/m],
    ["brief.json", /^script: no brief\.json: run brief\.mjs first$/m],
    [
      "excerpts.json",
      /^script: no excerpts\.json: run the source stage first$/m,
    ],
  ]) {
    const fx = fixture();
    fs.rmSync(path.join(fx.dir, file));
    const r = check(fx);
    assert.equal(r.code, 1, file);
    assert.match(r.err, why, file);
  }
});
