// The storyboard card's menus through board.mjs: the board document carries
// each card's component, camera beat, emphasised item and seam with the options
// the page offers, and apply writes a changed pick back into the scene file.
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import {
  board,
  compile,
  doc,
  fixture,
  ok,
  prep,
  read,
  run,
  skill,
  stills,
  voice,
} from "./board-lib.mjs";
import {
  applyPick,
  cardMenus,
} from "../../skills/explainer-video/scripts/storyboard/menus.mjs";
import { VISUALS } from "../../skills/explainer-video/scripts/lib/visuals.mjs";
import { profiled } from "./render-lib.mjs";
import { SCRIPT } from "./scene-file.mjs";

const WORDS =
  '{ "component": "words", "props": { "lines": [ { "at": 1, "text": "reads the issue", "on": "reads" } ] } }\n';
const noCamera = { pick: "none", options: ["none"], disabled: true };

test("a card's menus hold the agent's pick and the options the page offers", () => {
  const fx = fixture();
  prep(fx);
  ok(board(fx, "build"), "build");
  const [hook, steps, gate] = doc(fx, 1).scenes.map((c) => c.menus);

  // Every component the profile does not ban, plus custom, whatever the card.
  assert.equal(steps.component.pick, "cards");
  for (const name of ["title", "cards", "terminal", "flow", "chart", "custom"])
    assert.ok(steps.component.options.includes(name), name);
  assert.deepEqual(hook.component.options, steps.component.options);

  // The camera beat is one of the scene's own cues, the last reveal by default.
  assert.deepEqual(steps.camera, { pick: "3", options: ["1", "2", "3"] });

  // The emphasised item is one of the scene's item labels, or none.
  assert.deepEqual(steps.emphasis, {
    pick: "none",
    options: ["none", "Input", "First", "Then"],
  });
  assert.deepEqual(gate.emphasis.options, [
    "none",
    "$ scripts/local-gate.sh",
    "gh pr create",
  ]);

  // The seam is a move of the profile's family or a plain cut; the last scene
  // has no seam out.
  assert.deepEqual(steps.seam, {
    pick: "zoom-through",
    options: ["zoom-through", "cut-the-curve", "cut"],
  });
  assert.deepEqual(gate.seam, {
    pick: "cut",
    options: ["cut"],
    disabled: true,
  });
});

test("a component the profile bans leaves the component menu, and a camera it bans is disabled", () => {
  const fx = fixture(SCRIPT.replace("style: claude-code", "style: plain"));
  profiled(fx, "plain", { grammar: { bans: ["chart", "camera"] } });
  prep(fx);
  ok(board(fx, "build"), "build");
  const [hook, steps] = doc(fx, 1).scenes.map((c) => c.menus);
  assert.ok(!hook.component.options.includes("chart"));
  assert.ok(hook.component.options.includes("cards"));
  assert.deepEqual(steps.camera, noCamera);
});

test("a rich component draws its own camera, so its card's camera menu is disabled", () => {
  const fx = fixture(
    SCRIPT.replace(/\{\n {2}"component": "cards"[\s\S]*?\n\}\n/, WORDS),
  );
  prep(fx);
  ok(board(fx, "build"), "build");
  const words = doc(fx, 1).scenes[1].menus;
  assert.equal(words.component.pick, "words");
  assert.deepEqual(words.camera, noCamera);
});

test("the brief's menu knobs arrive as menus with their options, length as a number, the rest as text", () => {
  const fx = fixture();
  prep(fx);
  // The brief lands after the voice stage, whose length gate would hold a
  // 13 s fixture to the brief's two minutes.
  ok(run(fx, "brief/brief.mjs", ["voice=am_fenrir"]), "brief");
  ok(board(fx, "build"), "build");
  const d = doc(fx, 1);
  const knob = (k) => d.brief.find((x) => x.knob === k);
  assert.deepEqual(
    d.brief.map((x) => [x.knob, x.type]),
    [
      ["focus", "text"],
      ["length", "number"],
      ["audience", "text"],
      ["language", "menu"],
      ["style", "menu"],
      ["voice", "menu"],
      ["aspect", "menu"],
      ["score", "menu"],
      ["must", "text"],
      ["avoid", "text"],
    ],
  );
  assert.deepEqual(knob("language").options, ["en", "ar"]);
  assert.deepEqual(knob("style").options, ["claude-code", "itworx"]);
  assert.deepEqual(knob("aspect").options, ["16:9"]);
  assert.deepEqual(knob("score").options, ["on", "off", "ace-step"]);
  // A voice menu follows the language, so the document holds each language's.
  assert.deepEqual(knob("voice").options, [
    "bf_emma",
    "am_fenrir",
    "af_heart",
    "elevenlabs-george",
  ]);
  assert.deepEqual(d.voices, [
    {
      language: "en",
      options: ["bf_emma", "am_fenrir", "af_heart", "elevenlabs-george"],
    },
    { language: "ar", options: ["ar-eg-csagent-2", "ar-eg-commercial-11"] },
  ]);
  assert.equal(knob("focus").options, undefined);
});

