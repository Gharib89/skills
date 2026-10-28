// The storyboard stage, node board.mjs <run> build|apply: the board document
// and its page from a timed run folder, the stills it takes in one snapshot
// launch, the refusals, what an answers file asks the agent to do, and the
// guard that lets a comment on one scene re-author only that scene.
import { test } from "node:test";
import assert from "node:assert/strict";
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { calls, readJson } from "./timing-lib.mjs";
import { compose, timeline } from "./gates-lib.mjs";
import { cited } from "./support-lib.mjs";
import { sampleTimes } from "../../skills/creative-video/scripts/gates/samples.mjs";
import {
  answersText,
  apply,
  boardDir,
  build,
  built,
  ok,
  ready,
  storyboard,
  writeStoryboard,
} from "./board-lib.mjs";

const mmss = (s) =>
  `${Math.floor(Math.round(s) / 60)}:${String(Math.round(s) % 60).padStart(2, "0")}`;
const sha16 = (f) =>
  crypto
    .createHash("sha256")
    .update(fs.readFileSync(f))
    .digest("hex")
    .slice(0, 16);
const snapshots = (fx) => calls(fx).filter((c) => c.call === "snapshot");

test("build writes board 1: one chapter, one plan row, every scene's three stills, the directions and the notes", () => {
  const fx = ready();
  const r = build(fx);
  ok(r);
  const tl = timeline(fx);
  const doc = built(fx);
  assert.equal(doc.version, 1);
  assert.equal(doc.title, "Why agentic engineering");
  assert.equal(doc.language, "en");
  assert.deepEqual(doc.chapters, [
    { n: 1, title: "Why agentic engineering", status: "awaiting" },
  ]);
  assert.deepEqual(doc.plan, [
    {
      chapter: 1,
      title: "Why agentic engineering",
      length: mmss(tl.total),
      focus: "what an agent loop is",
      sources: [],
      status: "awaiting",
    },
  ]);
  assert.equal(doc.length, mmss(tl.total));
  assert.deepEqual(
    doc.scenes.map((s) => s.id),
    tl.scenes.map((s) => s.id),
  );
  const script = readJson(path.join(fx.dir, "script.json"));
  for (const [i, sc] of tl.scenes.entries()) {
    const s = doc.scenes[i];
    assert.equal(s.chapter, 1);
    assert.equal(s.title, `The ${sc.id} scene`);
    assert.equal(s.notes, `${sc.id} notes`);
    assert.equal(s.start, sc.start);
    assert.equal(s.end, sc.start + sc.duration);
    assert.equal(
      s.timecode,
      `${mmss(sc.start)} to ${mmss(sc.start + sc.duration)}`,
    );
    assert.equal(s.narration, script.scenes[i].narration.join(" "));
    assert.equal(s.changed, false);
    assert.match(s.hash, /^[0-9a-f]{16}$/);
    assert.deepEqual(Object.keys(s.stills), ["in", "key", "out"]);
    for (const f of Object.values(s.stills)) {
      const file = path.join(fx.dir, "board", f);
      assert.match(f, /^stills\/[0-9a-f]{16}\.png$/);
      assert.equal(path.basename(f, ".png"), sha16(file), "a content name");
    }
    // The still at each sample is the frame taken there.
    const at = sampleTimes(sc);
    for (const phase of ["in", "key", "out"])
      assert.match(
        fs.readFileSync(path.join(fx.dir, "board", s.stills[phase]), "utf8"),
        new RegExp(`^pixels ${sc.id} ${at[phase]} `),
      );
  }
  assert.deepEqual(
    doc.directions.map((d) => [d.id, d.name, d.kind, d.recommended, d.picked]),
    [
      ["switch", "The Switchboard", "a world", true, true],
      ["kitchen", "The Kitchen", "a format", false, false],
      ["plain", "Drawn Straight", "the subject itself", false, false],
    ],
  );
  // The picked direction is shown by chapter 1's first scene at its key.
  assert.equal(doc.directions[0].frame, doc.scenes[0].stills.key);
  for (const d of doc.directions.slice(1)) {
    assert.match(d.frame, /^stills\/[0-9a-f]{16}\.png$/);
    assert.match(
      fs.readFileSync(path.join(fx.dir, "board", d.frame), "utf8"),
      new RegExp(`^pixels ${d.id} 1 `),
    );
  }
  assert.match(doc.kit, /^[0-9a-f]{16}$/);
  const stills = new Set(
    doc.scenes
      .flatMap((s) => Object.values(s.stills))
      .concat(doc.directions.map((d) => d.frame)),
  );
  assert.equal(
    r.out,
    `board: 1 -> board/storyboard.html (${doc.scenes.length} scenes, ${stills.size} stills, 0 changed)\nboard: files board/files.json\n`,
  );
});

