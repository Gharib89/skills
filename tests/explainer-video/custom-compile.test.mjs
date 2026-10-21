// The `custom` component at compile: the agent's own HTML fragment beside the
// scene file, with its intent and the cues it reads by name. Compile reads the
// file, lints it and keeps its text in script.json, so every later stage plays
// the fragment the run compiled. A custom scene is rich, so `camera` is refused.
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { banReason } from "../../skills/explainer-video/scripts/lib/allowed.mjs";
import {
  VISUALS,
  checkVisual,
} from "../../skills/explainer-video/scripts/lib/visuals.mjs";
import { compiled, fixture, run } from "./compile-lib.mjs";

const said = ["The client sends a request.", "The server reads the cache."];
const FRAGMENT = `<div class="orb">Request</div>
<style>.orb { color: var(--accent); font: 600 var(--size-title) var(--font-title); }</style>
<script>tl.fromTo($(".orb"), { opacity: 0 }, { opacity: 1, duration: 0.3 }, cue("land"));</script>`;
const custom = (props = {}, more = {}) => ({
  component: "custom",
  props: {
    file: "scenes/orbit.html",
    intent: "an orb lands on the request",
    cues: [{ name: "land", at: 1 }],
    ...props,
  },
  ...more,
});
const ctx = (src = FRAGMENT, language = "en") => ({
  read: () => src,
  language,
});
const bad = (visual, why, c = ctx()) =>
  assert.throws(() => checkVisual(visual, said, c), why);

test("a custom scene with a fragment, an intent and declared cues compiles", () => {
  assert.doesNotThrow(() => checkVisual(custom(), said, ctx()));
  // cues are optional: a static fragment names none
  assert.doesNotThrow(() =>
    checkVisual(custom({ cues: undefined }), said, ctx("<p>Hi</p>")),
  );
});

test("a custom scene is rich: it draws its own frame, so a camera key is refused", () => {
  assert.equal(VISUALS.custom.ownCamera, true);
  bad(
    custom({}, { camera: { at: 1 } }),
    /custom draws its own camera, so it takes no camera key/,
  );
});

test("the file and the intent are required, and the file stays beside the scene file", () => {
  bad(
    custom({ file: undefined }),
    /custom file needs a file beside the scene file/,
  );
  bad(custom({ intent: " " }), /custom intent needs an intent/);
  bad(custom({ intent: "one\ntwo" }), /custom intent is one line/);
  for (const file of [
    "/etc/hosts",
    "../up.html",
    "scenes/../../up.html",
    "C:\\x.html",
    "orbit.js",
  ])
    bad(custom({ file }), /custom file .* beside the scene file/);
  bad(custom({ extra: 1 }), /custom has no prop extra \(file, intent, cues\)/);
  // the fragment text is compile's to add, never the scene file's
  bad(custom({ source: "<p>x</p>" }), /custom has no prop source/);
});

test("a file compile cannot read is refused naming it, and a read error that is not a missing file says what it was", () => {
  const failing = (code, message) => ({
    read: () => {
      throw Object.assign(new Error(message), { code });
    },
  });
  bad(
    custom(),
    /custom file scenes\/orbit\.html is not beside the scene file/,
    failing("ENOENT", "no such file"),
  );
  bad(
    custom(),
    /custom file scenes\/orbit\.html cannot be read: EISDIR: illegal operation on a directory/,
    failing("EISDIR", "EISDIR: illegal operation on a directory"),
  );
});

test("a cue of a custom scene has a plain name, a sentence and optionally a phrase said in it", () => {
  bad(custom({ cues: [{ at: 1 }] }), /a custom cue needs a name/);
  bad(
    custom({ cues: [{ name: "has space", at: 1 }] }),
    /custom cue name "has space" is not a plain name/,
  );
  bad(
    custom({
      cues: [
        { name: "land", at: 1 },
        { name: "land", at: 2 },
      ],
    }),
    /custom cue land is named twice/,
  );
  bad(
    custom({ cues: [{ name: "land", at: 3 }] }),
    /at 3 is not a sentence \(1 to 2\)/,
  );
  bad(
    custom({ cues: [{ name: "land", at: 1, on: "the moon" }] }),
    /on "the moon" is not said in sentence 1/,
  );
  bad(
    custom({ cues: [{ name: "land", at: 1, x: 1 }] }),
    /a custom cue has no prop x/,
  );
  bad(custom({ cues: "land" }), /custom cues needs a list of cues/);
  assert.doesNotThrow(() =>
    checkVisual(
      custom({ cues: [{ name: "land", at: 1, on: "a request" }] }),
      said,
      ctx(),
    ),
  );
});

test("a fragment is refused with its pattern named, its file and the lint's reason", () => {
  bad(
    custom(),
    /custom file scenes\/orbit\.html: literal colour #fff/,
    ctx(FRAGMENT.replace("var(--accent)", "#fff")),
  );
  bad(
    custom(),
    /custom file scenes\/orbit\.html: time source Date\.now/,
    ctx(FRAGMENT.replace("cue(", "Date.now() + cue(")),
  );
  bad(custom({ cues: [] }), /cue "land" is not declared \(none\)/);
});

test("an Arabic run refuses a per-letter span, and the language reaches the lint", () => {
  const letters = "<p><span>a</span><span>b</span></p>";
  assert.doesNotThrow(() =>
    checkVisual(custom({ cues: [] }), said, ctx(letters, "en")),
  );
  bad(custom({ cues: [] }), /per-letter span/, ctx(letters, "ar"));
});

