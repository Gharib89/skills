// Velocity seams: the plan that picks each scene's seam, the tweens a scene
// draws for it, and the render's timeline and composition with the slots a
// seam extends.
import { test } from "node:test";
import assert from "node:assert/strict";
import vm from "node:vm";
import {
  grammar,
  validate,
} from "../../skills/explainer-video/scripts/lib/style.mjs";
import { sceneFile } from "../../skills/explainer-video/scripts/render/compose.mjs";
import {
  seamPlan,
  slot,
} from "../../skills/explainer-video/scripts/render/seams.mjs";
import { SCRIPT } from "./scene-file.mjs";
import {
  comp,
  fixture,
  profiled,
  read,
  render,
  skill,
  stage,
} from "./render-lib.mjs";

const claude = JSON.parse(read(skill, "styles", "claude-code.json"));
const styled = (seams, extra = {}) => ({
  ...claude,
  grammar: { seams, ...extra },
});
const scenes = (...roles) =>
  roles.map((role) => ({ role, visual: { component: "title" } }));

// SCRIPT with an arc: a hook, then two scenes of one point.
const ARC = SCRIPT.replace("target: about fifteen seconds", "role: hook · 15 s")
  .replace(
    "## Scene steps · The steps\n",
    "## Scene steps · The steps\nrole: point · 15 s\n",
  )
  .replace(
    "## Scene gate · The gate\n",
    "## Scene gate · The gate\nrole: point · 15 s\n",
  );

test("the composer picks a zoom-through at a beat change and a cut on a curve inside a beat", () => {
  const plan = seamPlan(scenes("hook", "point", "point", "recap"), claude);
  assert.deepEqual(
    plan.map((p) => p.out?.move ?? null),
    ["zoom-through", "cut-the-curve", "zoom-through", null],
  );
  // a scene's seam in is the seam out of the scene before it
  assert.deepEqual(
    plan.map((p) => p.in?.move ?? null),
    [null, "zoom-through", "cut-the-curve", "zoom-through"],
  );
  // with no arc to read, a scene opens its own beat
  assert.equal(
    seamPlan(scenes(undefined, undefined), claude)[0].out.move,
    "zoom-through",
  );
});

test("a seam is whole frames, its blur the family's, and a scene's own seam wins", () => {
  const [zoom, curve] = seamPlan(scenes("hook", "point", "point"), claude);
  assert.deepEqual(zoom.out, {
    move: "zoom-through",
    frames: 6,
    duration: 0.2,
    blur: 18,
  });
  assert.equal(curve.out.blur, 8);
  const [wide] = seamPlan(
    scenes("hook", "point"),
    styled({ duration: 0.25, blur: 0 }),
  );
  assert.deepEqual(wide.out, {
    move: "zoom-through",
    frames: 8,
    duration: 0.266666,
    blur: 0,
  });
  const own = [
    { role: "hook", visual: { component: "title", seam: "cut-the-curve" } },
    { role: "point", visual: { component: "title", seam: "cut" } },
    { role: "point", visual: { component: "title" } },
  ];
  assert.deepEqual(
    seamPlan(own, claude).map((p) => p.out?.move ?? null),
    ["cut-the-curve", null, null],
  );
  // the cut family draws none
  assert.deepEqual(
    seamPlan(scenes("hook", "point"), styled("cut")).map((p) => p.out),
    [null, null],
  );
  assert.equal(slot(249, { out: zoom.out }), 8.5);
  assert.equal(slot(249, { out: null }), 8.299999);
});

// A scene's seam tweens, `[from, to, at]` each on `.content`, and its labels.
const drawn = async (seam, { dir = "ltr", profile = claude } = {}) => {
  const scene = {
    id: "a",
    narration: ["Hi."],
    visual: { component: "title", props: { title: "T" } },
  };
  const timing = { duration: 3, slot: 3.2, sentences: [0.1], words: [0.1] };
  const html = await sceneFile(scene, timing, profile, {
    backend: {},
    dir,
    seam,
  });
  return {
    html,
    tweens: [
      ...html.matchAll(
        /tl\.fromTo\('[^']*\.content', (\{.*?\}), (\{.*?\}), ([\d.]+)\);/g,
      ),
    ].map((m) => [JSON.parse(m[1]), JSON.parse(m[2]), +m[3]]),
    labels: [...html.matchAll(/addLabel\("(seam:\w+)", ([\d.]+)\)/g)].map(
      (m) => [m[1], +m[2]],
    ),
  };
};
const zoom = { move: "zoom-through", frames: 6, duration: 0.2, blur: 18 };
const curve = { move: "cut-the-curve", frames: 6, duration: 0.2, blur: 8 };

