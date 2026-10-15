// The compile stage through its process door: a run folder holding a house
// Markdown scene file, and assertions on the machine script it writes, the
// `explainers/.gitignore`, its refusals, and the voice stage reading its output.
import { after, test } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { SCRIPT } from "./scene-file.mjs";

const here = path.dirname(fileURLToPath(import.meta.url));
const scripts = path.join(
  here,
  "..",
  "..",
  "skills",
  "explainer-video",
  "scripts",
);

const temps = [];
after(() =>
  temps.forEach((t) => fs.rmSync(t, { recursive: true, force: true })),
);

function fixture(text = SCRIPT) {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "explainer-compile-"));
  temps.push(tmp);
  const dir = path.join(tmp, "explainers", "demo");
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(path.join(dir, "script.md"), text);
  return { tmp, dir, log: path.join(tmp, "calls.jsonl") };
}

function run(fx, stage = "script/compile.mjs") {
  const r = spawnSync(process.execPath, [path.join(scripts, stage), fx.dir], {
    env: {
      PATH: process.env.PATH,
      HOME: path.join(fx.tmp, "home"),
      XDG_CACHE_HOME: path.join(fx.tmp, "cache"),
      EXPLAINER_VIDEO_BACKEND: path.join(here, "fake-backend.mjs"),
      EXPLAINER_VIDEO_FAKE_LOG: fx.log,
    },
    encoding: "utf8",
  });
  return { code: r.status, out: r.stdout, err: r.stderr };
}

const compiled = (fx) =>
  JSON.parse(fs.readFileSync(path.join(fx.dir, "script.json"), "utf8"));

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
    "*/snapshots/",
    "*/.cache/",
    "*/composition/",
    "*/out/",
  ])
    assert.ok(ignore.split("\n").includes(entry), entry);
  assert.ok(!/script\.md|style\.json|manifest\.json/.test(ignore));
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