test("an enrolled own voice the brief holds stays in the voice menu and its language's voices", () => {
  const fx = fixture();
  prep(fx);
  ok(run(fx, "brief/brief.mjs", ["voice=am_fenrir"]), "brief");
  const file = path.join(fx.dir, "brief.json");
  const held = JSON.parse(fs.readFileSync(file, "utf8"));
  fs.writeFileSync(
    file,
    JSON.stringify({ ...held, language: "ar", voice: "own:maya" }),
  );
  ok(board(fx, "build"), "build");
  const d = doc(fx, 1);
  const arabic = ["ar-eg-csagent-2", "ar-eg-commercial-11", "own:maya"];
  assert.deepEqual(d.brief.find((x) => x.knob === "voice").options, arabic);
  assert.deepEqual(d.voices.find((v) => v.language === "ar").options, arabic);
  assert.equal(d.voices.find((v) => v.language === "en").options.length, 4);
});

// Answers approving every card but `steps`, which is revised with `lines`
// under it, applied to board 1.
const answered = (fx, lines) => {
  const file = path.join(fx.tmp, "answers.txt");
  fs.writeFileSync(
    file,
    [
      "explainer-video: board 1 answers (database document answers/board-1)",
      "hook: Approve",
      "steps: Revise",
      ...lines,
      "gate: Approve",
    ].join("\n"),
  );
  return board(fx, "apply", file);
};
// A scene's `### Visual` JSON in script.md, read back.
const visual = (fx, id) =>
  JSON.parse(
    read(fx.dir, "script.md")
      .split(new RegExp(`^## Scene ${id} .*$`, "m"))[1]
      .split("## Scene ")[0]
      .match(/```json\n([\s\S]*?)\n```/)[1],
  );

test("a changed camera pick is written into the scene file, and only that scene is rebuilt", () => {
  const fx = fixture();
  prep(fx);
  ok(board(fx, "build"), "build");
  const r = ok(answered(fx, ["  pick: camera=1"]), "apply");
  assert.match(r.out, /^board steps pick: camera=1$/m);
  assert.match(r.out, /^board: redo steps$/m);
  assert.deepEqual(visual(fx, "steps").camera, { at: 1 });
  assert.deepEqual(
    JSON.parse(read(fx.dir, "board", "answers-1.json")).scenes[1].picks,
    { camera: "1" },
  );

  ok(compile(fx), "compile");
  assert.match(voice(fx).out, /^voice steps: cached/m);
  assert.match(stills(fx).out, /^render: stills 2\/3 cached$/m);
  ok(board(fx, "build"), "build 2");
  assert.deepEqual(
    doc(fx, 2).scenes.map((c) => [c.id, c.status, c.menus.camera.pick]),
    [
      ["hook", "approved", doc(fx, 1).scenes[0].menus.camera.pick],
      ["steps", "open", "1"],
      ["gate", "approved", doc(fx, 1).scenes[2].menus.camera.pick],
    ],
  );
});

test("an emphasis pick names its item and lands with it, and none takes the emphasis off", () => {
  const fx = fixture();
  prep(fx);
  ok(board(fx, "build"), "build");
  ok(answered(fx, ["  pick: emphasis=First"]), "apply");
  assert.deepEqual(visual(fx, "steps").props.emphasis, {
    target: "First",
    at: 2,
  });
  ok(compile(fx), "compile");
  ok(voice(fx), "voice");
  ok(stills(fx), "stills");
  ok(board(fx, "build"), "build 2");
  assert.equal(doc(fx, 2).scenes[1].menus.emphasis.pick, "First");
  const file = path.join(fx.tmp, "none.txt");
  fs.writeFileSync(
    file,
    [
      "explainer-video: board 2 answers (database document answers/board-2)",
      "hook: Approve",
      "steps: Revise",
      "  pick: emphasis=none",
      "gate: Approve",
    ].join("\n"),
  );
  ok(board(fx, "apply", file), "apply 2");
  assert.equal(visual(fx, "steps").props.emphasis, undefined);
});

test("a seam pick is written into the scene file", () => {
  const fx = fixture();
  prep(fx);
  ok(board(fx, "build"), "build");
  ok(answered(fx, ["  pick: seam=cut"]), "apply");
  assert.equal(visual(fx, "steps").seam, "cut");
  ok(compile(fx), "compile");
});

test("a component pick is reported for Claude to rebuild the scene, and the scene file is left alone", () => {
  const fx = fixture();
  prep(fx);
  ok(board(fx, "build"), "build");
  const before = read(fx.dir, "script.md");
  const r = ok(answered(fx, ["  pick: component=flow"]), "apply");
  assert.match(r.out, /^board steps pick: component=flow$/m);
  assert.match(r.out, /^board: redo steps$/m);
  assert.equal(read(fx.dir, "script.md"), before);
});

