// The sounds gate: each sound the gates judge is one the render plays at that
// start, a static <audio> at its scene file's start, a script-created one at
// its live start in video seconds (the canned backend's markers are in
// fake-backend-gates.mjs).
import { test } from "node:test";
import assert from "node:assert/strict";
import {
  compose,
  gateLine,
  only,
  runGates,
  timed,
  timeline,
} from "./gates-lib.mjs";

const warns = (r, name) =>
  [...r.out.matchAll(new RegExp(`^warn ${name}: (.*)$`, "gm"))].map(
    (m) => m[1],
  );
// The context scene, which starts after the hook, with one tween at 0 to 0.3 s.
function context(audio) {
  const fx = timed();
  const { start } = timeline(fx).scenes[1];
  compose(
    fx,
    "context",
    `<p>a line</p><i data-tween="0-0.3"></i>${audio(start)}`,
  );
  return runGates(fx);
}

test("a static <audio> whose start its script moves fails sounds, naming the scene, the id and both starts", () => {
  const r = context(
    () => '<audio id="ding" data-sound="0.5" data-moved="1.5"></audio>',
  );
  assert.equal(r.code, 1, r.out + r.err);
  only(r, "sounds");
  assert.equal(
    gateLine(r, "sounds"),
    'fail: 1 finding(s), first: context: <audio id="ding"> starts at 0.5 s in its scene file and 1.5 s after its script ran: the render plays 0.5 s, so create the sound in the script instead vs every sound plays where the gates judge it',
  );
});

test("the same sound created by the script at the scene's start plus 1.5 s passes sounds, and effect onset judges it at 1.5 s", () => {
  const r = context(
    (start) =>
      `<audio id="ding" data-created="${(start + 1.5).toFixed(3)}"></audio>`,
  );
  assert.equal(r.code, 0, r.out + r.err);
  assert.match(gateLine(r, "sounds"), /^pass: /);
  assert.deepEqual(warns(r, "effect onset"), [
    "context: the sound at 1.50 s is 1.50 s from the nearest tween start",
  ]);
});

test("a static <audio> no script touches passes sounds", () => {
  const r = context(() => '<audio id="ding" data-sound="0.1"></audio>');
  assert.equal(r.code, 0, r.out + r.err);
  assert.match(gateLine(r, "sounds"), /^pass: /);
  assert.deepEqual(warns(r, "effect onset"), []);
});

test("a created <audio> with no id, or with an id another <audio> carries, fails sounds", () => {
  const unnamed = context(
    (start) => `<audio data-created="${start + 0.1}"></audio>`,
  );
  assert.equal(unnamed.code, 1);
  only(unnamed, "sounds");
  assert.match(
    gateLine(unnamed, "sounds"),
    /first: context: an <audio> with no id: the render cannot place it, so give it an id vs /,
  );
  const fx = timed({
    hook: '<p>a line</p><audio id="ding" data-sound="0.1"></audio>',
  });
  const { start } = timeline(fx).scenes[1];
  compose(
    fx,
    "context",
    `<p>a line</p><audio id="ding" data-created="${start + 0.1}"></audio>`,
  );
  const shared = runGates(fx);
  assert.equal(shared.code, 1);
  only(shared, "sounds");
  assert.match(
    gateLine(shared, "sounds"),
    /first: context: <audio id="ding"> is created by its script with an id another <audio> carries: the render drops it, so give it an id no other <audio> has vs /,
  );
});
