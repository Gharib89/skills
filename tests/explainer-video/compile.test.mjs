// The compile stage through its process door: a run folder holding a house
// Markdown scene file, and assertions on the machine script it writes, the
// `explainers/.gitignore`, its refusals, and the voice stage reading its output.
// Part 2, compile-cues.test.mjs, holds the cue, emphasis and prop refusals.
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { compiled, fixture, run } from "./compile-lib.mjs";
import { ARABIC, DIAGRAMS, SCRIPT } from "./scene-file.mjs";
test("a scene file compiles to the machine script: header, scenes, spoken narration, written captions, cites and visuals", () => {
  const fx = fixture();
  const r = run(fx);
  assert.equal(r.code, 0, r.out + r.err);
  assert.equal(r.out.trim(), "compile: 3 scene(s) -> script.json");
  const s = compiled(fx);
  assert.equal(s.title, "How Ship lands a pull request");
  assert.equal(s.language, "en");
  assert.equal(s.narrator, "am_fenrir");
  assert.equal(s.style, "claude-code");
  assert.deepEqual(
    s.scenes.map((x) => [x.id, x.title]),
    [
      ["hook", "The promise"],
      ["steps", "The steps"],
      ["gate", "The gate"],
    ],
  );
  const hook = s.scenes[0];
  assert.deepEqual(hook.narration, [
    "Ship drives issue six two six to a merged pull request.",
    "Here is how.",
  ]);
  assert.deepEqual(hook.captions[0], [
    { text: "Ship", words: 1 },
    { text: "drives", words: 1 },
    { text: "#626", words: 4 },
    { text: "to", words: 1 },
    { text: "a", words: 1 },
    { text: "merged", words: 1 },
    { text: "pull", words: 1 },
    { text: "request.", words: 1 },
  ]);
  assert.deepEqual(hook.cites, [["ex-3", "ex-4"], []]);
  assert.deepEqual(hook.visual, {
    component: "title",
    props: {
      kicker: "Ship",
      title: "Issue to pull request",
      subtitle: "One run, one merge",
    },
  });
  assert.equal(s.scenes[1].visual.props.items[1].note, "failing");
  for (const scene of s.scenes)
    scene.narration.forEach((sentence, i) =>
      assert.equal(
        scene.captions[i].reduce((n, t) => n + t.words, 0),
        sentence.split(/\s+/).length,
        `${scene.id} sentence ${i + 1}`,
      ),
    );
});

test("language defaults to en and narrator and style stay unset when the header omits them", () => {
  const fx = fixture(
    SCRIPT.replace(
      /^language: en\nnarrator: am_fenrir\nstyle: claude-code\n/m,
      "",
    ),
  );
  assert.equal(run(fx).code, 0);
  const s = compiled(fx);
  assert.equal(s.language, "en");
  assert.ok(!("narrator" in s) && !("style" in s));
});

test("compile writes explainers/.gitignore so compiled files, caches and output stay out of git", () => {
  const fx = fixture();
  assert.equal(run(fx).code, 0);
  const ignore = fs.readFileSync(
    path.join(fx.tmp, "explainers", ".gitignore"),
    "utf8",
  );
  for (const entry of [
    "*/script.json",
    "*/timeline.json",
    "*/gates.json",
    "*/score.json",
    "*/check.json",
    "*/support.json",
    "*/stills.json",
    "*/board/",
    "*/storyboard.html",
    "*/snapshots/",
    "*/.cache/",
    "*/composition/",
    "*/out/",
  ])
    assert.ok(ignore.split("\n").includes(entry), entry);
  assert.ok(!/brief\.json|script\.md|style\.json|manifest\.json/.test(ignore));
});

test("compile keeps the user's own ignore lines and writes its block once", () => {
  const fx = fixture();
  const file = path.join(fx.tmp, "explainers", ".gitignore");
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, "drafts/\n");
  assert.equal(run(fx).code, 0);
  fs.appendFileSync(file, "*.tmp\n");
  assert.equal(run(fx).code, 0);
  const lines = fs.readFileSync(file, "utf8").split("\n");
  assert.ok(lines.includes("drafts/") && lines.includes("*.tmp"));
  assert.equal(lines.filter((l) => l === "*/out/").length, 1);
});

test("the voice stage voices a compiled script unchanged", () => {
  const fx = fixture();
  assert.equal(run(fx).code, 0);
  const r = run(fx, "voice/voice.mjs");
  assert.equal(r.code, 0, r.out + r.err);
  const voiced = JSON.parse(
    fs.readFileSync(path.join(fx.dir, "voice.json"), "utf8"),
  );
  assert.equal(voiced.narrator, "am_fenrir");
  assert.deepEqual(
    voiced.scenes.map((x) => x.id),
    ["hook", "steps", "gate"],
  );
  assert.equal(voiced.scenes[0].words[2].text, "issue");
});

