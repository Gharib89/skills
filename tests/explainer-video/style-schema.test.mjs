// Style profile schema 2: the loader's grammar, bans and type scale, direct
// against lib/style.mjs; the composed page and the compile refusal run through
// their process doors.
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import {
  SCALE,
  checkBans,
  grammar,
  scale,
  validate,
} from "../../skills/explainer-video/scripts/lib/style.mjs";
import { CONTENT } from "../../skills/explainer-video/scripts/render/compose.mjs";
import { ARABIC, DIAGRAMS, SCRIPT } from "./scene-file.mjs";
import {
  comp,
  fixture,
  profiled,
  read,
  render,
  skill,
  stage,
} from "./render-lib.mjs";

const bundled = (name) => JSON.parse(read(skill, "styles", `${name}.json`));
const odd = (extra) => ({ ...bundled("claude-code"), name: "odd", ...extra });
const refused = (extra, why) => assert.throws(() => validate(odd(extra)), why);

test("both bundled profiles load as schema 2, claude-code with no grammar block and itworx with only its departures", () => {
  for (const name of ["claude-code", "itworx"]) {
    const p = bundled(name);
    assert.equal(p.schema, 2, name);
    assert.doesNotThrow(() => validate({ ...p, name }), name);
  }
  assert.equal(bundled("claude-code").grammar, undefined);
  assert.deepEqual(bundled("itworx").grammar, {
    texture: { surface: "flat" },
  });
});

test("a schema 1 profile is refused with a message naming what to change", () => {
  const { schema, grammar: _, ...rest } = bundled("claude-code");
  const one = {
    ...rest,
    schema: 1,
    motion: "rise",
    look: "clean",
    effects: [],
  };
  assert.throws(
    () => validate({ ...one, name: "old" }),
    /style profile old is schema 1.*motion.*ease.*look.*texture\.surface.*clean.*flat.*effects/s,
  );
  assert.throws(() => validate({ ...rest, name: "old" }), /is schema 1/);
});

test("a schema is read before contrast, and a schema 2 profile holding a schema 1 key is refused naming it", () => {
  const base = bundled("claude-code");
  const bad = {
    ...base,
    name: "old",
    schema: 1,
    colors: { ...base.colors, text: base.colors.bg },
  };
  assert.throws(() => validate(bad), /is schema 1/);
  for (const [k, to] of [
    ["motion", "grammar.ease"],
    ["look", "grammar.texture.surface"],
    ["effects", "nothing"],
    ["layout", "grammar.layout"],
  ])
    assert.throws(
      () => validate({ ...base, name: "old", [k]: "x" }),
      new RegExp(
        `style profile old: ${k} is a schema 1 key, replaced by ${to}`,
      ),
    );
});

test("a field left out of the grammar takes today's look", () => {
  assert.deepEqual(grammar(bundled("claude-code")), {
    layout: "bands",
    seams: { family: "cut" },
    camera: { family: "locked" },
    type: { family: "block" },
    ease: "soft",
    texture: { surface: "flat" },
    bans: [],
  });
  const g = grammar(
    odd({ grammar: { ease: "spring", seams: { duration: 0.3 } } }),
  );
  assert.equal(g.ease, "spring");
  assert.deepEqual(g.seams, { family: "cut", duration: 0.3 });
  assert.equal(g.camera.family, "locked");
});

