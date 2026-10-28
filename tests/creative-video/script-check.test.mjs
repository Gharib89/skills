// The script check: every narration sentence carries its cites, every cite is
// an excerpt of the pack, and the support checker judged every sentence
// supported or connective, before anything is voiced. A red support verdict
// is one fix attempt, two at most.
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fixture, SCENES, write } from "./voice-lib.mjs";
import { readJson } from "./timing-lib.mjs";
import { cited, judge, pack, runCheck } from "./support-lib.mjs";

const CITES = { hook: [["ex-1"]], context: [[], ["ex-2"]] };

function run(scenes = cited(SCENES, CITES), verdicts) {
  const fx = fixture(scenes);
  pack(fx);
  if (verdicts !== null) judge(fx, scenes, verdicts);
  return fx;
}
const gate = (r, name) =>
  r.out.match(new RegExp(`^script ${name}: (.*)$`, "m"))?.[1];
const record = (fx) => readJson(path.join(fx.dir, "check.json"));

test("a script whose every sentence is supported or connective passes, and check.json records the narration it passed", () => {
  const fx = run();
  const r = runCheck(fx);
  assert.equal(r.code, 0, r.out + r.err);
  assert.equal(gate(r, "cites"), "pass");
  assert.equal(gate(r, "support"), "pass");
  assert.match(r.out, /^script: 2 pass, 0 fail, 0 warn$/m);
  assert.match(record(fx).passed, /^[0-9a-f]{16}$/);
});

test("a scene without cites, a cites list of another length, or a cite outside the pack fails cites", () => {
  const scenes = cited(SCENES, CITES);
  delete scenes[2].cites;
  scenes[1].cites = [["ex-2"]];
  scenes[0].cites = [["ex-9"]];
  const fx = run(scenes, null);
  const r = runCheck(fx);
  assert.equal(r.code, 1);
  assert.equal(
    gate(r, "cites"),
    "fail: hook 1: ex-9 is not in excerpts.json; context: 2 sentence(s), 1 cites list(s); recap: no cites, one list of excerpt ids per sentence, [] for a sentence stating no fact",
  );
  assert.equal(record(fx).passed, undefined);
});

test("a cited sentence its excerpts do not support, or an uncited one stating a fact, fails support: attempt 1, again 1, a new set 2, then stop", () => {
  const scenes = cited(SCENES, CITES);
  const fx = run(scenes, { "hook 1": "unsupported", "recap 1": "unmarked" });
  let r = runCheck(fx);
  assert.equal(r.code, 1);
  assert.equal(
    gate(r, "support"),
    "fail: hook 1 unsupported: fixture; recap 1 unmarked: fixture",
  );
  assert.match(
    r.out,
    /^script: 1 pass, 1 fail, 0 warn; next: fix attempt 1 of 2$/m,
  );
  assert.match(runCheck(fx).out, /; next: fix attempt 1 of 2$/m);
  // the narration rewritten: a new verdict set is the next attempt
  const fixed = scenes.map((s) =>
    s.id === "recap" ? { ...s, narration: ["It ends where it began."] } : s,
  );
  write(fx, fixed);
  judge(fx, fixed, { "hook 1": "unsupported" });
  assert.match(runCheck(fx).out, /; next: fix attempt 2 of 2$/m);
  const again = fixed.map((s) =>
    s.id === "hook"
      ? { ...s, narration: ["Ship drives an issue to a merge."] }
      : s,
  );
  write(fx, again);
  judge(fx, again, { "hook 1": "unsupported" });
  r = runCheck(fx);
  assert.equal(r.code, 1);
  assert.match(r.out, /; stop: unsupported claims after two fix attempts$/m);
});

test("no support.json, one older than excerpts.json, or one judging other words fails support with what to run", () => {
  const scenes = cited(SCENES, CITES);
  const fx = run(scenes, null);
  assert.equal(
    gate(runCheck(fx), "support"),
    "fail: no support.json: run the support check",
  );
  judge(fx, scenes);
  const later = new Date(Date.now() + 5000);
  fs.utimesSync(path.join(fx.dir, "excerpts.json"), later, later);
  assert.equal(
    gate(runCheck(fx), "support"),
    "fail: support.json predates excerpts.json: run the support check",
  );
  judge(fx, scenes);
  fs.utimesSync(path.join(fx.dir, "support.json"), later, later);
  write(
    fx,
    scenes.map((s) =>
      s.id === "hook" ? { ...s, narration: ["Ship drives one issue."] } : s,
    ),
  );
  const r = runCheck(fx);
  assert.equal(r.code, 1);
  assert.equal(
    gate(r, "support"),
    "fail: hook 1 not judged: run the support check",
  );
});

test("an unchanged sentence judged again keeps its first verdict, and a different one warns as drift", () => {
  const scenes = cited(SCENES, CITES);
  const fx = run(scenes);
  assert.equal(runCheck(fx).code, 0);
  judge(fx, scenes, { "hook 1": "unsupported" });
  const r = runCheck(fx);
  assert.equal(r.code, 0, r.out);
  assert.equal(
    gate(r, "support"),
    "warn: hook 1 drift: judged unsupported on unchanged words, kept supported",
  );
  assert.match(r.out, /^script: 1 pass, 0 fail, 1 warn$/m);
});

test("a run folder with no excerpts.json is refused by name", () => {
  const fx = fixture(cited(SCENES, CITES));
  const r = runCheck(fx);
  assert.equal(r.code, 1);
  assert.match(r.err, /^script: no excerpts\.json: run the source stage first/);
  assert.equal(r.out, "");
});
