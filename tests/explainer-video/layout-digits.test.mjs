// The layout gate's right to left reading rules on numerals (#947): Arabic-Indic
// digits have no strong direction, so an isolated `<bdi>` of them computes `ltr`
// (which is how a number reads inside Arabic text), and they span less than the
// letters' ink. Only text holding an Arabic letter is held to the reading
// direction and the ink floor; a Latin run is held to its own rules whatever
// else the text holds. The element is as the probe reports it in real Chrome.
import { test } from "node:test";
import assert from "node:assert/strict";
import { judge } from "../../skills/explainer-video/scripts/lib/layout.mjs";
import { floors } from "../../skills/explainer-video/scripts/lib/style.mjs";
import { read, skill } from "./render-lib.mjs";

const profile = JSON.parse(read(skill, "styles", "claude-code.json"));

const box = (text, extra = {}) => ({
  text,
  words: 1,
  scene: "s",
  nth: 0,
  line: null,
  along: false,
  rect: { left: 742.7, top: 374, right: 829.3, bottom: 498 },
  fontPx: 112,
  weight: 600,
  inline: true,
  scrollW: 0,
  scrollH: 0,
  clientW: 0,
  clientH: 0,
  opacity: 1,
  blur: 0,
  clip: null,
  cut: false,
  indent: null,
  color: "#000000",
  bg: "#ffffff",
  dir: "ltr",
  within: "rtl",
  bidi: "isolate",
  wrap: "nowrap",
  lineH: 1,
  face: "noto-naskh-arabic",
  ink: 1.4,
  ...extra,
});

const found = (...elements) => {
  const out = [];
  judge(
    { layout: { findings: [] }, contrast: { findings: [] } },
    [{ t: 1, elements, rootDir: [] }],
    floors(profile),
    (gate, _t, what) => gate === "layout" && out.push(what),
  );
  return out;
};

test("Arabic-Indic digits in an isolated ltr bdi at line height 1 pass the reading rules", () => {
  assert.deepEqual(found(box("٤٠")), []);
});

test("Arabic letters still fail when they read ltr or sit under their ink", () => {
  assert.deepEqual(found(box("ثانية", { inline: false, lineH: 1.6 })), [
    'Arabic reads ltr "ثانية"',
  ]);
  assert.deepEqual(
    found(box("ثانية", { inline: false, dir: "rtl", lineH: 1 })),
    ['line height 1 under the ink 1.4 of noto-naskh-arabic "ثانية"'],
  );
});

test("a Latin run beside Arabic digits is still held to the isolation rule", () => {
  assert.deepEqual(found(box("٤٠ ms", { dir: "rtl" })), [
    'Latin run not isolated in "٤٠ ms"',
  ]);
});
