// The render stage through its process door, part 4: soft and spring ease,
// profiles the grammar refuses, fetched fonts and Arabic scripts.
import { test } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import vm from "node:vm";
import { FPS } from "../../skills/explainer-video/scripts/render/compose.mjs";
import { grammar } from "../../skills/explainer-video/scripts/lib/style.mjs";
import { SLIDE } from "./fake-backend.mjs";
import { ARABIC, DIAGRAMS, SCRIPT } from "./scene-file.mjs";
import {
  at,
  calls,
  comp,
  fixture,
  near,
  profile,
  profiled,
  put,
  read,
  render,
  skill,
  tweens,
} from "./render-lib.mjs";

// A scene's script run against a stub GSAP that records each fromTo, with the
// timeline paused and nothing else on the page.
const played = (fx, id) => {
  const calls = [];
  const tl = {
    fromTo: (sel, from, to, t) => calls.push({ sel, from, to, t }),
    addLabel: () => tl,
    duration: () => 0,
    time: () => {},
  };
  const script = comp(fx, `scenes/${id}.html`).match(
    /<script>([\s\S]*?)<\/script>/,
  )[1];
  vm.runInNewContext(script, {
    gsap: { timeline: () => tl },
    window: { __stills: true },
  });
  return calls;
};

test("a spring profile renders: each reveal carries its class at its sentence, nothing on the clock", () => {
  const fx = fixture(DIAGRAMS.replace("style: claude-code", "style: bouncy"));
  profiled(fx, "bouncy", { grammar: { ease: "spring" } });
  const r = render(fx);
  assert.equal(r.code, 0, r.out + r.err);
  for (const id of ["flow", "sides", "gates", "code", "diff"]) {
    const html = comp(fx, `scenes/${id}.html`);
    assert.doesNotMatch(
      html,
      /transition|animation|@keyframes|setTimeout|setInterval|requestAnimationFrame|Date\.now|performance\.now|Math\.random/,
      id,
    );
    assert.match(html, /gsap\.timeline\(\{ paused: true \}\)/, id);
  }
  const classOf = (id, sel) =>
    tweens(fx, id)
      .find(([s]) => s === sel)
      ?.slice(3);
  const [t, cls] = classOf("flow", ".n1");
  assert.ok(near(t, at(fx, "flow", 2)));
  assert.equal(cls, "settle");
  assert.equal(classOf("flow", ".a1")[1], "snap");
  assert.equal(classOf("gates", ".i0")[1], "snap");
  assert.equal(classOf("gates", ".lt")[1], "land");
  // the springs are sampled on the scene's timeline: opacity never past 1, and
  // each settles before its scene's last frame
  const timeline = JSON.parse(read(fx.dir, "timeline.json"));
  for (const id of ["flow", "sides", "gates", "code", "diff"]) {
    const { duration } = timeline.scenes.find((s) => s.id === id);
    // the push-in is no reveal: it has no class and no rise
    const calls = played(fx, id).filter((c) => !c.sel.endsWith(".camera"));
    assert.ok(calls.length, id);
    for (const { from, to, t: start } of calls) {
      assert.ok(to.opacity === undefined || to.opacity <= 1, id);
      if (typeof to.ease !== "function") continue;
      assert.equal(to.ease(1), 1);
      assert.equal(to.ease(0), 0);
      assert.ok(
        start + to.duration <= duration - 1 / FPS,
        `${id} settles before the last frame of ${duration}`,
      );
      for (let p = 0; p <= 1; p += 0.01) assert.ok(to.ease(p) <= 1.2, id);
      assert.equal(from.y, 20);
      // the stills page seeks past where rise ends: in place, full size
      assert.equal(to.y, 0);
      assert.equal(to.scale ?? 1, 1);
    }
  }
});

test("a soft profile's scene carries no spring and its tweens are the old ones", () => {
  const fx = fixture(DIAGRAMS.replace("style: claude-code", "style: calm"));
  profiled(fx, "calm", { grammar: { ease: "soft" } });
  assert.equal(render(fx).code, 0);
  for (const id of ["flow", "sides", "gates", "code", "diff"]) {
    assert.doesNotMatch(comp(fx, `scenes/${id}.html`), /SPRING|settleTime/, id);
    // every reveal is the rise tween: a 4-slot entry from y 20 to 0 in 0.35 s
    const reveals = tweens(fx, id).filter(
      ([s]) => !/^\.(em|del|add)|path$/.test(s),
    );
    assert.ok(reveals.length, id);
    for (const [, from, to, t] of reveals) {
      assert.deepEqual(from, { opacity: 0, y: 20 }, id);
      assert.deepEqual(
        to,
        { opacity: 1, y: 0, duration: 0.35, ease: "power2.out" },
        id,
      );
      assert.equal(typeof t, "number", id);
    }
    assert.ok(
      tweens(fx, id).every((x) => x.length === 4),
      id,
    );
  }
  for (const f of ["claude-code", "itworx"])
    assert.equal(
      grammar(JSON.parse(read(skill, "styles", `${f}.json`))).ease,
      "velocity",
    );
});

