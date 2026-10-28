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
// The context scene, which starts after the hook, with one tween at 0 to 0.3 s;
// `audio` gets its start and end in video seconds.
function context(audio) {
  const fx = timed();
  const { start, duration } = timeline(fx).scenes[1];
  compose(
    fx,
    "context",
    `<p>a line</p><i data-tween="0-0.3"></i>${audio(start, start + duration)}`,
  );
  return runGates(fx);
}

test("a static <audio> whose start its script moves fails sounds, naming the scene, the id and both starts", () => {
  let at;
  const r = context((start) => {
    at = (start + 1.5).toFixed(3);
    return '<audio id="ding" data-sound="0.5" data-moved="1.5"></audio>';
  });
  assert.equal(r.code, 1, r.out + r.err);
  only(r, "sounds");
  assert.equal(
    gateLine(r, "sounds"),
    `fail: 1 finding(s), first: context: <audio id="ding"> starts at 0.5 s in its scene file and 1.5 s after its script ran: the render plays 0.5 s, so remove it from the scene file and create it in the script at data-start ${at} (the scene's start plus 1.5 s) vs every <audio> has an id and plays at its live data-start, in its scene`,
  );
});

test("a static <audio> moved by 1 ms fails sounds", () => {
  const r = context(
    () => '<audio id="ding" data-sound="0.5" data-moved="0.501"></audio>',
  );
  assert.equal(r.code, 1, r.out + r.err);
  only(r, "sounds");
});

test("a created <audio> at a scene-local start fails sounds; inside its scene, from 0.5 ms before its start to before its end, it passes", () => {
  const local = context(() => '<audio id="ding" data-created="0.1"></audio>');
  assert.equal(local.code, 1);
  only(local, "sounds");
  assert.match(
    gateLine(local, "sounds"),
    /first: context: <audio id="ding"> is created by its script at 0.1 s, outside its scene \(\d+\.\d{3} s to \d+\.\d{3} s\): a created <audio>'s data-start counts seconds of the whole video, so add TIMING.scenes\["context"\].start to it vs /,
  );
  for (const [at, code] of [
    [(start) => start - 0.0005, 0],
    [(start) => start - 0.001, 1],
    [(start, end) => end - 0.001, 0],
    [(start, end) => end, 1],
  ]) {
    const r = context(
      (start, end) =>
        `<audio id="ding" data-created="${at(start, end)}"></audio>`,
    );
    assert.equal(r.code, code, `${at}: ${r.out}${r.err}`);
    if (code) only(r, "sounds");
  }
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

test("an <audio> with no id, written or created, or a created one with an id another <audio> carries, fails sounds", () => {
  for (const audio of [
    () => '<audio data-sound="0.1"></audio>',
    (start) => `<audio data-created="${start + 0.1}"></audio>`,
  ]) {
    const unnamed = context(audio);
    assert.equal(unnamed.code, 1);
    only(unnamed, "sounds");
    assert.match(
      gateLine(unnamed, "sounds"),
      /first: context: an <audio> with no id: the render refuses one written in the scene file and never plays one a script created, so give it an id vs /,
    );
  }
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
    /first: context: <audio id="ding"> is created by its script with an id another <audio> carries: the render never plays it, so give it an id no other <audio> has vs /,
  );
});

test("over.html's sounds are judged too, across the whole video: a moved written start fails, a created one passes", () => {
  const moved = timed();
  compose(
    moved,
    "over",
    '<audio id="bed" data-sound="0" data-moved="2"></audio>',
  );
  const r = runGates(moved);
  assert.equal(r.code, 1, r.out + r.err);
  only(r, "sounds");
  assert.match(
    gateLine(r, "sounds"),
    /first: over: <audio id="bed"> starts at 0 s in its scene file and 2 s after its script ran: /,
  );
  const created = timed();
  compose(created, "over", '<audio id="bed" data-created="2"></audio>');
  const ok = runGates(created);
  assert.equal(ok.code, 0, ok.out + ok.err);
});

test("a created <audio> reusing a written one's id in the same scene fails sounds", () => {
  const r = context(
    (start) =>
      `<audio id="ding" data-sound="0.1"></audio><audio id="ding" data-created="${start + 0.1}"></audio>`,
  );
  assert.equal(r.code, 1, r.out + r.err);
  only(r, "sounds");
  assert.match(
    gateLine(r, "sounds"),
    /first: context: <audio id="ding"> is created by its script with an id another <audio> carries: /,
  );
});
