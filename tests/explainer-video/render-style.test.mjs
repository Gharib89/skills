// The render stage through its process door, part 2: the style profile a run
// takes, its fonts and contrast floor, and the refusals before any render.
import { after, test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import {
  catalogue,
  dest,
} from "../../skills/explainer-video/scripts/lib/tools.mjs";
import { SCRIPT } from "./scene-file.mjs";
import {
  at,
  calls,
  fixture,
  own,
  profile,
  put,
  read,
  render,
  skill,
  stage,
  unstyled,
} from "./render-lib.mjs";

test("with no default named anywhere the run takes the bundled claude-code and copies it into the run", () => {
  const fx = fixture(unstyled);
  assert.equal(render(fx).code, 0);
  assert.equal(own(fx).name, "claude-code");
  assert.equal(
    JSON.parse(read(fx.dir, "manifest.json")).profile,
    "claude-code",
  );
});

test("a store's default file is honoured, and the project store beats the user store", () => {
  const fx = fixture(unstyled);
  const user = path.join(fx.tmp, "config", "explainer-video", "styles");
  put(user, "default", "mine\n");
  put(user, "mine.json", profile("user"));
  assert.equal(render(fx).code, 0);
  assert.equal(own(fx).name, "mine");
  assert.equal(own(fx).label, "user");

  const fx2 = fixture(unstyled);
  const user2 = path.join(fx2.tmp, "config", "explainer-video", "styles");
  put(user2, "default", "mine\n");
  put(user2, "mine.json", profile("user"));
  put(
    path.join(fx2.tmp, "proj", "explainers", ".styles"),
    "mine.json",
    profile("project"),
  );
  assert.equal(render(fx2).code, 0);
  assert.equal(own(fx2).label, "project");
});

test("a font only the profile carries is refused until setup's install lands it, then renders", () => {
  const fx = fixture();
  for (const s of ["script/compile.mjs", "voice/voice.mjs"])
    assert.equal(stage(fx, s).code, 0, s);
  const lora = {
    id: "font:lora",
    kind: "font",
    family: "lora",
    class: "serif",
    version: "5.3.0",
    files: ["latin-400-normal"],
    licence: "OFL-1.1",
  };
  styled(
    fx,
    {},
    {
      fonts: [lora],
      type: { ...latin, title: { ...latin.title, font: "lora" } },
    },
  );
  const before = render(fx);
  assert.equal(before.code, 1, before.out + before.err);
  assert.match(
    before.err,
    /^render: font:lora is not installed: run \/explainer-video setup/m,
  );
  // What `setup install` writes for the row: its files, then the stamp.
  const dir = dest(lora, fx.dirs);
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(path.join(dir, "latin-400-normal.woff2"), "woff2");
  fs.writeFileSync(path.join(dir, ".stamp"), "");
  const after = render(fx);
  assert.equal(after.code, 0, after.out + after.err);
});

test("the run keeps its own style.json after the store's copy is edited", () => {
  const fx = fixture(unstyled);
  const project = path.join(fx.tmp, "proj", "explainers", ".styles");
  put(project, "default", "mine");
  put(project, "mine.json", profile("first"));
  assert.equal(render(fx).code, 0);
  put(project, "mine.json", profile("edited"));
  assert.equal(render(fx).code, 0);
  assert.equal(own(fx).label, "first");
});

test("a profile with a pair under its contrast floor refuses the run by name before any render", () => {
  const fx = fixture(unstyled);
  const project = path.join(fx.tmp, "proj", "explainers", ".styles");
  put(project, "default", "pale");
  put(project, "pale.json", profile("pale", { muted: "#c8c8c0" }));
  const r = render(fx);
  assert.equal(r.code, 1, r.out + r.err);
  assert.match(
    r.err,
    /^render: style profile pale fails contrast: .*muted on bg [\d.]+:1, floor 4\.5:1/m,
  );
  assert.equal(calls(fx).length, 0);
  assert.ok(!fs.existsSync(path.join(fx.dir, "style.json")));
});

test("a narration edit that keeps the word count still asks for the voice stage again", () => {
  const fx = fixture();
  assert.equal(render(fx).code, 0);
  put(
    fx.dir,
    "script.md",
    SCRIPT.replace("It reads the issue.", "It ignores the issue."),
  );
  assert.equal(stage(fx, "script/compile.mjs").code, 0);
  const r = stage(fx, "render/render.mjs");
  assert.equal(r.code, 1, r.out + r.err);
  assert.match(
    r.err,
    /^render: voice\.json does not match scene steps: run the voice stage again/m,
  );
});

// A WAV header field rewritten in place, 16-bit or 32-bit little-endian.
const patchWav = (fx, scene, at, value, bits = 16) => {
  const v = JSON.parse(read(fx.dir, "voice.json")).scenes[scene];
  const f = path.join(fx.dir, v.audio);
  const b = fs.readFileSync(f);
  if (bits === 16) b.writeUInt16LE(value, at);
  else b.writeUInt32LE(value, at);
  fs.writeFileSync(f, b);
};
// A project profile `odd` the script names, then compiled.
const styled = (fx, colors, extra) => {
  const p = JSON.parse(profile("odd", colors));
  put(
    path.join(fx.tmp, "proj", "explainers", ".styles"),
    "odd.json",
    JSON.stringify({ ...p, ...extra }),
  );
  put(fx.dir, "script.md", SCRIPT.replace("style: claude-code", "style: odd"));
  assert.equal(stage(fx, "script/compile.mjs").code, 0);
};
const latin = JSON.parse(read(skill, "styles", "claude-code.json")).type;

for (const [name, arrange, why, voiced = true] of [
  [
    "a run with no compiled script",
    () => {},
    /^render: no script\.json: run the compile stage first/m,
    false,
  ],
  [
    "a setup row that is not installed",
    (fx) =>
      fs.rmSync(
        path.join(
          dest(
            catalogue().find((r) => r.id === "font:inter"),
            fx.dirs,
          ),
          ".stamp",
        ),
      ),
    /^render: font:inter is not installed: run \/explainer-video setup/m,
  ],
  [
    "a font folder that holds the stamp but lacks one of its files",
    (fx) => {
      const row = catalogue().find((r) => r.id === "font:inter");
      fs.rmSync(path.join(dest(row, fx.dirs), `${row.files[0]}.woff2`));
    },
    /^render: font:inter lacks latin-\d+-normal\.woff2: run \/explainer-video setup/m,
  ],
  [
    "a language with no render fonts",
    (fx) => {
      put(fx.dir, "script.md", SCRIPT.replace("language: en", "language: de"));
      assert.equal(stage(fx, "script/compile.mjs").code, 0);
    },
    /^render: no render fonts for language de/m,
    false,
  ],
  [
    "a profile in a layout this version does not draw",
    (fx) => styled(fx, {}, { grammar: { layout: "grid" } }),
    /^render: style profile odd: grammar\.layout grid is not open or bands$/m,
    false,
  ],
  [
    "a profile naming a font no setup row installs",
    (fx) =>
      styled(
        fx,
        {},
        { type: { ...latin, text: { font: "comic", weight: 400 } } },
      ),
    /^render: style profile odd names font comic, which no setup row installs/m,
  ],
  [
    "a profile with no text font",
    (fx) => styled(fx, {}, { type: { ...latin, text: undefined } }),
    /^render: style profile odd names no text font/m,
  ],
  [
    "a contrast floor that is not a number",
    (fx) => styled(fx, {}, { gates: { contrast: { body: "bogus" } } }),
    /^render: style profile odd fails contrast: gates\.contrast\.body: not a number/m,
    false,
  ],
  [
    "a profile that lowers a contrast floor",
    (fx) => styled(fx, {}, { gates: { contrast: { body: 3 } } }),
    /^render: style profile odd: gates\.contrast\.body 3 lowers the skill's floor 4\.5$/m,
    false,
  ],
  [
    "a profile that loosens the peak floor",
    (fx) => styled(fx, {}, { gates: { loudness: { peak: 0 } } }),
    /^render: style profile odd: gates\.loudness\.peak 0 lowers the skill's floor -1$/m,
    false,
  ],
  [
    "a profile that allows more sound effects a minute",
    (fx) => styled(fx, {}, { gates: { sfx: { perMinute: 30 } } }),
    /^render: style profile odd: gates\.sfx\.perMinute 30 lowers the skill's floor 24$/m,
    false,
  ],
  [
    "a negative sound effect floor",
    (fx) => styled(fx, {}, { gates: { sfx: { perMinute: -1 } } }),
    /^render: style profile odd: gates\.sfx\.perMinute -1 must be a whole number 0 or more$/m,
    false,
  ],
  [
    "a fractional sound effect floor",
    (fx) => styled(fx, {}, { gates: { sfx: { perMinute: 0.5 } } }),
    /^render: style profile odd: gates\.sfx\.perMinute 0\.5 must be a whole number 0 or more$/m,
    false,
  ],
  [
    "a loudness tolerance of zero",
    (fx) => styled(fx, {}, { gates: { loudness: { tolerance: 0 } } }),
    /^render: style profile odd: gates\.loudness\.tolerance 0 must be above 0$/m,
    false,
  ],
  [
    "a peak floor under what the master can aim beneath",
    (fx) => styled(fx, {}, { gates: { loudness: { peak: -9 } } }),
    /^render: style profile odd: gates\.loudness\.peak -9 is under -8\.5, the lowest the master reaches$/m,
    false,
  ],
  [
    "a profile naming a floor the skill has not",
    (fx) => styled(fx, {}, { gates: { layout: { width: 2 } } }),
    /^render: style profile odd: gates\.layout\.width: no such floor$/m,
    false,
  ],
  [
    "a profile naming a gate group the skill has not",
    (fx) => styled(fx, {}, { gates: { motion: { speed: 2 } } }),
    /^render: style profile odd: gates\.motion: no such floor$/m,
    false,
  ],
  [
    "a profile with a determinism block, whose floor is equality",
    (fx) => styled(fx, {}, { gates: { determinism: { tolerance: 1 } } }),
    /^render: style profile odd: gates\.determinism: no such floor$/m,
    false,
  ],
  [
    "a layout floor that is not a number",
    (fx) => styled(fx, {}, { gates: { layout: { textPx: "big" } } }),
    /^render: style profile odd: gates\.layout\.textPx: not a number$/m,
    false,
  ],
  [
    "a profile colour that is not #rrggbb",
    (fx) => styled(fx, { muted: "grey" }),
    /^render: style profile odd fails contrast: muted on bg: not a #rrggbb colour/m,
    false,
  ],
  [
    "a scene WAV that is not mono PCM",
    (fx) => patchWav(fx, 0, 22, 2),
    /^render: \.cache\/voice\/\w+\.wav is not 16-bit mono PCM: run the voice stage again/m,
  ],
  [
    "scene WAVs at different sample rates",
    (fx) => patchWav(fx, 1, 24, 8000, 32),
    /^render: the scenes' WAVs differ in sample rate: run the voice stage again/m,
  ],
]) {
  test(`render refuses ${name} by name, before any HyperFrames call`, () => {
    const fx = fixture();
    if (voiced)
      for (const s of ["script/compile.mjs", "voice/voice.mjs"])
        assert.equal(stage(fx, s).code, 0, s);
    arrange(fx);
    const r = stage(fx, "render/render.mjs");
    assert.equal(r.code, 1, r.out + r.err);
    assert.match(r.err, why);
    assert.equal(calls(fx).length, 0);
  });
}
