// The menus on the storyboard page: every option comes from the board document
// (the page hardcodes none), a changed pick answers the card Revise with the new
// value, and the picks and the brief's menu knobs read back through
// `board.mjs apply`.
import { after, test } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { SCRIPT } from "./scene-file.mjs";
import {
  P,
  clone,
  read,
  sample,
  session,
  shapeProblems,
  skill,
} from "./page-lib.mjs";

const temps = [];
after(() =>
  temps.forEach((t) => fs.rmSync(t, { recursive: true, force: true })),
);

// The select a card's menu (`data-menu`) or a brief knob (`data-brief`) renders
// as: its tag and its options, the picked one marked.
function select(v, attr, key, id) {
  const tag = `<select[^>]*${attr}="${key}"${id ? `[^>]*data-id="${id}"` : ""}[^>]*>`;
  const m = v.match(new RegExp(`(${tag})([\\s\\S]*?)</select>`));
  if (!m) return null;
  return {
    disabled: /\sdisabled/.test(m[1]),
    options: [...m[2].matchAll(/<option value="([^"]*)"( selected)?/g)].map(
      (o) => o[1],
    ),
    picked: m[2].match(/<option value="([^"]*)" selected/)?.[1],
  };
}
const menu = (v, name, id) => select(v, "data-menu", name, id);
const knob = (v, name) => select(v, "data-brief", name);

test("every menu's options come from the board document", () => {
  const board = sample("board-review");
  assert.deepEqual(shapeProblems(board, "board"), []);
  const odd = ["one", "two", "three"];
  for (const c of board.scenes)
    for (const m of ["component", "camera", "emphasis", "seam"]) {
      c.menus[m] = { pick: "two", options: odd };
    }
  for (const k of board.brief)
    if (k.type === "menu") k.options = ["x", "y", k.value];
  const v = P.view(session([board]));
  for (const c of board.scenes)
    for (const m of ["component", "camera", "emphasis", "seam"]) {
      const s = menu(v, m, c.id);
      assert.deepEqual(s.options, odd, `${c.id} ${m}`);
      assert.equal(s.picked, "two");
    }
  for (const k of board.brief.filter((x) => x.type === "menu")) {
    if (k.knob === "voice") continue;
    assert.deepEqual(knob(v, k.knob).options, ["x", "y", k.value], k.knob);
  }
});

test("a menu the board disables renders disabled, and every menu does once the page is locked", () => {
  const v = P.view(session([sample("board-finding")]));
  // The rich card's camera and the last scene's seam cannot change.
  assert.equal(menu(v, "camera", "steps").disabled, true);
  assert.equal(menu(v, "seam", "gate").disabled, true);
  assert.equal(menu(v, "camera", "hook").disabled, false);
  assert.equal(menu(v, "seam", "hook").disabled, false);
  const locked = P.view(
    session([sample("board-review")], [{ version: 1, scenes: [], brief: [] }]),
  );
  for (const id of ["hook", "steps", "gate"])
    for (const m of ["component", "camera", "emphasis", "seam"])
      assert.equal(menu(locked, m, id).disabled, true, `${id} ${m}`);
});

test("a changed pick answers the card Revise with the new value, and only a changed pick is sent", () => {
  const S = session([sample("board-review")]);
  P.ACT.choose(S, { id: "steps", choice: "approve" });
  P.ACT.pick(S, { id: "steps", menu: "camera", value: "2" });
  const doc = clone(P.answersDoc(S));
  const steps = doc.scenes.find((c) => c.id === "steps");
  assert.equal(steps.choice, "revise");
  assert.deepEqual(steps.picks, { camera: "2" });
  assert.deepEqual(doc.scenes.find((c) => c.id === "hook").picks, {});
  assert.match(P.answersText(S), /^steps: Revise\n {2}pick: camera=2$/m);
  assert.equal(menu(P.view(S), "camera", "steps").picked, "2");
  // Back on the agent's pick, the card sends no pick.
  P.ACT.pick(S, { id: "steps", menu: "camera", value: "1" });
  assert.deepEqual(clone(P.answersDoc(S)).scenes[1].picks, {});
  assert.doesNotMatch(P.answersText(S), /pick:/);
});

