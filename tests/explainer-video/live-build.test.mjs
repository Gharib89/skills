// The live build: the composition Render draws, made into one document a
// sandboxed frame plays, and the script inside the frame that seeks it.
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import vm from "node:vm";
import { board, doc, fixture, ok, prep, read, skill } from "./board-lib.mjs";

// The build asset as the page loads it: a script setting window.__build.
const loaded = (fx) => {
  const win = {};
  vm.runInNewContext(read(fx.dir, doc(fx, 1).build), { window: win });
  return win.__build;
};

test("the build is the composition made self-contained: scenes inline, fonts apart, narration left out, its own script last", () => {
  const fx = fixture();
  prep(fx);
  ok(board(fx, "build"), "build");
  const { html, fonts } = loaded(fx);
  // the narration element is the page's to play, so its window is not the build's
  const comp = read(fx.dir, "composition", "index.html").replace(
    / *<audio.*\n/,
    "",
  );
  // nothing is fetched: a frame with no origin has nothing to fetch from
  assert.doesNotMatch(html, /data-composition-src|<audio|@font-face|src="/);
  assert.match(html, /<script>\/\* gsap \*\/<\/script>/);
  for (const id of ["hook", "steps", "gate"]) {
    const scene = read(fx.dir, "composition", "scenes", `${id}.html`);
    const inner = scene.match(/<template[^>]*>([\s\S]*)<\/template>/)[1];
    assert.ok(html.includes(inner), `${id} is inline`);
    assert.match(
      html,
      new RegExp(
        `<div id="scene-${id}" class="clip" data-composition-id="${id}" data-start="[\\d.]+" data-duration="[\\d.]+" data-track-index="1">\\s*<div data-composition-id="${id}"`,
      ),
    );
  }
  // the composition's own hosts and captions keep their windows
  for (const m of comp.matchAll(
    /data-start="([\d.]+)" data-duration="([\d.]+)"/g,
  ))
    assert.ok(html.includes(m[0]), m[0]);
  assert.ok(
    html.trimEnd().endsWith(`</script>\n  </body>\n</html>`),
    "the page ends with the frame's script",
  );
  assert.ok(
    html.lastIndexOf('addEventListener("message"') >
      html.lastIndexOf("data-composition-id"),
    "the frame's script comes after every scene",
  );
  // one entry per @font-face the composition declares, the bytes base64
  assert.equal(fonts.length, comp.split("@font-face").length - 1);
  assert.ok(fonts.length > 0);
  for (const f of fonts) {
    assert.equal(typeof f.family, "string");
    assert.equal(typeof f.weight, "number");
    assert.match(f.style, /^(normal|italic)$/);
    assert.equal(Buffer.from(f.data, "base64").toString(), "woff2");
  }
  // a script ending a tag inside the asset would end the page's own script
  assert.ok(!html.includes("</script></script"));
});

// The frame's script run against a stub document: three clips (two scenes whose
// windows overlap by a seam, and a caption), a timeline each, a clock the test turns.
function frame() {
  const clip = (start, duration, compositionId) => ({
    dataset: {
      start: String(start),
      duration: String(duration),
      compositionId,
    },
    style: {},
  });
  const els = [clip(0, 3.2, "a"), clip(3, 3.2, "b"), clip(0.5, 1)];
  const tls = Object.fromEntries(
    ["a", "b", "main"].map((id) => [
      id,
      {
        id,
        at: [],
        time(t) {
          this.at.push(t);
        },
      },
    ]),
  );
  const sent = [];
  const parent = { postMessage: (m) => sent.push(m) };
  let onMessage;
  let tick = null;
  let now = 0;
  const added = [];
  const styles = {};
  vm.runInNewContext(
    fs.readFileSync(
      path.join(skill, "scripts", "render", "live-frame.js"),
      "utf8",
    ),
    {
      window: { __timelines: tls },
      document: {
        querySelectorAll: () => els,
        getElementById: (id) => styles[id] ?? null,
        createElement: () => ({}),
        head: { append: (el) => (styles[el.id] = el) },
        fonts: { add: (f) => added.push(f), ready: Promise.resolve() },
      },
      FontFace: class {
        constructor(family, data, opts) {
          Object.assign(this, { family, data, opts });
        }
        load() {
          return Promise.resolve(this);
        }
      },
      parent,
      addEventListener: (_, f) => (onMessage = f),
      requestAnimationFrame: (f) => ((tick = f), 1),
      cancelAnimationFrame: () => (tick = null),
      performance: { now: () => now },
    },
  );
  const settle = () => new Promise((r) => setImmediate(r));
  return {
    els,
    tls,
    styles,
    sent,
    added,
    async post(data, source = parent) {
      onMessage({ source, data });
      await settle();
    },
    advance(ms) {
      now = ms;
      const t = tick;
      tick = null;
      t?.(now);
    },
    running: () => tick !== null,
  };
}
// The frame runs in its own realm: plain copies compare equal to ours.
const clone = (o) => JSON.parse(JSON.stringify(o));
const shown = (f) => f.els.map((e) => e.style.visibility);

test("the frame shows each clip inside its window and seeks each scene at its own offset", async () => {
  const f = frame();
  assert.deepEqual(clone(f.sent), [{ type: "ready" }]);
  await f.post({ type: "seek", t: 1 });
  assert.deepEqual(shown(f), ["visible", "hidden", "visible"]);
  assert.equal(f.tls.a.at.at(-1), 1);
  assert.equal(
    f.tls.b.at.at(-1),
    0,
    "a scene not yet begun is held at its start",
  );
  assert.equal(f.tls.main.at.at(-1), 1);
  // inside the seam both scenes show, the later one at its own 0.2 s
  await f.post({ type: "seek", t: 3.2 });
  assert.deepEqual(shown(f), ["hidden", "visible", "hidden"]);
  await f.post({ type: "seek", t: 3.1 });
  assert.deepEqual(shown(f), ["visible", "visible", "hidden"]);
  assert.ok(Math.abs(f.tls.b.at.at(-1) - 0.1) < 1e-9);
});

test("the frame takes commands only from its page, fonts first, and runs a loop on its own clock", async () => {
  const f = frame();
  await f.post({ type: "seek", t: 2 }, {});
  assert.equal(
    f.tls.main.at.at(-1),
    0,
    "a message from another window is ignored",
  );
  await f.post({
    type: "fonts",
    fonts: [
      {
        family: "Inter",
        weight: 400,
        style: "normal",
        data: new ArrayBuffer(4),
      },
    ],
  });
  assert.equal(f.added.length, 1);
  assert.deepEqual(clone(f.added[0].opts), { weight: "400", style: "normal" });
  assert.deepEqual(clone(f.sent.at(-1)), { type: "shown" });
  // a loop over [3, 4] runs on and wraps
  await f.post({ type: "run", from: 3, to: 4, loop: true });
  f.advance(500);
  assert.equal(f.tls.main.at.at(-1), 3.5);
  f.advance(1250);
  assert.equal(f.tls.main.at.at(-1), 3.25);
  assert.ok(f.running());
  // once, it holds at the end and says so
  await f.post({ type: "run", from: 3, to: 4, loop: false });
  f.advance(1500 + 0);
  f.advance(2600);
  assert.equal(f.tls.main.at.at(-1), 4);
  assert.deepEqual(clone(f.sent.at(-1)), { type: "done" });
  assert.ok(!f.running());
});

test("a css message puts the page's edited palette in one style element, replaced on the next", async () => {
  const f = frame();
  await f.post({ type: "css", css: ":root { --bg: #111111; }" });
  assert.equal(f.styles.edits.textContent, ":root { --bg: #111111; }");
  const first = f.styles.edits;
  await f.post({ type: "css", css: ":root { --bg: #222222; }" });
  assert.equal(f.styles.edits, first);
  assert.equal(first.textContent, ":root { --bg: #222222; }");
  await f.post({ type: "css", css: "x" }, {});
  assert.equal(first.textContent, ":root { --bg: #222222; }");
});

test("a timeline of the wrong shape is refused by name, not with a stack", () => {
  const fx = fixture();
  prep(fx);
  fs.writeFileSync(path.join(fx.dir, "timeline.json"), "{}");
  const r = board(fx, "build");
  assert.equal(r.code, 1);
  assert.match(r.err, /^board: timeline\.json: total is not a number$/m);
  assert.doesNotMatch(r.err, /TypeError/);
});

test("a timeline missing a scene's slot, or a scene file with no template, is refused by name", async () => {
  const fx = fixture();
  prep(fx);
  const file = path.join(fx.dir, "timeline.json");
  const tl = JSON.parse(fs.readFileSync(file, "utf8"));
  delete tl.scenes[0].slot;
  fs.writeFileSync(file, JSON.stringify(tl));
  const r = board(fx, "build");
  assert.equal(r.code, 1);
  assert.match(
    r.err,
    /^board: timeline\.json: scenes\[0\]\.slot is not a number$/m,
  );
  const { liveScript } = await import(
    path.join(skill, "scripts", "render", "live.mjs")
  );
  const comp = path.join(fx.dir, "composition");
  fs.writeFileSync(path.join(comp, "scenes", "hook.html"), "x");
  assert.throws(
    () => liveScript(comp),
    /scenes\/hook\.html holds no <template>/,
  );
  // the CLI shows it as a board line, not a stack
  tl.scenes[0].start = 0;
  tl.scenes[0].slot = 1;
  fs.writeFileSync(file, JSON.stringify(tl));
  const r2 = board(fx, "build");
  assert.equal(r2.code, 1);
  assert.match(r2.err, /^board: .*(holds no <template>|no start and slot)/m);
  assert.doesNotMatch(r2.err, /\n\s+at /);
});
