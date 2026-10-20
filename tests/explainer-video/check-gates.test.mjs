// The script check stage through its process door, part 1: the arc, the scene
// budget, cites and the support gate.
import { after, test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import {
  chars,
  sentences,
} from "../../skills/explainer-video/scripts/lib/length.mjs";
import {
  DOC,
  SCENES,
  check,
  edit,
  fixture,
  judge,
  line,
  reword,
  say,
  scripts,
  spoken,
} from "./check-lib.mjs";

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
    "script dashes: pass",
    "script sentences: pass",
    "script: 7 pass, 0 fail, 0 warn",
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

test("a scene runs 12 to 30 s, its spoken characters within 10 percent of its seconds less a pause a sentence at the narrator's rate, and the scenes and hold the brief's length", () => {
  let r = check(fixture({ scenes: edit(SCENES, 0, { seconds: 31 }) }));
  assert.equal(r.code, 1);
  assert.match(line(r, "budget"), /hook 31 s is outside 12 to 30 s/);
  assert.match(
    line(r, "budget"),
    /hook 147 spoken characters \(\{written\|spoken\} counts its spoken form\) vs 474 \(31 s less 3 sentences at 0\.78 s, at 16\.55 chars\/s\) ±10%/,
  );
  r = check(
    fixture({
      scenes: edit(SCENES, 2, { sentences: [say(12), say(12, "[no-claim]")] }),
    }),
  );
  assert.equal(
    line(r, "budget"),
    "script budget: fail: steps 98 spoken characters ({written|spoken} counts its spoken form) vs 173 (12 s less 2 sentences at 0.78 s, at 16.55 chars/s) ±10%",
  );
  // #725: `{304|three oh four}` counts its 12 spoken characters, not the 3
  // written ones, so the scene's 88 written characters are 96.
  r = check(
    fixture({
      scenes: edit(SCENES, 2, {
        sentences: [
          `A {304|three oh four} ${spoken(8)}. [ex-1]`,
          say(12, "[no-claim]"),
        ],
      }),
    }),
  );
  assert.equal(
    line(r, "budget"),
    "script budget: fail: steps 96 spoken characters ({written|spoken} counts its spoken form) vs 173 (12 s less 2 sentences at 0.78 s, at 16.55 chars/s) ±10%",
  );
  // Kokoro voices a sentence where a full stop, ! or ? meets a space, not a
  // numbered item: three items with no full stop run as one sentence, and one
  // item of three sentences as three.
  r = check(
    fixture({
      scenes: edit(SCENES, 2, {
        sentences: [
          `${spoken(12)} [ex-1]`,
          `${spoken(12)} [no-claim]`,
          `${spoken(12)} [ex-2, ex-3]`,
        ],
      }),
    }),
  );
  assert.equal(
    line(r, "budget"),
    "script budget: fail: steps 147 spoken characters ({written|spoken} counts its spoken form) vs 186 (12 s less 1 sentences at 0.78 s, at 16.55 chars/s) ±10%",
  );
  r = check(
    fixture({
      scenes: edit(SCENES, 2, {
        sentences: [`${spoken(12)}. ${spoken(12)}. ${spoken(12)}. [ex-1]`],
      }),
    }),
  );
  assert.equal(line(r, "budget"), "script budget: pass");
  r = check(fixture({ scenes: edit(SCENES, 0, { seconds: 0 }) }));
  assert.match(line(r, "budget"), /hook 0 s is outside 12 to 30 s/);
  r = check(fixture({ brief: ["length=2", "must=local gate"] }));
  assert.equal(
    line(r, "budget"),
    "script budget: fail: the scenes run 60 s and the 1 s hold vs the brief's 120 s ±10%",
  );
  // 66 s of scenes is at the edge of a one-minute brief's band: the hold
  // takes it past.
  r = check(
    fixture({
      scenes: edit(SCENES, 2, {
        seconds: 18,
        sentences: [say(20), say(20, "[no-claim]"), say(20, "[ex-2, ex-3]")],
      }),
    }),
  );
  assert.equal(
    line(r, "budget"),
    "script budget: fail: the scenes run 66 s and the 1 s hold vs the brief's 60 s ±10%",
  );
});

// #783: Kokoro speaks a near-constant number of characters a second, whatever
// the words' length, so two scenes of the same characters budget the same.
test("the budget counts a scene's spoken characters, so a short-word scene and a long-word scene of the same characters both pass, and one off by over 10 percent fails naming characters", () => {
  const { rate, pause } = JSON.parse(
    fs.readFileSync(path.join(scripts, "..", "narrators.json"), "utf8"),
  ).narrators.find((n) => n.id === "bf_emma");
  const each = ((12 - 3 * pause) * rate) / 3;
  const of = (word) =>
    Array(Math.round(each / word.length))
      .fill(word)
      .join(" ");
  const scene = (word) => ({
    sentences: [
      `${of(word)}. [ex-1]`,
      `${of(word)}. [no-claim]`,
      `${of(word)}. [ex-2, ex-3]`,
    ],
  });
  const short = of("pod").split(" ").length;
  const long = of("kubernetes").split(" ").length;
  assert.ok(short > long * 1.1, `${short} vs ${long} words`);
  let r = check(
    fixture({
      scenes: edit(edit(SCENES, 2, scene("pod")), 3, scene("kubernetes")),
    }),
  );
  assert.equal(line(r, "budget"), "script budget: pass");
  r = check(
    fixture({ scenes: edit(SCENES, 2, { ...scene("pod"), seconds: 15 }) }),
  );
  assert.match(
    line(r, "budget"),
    new RegExp(
      `^script budget: fail: steps ${3 * short * 3} spoken characters \\(\\{written\\|spoken\\} counts its spoken form\\) vs \\d+ \\(15 s less 3 sentences at ${pause} s, at ${rate} chars/s\\) ±10%$`,
    ),
  );
});

test("the spoken characters are its letters and digits in any script, not its spaces or punctuation", () => {
  assert.equal(chars("Git's 304, ok? نعم!"), 12);
});

test("a sentence ends where a full stop, ! or ? meets a space, so one closed inside quotes ends none, and at an Arabic question mark", () => {
  assert.equal(sentences('He said "Ship it." Then the merge began.').length, 1);
  assert.equal(sentences("مين يقدر يغير؟ ولا حد! كل تغيير بيعدي.").length, 3);
});

test("every cite names an excerpt still word for word in its snapshot", () => {
  let fx = fixture({
    scenes: edit(SCENES, 1, {
      sentences: [say(10, "[ex-9]"), say(10), say(10)],
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
  assert.match(r.out, /^script: 6 pass, 1 fail, 0 warn$/m);

  judge(fx, { "steps 1": "unsupported" });
  r = check(fx);
  assert.equal(
    line(r, "support"),
    "script support: fail: steps 1 unsupported: fixture",
  );
  assert.match(
    r.out,
    /^script: 6 pass, 1 fail, 0 warn; next: fix attempt 1 of 2$/m,
  );
  // The same verdicts judged again are not another attempt.
  r = check(fx);
  assert.match(r.out, /; next: fix attempt 1 of 2$/m);

  reword(fx, "steps 1", "steps 2");
  judge(fx, { "steps 2": "unmarked" });
  assert.match(check(fx).out, /; next: fix attempt 2 of 2$/m);
  reword(fx, "hook 1");
  judge(fx, { "hook 1": "unsupported", "steps 2": "unmarked" });
  r = check(fx);
  assert.equal(r.code, 1);
  assert.match(r.out, /; stop: unsupported claims after two fix attempts$/m);

  // A third rewrite brings no third attempt: the stop holds until it passes.
  reword(fx, "why 1");
  judge(fx, {
    "why 1": "unsupported",
    "hook 1": "unsupported",
    "steps 2": "unmarked",
  });
  assert.match(
    check(fx).out,
    /; stop: unsupported claims after two fix attempts$/m,
  );

  reword(fx, "why 1", "hook 1", "steps 2");
  judge(fx);
  r = check(fx);
  assert.equal(r.code, 0, r.out);
  const rec = JSON.parse(
    fs.readFileSync(path.join(fx.dir, "check.json"), "utf8"),
  );
  assert.equal(rec.support.attempts, 0);
});
