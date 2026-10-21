// The recipes reference: it exists, SKILL.md sends the agent to it before a
// custom or rich scene, and it carries the motion rule and each borrowed move
// in prose, with no code from the library the moves come from.
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { skill } from "./render-lib.mjs";

const read = (f) => fs.readFileSync(`${skill}/${f}`, "utf8");

test("SKILL.md tells the agent to read the recipes before a custom or rich scene", () => {
  assert.match(
    read("SKILL.md").replace(/\s+/g, " "),
    /Before a `custom` or rich scene, read \[reference\/recipes\.md\]\(reference\/recipes\.md\)/,
  );
  assert.ok(fs.existsSync(`${skill}/reference/recipes.md`));
});

test("the recipes hold the motion rule, the five directions and the six borrowed moves", () => {
  const md = read("reference/recipes.md");
  assert.match(md, /^## Contents$/m);
  assert.match(md, /at\s+most about 250 ms/);
  assert.match(md, /One element moves at a time/);
  assert.match(md, /400 to 500 ms/);
  for (const d of ["Type", "Data", "System", "Interface", "Camera"])
    assert.match(md, new RegExp(`^\\| ${d} \\|`, "m"), d);
  for (const move of [
    "Tool calls ticking by",
    "A diff card that counts",
    "A score jump",
    "A checklist collapsing",
    "A fan-out",
    "A punch-in with a ring",
  ])
    assert.match(md, new RegExp(`\\*\\*${move}`), move);
  // every move names its timings, so none is a bare idea
  const moves = md.split("## Moves to borrow")[1];
  for (const para of moves.split("\n\n").filter((p) => p.startsWith("**")))
    assert.match(para, /\d+ ?(ms|s)\b/, para.slice(0, 30));
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