test("a zoom-through exits to 1.2 under power3.in from the scene's end and enters from 0.75 under expo.out", async () => {
  const { tweens, labels, html } = await drawn({ in: zoom, out: zoom });
  assert.deepEqual(tweens, [
    [
      { scale: 0.75, opacity: 0, filter: "blur(18px)" },
      {
        scale: 1,
        opacity: 1,
        filter: "blur(0px)",
        duration: 0.2,
        ease: "expo.out",
        clearProps: "all",
      },
      0,
    ],
    [
      { scale: 1, opacity: 1, filter: "blur(0px)" },
      {
        scale: 1.2,
        opacity: 0,
        filter: "blur(18px)",
        duration: 0.2,
        ease: "power3.in",
        immediateRender: false,
      },
      3,
    ],
  ]);
  assert.deepEqual(labels, [
    ["seam:start", 0],
    ["seam:end", 0.2],
    ["seam:start2", 3],
    ["seam:end2", 3.2],
  ]);
  // the template runs for the slot, the seam out included
  assert.match(
    html,
    /data-composition-id="a" data-width="1920" data-height="1080" data-duration="3.2"/,
  );
});

test("a cut on a curve slides 13 percent along the reading direction with 8 px of blur", async () => {
  const ltr = await drawn({ in: curve, out: curve });
  assert.deepEqual(ltr.tweens[0][0], {
    xPercent: 13,
    opacity: 0,
    filter: "blur(8px)",
  });
  assert.deepEqual(ltr.tweens[0][1].ease, "power4.out");
  assert.deepEqual(ltr.tweens[1][1].xPercent, -13);
  assert.deepEqual(ltr.tweens[1][1].ease, "power2.in");
  const rtl = await drawn({ in: curve, out: curve }, { dir: "rtl" });
  assert.equal(rtl.tweens[0][0].xPercent, -13);
  assert.equal(rtl.tweens[1][1].xPercent, 13);
});

test("a seam with no blur sets no filter, and a scene with no seam draws none", async () => {
  const flat = await drawn({ out: { ...zoom, blur: 0 } });
  assert.equal(JSON.stringify(flat.tweens).includes("filter"), false);
  const none = await drawn({});
  assert.deepEqual(none.tweens, []);
  assert.doesNotMatch(none.html, /seam:/);
});

// The scene's script run as a stills page runs it, against a stub timeline
// that records where it is seeked: `reveals` is when its last reveal lands.
const seeked = async (seam, reveals) => {
  const at = [];
  const tl = {
    fromTo: () => {},
    addLabel: () => tl,
    duration: () => reveals,
    time: (t) => at.push(t),
  };
  const { html } = await drawn(seam);
  vm.runInNewContext(html.match(/<script>([\s\S]*?)<\/script>/)[1], {
    gsap: { timeline: () => tl },
    window: { __stills: true },
  });
  return at;
};

test("a stills page seeks each scene to its fullest moment: every reveal landed, the exit not begun", async () => {
  // the seam is in the timeline the still seeks, so the timeline's end is no
  // longer the still's moment: the reveals' last landing is
  assert.deepEqual(await seeked({ in: zoom, out: zoom }, 2.4), [2.4]);
  assert.deepEqual(await seeked({}, 2.4), [2.4]);
  // a reveal landing past the scene's own end (3 s) leaves the still at that
  // end, where the exit starts
  assert.deepEqual(await seeked({ in: zoom, out: zoom }, 3.4), [3]);
  // a scene whose reveals land inside the entry, or that has none, is seeked
  // to the entry's end: earlier the content is still fading in
  assert.deepEqual(await seeked({ in: zoom, out: zoom }, 0.1), [0.2]);
  assert.deepEqual(await seeked({ in: zoom, out: zoom }, 0), [0.2]);
  assert.deepEqual(await seeked({ in: zoom, out: zoom }, 0.2), [0.2]);
});