for (const [name, g, why] of [
  [
    "a knob under its range",
    { seams: { duration: 0.1 } },
    /grammar\.seams\.duration 0\.1 is outside 0\.2 to 0\.4/,
  ],
  [
    "a knob over its range",
    { seams: { blur: 25 } },
    /grammar\.seams\.blur 25 is outside 0 to 24/,
  ],
  [
    "a camera scale out of range",
    { camera: { scale: 1.5 } },
    /grammar\.camera\.scale 1\.5 is outside 1\.03 to 1\.12/,
  ],
  [
    "a stagger out of range",
    { type: { stagger: 0.2 } },
    /grammar\.type\.stagger 0\.2 is outside 0\.03 to 0\.08/,
  ],
  [
    "a knob that is not a number",
    { seams: { duration: "slow" } },
    /grammar\.seams\.duration slow is not a number/,
  ],
  [
    "a knob the field lacks",
    { seams: { zoom: 1 } },
    /grammar\.seams\.zoom: no such knob/,
  ],
  [
    "an unknown family",
    { camera: { family: "orbit" } },
    /grammar\.camera orbit is not locked/,
  ],
  [
    "an unknown ease",
    { ease: "bounce" },
    /grammar\.ease bounce is not soft or spring/,
  ],
  [
    "a layout not drawn yet",
    { layout: "grid" },
    /grammar\.layout grid is not bands/,
  ],
  [
    "an unknown surface",
    { texture: { surface: "glass" } },
    /grammar\.texture\.surface glass is not flat or sketch/,
  ],
  ["an unknown field", { motion: "rise" }, /grammar\.motion: no such field/],
  [
    "a layout that is not a family name",
    { layout: 5 },
    /grammar\.layout is not a family name/,
  ],
  [
    "an ease given as an object",
    { ease: { family: "spring" } },
    /grammar\.ease is not a family name/,
  ],
  [
    "a field with knobs given as a number",
    { seams: 7 },
    /grammar\.seams is not a family name or \{ family, \.\.\.knobs \}/,
  ],
  [
    "a texture given as a bare surface",
    { texture: "sketch" },
    /grammar\.texture is not an object/,
  ],
  [
    "a ban that names no component",
    { bans: ["confetti"] },
    /grammar\.bans: confetti is not a component/,
  ],
  ["bans that are not a list", { bans: "flow" }, /grammar\.bans is not a list/],
]) {
  test(`the loader refuses ${name}, naming the field`, () =>
    refused({ grammar: g }, new RegExp(`style profile odd: ${why.source}`)));
}

test("a grammar that uses a component it bans is refused, naming the family and the component", () => {
  const g = { seams: { family: "canvas" }, bans: ["canvas"] };
  assert.throws(
    () => checkBans(g, { "seams.canvas": ["canvas"] }, "odd"),
    /style profile odd: grammar\.seams canvas uses the canvas component, which grammar\.bans bans/,
  );
  assert.doesNotThrow(() =>
    checkBans({ ...g, bans: ["flow"] }, { "seams.canvas": ["canvas"] }, "odd"),
  );
});

test("a type step is the profile's, else the scale's, and never under the layout floor", () => {
  assert.deepEqual(SCALE, {
    display: 112,
    title: 56,
    heading: 46,
    body: 40,
    code: 32,
    small: 28,
    label: 24,
  });
  assert.deepEqual(scale(bundled("claude-code")), SCALE);
  assert.equal(scale(odd({ scale: { label: 20 } })).label, 20);
  refused(
    { scale: { label: 17 } },
    /style profile odd: scale\.label 17 is under the 18 px layout floor/,
  );
  refused(
    { scale: { huge: 200 } },
    /style profile odd: scale\.huge: no such step/,
  );
  refused({ scale: { body: "big" } }, /scale\.body big is not a number/);
  refused(
    { scale: { small: 34, label: 30 }, gates: { layout: { textPx: 32 } } },
    /scale\.label 30 is under the 32 px layout floor/,
  );
  refused(
    { gates: { layout: { textPx: 32 } } },
    /scale\.small 28 is under the 32 px layout floor/,
  );
});

test("the composed page defines every size, face and palette token, and no component writes a literal font size", () => {
  const fx = fixture(
    `${SCRIPT}\n${DIAGRAMS.replace(/^[\s\S]*?(?=## Scene)/, "")}`,
  );
  const r = render(fx);
  assert.equal(r.code, 0, r.out + r.err);
  const index = comp(fx);
  for (const step of Object.keys(SCALE))
    assert.match(index, new RegExp(`--size-${step}: ${SCALE[step]}px;`));
  assert.match(index, /--font-title: "source-serif-4";/);
  assert.match(index, /--font-text: "inter";/);
  assert.match(index, /--font-code: "jetbrains-mono";/);
  for (const t of ["bg", "panel", "accent", "stop"])
    assert.match(index, new RegExp(`--${t}: #[0-9a-f]{6};`));
  const files = [
    "index.html",
    ...fs
      .readdirSync(path.join(fx.dir, "composition", "scenes"))
      .map((f) => `scenes/${f}`),
  ];
  assert.ok(files.length > 8);
  for (const f of files)
    assert.doesNotMatch(
      comp(fx, f),
      /font(-size)?:\s*(\d+\s+)?\d+(\.\d+)?px/,
      `${f} writes a literal font size`,
    );
});

