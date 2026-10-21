// A draft profile's grammar: the fields measured from a reference video, the
// ones the agent judged from its frame strips, and the marks that say which.
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { measuredFields } from "../../skills/explainer-video/scripts/style/grammar.mjs";
import { candidates, fixture, loads, node } from "./style-lib.mjs";

// A run measured from a fake video, its roles written from the colours the
// frames show, and the agent's judged fields when it wrote any. Returns the
// draft run's result and the profile it wrote.
function drafted(config, judged) {
  const { run, docs, env } = fixture();
  if (config) {
    fs.writeFileSync(path.join(docs, "talk.mp4"), "mp4");
    env.EXPLAINER_VIDEO_FAKE_VIDEO = JSON.stringify({ "talk.mp4": config });
  } else {
    fs.writeFileSync(path.join(docs, "deck.pdf"), "pdf");
  }
  const m = node(
    "measure.mjs",
    [run, path.join(docs, config ? "talk.mp4" : "deck.pdf")],
    env,
  );
  assert.equal(m.status, 0, m.stderr);
  const c = candidates(run);
  const by = (hex) =>
    [...c.surfaces, ...c.accents].find((x) => x.hex === hex).id;
  const dir = path.join(run, "style-draft");
  fs.writeFileSync(
    path.join(dir, "roles.json"),
    JSON.stringify({
      bg: { candidate: by("#f5f4ed"), why: "ground" },
      text: { candidate: by("#141413"), why: "text" },
    }),
  );
  if (judged)
    fs.writeFileSync(path.join(dir, "grammar.json"), JSON.stringify(judged));
  const r = node("draft.mjs", [run, "talk"], env);
  const file = path.join(dir, "talk.json");
  return {
    r,
    file,
    profile: fs.existsSync(file)
      ? JSON.parse(fs.readFileSync(file, "utf8"))
      : null,
  };
}

const REEL = { duration: 6, cuts: [2, 4], blur: 0.7, grain: 0.5 };

test("a reference video's motion becomes the seam and grain fields, each marked measured", () => {
  const { r, file, profile } = drafted(REEL);
  assert.equal(r.status, 0, r.stderr);
  const { seams, texture } = profile.grammar;
  assert.equal(seams.family, "velocity");
  assert.ok(seams.blur >= 8 && seams.blur <= 24, `blur ${seams.blur}`);
  // 20 cuts a minute sits between the slowest (0.4 s) and the fastest (0.2 s).
  assert.equal(seams.duration, 0.28);
  assert.ok(
    texture.grain > 0.1 && texture.grain < 0.2,
    `grain ${texture.grain}`,
  );
  for (const f of [
    "seams.family",
    "seams.blur",
    "seams.duration",
    "texture.grain",
  ])
    assert.equal(profile.grammarMarks[f].mark, "measured", f);
  assert.match(profile.grammarMarks["seams.duration"].why, /20 cuts\/min/);
  assert.match(
    r.stdout,
    /^style grammar seams\.duration: 0\.28 · measured · /m,
  );
  // The draft loads as schema 2.
  assert.equal(loads(file, "talk").schema, 2);
});

test("a seam's length clamps at 6 and 30 cuts a minute, and the blur is plain under 2 px", () => {
  const at = (cutsPerMinute, blurAtCuts) =>
    measuredFields({ cutsPerMinute, blurAtCuts, grain: 0 });
  assert.equal(at(3, 0.5)["seams.duration"].value, 0.4);
  assert.equal(at(6, 0.5)["seams.duration"].value, 0.4);
  assert.equal(at(30, 0.5)["seams.duration"].value, 0.2);
  assert.equal(at(90, 0.5)["seams.duration"].value, 0.2);
  assert.equal(at(20, 1 / 24)["seams.family"].value, "cut");
  assert.equal(at(20, 2 / 24)["seams.family"].value, "velocity");
  assert.equal(at(20, 2 / 24)["seams.blur"].value, 2);
});

test("a video with no blur at its cuts is a plain cut, and says only that", () => {
  const { r, profile } = drafted({ duration: 6, cuts: [2, 4], grain: 0.5 });
  assert.equal(r.status, 0, r.stderr);
  assert.deepEqual(profile.grammar.seams, { family: "cut" });
  // The cut rate has no field of its own then, so the family's reason holds it.
  assert.match(profile.grammarMarks["seams.family"].why, /20 cuts\/min/);
  assert.deepEqual(Object.keys(profile.grammarMarks).sort(), [
    "seams.family",
    "texture.grain",
  ]);
});

test("the agent's judged fields join the draft marked judged", () => {
  const { r, file, profile } = drafted(REEL, {
    "camera.family": { value: "locked", why: "the strips show no push-in" },
    layout: { value: "bands", why: "a header band sits over every shot" },
    "texture.surface": { value: "flat", why: "no glass in the strips" },
  });
  assert.equal(r.status, 0, r.stderr);
  assert.equal(profile.grammar.camera.family, "locked");
  assert.equal(profile.grammar.layout, "bands");
  assert.equal(profile.grammar.texture.surface, "flat");
  // The judged surface sits beside the measured grain, not over it.
  assert.ok(profile.grammar.texture.grain > 0.1);
  assert.deepEqual(profile.grammarMarks["camera.family"], {
    mark: "judged",
    why: "the strips show no push-in",
  });
  assert.equal(profile.grammarMarks["seams.blur"].mark, "measured");
  assert.match(r.stdout, /^style grammar layout: bands · judged · /m);
  assert.equal(loads(file, "talk").grammar.layout, "bands");
});

test("a draft from screenshots keeps the bundled grammar, and a judged field alone is marked judged", () => {
  const none = drafted(null);
  assert.equal(none.r.status, 0, none.r.stderr);
  assert.equal(none.profile.grammar, undefined);
  assert.equal(none.profile.grammarMarks, undefined);

  const some = drafted(null, {
    ease: { value: "soft", why: "every move eases out slowly" },
  });
  assert.equal(some.r.status, 0, some.r.stderr);
  assert.equal(some.profile.grammar.ease, "soft");
  assert.equal(some.profile.grammarMarks.ease.mark, "judged");
});

test("a judged field is refused when it is unknown, unexplained, measured already or out of range", () => {
  const cases = [
    [
      { "camera.zoom": { value: 1, why: "x" } },
      /camera\.zoom: not a grammar field/,
    ],
    [{ ease: { value: "soft" } }, /ease: needs a one-line why/],
    [
      { "seams.blur": { value: 4, why: "looks sharp" } },
      /seams\.blur: measured from the video/,
    ],
    [{ "camera.scale": { value: 2, why: "big push" } }, /camera/],
  ];
  for (const [judged, want] of cases) {
    const { r, profile } = drafted(REEL, judged);
    assert.equal(r.status, 1, JSON.stringify(judged));
    assert.match(r.stderr, want);
    assert.equal(profile, null);
  }
});
