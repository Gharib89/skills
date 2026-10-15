// The script gates through their process door: a run folder holding a brief,
// a source pack, a compiled scene file and the support checker's verdicts,
// and assertions on the one line per gate, the summary, the exit code and the
// fix attempts the support gate counts in check.json.
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

const VOCAB =
  "ship reads the issue then writes a failing test and the code that makes it pass before review".split(
    " ",
  );
// A sentence of n spoken words ending in its cites.
const say = (n, cites = "[ex-1]") =>
  `${Array.from({ length: n }, (_, i) => VOCAB[i % VOCAB.length]).join(" ")}. ${cites}`;

const TITLE = { component: "title", props: { title: "The local gate" } };

// bf_emma speaks 3.12 words a second, so a 12 s scene budgets 37 words and a
// one-minute brief five such scenes.
const SCENES = [
  { id: "hook", role: "hook" },
  { id: "why", role: "context" },
  { id: "steps", role: "point" },
  { id: "recap", role: "recap" },
  { id: "bye", role: "end" },
].map((s) => ({
  ...s,
  seconds: 12,
  sentences: [say(13), say(12, "[no-claim]"), say(12, "[ex-2, ex-3]")],
  visual: TITLE,
}));

function sceneFile(scenes) {
  return [
    "# How Ship lands a pull request",
    "",
    ...scenes.flatMap((s) => [
      `## Scene ${s.id} · ${s.id}`,
      ...(s.role ? [`role: ${s.role} · ${s.seconds} s`] : []),
      "",
      "### Narration",
      ...s.sentences.map((x, i) => `${i + 1}. ${x}`),
      "",
      "### Visual",
      "```json",
      JSON.stringify(s.visual),
      "```",
      "",
    ]),
  ].join("\n");
}

const DOC =
  "# Ship\n\nShip reads the issue.\n\n## Gate\n\nThe local gate runs every check.\n";

function node(fx, stage, args = []) {
  const r = spawnSync(
    process.execPath,
    [path.join(scripts, stage), fx.dir, ...args],
    {
      env: {
        PATH: process.env.PATH,
        HOME: path.join(fx.tmp, "home"),
        XDG_CONFIG_HOME: path.join(fx.tmp, "config"),
      },
      encoding: "utf8",
    },
  );
  return { code: r.status, out: r.stdout, err: r.stderr };
}

// Every sentence of the compiled script judged as its mark says, unless
// `verdicts` overrides one by `<scene> <n>`.
function judge(fx, verdicts = {}) {
  const s = JSON.parse(
    fs.readFileSync(path.join(fx.dir, "script.json"), "utf8"),
  );
  const sentences = s.scenes.flatMap((sc) =>
    sc.narration.map((text, i) => ({
      scene: sc.id,
      n: i + 1,
      text,
      cites: sc.cites[i],
      verdict:
        verdicts[`${sc.id} ${i + 1}`] ??
        (sc.cites[i].length ? "supported" : "connective"),
      why: "fixture",
    })),
  );
  fs.writeFileSync(
    path.join(fx.dir, "support.json"),
    JSON.stringify({ sentences }),
  );
}

function fixture({
  scenes = SCENES,
  brief = ["length=1", "must=local gate", "avoid=pricing"],
  md,
} = {}) {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "explainer-check-"));
  temps.push(tmp);
  const dir = path.join(tmp, "explainers", "demo");
  fs.mkdirSync(path.join(dir, "snapshots"), { recursive: true });
  const fx = { tmp, dir };
  assert.equal(node(fx, "brief/brief.mjs", brief).code, 0);
  fs.writeFileSync(path.join(dir, "snapshots", "doc.md"), DOC);
  fs.writeFileSync(
    path.join(dir, "snapshots", "sources.json"),
    JSON.stringify({
      minutes: 1,
      budget: 12,
      sources: [
        {
          id: "doc",
          kind: "md",
          source: "doc.md",
          title: "Ship",
          snapshot: "doc.md",
          share: 12,
        },
      ],
    }),
  );
  const ex = (id, locator, text) => ({
    id,
    source: "doc",
    locator,
    text,
    note: "n",
  });
  fs.writeFileSync(
    path.join(dir, "excerpts.json"),
    JSON.stringify({
      minutes: 1,
      budget: 12,
      sources: [],
      excerpts: [
        ex("ex-1", "§ Ship", "Ship reads the issue."),
        ex("ex-2", "§ Gate", "The local gate runs every check."),
        ex("ex-3", "line 3", "Ship reads the issue."),
      ],
    }),
  );
  fs.writeFileSync(path.join(dir, "script.md"), md ?? sceneFile(scenes));
  const c = node(fx, "script/compile.mjs");
  assert.equal(c.code, 0, c.err);
  judge(fx);
  return fx;
}

const check = (fx) => node(fx, "script/check.mjs");
const line = (r, name) =>
  r.out.split("\n").find((l) => l.startsWith(`script ${name}:`));
const edit = (scenes, i, patch) =>
  scenes.map((s, k) => (k === i ? { ...s, ...patch } : s));

test("a script meeting every gate passes each one and writes check.json", () => {
  const fx = fixture();
  const r = check(fx);
  assert.equal(r.code, 0, r.out + r.err);
  assert.deepEqual(r.out.trim().split("\n"), [
    "script arc: pass",
    "script budget: pass",
    "script cites: pass",
    "script support: pass",
    "script coverage: pass",
    "script reading: pass",
    "script dashes: pass",
    "script sentences: pass",
    "script: 8 pass, 0 fail, 0 warn",
  ]);
  const rec = JSON.parse(
    fs.readFileSync(path.join(fx.dir, "check.json"), "utf8"),
  );
  assert.equal(rec.checks.arc.status, "pass");
  assert.equal(rec.support.attempts, 0);
});

