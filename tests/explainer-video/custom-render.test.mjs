// The `custom` component through the render stage (fake backend, no browser):
// the fragment's markup, scoped rules and script reach the scene's paused
// timeline, its cues arrive by name, and a custom scene that shows no text is a
// hard error like any other component's.
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fragmentScript } from "../../skills/explainer-video/scripts/render/fragment-script.mjs";
import { SCRIPT } from "./scene-file.mjs";
import { at, comp, fixture, near, render } from "./render-lib.mjs";

const TERMINAL = /\{ "component": "terminal".*\}\n/;
const VISUAL = `{ "component": "custom", "props": { "file": "scenes/orbit.html", "intent": "an orb lands on the gate", "cues": [{ "name": "land", "at": 1 }, { "name": "done", "at": 2 }] } }\n`;
const FRAGMENT = `<div class="orb">Gate open</div>
<div class="tag">Merged</div>
<style>
.orb, .tag { color: var(--accent); font: 600 var(--size-title) var(--font-title); }
.tag { opacity: 0; }
</style>
<script>
tl.fromTo($(".orb"), { opacity: 0 }, { opacity: 1, duration: 0.3 }, cue("land"));
tl.to($(".tag"), { opacity: 1, duration: 0.3 }, cue("done"));
</script>`;

function custom(fragment = FRAGMENT) {
  const fx = fixture(SCRIPT.replace(TERMINAL, VISUAL));
  fs.mkdirSync(path.join(fx.dir, "scenes"));
  fs.writeFileSync(path.join(fx.dir, "scenes", "orbit.html"), fragment);
  return fx;
}

test("a custom scene composes its fragment onto the scene's paused timeline, its cues resolved by name", () => {
  const fx = custom();
  const r = render(fx);
  assert.equal(r.code, 0, r.out + r.err);
  const html = comp(fx, "scenes/gate.html");
  assert.match(html, /<div class="orb">Gate open<\/div>/);
  // the fragment's script is not left in the markup as a script tag
  assert.equal(html.match(/<script>/g).length, 1);
  // each selector of a rule list is scoped on its own
  assert.match(html, /\[data-composition-id="gate"\] \.orb \{ color:/);
  assert.match(html, /\[data-composition-id="gate"\] \.tag \{ color:/);
  assert.match(html, /\[data-composition-id="gate"\] \.tag \{ opacity: 0; \}/);
  assert.match(html, /gsap\.timeline\(\{ paused: true \}\)/);
  const cues = JSON.parse(html.match(/const cues = (\{.*\});/)[1]);
  assert.ok(near(cues.land, at(fx, "gate", 1)), JSON.stringify(cues));
  assert.ok(near(cues.done, at(fx, "gate", 2)), JSON.stringify(cues));
  // `$()` scopes a selector to the scene, so two scenes never share a class
  assert.match(html, /const scope = "\[data-composition-id=\\"gate\\"\]"/);
  assert.match(
    html,
    /splitSelectors\(sel\)\.map\(\(s\) => scope \+ " " \+ s\)/,
  );
  assert.doesNotMatch(
    html,
    /transition|animation|@keyframes|setTimeout|setInterval|requestAnimationFrame|Date\.now|performance\.now|Math\.random/,
  );
});

test("a selector list is split per selector, except a comma inside parentheses or brackets", () => {
  const fx = custom(
    `<div class="orb" data-x="a,b">Gate open</div>
<style>
:is(.orb, .tag) { opacity: 1; }
[data-x="a,b"], .tag { opacity: 1; }
</style>`,
  );
  const r = render(fx);
  assert.equal(r.code, 0, r.out + r.err);
  const html = comp(fx, "scenes/gate.html");
  const scope = '[data-composition-id="gate"]';
  assert.ok(html.includes(`${scope} :is(.orb, .tag) { opacity: 1; }`));
  assert.ok(html.includes(`${scope} [data-x="a,b"] { opacity: 1; }`));
  assert.ok(html.includes(`${scope} .tag { opacity: 1; }`));
});

test("the script's $ scopes every selector of a list to the scene, as the rules are, so no other scene's element moves", () => {
  const scope = '[data-composition-id="gate"]';
  const seen = [];
  const code = fragmentScript(
    scope,
    'seen.push($(".a, .b"), $(":is(.a, .b), .c"), $(\'[data-x="a,b"]\'), $(".a"), $());',
    {},
    1,
  );
  new Function("tl", "seen", code)({}, seen);
  assert.deepEqual(seen, [
    `${scope} .a, ${scope} .b`,
    `${scope} :is(.a, .b), ${scope} .c`,
    `${scope} [data-x="a,b"]`,
    `${scope} .a`,
    `${scope} .content`,
  ]);
});

test("a custom scene that shows no text stops the gates as a tool error, not a pass", () => {
  const fx = custom(
    '<div class="orb"></div><style>.orb { opacity: 1; }</style>',
  );
  const r = render(fx);
  assert.equal(r.code, 1, r.out + r.err);
  assert.match(r.err, /^gates: layout probe: no text in scene gate$/m);
  assert.ok(!fs.existsSync(path.join(fx.tmp, "videos")));
});