for (const [name, extra, why] of [
  [
    "an unknown surface",
    { grammar: { texture: { surface: "neon" } } },
    /^render: style profile odd: grammar\.texture\.surface neon is not glass or flat or sketch/m,
  ],
  [
    "an unknown ease",
    { grammar: { ease: "bounce" } },
    /^render: style profile odd: grammar\.ease bounce is not velocity or soft or spring$/m,
  ],
  [
    "schema 1",
    { schema: 1, motion: "rise", look: "clean", effects: [] },
    /^render: style profile odd is schema 1.*motion.*look.*effects/m,
  ],
]) {
  test(`a profile naming ${name} refuses the run by name before any render`, () => {
    const fx = fixture(DIAGRAMS.replace("style: claude-code", "style: odd"));
    profiled(fx, "odd", extra);
    const r = render(fx);
    assert.equal(r.code, 1, r.out + r.err);
    assert.match(r.err, why);
    assert.equal(calls(fx).length, 0);
  });
}

test("a draft naming a family no setup row installs renders it from the font store its draft fetched it into", () => {
  const fx = fixture();
  const env = {
    ...fx.env,
    EXPLAINER_VIDEO_FAKE_PRESENT: "ffmpeg",
    EXPLAINER_VIDEO_FAKE_SITE: JSON.stringify({
      "https://acme.test/": {
        pages: [SLIDE],
        colors: [],
        fonts: [{ role: "text", stack: "'Noto Serif', serif" }],
      },
    }),
  };
  const acme = path.join(fx.tmp, "proj", "explainers", "acme");
  const style = (script, ...args) =>
    spawnSync(
      process.execPath,
      [path.join(skill, "scripts", "style", script), acme, ...args],
      { env, encoding: "utf8" },
    );
  let r = style("measure.mjs", "https://acme.test/");
  assert.equal(r.status, 0, r.stderr);
  put(
    path.join(acme, "style-draft"),
    "roles.json",
    JSON.stringify({
      bg: { candidate: "s1", why: "ground" },
      text: { candidate: "s3", why: "text" },
    }),
  );
  r = style("draft.mjs", "odd");
  assert.equal(r.status, 0, r.stderr);
  put(
    path.join(fx.tmp, "proj", "explainers", ".styles"),
    "odd.json",
    read(acme, "style-draft", "odd.json"),
  );
  put(fx.dir, "script.md", SCRIPT.replace("style: claude-code", "style: odd"));

  const done = render(fx);
  assert.equal(done.code, 0, done.out + done.err);
  assert.ok(
    fs
      .readdirSync(path.join(fx.dir, "composition", "fonts"))
      .includes("noto-serif-latin-400-normal.woff2"),
  );
  assert.match(
    comp(fx),
    /\.cue \{[^}]*font: 400 var\(--size-caption\)\/1\.3 "noto-serif"/,
  );
});

test("an Arabic script renders right to left on its text boxes, its English terms whole and left to right", () => {
  const fx = fixture(ARABIC);
  fx.env.GEMINI_API_KEY = "test-key";
  const r = render(fx);
  assert.equal(r.code, 0, r.out + r.err);

  const index = comp(fx);
  assert.match(index, /<html lang="ar">/);
  assert.doesNotMatch(index, /<(html|body)[^>]* dir=/);
  assert.doesNotMatch(index, /id="root"[^>]* dir=/);
  assert.doesNotMatch(index, /class="header"/);
  for (const family of ["noto-naskh-arabic", "ibm-plex-sans-arabic"])
    assert.match(index, new RegExp(`@font-face \\{ font-family: "${family}"`));
  assert.match(
    index,
    /\.cue \{[^}]*font: 400 var\(--size-caption\)\/1\.7 "ibm-plex-sans-arabic", "inter"/,
  );
  assert.match(index, /\.lat \{ font-family: "inter"; white-space: nowrap; \}/);
  const cues = [...index.matchAll(/<div class="cue clip"[^>]*>/g)];
  assert.ok(cues.length > 0);
  for (const [cue] of cues) assert.match(cue, / dir="rtl"/);
  // A multi-word term is one caption token, isolated, so it keeps its order.
  assert.match(
    index,
    /<span class="w" data-at="[\d.]+"><bdi class="lat">pull request<\/bdi><\/span>/,
  );

  const steps = comp(fx, "scenes/steps.html");
  assert.match(steps, /<div class="content" dir="rtl">/);
  assert.match(steps, /<bdi class="lat ti">branch<\/bdi>/);
  assert.match(steps, /\.label \{[^}]*"noto-naskh-arabic", "source-serif-4"/);
  const code = comp(fx, "scenes/code.html");
  assert.match(code, /<div class="code rt" dir="ltr">/);
  assert.doesNotMatch(code, /<bdi/);
  assert.match(
    comp(fx, "scenes/hook.html"),
    /<bdi class="lat ti">pull request<\/bdi>/,
  );
});