test("a pick the card's menu does not offer is refused, and an unchanged pick is no change", () => {
  const fx = fixture();
  prep(fx);
  ok(board(fx, "build"), "build");
  for (const bad of ["camera=9", "seam=wipe", "colour=red"]) {
    const r = answered(fx, [`  pick: ${bad}`]);
    assert.equal(r.code, 1, bad);
    assert.match(r.err, /^board: scene steps has no (camera|seam|colour) /m);
  }
  const r = ok(answered(fx, ["  pick: camera=3"]), "apply");
  assert.doesNotMatch(r.out, /pick/);
  assert.match(r.out, /^board: redo steps$/m);
});

test("a pick on a scene whose visual block is not JSON is refused by name, not with a stack trace", () => {
  const fx = fixture();
  prep(fx);
  ok(board(fx, "build"), "build");
  const file = path.join(fx.dir, "script.md");
  fs.writeFileSync(
    file,
    read(fx.dir, "script.md").replace(
      '"component": "cards"',
      '"component": cards',
    ),
  );
  const r = answered(fx, ["  pick: seam=cut"]);
  assert.equal(r.code, 1);
  assert.match(r.err, /^board: script\.md visual block for steps is not JSON/m);
});

test("an approved card with a changed pick is still redone, so no change is lost to Approve", () => {
  const fx = fixture();
  prep(fx);
  ok(board(fx, "build"), "build");
  const file = path.join(fx.tmp, "approve.txt");
  fs.writeFileSync(
    file,
    [
      "explainer-video: board 1 answers (database document answers/board-1)",
      "hook: Approve",
      "steps: Approve",
      "  pick: seam=cut",
      "gate: Approve",
    ].join("\n"),
  );
  const r = ok(board(fx, "apply", file), "apply");
  assert.match(r.out, /^board: redo steps$/m);
});

test("a custom scene, which the composer has no component for, gets disabled camera and emphasis menus", () => {
  const scene = { visual: { component: "custom" }, narration: ["It reads."] };
  const m = cardMenus(scene, { name: "claude-code" }, null, false);
  assert.equal(m.component.pick, "custom");
  assert.deepEqual(m.camera, noCamera);
  assert.deepEqual(m.emphasis, {
    pick: "none",
    options: ["none"],
    disabled: true,
  });
});

test("an item labelled none stays selectable beside the no-emphasis option, and the pick removes only the emphasis", () => {
  const rows = VISUALS.cards.rows;
  const scene = (emphasis) => ({
    visual: {
      component: "cards",
      props: {
        [rows]: [
          { label: "none", at: 1 },
          { label: "Then", at: 2 },
        ],
        ...(emphasis && { emphasis }),
      },
    },
    narration: ["It reads.", "Then it runs."],
  });
  const profile = { name: "claude-code" };
  const plain = cardMenus(scene(), profile, null, false).emphasis;
  assert.deepEqual(plain, {
    pick: "(none)",
    options: ["(none)", "none", "Then"],
  });
  // An emphasis on the item labelled none is a pick of its own.
  const on = cardMenus(
    scene({ target: "none", at: 1 }),
    profile,
    null,
    false,
  ).emphasis;
  assert.equal(on.pick, "none");
  const { visual } = scene({ target: "none", at: 1 });
  assert.ok(applyPick(visual, "emphasis", "(none)"));
  assert.equal(visual.props.emphasis, undefined);
  assert.ok(applyPick(visual, "emphasis", "none"));
  assert.equal(visual.props.emphasis.target, "none");
});

test("a code card's emphasis menu shows its line range and cannot change", () => {
  const scene = {
    visual: {
      component: "code",
      props: { code: "a\nb\nc\nd", emphasis: { target: [2, 3] } },
    },
    narration: ["It reads."],
  };
  const m = cardMenus(scene, { name: "claude-code" }, null, false);
  assert.deepEqual(m.emphasis, {
    pick: "lines 2-3",
    options: ["lines 2-3"],
    disabled: true,
  });
});

test("the style menu lists the profile the run holds beside the installed ones", () => {
  // A profile only the run holds, drawn from images: no store lists it.
  const fx = fixture(
    SCRIPT.replace("style: claude-code", "style: held-by-run"),
  );
  const base = path.join(skill, "styles", "claude-code.json");
  fs.writeFileSync(
    path.join(fx.dir, "style.json"),
    JSON.stringify({
      ...JSON.parse(fs.readFileSync(base, "utf8")),
      name: "held-by-run",
    }),
  );
  prep(fx);
  ok(run(fx, "brief/brief.mjs", ["voice=am_fenrir"]), "brief");
  ok(board(fx, "build"), "build");
  const style = doc(fx, 1).brief.find((x) => x.knob === "style");
  assert.ok(style.options.includes("held-by-run"), style.options.join());
  assert.ok(style.options.includes("claude-code"));
});