test("a locked page takes no pick", () => {
  const S = session(
    [sample("board-review")],
    [{ version: 1, scenes: [], brief: [] }],
  );
  P.ACT.pick(S, { id: "steps", menu: "camera", value: "2" });
  assert.deepEqual(clone(P.answersDoc(S)).scenes[1].picks, {});
});

test("the answers text of a pick card reads back through apply and writes the pick", () => {
  const dir = path.join(
    fs.mkdtempSync(path.join(os.tmpdir(), "explainer-page-")),
    "demo",
  );
  temps.push(path.dirname(dir));
  fs.mkdirSync(path.join(dir, "board"), { recursive: true });
  fs.writeFileSync(path.join(dir, "script.md"), SCRIPT);
  fs.writeFileSync(
    path.join(dir, "board", "1.json"),
    JSON.stringify(sample("board-review")),
  );
  const S = session([sample("board-review")]);
  P.ACT.approveAll(S);
  P.ACT.pick(S, { id: "hook", menu: "seam", value: "cut-the-curve" });
  P.ACT.pick(S, { id: "steps", menu: "component", value: "terminal" });
  const file = path.join(dir, "answers.txt");
  fs.writeFileSync(file, P.answersText(S));
  const r = spawnSync(
    process.execPath,
    [
      path.join(skill, "scripts", "storyboard", "board.mjs"),
      dir,
      "apply",
      file,
    ],
    { encoding: "utf8" },
  );
  assert.equal(r.status, 0, r.stdout + r.stderr);
  assert.match(r.stdout, /board hook pick: seam=cut-the-curve/);
  assert.match(r.stdout, /board steps pick: component=terminal/);
  assert.match(r.stdout, /board: redo hook,steps/);
  const got = JSON.parse(read(path.join(dir, "board", "answers-1.json")));
  assert.deepEqual(got.scenes, clone(P.answersDoc(S)).scenes);
  assert.match(read(path.join(dir, "script.md")), /"seam": ?"cut-the-curve"/);
});

test("the brief's menu knobs are menus, length is a number, and the rest stay text", () => {
  const v = P.view(session([sample("board-review")]));
  assert.deepEqual(knob(v, "language").options, ["en", "ar"]);
  assert.deepEqual(knob(v, "style").options, ["claude-code", "itworx"]);
  assert.deepEqual(knob(v, "aspect").options, ["16:9"]);
  assert.equal(knob(v, "voice").picked, "am_fenrir");
  assert.match(
    v,
    /<input type="number" min="1" step="any" data-brief="length" value="2"/,
  );
  for (const t of ["focus", "audience", "must", "avoid"])
    assert.match(v, new RegExp(`<input type="text" data-brief="${t}"`));
});

test("a language pick shows that language's voices and resets the voice, and both read back as brief arguments", () => {
  const S = session([sample("board-review")]);
  assert.deepEqual(knob(P.view(S), "voice").options, [
    "bf_emma",
    "am_fenrir",
    "af_heart",
    "elevenlabs-george",
  ]);
  P.ACT.brief(S, { knob: "language", value: "ar" });
  const v = P.view(S);
  assert.deepEqual(knob(v, "voice").options, [
    "ar-eg-csagent-2",
    "ar-eg-commercial-11",
  ]);
  assert.equal(knob(v, "voice").picked, "ar-eg-csagent-2");
  assert.deepEqual(clone(P.answersDoc(S)).brief, [
    "language=ar",
    "voice=ar-eg-csagent-2",
  ]);
  // A voice the new language offers is kept.
  P.ACT.brief(S, { knob: "voice", value: "ar-eg-commercial-11" });
  P.ACT.brief(S, { knob: "language", value: "ar" });
  assert.equal(knob(P.view(S), "voice").picked, "ar-eg-commercial-11");
});