test("the numbers a custom scene shows are its fragment's text, held to a cited excerpt", () => {
  assert.deepEqual(
    VISUALS.custom.numbers({
      source: "<p>42 runs, 1,200 files</p><script>const n = 7;</script>",
    }),
    ["42", "1,200"],
  );
  assert.deepEqual(VISUALS.custom.numbers({}), []);
});

test("a number the script writes is a claim too, and a counter's start at 0 is not", () => {
  const source =
    '<p class="n">0</p><script>tl.fromTo($(".n"), { textContent: 0 }, { textContent: 87, duration: 1 }, 0); tl.set($(".m"), { textContent: 42 }, 0);</script>';
  assert.deepEqual(VISUALS.custom.numbers({ source }), ["0", "87", "42"]);
  assert.deepEqual(VISUALS.custom.shown({ source }), ["0 87 42"]);
  assert.deepEqual(VISUALS.custom.shown({}), [""]);
});

test("a fragment that moves the frame or blurs is refused by the profile's ban on that technique, and a ban on custom refuses it whole", () => {
  const blurry = "<style>.a { filter: blur(4px); }</style><p class='a'>x</p>";
  assert.equal(
    banReason(["blur"], "custom", "odd", blurry),
    "component custom uses blur, which style profile odd bans",
  );
  assert.equal(banReason(["blur"], "custom", "odd", FRAGMENT), null);
  assert.equal(banReason(["blur"], "custom", "odd"), null);
  assert.equal(
    banReason(["custom"], "custom", "odd", FRAGMENT),
    "component custom is banned by style profile odd",
  );
  assert.equal(
    banReason(
      ["camera"],
      "custom",
      "odd",
      "<script>tl.to($(), { scale: 1.1 }, 0);</script>",
    ),
    "component custom uses camera, which style profile odd bans",
  );
  assert.equal(
    banReason(
      ["kinetic"],
      "custom",
      "odd",
      "<script>const w = t.split(' ');</script>",
    ),
    "component custom uses kinetic, which style profile odd bans",
  );
  assert.equal(
    banReason(
      ["draw"],
      "custom",
      "odd",
      "<style>.a { stroke-dashoffset: 9; }</style>",
    ),
    "component custom uses draw, which style profile odd bans",
  );
});

const SCENE = (visual) => `# Custom
language: en
narrator: am_fenrir
style: claude-code

## Scene orbit · The orb

### Narration
1. The client sends a request. [ex-1]
2. The server reads the cache. [ex-2]

### Visual
\`\`\`json
${JSON.stringify(visual)}
\`\`\`
`;
const compile = (fragment, visual = custom()) => {
  const fx = fixture(SCENE(visual));
  fs.mkdirSync(path.join(fx.dir, "scenes"));
  if (fragment !== undefined)
    fs.writeFileSync(path.join(fx.dir, "scenes", "orbit.html"), fragment);
  return { fx, r: run(fx) };
};

test("compile reads the fragment beside the scene file and keeps its text in script.json", () => {
  const { fx, r } = compile(FRAGMENT);
  assert.equal(r.code, 0, r.err);
  const { props } = compiled(fx).scenes[0].visual;
  assert.equal(props.source, FRAGMENT);
  assert.equal(props.file, "scenes/orbit.html");
  assert.equal(props.intent, "an orb lands on the request");
});

test("compile refuses a missing fragment, a lint hit and a ban, each naming its scene", () => {
  let { r } = compile(undefined);
  assert.equal(r.code, 1);
  assert.match(
    r.err,
    /^compile: orbit: custom file scenes\/orbit\.html is not beside the scene file$/m,
  );

  ({ r } = compile(FRAGMENT.replace("var(--accent)", "#fff")));
  assert.equal(r.code, 1);
  assert.match(
    r.err,
    /^compile: orbit: custom file scenes\/orbit\.html: literal colour #fff/m,
  );

  // a profile that bans blur refuses the fragment that blurs
  const fx = fixture(SCENE(custom()));
  fs.mkdirSync(path.join(fx.dir, "scenes"));
  fs.writeFileSync(
    path.join(fx.dir, "scenes", "orbit.html"),
    "<p class='a'>x</p><style>.a { filter: blur(2px); }</style>",
  );
  const profile = JSON.parse(
    fs.readFileSync(
      new URL(
        "../../skills/explainer-video/styles/claude-code.json",
        import.meta.url,
      ),
      "utf8",
    ),
  );
  fs.mkdirSync(path.join(fx.dir, "..", ".styles"));
  fs.writeFileSync(
    path.join(fx.dir, "..", ".styles", "calm.json"),
    JSON.stringify({
      ...profile,
      name: "calm",
      grammar: {
        bans: ["blur"],
        texture: { surface: "flat", overlays: ["vignette"] },
        seams: { family: "velocity", blur: 0 },
      },
    }),
  );
  fs.writeFileSync(
    path.join(fx.dir, "script.md"),
    SCENE(custom()).replace("style: claude-code", "style: calm"),
  );
  r = run(fx);
  assert.equal(r.code, 1, r.err);
  assert.match(
    r.err,
    /^compile: orbit: component custom uses blur, which style profile calm bans$/m,
  );
});
