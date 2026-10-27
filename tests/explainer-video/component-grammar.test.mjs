// Every component against the style profile's grammar, over the fixture scenes
// of all of them: each declares the techniques a ban reaches it by, its
// composed output draws none it leaves out, and every reveal it plays (a tween
// from opacity 0) takes the profile's `grammar.ease`, but the ones the named
// exception list keeps on their own.
import { test } from "node:test";
import assert from "node:assert/strict";
import vm from "node:vm";
import { FIXTURE } from "../../skills/explainer-video/maintainer/real-render-fixture.mjs";
import { sceneFile } from "../../skills/explainer-video/scripts/render/compose.mjs";
import { OWN_EASE } from "../../skills/explainer-video/scripts/render/components.mjs";
import { words } from "../../skills/explainer-video/scripts/lib/props.mjs";
import {
  TECHNIQUES,
  VISUALS,
} from "../../skills/explainer-video/scripts/lib/visuals.mjs";
import { read, skill } from "./render-lib.mjs";
import { DIAGRAMS, SCRIPT } from "./scene-file.mjs";

const claude = JSON.parse(read(skill, "styles", "claude-code.json"));
const eased = (ease) => ({
  ...claude,
  grammar: { ...claude.grammar, ease },
});

// The scenes of a house Markdown scene file, as compile writes them: each
// sentence without its claim tags, the visual as its JSON block holds it.
const scenesOf = (md) =>
  md
    .split(/^## Scene /m)
    .slice(1)
    .map((s) => ({
      id: s.split(/\s/)[0],
      narration: [...s.matchAll(/^\d+\. (.*?)(?: \[[^\]]*\])+$/gm)].map((m) =>
        m[1].replaceAll("`", ""),
      ),
      visual: JSON.parse(s.match(/```json\n([\s\S]*?)\n```/)[1]),
    }));
const SCENES = [
  ...FIXTURE.map((f) => f.scene),
  ...scenesOf(SCRIPT),
  ...scenesOf(DIAGRAMS),
];

// Each spoken word 0.4 s after the last, the scene running on 6 s past its
// last word, room for a canvas's camera to pull back.
const timingOf = (narration) => {
  const counts = narration.map((s) => words(s).length);
  const total = counts.reduce((a, b) => a + b, 0);
  const sentences = counts.map(
    (_, i) => +(counts.slice(0, i).reduce((a, b) => a + b, 0) * 0.4).toFixed(6),
  );
  const duration = +(total * 0.4 + 6).toFixed(6);
  return {
    duration,
    slot: duration,
    sentences,
    words: Array.from({ length: total }, (_, i) => +(i * 0.4).toFixed(6)),
  };
};

const compose = (scene, profile) =>
  sceneFile(scene, timingOf(scene.narration), profile, {
    backend: {
      highlight: async (code) =>
        code.split("\n").map((l) => [{ text: l, color: "#000" }]),
    },
    seam: {},
  });

// Each tween the scene's script puts on its timeline, `[selector, from, to]`,
// run against a stub GSAP: a `to` has no from state, so it is never a reveal
// here. Whatever else the script reaches (WebGL, the page) is a stub too.
const tweens = (html, id) => {
  const out = [];
  const scope = `[data-composition-id="${id}"] `;
  const sel = (s) => String(s).replace(scope, "");
  const any = new Proxy(function () {}, {
    get: (t, k) => (k === Symbol.toPrimitive ? () => "" : any),
    apply: () => any,
    construct: () => any,
  });
  const tl = new Proxy(
    {
      fromTo: (s, from, to) => out.push([sel(s), from, to]),
      from: (s, from) => out.push([sel(s), from, from]),
      to: (s, to) => out.push([sel(s), {}, to]),
      duration: () => 0,
    },
    { get: (t, k) => t[k] ?? (() => any) },
  );
  vm.runInNewContext(html.match(/<script>([\s\S]*?)<\/script>/)[1], {
    gsap: { timeline: () => tl },
    window: { __stills: true },
    document: any,
    THREE: any,
    getComputedStyle: any,
  });
  return out;
};

test("every component declares its techniques, each one the profile may ban", () => {
  for (const [name, v] of Object.entries(VISUALS)) {
    assert.ok(Array.isArray(v.techniques), `${name} declares no techniques`);
    for (const t of v.techniques)
      assert.ok(Object.hasOwn(TECHNIQUES, t), `${name}: ${t} is no technique`);
  }
  // a technique's components are the ones declaring it, and no other list
  for (const [t, components] of Object.entries(TECHNIQUES))
    assert.deepEqual(
      components,
      Object.keys(VISUALS).filter((c) => VISUALS[c].techniques.includes(t)),
    );
});

test("the fixture scenes cover every component", () => {
  const covered = new Set(SCENES.map((s) => s.visual.component));
  assert.deepEqual(
    Object.keys(VISUALS).filter((c) => !covered.has(c)),
    [],
  );
});

test("a component whose output strokes lines on declares draw, and one drawing WebGL declares 3d", async () => {
  for (const scene of SCENES) {
    const c = scene.visual.component;
    const html = await compose(scene, claude);
    if (html.includes("strokeDashoffset"))
      assert.ok(
        VISUALS[c].techniques.includes("draw"),
        `${c} (scene ${scene.id}) strokes lines on but does not declare draw`,
      );
    if (VISUALS[c].webgl)
      assert.ok(
        VISUALS[c].techniques.includes("3d"),
        `${c} draws WebGL but does not declare 3d`,
      );
  }
});

// `soft` and `velocity` share no reveal ease, so every reveal taking the
// profile's moves between them. (`spring` fades opacity on `soft`'s ease, and
// its per-word rise is `velocity`'s: a spring has no opacity or per-word form.)
test("every reveal of every component takes the profile's ease, but the named exceptions", async () => {
  const own = new Set();
  for (const scene of SCENES) {
    const c = scene.visual.component;
    const soft = tweens(await compose(scene, eased("soft")), scene.id);
    const fast = tweens(await compose(scene, eased("velocity")), scene.id);
    assert.equal(soft.length, fast.length, `${c}: the tweens differ in number`);
    soft.forEach(([s, from, to], i) => {
      if (from.opacity !== 0) return;
      const kept = OWN_EASE.find((e) => e.component === c && e.target.test(s));
      if (kept) return own.add(kept);
      assert.notEqual(
        String(to.ease),
        String(fast[i][2].ease),
        `${c} (scene ${scene.id}): the reveal of ${s} keeps ${to.ease} under both soft and velocity`,
      );
    });
  }
  // an exception no reveal needs any more is gone from the list
  for (const e of OWN_EASE)
    assert.ok(own.has(e), `${e.component} ${e.target}: no reveal matches it`);
});

test("under velocity, the browser's typed words take the profile's ease", async () => {
  for (const scene of SCENES.filter((s) => s.visual.component === "browser")) {
    const typed = tweens(
      await compose(scene, eased("velocity")),
      scene.id,
    ).filter(([s]) => /^\.tw\d+$/.test(s));
    assert.ok(typed.length, `scene ${scene.id} types no words`);
    for (const [s, , to] of typed)
      assert.notEqual(to.ease, "power2.out", `${s} still eases power2.out`);
  }
});