test("compiling the fixture keeps every scene start and extends each outgoing slot by its seam", () => {
  const run = (grammar) => {
    const fx = fixture(ARC.replace("style: claude-code", "style: odd"));
    profiled(fx, "odd", { grammar });
    const r = render(fx);
    assert.equal(r.code, 0, r.out + r.err);
    return { fx, timeline: JSON.parse(read(fx.dir, "timeline.json")) };
  };
  const cut = run({ seams: "cut" });
  const vel = run({});
  assert.deepEqual(
    vel.timeline.scenes.map((s) => s.start),
    cut.timeline.scenes.map((s) => s.start),
  );
  assert.equal(vel.timeline.total, cut.timeline.total);
  // no narration time moves either
  assert.deepEqual(
    vel.timeline.scenes.map((s) => s.words),
    cut.timeline.scenes.map((s) => s.words),
  );
  assert.deepEqual(
    cut.timeline.scenes.map((s) => [s.slot - s.duration, s.seam]),
    [
      [0, "cut"],
      [0, "cut"],
      [0, "cut"],
    ],
  );
  const { scenes } = vel.timeline;
  assert.deepEqual(
    scenes.map((s) => s.seam),
    ["zoom-through", "cut-the-curve", "cut"],
  );
  assert.deepEqual(
    scenes.map((s) => +(s.slot - s.duration).toFixed(6)),
    [0.2, 0.2, 0],
  );
  // the page mounts each scene for its slot
  const hosts = [
    ...comp(vel.fx).matchAll(
      /data-start="([\d.]+)" data-duration="([\d.]+)" data-track-index="1"><\/div>/g,
    ),
  ];
  assert.deepEqual(
    hosts.map((m) => +m[1]),
    scenes.map((s) => s.start),
  );
  assert.deepEqual(
    hosts.map((m) => +m[2]),
    scenes.map((s) => s.slot),
  );
  for (const s of scenes)
    assert.match(
      comp(vel.fx, `scenes/${s.id}.html`),
      new RegExp(`data-duration="${s.slot}"`),
    );
});

test("compile refuses a scene seam outside the profile's seams family and cut", () => {
  const text = (seam) =>
    SCRIPT.replace("style: claude-code", "style: odd").replace(
      '"props": { "kicker": "Ship"',
      `"seam": "${seam}", "props": { "kicker": "Ship"`,
    );
  const compile = (seam, seams) => {
    const fx = fixture(text(seam));
    profiled(fx, "odd", { grammar: { seams } });
    return stage(fx, "script/compile.mjs");
  };
  const refused = compile("zoom-through", "cut");
  assert.equal(refused.code, 1);
  assert.match(
    refused.err,
    /compile: hook: seam zoom-through is not one of cut: the moves of style profile odd's seams family cut/,
  );
  assert.equal(compile("whip", "velocity").code, 1);
  // a seam that is not a name is refused before the family is asked
  const named = SCRIPT.replace("style: claude-code", "style: odd").replace(
    '"props": { "kicker": "Ship"',
    '"seam": 3, "props": { "kicker": "Ship"',
  );
  const fx = fixture(named);
  profiled(fx, "odd", { grammar: {} });
  const bad = stage(fx, "script/compile.mjs");
  assert.equal(bad.code, 1);
  assert.match(bad.err, /seam is not a name like zoom-through/);
  for (const [seam, seams] of [
    ["cut", "cut"],
    ["cut-the-curve", "velocity"],
    ["zoom-through", "velocity"],
  ])
    assert.equal(compile(seam, seams).code, 0, `${seam} in ${seams}`);
  // the family is the profile's to name, and the default is velocity
  assert.equal(grammar(validate(claude) ?? claude).seams.family, "velocity");
});