test("the arc wants hook, context, one or more points, recap, end, each scene with a role", () => {
  let r = check(fixture({ scenes: edit(SCENES, 3, { role: "point" }) }));
  assert.equal(r.code, 1);
  assert.equal(
    line(r, "arc"),
    "script arc: fail: roles hook, context, point, point, end; want hook, context, point..., recap, end",
  );
  r = check(fixture({ scenes: edit(SCENES, 1, { role: undefined }) }));
  assert.match(line(r, "arc"), /^script arc: fail: why has no role line/);
  assert.match(r.out, /^script: \d+ pass, \d+ fail, 0 warn$/m);
});

test("a scene runs 12 to 30 s, its words within 10 percent of its seconds at the narrator's rate, and the scenes the brief's length", () => {
  let r = check(fixture({ scenes: edit(SCENES, 0, { seconds: 31 }) }));
  assert.equal(r.code, 1);
  assert.match(line(r, "budget"), /hook 31 s is outside 12 to 30 s/);
  assert.match(
    line(r, "budget"),
    /hook 37 words vs 97 \(31 s at 3\.12\/s\) ±10%/,
  );
  r = check(
    fixture({
      scenes: edit(SCENES, 2, { sentences: [say(13), say(12, "[no-claim]")] }),
    }),
  );
  assert.equal(
    line(r, "budget"),
    "script budget: fail: steps 25 words vs 37 (12 s at 3.12/s) ±10%",
  );
  r = check(fixture({ scenes: edit(SCENES, 0, { seconds: 0 }) }));
  assert.match(line(r, "budget"), /hook 0 s is outside 12 to 30 s/);
  r = check(fixture({ brief: ["length=2", "must=local gate"] }));
  assert.equal(
    line(r, "budget"),
    "script budget: fail: the scenes run 60 s vs the brief's 120 s ±10%",
  );
});

test("every cite names an excerpt still word for word in its snapshot", () => {
  let fx = fixture({
    scenes: edit(SCENES, 1, {
      sentences: [say(13, "[ex-9]"), say(12), say(12)],
    }),
  });
  let r = check(fx);
  assert.equal(r.code, 1);
  assert.equal(
    line(r, "cites"),
    "script cites: fail: why 1: ex-9 is not in excerpts.json",
  );

  fx = fixture();
  fs.writeFileSync(
    path.join(fx.dir, "snapshots", "doc.md"),
    DOC.replace("every check", "some checks"),
  );
  r = check(fx);
  assert.match(
    line(r, "cites"),
    /^script cites: fail: .*ex-2 is no longer word for word in § Gate/,
  );

  // A locator the snapshot no longer holds says so.
  fx = fixture();
  const file = path.join(fx.dir, "excerpts.json");
  const pack = JSON.parse(fs.readFileSync(file, "utf8"));
  pack.excerpts[1].locator = "§ Nope";
  fs.writeFileSync(file, JSON.stringify(pack));
  r = check(fx);
  assert.match(line(r, "cites"), /ex-2: § Nope: no section "Nope"/);

  // With no snapshot the pack's own check stands.
  fx = fixture();
  fs.rmSync(path.join(fx.dir, "snapshots"), { recursive: true });
  assert.equal(line(check(fx), "cites"), "script cites: pass");
});

test("support blocks an unsupported claim, counts two fix attempts, then stops", () => {
  const fx = fixture();
  fs.rmSync(path.join(fx.dir, "support.json"));
  let r = check(fx);
  assert.equal(r.code, 1);
  assert.match(
    line(r, "support"),
    /^script support: fail: no support\.json: run the support check$/,
  );
  assert.match(r.out, /^script: 7 pass, 1 fail, 0 warn$/m);

  judge(fx, { "steps 1": "unsupported" });
  r = check(fx);
  assert.equal(
    line(r, "support"),
    "script support: fail: steps 1 unsupported: fixture",
  );
  assert.match(
    r.out,
    /^script: 7 pass, 1 fail, 0 warn; next: fix attempt 1 of 2$/m,
  );
  // The same verdicts judged again are not another attempt.
  r = check(fx);
  assert.match(r.out, /; next: fix attempt 1 of 2$/m);

  judge(fx, { "steps 2": "unmarked" });
  assert.match(check(fx).out, /; next: fix attempt 2 of 2$/m);
  judge(fx, { "hook 1": "unsupported" });
  r = check(fx);
  assert.equal(r.code, 1);
  assert.match(r.out, /; stop: unsupported claims after two fix attempts$/m);

  // A third rewrite brings no third attempt: the stop holds until it passes.
  judge(fx, { "why 1": "unsupported" });
  assert.match(
    check(fx).out,
    /; stop: unsupported claims after two fix attempts$/m,
  );

  judge(fx);
  r = check(fx);
  assert.equal(r.code, 0, r.out);
  const rec = JSON.parse(
    fs.readFileSync(path.join(fx.dir, "check.json"), "utf8"),
  );
  assert.equal(rec.support.attempts, 0);
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
        sentences: [say(26), say(5, "[no-claim]"), say(6)],
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
