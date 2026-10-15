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

const SCRIPT = `# How Ship lands a pull request
language: en
narrator: am_fenrir
style: claude-code

## Scene hook · The promise
target: about fifteen seconds

### Narration
1. Ship drives {#626|issue six two six} to a \`merged\` pull request. [ex-3, ex-4]
2. Here is how. [no-claim]

### Visual
\`\`\`json
{ "component": "title", "props": { "kicker": "Ship", "title": "Issue to pull request", "subtitle": "One run, one merge" } }
\`\`\`

## Scene steps · The steps

### Narration
1. It reads the issue. [ex-1]
2. It writes a failing test. [ex-2]
3. Then the code makes it pass. [ex-5]

### Visual
\`\`\`json
{
  "component": "cards",
  "props": {
    "items": [
      { "at": 1, "label": "Input", "value": "issue" },
      { "at": 2, "label": "First", "value": "test", "note": "failing" },
      { "at": 3, "label": "Then", "value": "code" }
    ]
  }
}
\`\`\`

## Scene gate · The gate

### Narration
1. The local gate runs every check. [ex-6]
2. Then it opens the pull request. [ex-7]

### Visual
\`\`\`json
{ "component": "terminal", "props": { "title": "scripts/local-gate.sh", "lines": [ { "at": 1, "text": "$ scripts/local-gate.sh" }, { "at": 2, "text": "gh pr create" } ] } }
\`\`\`
`;

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

for (const [name, from, to, why] of [
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
  test(`compile refuses ${name}, naming the scene, and writes no script`, () => {
    assert.ok(SCRIPT.includes(from), from);
    const fx = fixture(SCRIPT.replace(from, to));
    const r = run(fx);
    assert.equal(r.code, 1, r.out + r.err);
    assert.match(r.err, why);
    assert.ok(!fs.existsSync(path.join(fx.dir, "script.json")));
  });
}