test("one snapshot launch covers every scene, and one more each direction not picked", () => {
  const fx = ready();
  ok(build(fx));
  const shots = snapshots(fx);
  const times = [
    ...new Set(
      timeline(fx).scenes.flatMap((sc) => Object.values(sampleTimes(sc))),
    ),
  ].sort((a, b) => a - b);
  assert.equal(shots.length, 3);
  assert.deepEqual(shots[0].times, times);
  assert.deepEqual(
    shots.slice(1).map((s) => s.times),
    [[1], [1]],
  );
  assert.deepEqual(
    shots.slice(1).map((s) => path.basename(path.dirname(s.outDir))),
    ["kitchen", "plain"],
  );
  // A direction's frame is its own tiny project, its file the one authored.
  for (const id of ["kitchen", "plain"]) {
    const dir = path.join(fx.dir, ".cache", "board", "directions", id);
    assert.equal(
      fs.readFileSync(path.join(dir, "compositions", `${id}.html`), "utf8"),
      fs.readFileSync(path.join(fx.dir, "directions", `${id}.html`), "utf8"),
    );
    const root = fs.readFileSync(path.join(dir, "index.html"), "utf8");
    assert.match(root, new RegExp(`data-composition-id="${id}"`));
    assert.match(root, /data-duration="2"/);
    assert.doesNotMatch(root, /captions|narration|kit\//);
    assert.ok(fs.existsSync(path.join(dir, "assets", "gsap.min.js")));
  }
});

test("a picked direction other than the first is shown by the first scene, and the first one has its own frame", () => {
  const fx = ready({ picked: "kitchen" });
  ok(build(fx));
  const doc = built(fx);
  const kitchen = doc.directions.find((d) => d.id === "kitchen");
  assert.equal(kitchen.picked, true);
  assert.equal(kitchen.frame, doc.scenes[0].stills.key);
  assert.equal(snapshots(fx).length, 3);
  assert.match(
    fs.readFileSync(
      path.join(fx.dir, "board", doc.directions[0].frame),
      "utf8",
    ),
    /^pixels switch 1 /,
  );
});

test("the sources are the titles of the sources the script cites, in first-cited order", () => {
  const fx = ready();
  fs.writeFileSync(
    path.join(fx.dir, "excerpts.json"),
    JSON.stringify({
      sources: [
        { id: "s1", title: "Ship docs" },
        { id: "s2", title: "The loop paper" },
        { id: "s3", title: "Never cited" },
      ],
      excerpts: [
        { id: "ex-1", source: "s1", text: "a" },
        { id: "ex-2", source: "s2", text: "b" },
        { id: "ex-3", source: "s3", text: "c" },
      ],
    }),
  );
  const script = readJson(path.join(fx.dir, "script.json"));
  script.scenes = cited(script.scenes, {
    hook: [["ex-2"]],
    context: [["ex-1"], ["ex-2", "ex-1"]],
  });
  fs.writeFileSync(path.join(fx.dir, "script.json"), JSON.stringify(script));
  ok(build(fx));
  assert.deepEqual(built(fx).plan[0].sources, ["The loop paper", "Ship docs"]);
});

test("the page is the board embedded in storyboard.html beside page.css and page.js, and files.json lists them with every still", () => {
  const fx = ready({
    extra: { title: "Why <agentic> & </script> co" },
  });
  ok(build(fx));
  const out = path.join(fx.dir, "board");
  const html = fs.readFileSync(path.join(out, "storyboard.html"), "utf8");
  assert.match(
    html,
    /<title>Why &lt;agentic&gt; &amp; &lt;\/script&gt; co<\/title>/,
  );
  const m = html.match(
    /<script type="application\/json" id="board">(.*?)<\/script>/s,
  );
  assert.deepEqual(JSON.parse(m[1]), built(fx));
  assert.ok(!m[1].includes("<"), "every < is escaped");
  for (const f of ["page.css", "page.js"]) {
    assert.equal(
      fs.readFileSync(path.join(out, f), "utf8"),
      fs.readFileSync(path.join(boardDir, f), "utf8"),
    );
    assert.ok(html.includes(`"${f}"`), `${f} is linked`);
  }
  const files = JSON.parse(
    fs.readFileSync(path.join(out, "files.json"), "utf8"),
  );
  const doc = built(fx);
  const stills = [
    ...new Set(
      doc.scenes
        .flatMap((s) => Object.values(s.stills))
        .concat(doc.directions.map((d) => d.frame)),
    ),
  ];
  assert.deepEqual(
    Object.keys(files).sort(),
    ["page.css", "page.js", ...stills].sort(),
  );
  for (const [published, from] of Object.entries(files)) {
    assert.ok(path.isAbsolute(from), published);
    assert.equal(from, path.join(out, published));
    assert.ok(fs.existsSync(from), published);
  }
});

test("board/ is rebuildable, so the run folder's .gitignore keeps it out of git", () => {
  const fx = ready();
  ok(build(fx));
  const ignore = fs.readFileSync(
    path.join(path.dirname(fx.dir), ".gitignore"),
    "utf8",
  );
  assert.match(ignore, /^\*\/board\/$/m);
});

test("build refuses a missing storyboard.json, a scene with no entry, a missing direction file and a bad id", () => {
  let fx = ready();
  fs.rmSync(path.join(fx.dir, "storyboard.json"));
  let r = build(fx);
  assert.equal(r.code, 1);
  assert.match(r.err, /^board: storyboard\.json: is missing$/m);

  fx = ready();
  const doc = storyboard(["hook", "recap"]);
  writeStoryboard(fx, doc);
  r = build(fx);
  assert.equal(r.code, 1);
  assert.match(r.err, /^board: storyboard\.json: no entry for scene context$/m);

  fx = ready();
  fs.rmSync(path.join(fx.dir, "directions", "plain.html"));
  r = build(fx);
  assert.equal(r.code, 1);
  assert.match(
    r.err,
    /^board: directions\/plain\.html is missing: author the frame of the direction not picked$/m,
  );

  fx = ready();
  const bad = storyboard(["hook", "context", "recap"]);
  bad.directions.list[1].id = "The Kitchen";
  writeStoryboard(fx, bad);
  r = build(fx);
  assert.equal(r.code, 1);
  assert.match(r.err, /^board: storyboard\.json: direction id "The Kitchen"/m);
  assert.equal(snapshots(fx).length, 0, "refused before any snapshot");
});

test("build refuses a picked or recommended id the list lacks, and a list that is not three", () => {
  const ids = ["hook", "context", "recap"];
  for (const [mut, why] of [
    [(d) => (d.directions.picked = "nope"), /picked "nope" is not in/],
    [
      (d) => (d.directions.recommended = "nope"),
      /recommended "nope" is not in/,
    ],
    [(d) => d.directions.list.pop(), /three directions/],
    [(d) => (d.focus = 3), /^board: storyboard\.json: focus is not text$/m],
  ]) {
    const fx = ready();
    const doc = storyboard(ids);
    mut(doc);
    writeStoryboard(fx, doc);
    const r = build(fx);
    assert.equal(r.code, 1);
    assert.match(r.err, why);
  }
});

test("build refuses without a timeline, as the gates do", () => {
  const fx = ready();
  fs.rmSync(path.join(fx.dir, "timeline.json"));
  const r = build(fx);
  assert.equal(r.code, 1);
  assert.match(r.err, /^board: timeline\.json is missing/m);
});

test("apply of an approval prints approved, and writes the normalized answers", () => {
  const fx = ready();
  ok(build(fx));
  const r = apply(fx, answersText(1, "Approved: the look"));
  ok(r);
  assert.equal(r.out, "board: approved; next: run the gates\n");
  const doc = readJson(path.join(fx.dir, "board", "answers-1.json"));
  assert.equal(doc.version, 1);
  assert.equal(doc.approve, true);
  assert.equal(doc.direction, null);
  assert.equal(doc.look, "");
  assert.deepEqual(doc.scenes, []);
  assert.ok(!Number.isNaN(Date.parse(doc.submittedAt)));
  // The same answers as the document the database holds.
  const j = apply(fx, {
    version: 1,
    submittedAt: "2026-10-28T10:00:00.000Z",
    approve: true,
    direction: null,
    look: "",
    scenes: [],
  });
  ok(j);
  assert.equal(j.out, "board: approved; next: run the gates\n");
});

test("apply of scene notes prints a redo line for each noted scene and only those", () => {
  const fx = ready();
  ok(build(fx));
  const r = apply(
    fx,
    answersText(
      1,
      "hook: make the first beat slower",
      "context: drop the second metaphor",
      "  and keep the question",
    ),
  );
  ok(r);
  assert.equal(
    r.out,
    [
      "board: redo hook: make the first beat slower",
      "board: redo context: drop the second metaphor",
      "  and keep the question",
      "board: next: re-author only hook, context, then build the board again",
      "",
    ].join("\n"),
  );
  assert.doesNotMatch(r.out, /approved|recap/);
  const doc = readJson(path.join(fx.dir, "board", "answers-1.json"));
  assert.deepEqual(doc.scenes, [
    { id: "hook", note: "make the first beat slower" },
    { id: "context", note: "drop the second metaphor\nand keep the question" },
  ]);
});

test("apply of a direction pick and of a look comment each name the whole chapter", () => {
  const fx = ready();
  ok(build(fx));
  let r = apply(fx, answersText(1, "Direction: kitchen"));
  ok(r);
  assert.equal(
    r.out,
    [
      "board: direction kitchen; next: re-author chapter 1 in it, then build the board again",
      "board: next: re-author the whole chapter, then build the board again",
      "",
    ].join("\n"),
  );
  r = apply(
    fx,
    answersText(1, "Look: warmer colours", "  and a lighter ground"),
  );
  ok(r);
  assert.equal(
    r.out,
    [
      "board: look: warmer colours",
      "  and a lighter ground",
      "board: next: re-author the whole chapter, then build the board again",
      "",
    ].join("\n"),
  );
});

test("a comment wins over an approval: the board is not approved", () => {
  const fx = ready();
  ok(build(fx));
  for (const lines of [
    ["Approved: the look", "Look: darker"],
    ["Approved: the look", "hook: slower"],
    ["Approved: the look", "Direction: plain"],
  ]) {
    const r = apply(fx, answersText(1, ...lines));
    ok(r);
    assert.doesNotMatch(r.out, /approved/);
    assert.match(r.out, /^board: next: re-author /m);
  }
});

test("apply refuses a stale version, an unknown scene, an unknown direction, a cut text and a line it cannot read", () => {
  const fx = ready();
  ok(build(fx));
  const refused = (answers, why) => {
    const r = apply(fx, answers);
    assert.equal(r.code, 1, r.out + r.err);
    assert.match(r.err, why);
    assert.equal(r.out, "");
  };
  refused(
    answersText(2, "Approved: the look"),
    /^board: these answers are of board 2, the latest is board 1$/m,
  );
  refused(answersText(1, "nope: slower"), /^board: no scene nope in board 1$/m);
  refused(
    answersText(1, "Direction: nope"),
    /^board: no direction nope in board 1$/m,
  );
  refused(
    {
      version: 1,
      approve: false,
      direction: null,
      look: "",
      scenes: [{ id: "nope", note: "x" }],
    },
    /^board: no scene nope in board 1$/m,
  );
  refused(
    answersText(1, "hook: slower", "[cut to fit: read answers/board-1]"),
    /^board: the answers were cut to fit a comment: read answers\/board-1 from the database$/m,
  );
  refused(
    answersText(1, "Approved: the look", "this is not a line"),
    /^board: cannot read this answers line: this is not a line$/m,
  );
  refused(
    "hello",
    /^board: not an answers text: its first line is not the header$/m,
  );
  refused("{ not json", /^board: the answers document is not valid JSON/m);
  assert.ok(!fs.existsSync(path.join(fx.dir, "board", "answers-1.json")));
});

test("apply refuses before any board is built", () => {
  const fx = ready();
  const r = apply(fx, answersText(1, "Approved: the look"));
  assert.equal(r.code, 1);
  assert.match(r.err, /^board: no board built yet: run build first$/m);
});

test("a comment on one scene lets only that scene be re-authored: another scene's change refuses the next build", () => {
  const fx = ready();
  ok(build(fx));
  ok(apply(fx, answersText(1, "hook: slower")));
  compose(fx, "context", "<p>context changed on its own</p>");
  const r = build(fx);
  assert.equal(r.code, 1);
  assert.equal(
    r.err,
    "board: context changed, but board 1's comments named only hook: re-author only those scenes\n",
  );
  assert.ok(!fs.existsSync(path.join(fx.dir, "board", "2.json")));
  // The scene the note named is the one to change: board 2 flags it alone.
  compose(fx, "context", "<p>context line</p>");
  compose(fx, "hook", "<p>hook, slower</p>");
  ok(build(fx));
  const one = built(fx, 1);
  const two = built(fx, 2);
  assert.equal(two.version, 2);
  assert.deepEqual(
    two.scenes.map((s) => [s.id, s.changed]),
    [
      ["hook", true],
      ["context", false],
      ["recap", false],
    ],
  );
  // An unchanged scene keeps its stills' names across versions.
  assert.deepEqual(two.scenes[1].stills, one.scenes[1].stills);
  assert.notDeepEqual(two.scenes[0].stills, one.scenes[0].stills);
  assert.match(
    build(fx).out,
    /^board: 3 -> board\/storyboard\.html \(3 scenes, \d+ stills, 0 changed\)$/m,
  );
});

test("a change to the kit refuses the next build after notes on a scene", () => {
  const fx = ready();
  fs.mkdirSync(path.join(fx.dir, "project", "kit"), { recursive: true });
  fs.writeFileSync(path.join(fx.dir, "project", "kit", "kit.css"), "p{}");
  ok(build(fx));
  ok(apply(fx, answersText(1, "hook: slower", "recap: shorter")));
  fs.writeFileSync(
    path.join(fx.dir, "project", "kit", "kit.css"),
    "p{color:red}",
  );
  let r = build(fx);
  assert.equal(r.code, 1);
  assert.equal(
    r.err,
    "board: the kit changed, but board 1's comments named only hook, recap: re-author only those scenes\n",
  );
  compose(fx, "context", "<p>another</p>");
  r = build(fx);
  assert.match(
    r.err,
    /^board: context, the kit changed, but board 1's comments named only hook, recap: /,
  );
});

test("after a look comment, a direction pick or no answers, any change builds", () => {
  for (const answers of [
    answersText(1, "Look: warmer", "hook: slower"),
    answersText(1, "Direction: kitchen", "hook: slower"),
    answersText(1, "Approved: the look"),
    null,
  ]) {
    const fx = ready();
    fs.mkdirSync(path.join(fx.dir, "project", "kit"), { recursive: true });
    fs.writeFileSync(path.join(fx.dir, "project", "kit", "kit.css"), "p{}");
    ok(build(fx));
    if (answers) ok(apply(fx, answers));
    compose(fx, "context", "<p>context changed</p>");
    fs.writeFileSync(path.join(fx.dir, "project", "kit", "kit.css"), "p{x:1}");
    const r = build(fx);
    ok(r);
    const two = built(fx, 2);
    assert.equal(two.scenes.find((s) => s.id === "context").changed, true);
    assert.notEqual(two.kit, built(fx, 1).kit);
    assert.match(r.out, /\(3 scenes, \d+ stills, 1 changed\)/);
  }
});