test("a profile's type step override reaches the page as its token", () => {
  const fx = fixture(DIAGRAMS.replace("style: claude-code", "style: big"));
  profiled(fx, "big", { scale: { body: 44 } });
  const r = render(fx);
  assert.equal(r.code, 0, r.out + r.err);
  assert.match(comp(fx), /--size-body: 44px;/);
  assert.match(comp(fx), /--size-caption: 40px;/);
});

test("a malformed profile file is refused at compile naming the file", () => {
  const fx = fixture(DIAGRAMS.replace("style: claude-code", "style: broken"));
  const styles = path.join(fx.tmp, "proj", "explainers", ".styles");
  fs.mkdirSync(styles, { recursive: true });
  fs.writeFileSync(path.join(styles, "broken.json"), '{ "schema": 2,');
  const r = stage(fx, "script/compile.mjs");
  assert.equal(r.code, 1, r.out + r.err);
  assert.match(
    r.err,
    /^compile: style profile .*broken\.json is not valid JSON/m,
  );
});

test("the default code row is 45 px, so 12 rows fit the 690 px content band", () => {
  const fx = fixture(DIAGRAMS);
  const r = render(fx);
  assert.equal(r.code, 0, r.out + r.err);
  const row = comp(fx, "scenes/code.html").match(
    /\.ln \{[^}]*height: (\d+)px/,
  )[1];
  assert.equal(row, "45");
  // bar 56 + 1, body padding 2 * 28, 12 rows, frame border 2 * 2
  assert.ok(56 + 1 + 56 + 12 * Number(row) + 4 <= CONTENT.height);
});

test("a code step override moves the code row height with it", () => {
  const fx = fixture(DIAGRAMS.replace("style: claude-code", "style: big"));
  profiled(fx, "big", { scale: { code: 40 } });
  const r = render(fx);
  assert.equal(r.code, 0, r.out + r.err);
  assert.match(comp(fx), /--size-code: 40px;/);
  const code = comp(fx, "scenes/code.html");
  assert.match(code, /var\(--size-code\)\/56px/);
  assert.match(code, /\.ln \{[^}]*height: 56px/);
});

test("an Arabic run's face tokens resolve to the profile's Arabic companions", () => {
  const fx = fixture(ARABIC);
  fx.env.GEMINI_API_KEY = "test-key";
  const r = render(fx);
  assert.equal(r.code, 0, r.out + r.err);
  const index = comp(fx);
  assert.match(index, /--font-title: "noto-naskh-arabic", "source-serif-4";/);
  assert.match(index, /--font-text: "ibm-plex-sans-arabic", "inter";/);
  assert.match(index, /--font-code: "jetbrains-mono";/);
});

test("a ban added to the profile after compile is refused at render", () => {
  const fx = fixture(DIAGRAMS.replace("style: claude-code", "style: plain"));
  profiled(fx, "plain", {});
  for (const s of ["script/compile.mjs", "voice/voice.mjs"])
    assert.equal(stage(fx, s).code, 0, s);
  profiled(fx, "plain", { grammar: { bans: ["flow"] } });
  fs.rmSync(path.join(fx.dir, "style.json"), { force: true });
  const r = stage(fx, "render/render.mjs");
  assert.equal(r.code, 1, r.out + r.err);
  assert.match(
    r.err,
    /^render: scene flow: component flow is banned by style profile plain$/m,
  );
});

test("a scene naming a component the profile bans is refused at compile", () => {
  const fx = fixture(DIAGRAMS.replace("style: claude-code", "style: plain"));
  profiled(fx, "plain", { grammar: { bans: ["flow"] } });
  const r = stage(fx, "script/compile.mjs");
  assert.equal(r.code, 1, r.out + r.err);
  assert.match(
    r.err,
    /^compile: flow: component flow is banned by style profile plain$/m,
  );
});
