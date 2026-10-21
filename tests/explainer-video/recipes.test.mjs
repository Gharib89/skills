// The recipes reference: it exists, SKILL.md sends the agent to it before a
// custom or rich scene, and it carries the motion rule and each borrowed move
// in prose, with no code from the library the moves come from.
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { lintFragment } from "../../skills/explainer-video/scripts/lib/fragment.mjs";
import { skill } from "./render-lib.mjs";

const read = (f) => fs.readFileSync(`${skill}/${f}`, "utf8");

// The counter recipe's code, as one line: the recipes show it in backticks.
const counter = (md) =>
  md
    .match(/`(tl\.fromTo\(\$\("\.n"\)[\s\S]*?cue\("count"\)\);)`/)?.[1]
    .replace(/\s+/g, " ");

// What the counter recipe must be: code the lint accepts that a seek replays,
// a tween of the text through a modifier, never an `onUpdate` callback.
function holdsCounter(md) {
  const code = counter(md);
  assert.ok(code, "the recipes show the counter");
  assert.match(code, /modifiers: \{ textContent:/);
  assert.doesNotMatch(code, /onUpdate/);
  lintFragment(`<div class="n">0</div><script>${code}</script>`, {
    names: ["count"],
  });
}

test("SKILL.md tells the agent to read the recipes before a custom or rich scene", () => {
  assert.match(
    read("SKILL.md").replace(/\s+/g, " "),
    /Before a `custom` or rich scene, read \[reference\/recipes\.md\]\(reference\/recipes\.md\)/,
  );
  assert.ok(fs.existsSync(`${skill}/reference/recipes.md`));
});

const MOVES = [
  "Tool calls ticking by",
  "A diff card that counts",
  "A score jump",
  "A checklist collapsing",
  "A fan-out",
  "A punch-in with a ring",
];

// What the recipes must hold; throws on the first thing missing.
function holdsRecipes(md) {
  assert.match(md, /^## Contents$/m);
  assert.match(md, /at\s+most about 250 ms/);
  assert.match(md, /One element moves at a time/);
  assert.match(md, /400 to 500 ms/);
  for (const d of ["Type", "Data", "System", "Interface", "Camera"])
    assert.match(md, new RegExp(`^\\| ${d} \\|`, "m"), d);
  for (const move of MOVES) assert.match(md, new RegExp(`\\*\\*${move}`), move);
  // every move names its timings, so none is a bare idea
  const moves = md.split("## Moves to borrow")[1];
  for (const para of moves.split("\n\n").filter((p) => p.startsWith("**")))
    assert.match(para, /\d+ ?(ms|s)\b/, para.slice(0, 30));
}

test("the recipes hold the motion rule, the five directions and the six borrowed moves", () => {
  holdsRecipes(read("reference/recipes.md"));
});

test("the recipes check fails on a text missing a move, a timing or the motion rule", () => {
  const md = read("reference/recipes.md");
  assert.throws(
    () => holdsRecipes(md.replace("A fan-out", "A spread")),
    /A fan-out/,
  );
  assert.throws(
    () => holdsRecipes(md.replace("One element moves at a time", "")),
    /One element moves at a time/,
  );
  const [head, moves] = md.split("## Moves to borrow");
  const untimed = moves.replace(/\d+ ?(ms|s)\b/g, "a while");
  assert.throws(
    () => holdsRecipes(`${head}## Moves to borrow${untimed}`),
    /Tool calls ticking by/,
  );
});

test("the counter recipe lints clean and tweens the text with a modifier, so a seek replays it", () => {
  const md = read("reference/recipes.md");
  holdsCounter(md);
  assert.throws(
    () => holdsCounter(md.replace("modifiers: {", "onUpdate: {")),
    /modifiers/,
  );
  assert.throws(
    () => holdsCounter(md.replace("duration: 0.8", "duration: Date.now()")),
    /time source Date\.now/,
  );
});

test("the recipes carry no source library's code or asset, and no em dash", () => {
  const md = read("reference/recipes.md");
  assert.doesNotMatch(
    md,
    /everestchris|import .* from|<\/?(svg|canvas|img)\b/i,
  );
  assert.doesNotMatch(md, new RegExp(`[${"\\u2014"}${"\\u2013"}]`));
  assert.doesNotMatch(md, /!\[[^\]]*\]\(/);
});
