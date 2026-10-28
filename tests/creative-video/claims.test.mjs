// The claims check: every narration sentence carries its cites, every cite is
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
  r.out.match(new RegExp(`^claims ${name}: (.*)$`, "m"))?.[1];
const record = (fx) => readJson(path.join(fx.dir, "claims.json"));

test("a script whose every sentence is supported or connective passes, and claims.json records the narration it passed", () => {
  const fx = run();
  const r = runCheck(fx);
  assert.equal(r.code, 0, r.out + r.err);
  assert.equal(gate(r, "cites"), "pass");
  assert.equal(gate(r, "support"), "pass");
  assert.match(r.out, /^claims: 2 pass, 0 fail, 0 warn$/m);
  assert.match(record(fx).passed, /^[0-9a-f]{16}$/);
});

test("a scene without cites, a cites list of another length, or a cite outside the pack fails cites", () => {
  for (const [scene, cites, why] of [
    [
      2,
      undefined,
      "recap: no cites, one list of excerpt ids per sentence, [] for a sentence stating no fact",
    ],
    [1, [["ex-2"]], "context: 2 sentence(s), 1 cites list(s)"],
    [0, [["ex-9"]], "hook 1: ex-9 is not in excerpts.json"],
  ]) {
    const scenes = cited(SCENES, CITES);
    scenes[scene].cites = cites;
    const fx = run(scenes, null);
    const r = runCheck(fx);
    assert.equal(r.code, 1);
    assert.equal(gate(r, "cites"), `fail: ${why}`);
    assert.equal(record(fx).passed, undefined);
  }
});

test("a cited sentence its excerpts do not support, or an uncited one stating a fact, fails support", () => {
  for (const [at, verdict] of [
    ["hook 1", "unsupported"],
    ["recap 1", "unmarked"],
  ]) {
    const r = runCheck(run(cited(SCENES, CITES), { [at]: verdict }));
    assert.equal(r.code, 1);
    assert.equal(gate(r, "support"), `fail: ${at} ${verdict}: fixture`);
    assert.match(
      r.out,
      /^claims: 1 pass, 1 fail, 0 warn; next: fix attempt 1 of 2$/m,
    );
  }
});

test("several failing sentences print on one support line, joined in narration order", () => {
  const r = runCheck(
    run(cited(SCENES, CITES), {
      "recap 1": "unmarked",
      "hook 1": "unsupported",
    }),
  );
  assert.equal(
    gate(r, "support"),
    "fail: hook 1 unsupported: fixture; recap 1 unmarked: fixture",
  );
});

test("a red support verdict is fix attempt 1, again 1, a new failing set 2, then stop", () => {
  const scenes = cited(SCENES, CITES);
  const fx = run(scenes, { "hook 1": "unsupported" });
  assert.match(runCheck(fx).out, /; next: fix attempt 1 of 2$/m);
  assert.match(runCheck(fx).out, /; next: fix attempt 1 of 2$/m);
  // the failing sentence rewritten: a new verdict set is the next attempt
  let r;
  for (const [words, line] of [
    ["Ship drives an issue to a merge.", /; next: fix attempt 2 of 2$/m],
    [
      "Ship drives one issue to a merge.",
      /; stop: unsupported claims after two fix attempts$/m,
    ],
  ]) {
    const next = scenes.map((s) =>
      s.id === "hook" ? { ...s, narration: [words] } : s,
    );
    write(fx, next);
    judge(fx, next, { "hook 1": "unsupported" });
    r = runCheck(fx);
    assert.equal(r.code, 1);
    assert.match(r.out, line);
  }
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
  assert.match(r.out, /^claims: 1 pass, 0 fail, 1 warn$/m);
});

test("a claims.json whose fix attempts are not a number is refused by name", () => {
  const fx = run(cited(SCENES, CITES), { "hook 1": "unsupported" });
  runCheck(fx);
  const c = record(fx);
  c.support.attempts = "one";
  fs.writeFileSync(path.join(fx.dir, "claims.json"), JSON.stringify(c));
  const r = runCheck(fx);
  assert.equal(r.code, 1);
  assert.match(
    r.err,
    /^claims: claims\.json: support\.attempts is not a number/,
  );
});

test("a run folder with no excerpts.json is refused by name", () => {
  const fx = fixture(cited(SCENES, CITES));
  const r = runCheck(fx);
  assert.equal(r.code, 1);
  assert.match(r.err, /^claims: no excerpts\.json: run the source stage first/);
  assert.equal(r.out, "");
});