test("an indented line continues the sentence above, cites and all", () => {
  const fx = fixture(
    SCRIPT.replace(
      "1. It reads the issue. [ex-1]",
      "1. It reads\n   the issue. [ex-1]",
    ),
  );
  const r = run(fx);
  assert.equal(r.code, 0, r.out + r.err);
  const steps = compiled(fx).scenes[1];
  assert.equal(steps.narration[0], "It reads the issue.");
  assert.deepEqual(steps.cites[0], ["ex-1"]);
});

for (const [name, from, to, why] of [
  [
    "an unknown header key",
    "narrator: am_fenrir",
    "narator: am_fenrir",
    /^compile: unknown header key narator \(language, narrator, style\)/m,
  ],
  [
    "a header key in the wrong case",
    "narrator: am_fenrir",
    "Narrator: am_fenrir",
    /^compile: unknown header key Narrator/m,
  ],
  [
    "a line continuing a sentence past its cites",
    "1. It reads the issue. [ex-1]",
    "1. It reads the issue. [ex-1]\n   More words.",
    /^compile: steps: More words\. continues a sentence past its cites/m,
  ],
  [
    "an indented numbered line",
    "2. It writes a failing test. [ex-2]",
    "   2. It writes a failing test. [ex-2]",
    /^compile: steps: not a numbered sentence: +2\. It writes/m,
  ],
  [
    "a sentence with no cites and no [no-claim]",
    "2. Here is how. [no-claim]",
    "2. Here is how.",
    /^compile: hook: Here is how\. ends in no \[<cites>\] or \[no-claim\]/m,
  ],
  [
    "a written token longer than a caption",
    "2. Here is how. [no-claim]",
    `2. Here is {${"x".repeat(85)}|how}. [no-claim]`,
    /^compile: hook: x{85}\. is longer than a caption's 84 characters/m,
  ],
  [
    "a visual that is not an object",
    '{ "component": "title", "props": { "kicker": "Ship", "title": "Issue to pull request", "subtitle": "One run, one merge" } }',
    "null",
    /^compile: hook: visual is not a JSON object/m,
  ],
  [
    "a cards item that is not an object",
    '{ "at": 3, "label": "Then", "value": "code" }',
    "null",
    /^compile: steps: a cards item is not a JSON object/m,
  ],
  [
    "a heading that is not a scene",
    "## Scene gate · The gate",
    "## Gate",
    /^compile: not a scene heading: ## Gate/m,
  ],
  [
    "a scene id used twice",
    "## Scene gate · The gate",
    "## Scene hook · The gate",
    /^compile: hook: scene id used twice/m,
  ],
  [
    "the reserved scene id main",
    "## Scene hook · The promise",
    "## Scene main · The promise",
    /^compile: main: scene id main is reserved/m,
  ],
  [
    "a narration line that is neither numbered nor indented",
    "1. It reads the issue. [ex-1]",
    "1. It reads\nthe issue. [ex-1]",
    /^compile: steps: not a numbered sentence: the issue\. \[ex-1\]/m,
  ],
  [
    "a token with no spoken form",
    "2. Here is how. [no-claim]",
    "2. Here is {how.|} [no-claim]",
    /^compile: hook: \{how\.\|\} has no spoken form/m,
  ],
  [
    "a second visual block",
    '"gh pr create" } ] } }\n```\n',
    '"gh pr create" } ] } }\n```\n```json\n{ "component": "title", "props": { "title": "x" } }\n```\n',
    /^compile: gate: a second ```json visual block/m,
  ],
  [
    "a visual block never closed",
    '"gh pr create" } ] } }\n```\n',
    '"gh pr create" } ] } }\n',
    /^compile: gate: the ```json visual block is never closed/m,
  ],
  [
    "an unknown component",
    '"component": "cards"',
    '"component": "chart"',
    /^compile: steps: unknown component chart/m,
  ],
  [
    "a visual that is not JSON",
    '"component": "cards",',
    '"component": "cards"',
    /^compile: steps: visual is not JSON/m,
  ],
  [
    "an `at` past the last sentence",
    '{ "at": 3, "label": "Then"',
    '{ "at": 4, "label": "Then"',
    /^compile: steps: at 4 is not a sentence \(1 to 3\)/m,
  ],
  [
    "a scene with no narration",
    "1. It reads the issue. [ex-1]\n2. It writes a failing test. [ex-2]\n3. Then the code makes it pass. [ex-5]\n",
    "",
    /^compile: steps: no narration/m,
  ],
]) {
  test(`compile refuses ${name}, naming what to fix, and writes no script`, () => {
    assert.ok(SCRIPT.includes(from), from);
    const fx = fixture(SCRIPT.replace(from, to));
    const r = run(fx);
    assert.equal(r.code, 1, r.out + r.err);
    assert.match(r.err, why);
    assert.ok(!fs.existsSync(path.join(fx.dir, "script.json")));
  });
}

test("the diagram and code components compile with their props", () => {
  const fx = fixture(DIAGRAMS);
  const r = run(fx);
  assert.equal(r.code, 0, r.out + r.err);
  assert.deepEqual(
    compiled(fx).scenes.map((s) => s.visual.component),
    ["flow", "panels", "list", "code", "codediff"],
  );
});

for (const [name, from, to, why] of [
  [
    "a flow of one step",
    ', { "at": 2, "label": "Test", "note": "red" }, { "at": 3, "label": "Code", "note": "green" }',
    "",
    /^compile: flow: flow needs 2 to 5 steps/m,
  ],
  [
    "a flow step with no label",
    '"label": "Issue"',
    '"name": "Issue"',
    /^compile: flow: flow needs a label per step/m,
  ],
  [
    "a panel with no body",
    '"body": "Untouched until the merge"',
    '"text": "Untouched"',
    /^compile: sides: panels needs a body per item/m,
  ],
  [
    "a list item at a sentence past the last",
    '{ "at": 2, "text": "Run every test" }',
    '{ "at": 3, "text": "Run every test" }',
    /^compile: gates: at 3 is not a sentence \(1 to 2\)/m,
  ],
  [
    "code with no language",
    '"lang": "bash", ',
    "",
    /^compile: code: code needs a lang/m,
  ],
  [
    "code longer than the frame",
    '"code": "set -euo pipefail\\nscripts/check.sh full"',
    `"code": "${"x\\n".repeat(12)}x"`,
    /^compile: code: code runs 13 lines; a frame holds 12/m,
  ],
  [
    "an emphasis past the code's last line",
    '"target": [2, 2]',
    '"target": [2, 3]',
    /^compile: code: code emphasis lines 2 to 3 are not lines of the code \(1 to 2\)/m,
  ],
  [
    "highlights on code, which emphasis replaces",
    '"emphasis": { "target": [2, 2], "at": 2 }',
    '"highlights": [ { "at": 2, "lines": [2, 2] } ]',
    /^compile: code: code has no prop highlights: emphasis replaces it, as \{ "target": \[first, last\], "at": n \}/m,
  ],
  [
    "a diff with no after",
    '"after": ',
    '"later": ',
    /^compile: diff: codediff needs an after/m,
  ],
]) {
  test(`compile refuses ${name}, naming what to fix`, () => {
    assert.ok(DIAGRAMS.includes(from), from);
    const fx = fixture(DIAGRAMS.replace(from, to));
    const r = run(fx);
    assert.equal(r.code, 1, r.out + r.err);
    assert.match(r.err, why);
  });
}

test("a scene's role line gives its role and seconds, and a malformed one is refused", () => {
  let fx = fixture(
    SCRIPT.replace("target: about fifteen seconds", "role: hook · 15 s"),
  );
  assert.equal(run(fx).code, 0);
  const [hook, steps] = compiled(fx).scenes;
  assert.deepEqual([hook.role, hook.seconds], ["hook", 15]);
  assert.ok(!("role" in steps) && !("seconds" in steps));
  for (const bad of ["role: intro · 15 s", "role: hook", "role: hook · fast"]) {
    fx = fixture(SCRIPT.replace("target: about fifteen seconds", bad));
    const r = run(fx);
    assert.equal(r.code, 1, bad);
    assert.match(
      r.err,
      /^compile: hook: role: .* is not <hook\|context\|point\|recap\|end> · <n> s$/m,
      bad,
    );
  }
});

test("an Arabic scene file keeps each multi-word English term one caption token and lists its kept terms", () => {
  const fx = fixture(ARABIC);
  const r = run(fx);
  assert.equal(r.code, 0, r.out + r.err);
  const s = compiled(fx);
  assert.equal(s.language, "ar");
  const [hook] = s.scenes;
  assert.deepEqual(
    hook.captions[0].find((t) => t.text.startsWith("pull")),
    { text: "pull request", words: 2 },
  );
  assert.equal(
    hook.captions[0].reduce((n, t) => n + t.words, 0),
    hook.narration[0].split(" ").length,
  );
  // The code frame's `scripts/local-gate.sh` and `gh pr create` are code.
  assert.deepEqual(s.kept, [
    "Ship",
    "issue",
    "pull request",
    "merge",
    "branch",
    "CI",
    "review",
  ]);
});

test("an English term written after an Arabic prefix is still one caption token and one kept term", () => {
  const fx = fixture(
    ARABIC.replace("خلينا نشوف إزاي.", "خلينا نشوف الـ branch وpull request."),
  );
  const r = run(fx);
  assert.equal(r.code, 0, r.out + r.err);
  const s = compiled(fx);
  assert.deepEqual(
    s.scenes[0].captions[1].find((t) => t.text.includes("pull")),
    { text: "وpull request.", words: 2 },
  );
  assert.ok(!s.kept.includes("pull") && !s.kept.includes("request"), s.kept);
});

test("an English scene file lists no kept terms and captions each Latin word alone", () => {
  const fx = fixture();
  assert.equal(run(fx).code, 0);
  const s = compiled(fx);
  assert.ok(!("kept" in s));
  assert.ok(s.scenes[0].captions[0].some((t) => t.text === "pull"));
});
