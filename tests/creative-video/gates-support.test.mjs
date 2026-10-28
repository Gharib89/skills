// The support gate: the gates refuse a narration the claims check has not
// passed, so no claim reaches the render unjudged.
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { SCENES, write } from "./voice-lib.mjs";
import { cited } from "./support-lib.mjs";
import { gateLine, only, runGates, supported, timed } from "./gates-lib.mjs";

const FLOOR = "the claims check passed on this script and source pack";

test("a script the check passed passes the support gate", () => {
  const r = runGates(timed());
  assert.equal(r.code, 0, r.out + r.err);
  assert.equal(gateLine(r, "support"), `pass: 0 finding(s) vs ${FLOOR}`);
});

test("no claims.json, or one passed on other claims or another pack, fails support until the check passes again", () => {
  const fx = timed();
  fs.rmSync(path.join(fx.dir, "claims.json"));
  let r = runGates(fx);
  only(r, "support");
  assert.equal(
    gateLine(r, "support"),
    `fail: 1 finding(s), first: no claims.json: run source/claims.mjs vs ${FLOOR}`,
  );
  supported(fx);
  write(
    fx,
    cited(SCENES).map((s) =>
      s.id === "hook" ? { ...s, cites: [["ex-1"]] } : s,
    ),
  );
  r = runGates(fx);
  only(r, "support");
  assert.match(
    gateLine(r, "support"),
    /first: the claims check has not passed on this script and source pack: run source\/claims\.mjs/,
  );
  supported(fx);
  assert.equal(runGates(fx).code, 0);
  const pack = path.join(fx.dir, "excerpts.json");
  const p = JSON.parse(fs.readFileSync(pack, "utf8"));
  p.excerpts[0].text = "Ship drives two issues.";
  fs.writeFileSync(pack, JSON.stringify(p));
  only(runGates(fx), "support");
});

test("a narration edited after voicing fails support though the claims check passed on it", () => {
  const fx = timed();
  write(
    fx,
    cited(SCENES).map((s) =>
      s.id === "hook"
        ? {
            ...s,
            narration: ["Ship drives two issues to a merged pull request."],
          }
        : s,
    ),
  );
  supported(fx);
  const r = runGates(fx);
  only(r, "support");
  assert.equal(
    gateLine(r, "support"),
    `fail: 1 finding(s), first: scene hook's narration is not what voice.json voiced: run the voice stage again vs ${FLOOR}`,
  );
});

test("a scene dropped from the script after voicing fails support though the claims check passed on the rest", () => {
  const fx = timed();
  write(fx, cited(SCENES).slice(0, -1));
  supported(fx);
  const r = runGates(fx);
  only(r, "support");
  assert.equal(
    gateLine(r, "support"),
    `fail: 1 finding(s), first: voice.json voiced ${SCENES.length} scene(s), the script holds ${SCENES.length - 1}: run the voice stage again vs ${FLOOR}`,
  );
});
