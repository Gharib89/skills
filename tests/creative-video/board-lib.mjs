// Shared fixtures of the storyboard tests: a timed run folder with its
// storyboard.json and the direction frames written, and the runners of
// board.mjs's two commands.
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { here } from "./voice-lib.mjs";
import { exec, project, readJson } from "./timing-lib.mjs";
import { scene, timed } from "./gates-lib.mjs";

export const board = path.join(
  here,
  "..",
  "..",
  "skills",
  "creative-video",
  "scripts",
  "board",
  "board.mjs",
);
export const boardDir = path.join(
  here,
  "..",
  "..",
  "skills",
  "creative-video",
  "board",
);

export const DIRECTIONS = [
  { id: "switch", name: "The Switchboard", kind: "a world" },
  { id: "kitchen", name: "The Kitchen", kind: "a format" },
  { id: "plain", name: "Drawn Straight", kind: "the subject itself" },
];

// The storyboard.json the agent writes for `ids`' scenes.
export const storyboard = (ids, picked = "switch", extra = {}) => ({
  title: "Why agentic engineering",
  focus: "what an agent loop is",
  directions: {
    recommended: "switch",
    picked,
    list: DIRECTIONS.map((d) => ({ ...d })),
  },
  scenes: Object.fromEntries(
    ids.map((id) => [id, { title: `The ${id} scene`, notes: `${id} notes` }]),
  ),
  ...extra,
});

export function writeStoryboard(fx, doc) {
  fs.writeFileSync(path.join(fx.dir, "storyboard.json"), JSON.stringify(doc));
}

// A direction's frame, authored as a scene file is.
export function writeDirection(fx, id) {
  fs.mkdirSync(path.join(fx.dir, "directions"), { recursive: true });
  fs.writeFileSync(
    path.join(fx.dir, "directions", `${id}.html`),
    scene(id, `<p>${id} look</p>`),
  );
}

// A timed run folder ready for `board build`: its storyboard.json and the
// frame of each direction but the picked one.
export function ready({ bodies, picked = "switch", extra } = {}) {
  const fx = timed(bodies);
  const ids = readJson(path.join(fx.dir, "timeline.json")).scenes.map(
    (s) => s.id,
  );
  writeStoryboard(fx, storyboard(ids, picked, extra));
  for (const d of DIRECTIONS) if (d.id !== picked) writeDirection(fx, d.id);
  return fx;
}

export const build = (fx) => exec(board, fx, [fx.dir, "build"]);

// `board apply` on answers text or a document.
export function apply(fx, answers) {
  const file = path.join(fx.tmp, "answers.txt");
  fs.writeFileSync(
    file,
    typeof answers === "string" ? answers : JSON.stringify(answers),
  );
  return exec(board, fx, [fx.dir, "apply", file]);
}

export const built = (fx, n = 1) =>
  readJson(path.join(fx.dir, "board", `${n}.json`));

export const answersText = (n, ...lines) =>
  [
    `creative-video: board ${n} answers (database document answers/board-${n})`,
    ...lines,
  ].join("\n");

export const ok = (r) => assert.equal(r.code, 0, r.out + r.err);

export { project };
