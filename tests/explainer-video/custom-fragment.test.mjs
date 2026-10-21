// The custom scene's fragment: split into markup, style and script, and the one
// lint over all three. Every refusal names the pattern it found; a fragment
// that keeps to the profile's tokens and the timeline lints clean.
import { test } from "node:test";
import assert from "node:assert/strict";
import {
  fragmentText,
  lintFragment,
  shownText,
  splitFragment,
  techniquesIn,
} from "../../skills/explainer-video/scripts/lib/fragment.mjs";

const CLEAN = `<div class="orb"><span class="word">Ship</span></div>
<style>
.orb { color: var(--accent); font: 600 var(--size-title) var(--font-title); }
.word { font-size: calc(var(--size-body) * 1.2); background: color-mix(in srgb, var(--accent) 30%, transparent); }
</style>
<script>
tl.fromTo($(".orb"), { opacity: 0 }, { opacity: 1, duration: 0.3 }, cue("land"));
</script>`;
const lint = (src, opts = { names: ["land"] }) => lintFragment(src, opts);
const bad = (src, why, opts) => assert.throws(() => lint(src, opts), why);
const css = (rule) => `<p class="a">x</p><style>${rule}</style>`;
const js = (code) => `<p>x</p><script>${code}</script>`;

test("a fragment splits into its markup, its plain rules one to a line, and its script", () => {
  const { markup, css, script } = splitFragment(CLEAN);
  assert.match(markup, /<span class="word">Ship<\/span>/);
  assert.doesNotMatch(markup, /<style|<script/);
  assert.deepEqual(css, [
    ".orb { color: var(--accent); font: 600 var(--size-title) var(--font-title); }",
    ".word { font-size: calc(var(--size-body) * 1.2); background: color-mix(in srgb, var(--accent) 30%, transparent); }",
  ]);
  assert.match(script, /tl\.fromTo\(\$\("\.orb"\)/);
});

test("a comment in the style is not a rule, nor part of the rule after it", () => {
  const { css } = splitFragment(
    "<p>x</p><style>/* the card */ .a { opacity: 1; } /* { */ .b { opacity: 0; }</style>",
  );
  assert.deepEqual(css, [".a { opacity: 1; }", ".b { opacity: 0; }"]);
});

test("a fragment that keeps to tokens and the timeline lints clean", () => {
  assert.doesNotThrow(() => lint(CLEAN));
  assert.doesNotThrow(() =>
    lint('<p style="color: var(--muted)">issue #626 and #abc</p>'),
  );
});

test("a literal colour is refused in a rule, an inline style, an attribute and a tween", () => {
  bad(css(".a { color: #fff; }"), /literal colour #fff/);
  bad(css(".a { background: rgba(0, 0, 0, 0.5); }"), /literal colour rgba\(/);
  bad(css(".a { border: 2px solid red; }"), /literal colour red/);
  bad('<p style="color: hsl(10 20% 30%)">x</p>', /literal colour hsl\(/);
  bad('<svg><path fill="#0af" /></svg>', /literal colour #0af/);
  bad(
    js('tl.to($(".a"), { backgroundColor: "#123456" }, 0);'),
    /literal colour #123456/,
  );
  // a colour function in any string of the script, not only a coloured property
  bad(js('el.style.setProperty("x", "rgb(1, 2, 3)");'), /literal colour rgb\(/);
  // a colour named inside var() is a token's name, not a colour; a url() holds
  // a file's name
  assert.doesNotThrow(() => lint(css(".a { color: var(--tan); }")));
  assert.doesNotThrow(() =>
    lint(css(".a { background: var(--chip) url(red.png); }")),
  );
});

test("a literal font size is refused, in a rule, the font shorthand and a tween; a token or a relative size is not", () => {
  bad(css(".a { font-size: 48px; }"), /literal size 48px/);
  bad(css(".a { font: 600 40px/1.2 serif; }"), /literal size 40px/);
  bad(css(".a { font-size: x-large; }"), /literal size x-large/);
  bad(
    css(".a { font-size: calc(var(--size-body) + 4px); }"),
    /literal size 4px/,
  );
  bad(js('tl.to($(".a"), { fontSize: 52 }, 0);'), /literal size fontSize/);
  bad(js('tl.to($(".a"), { fontSize: "40px" }, 0);'), /literal size fontSize/);
  assert.doesNotThrow(() =>
    lint(js('tl.to($(".a"), { fontSize: "1.2em" }, 0);')),
  );
  assert.doesNotThrow(() =>
    lint(css(".a { font-size: 1.2em; width: 300px; }")),
  );
  assert.doesNotThrow(() =>
    lint(js('tl.to($(".a"), { fontSize: "var(--size-title)" }, 0);')),
  );
});

test("each time source is refused in the script, named", () => {
  for (const [code, name] of [
    ["const r = Math.random();", "Math.random"],
    ["const t = Date.now();", "Date.now"],
    ["const d = new Date();", "new Date"],
    ["const t = performance.now();", "performance.now"],
    ["setTimeout(() => {}, 100);", "setTimeout"],
    ["setInterval(() => {}, 100);", "setInterval"],
    ["requestAnimationFrame(() => {});", "requestAnimationFrame"],
    ["gsap.ticker.add(() => {});", "gsap.ticker"],
  ])
    bad(js(code), new RegExp(`time source ${name.replace(".", "\\.")}`));
  // text that merely says it is not a script
  assert.doesNotThrow(() => lint("<p>Date.now() reads the clock</p>"));
});

test("text drawn into a canvas or WebGL is refused in the script, named, so the layout gate sees every word", () => {
  for (const [code, name] of [
    ['ctx.fillText("Ship", 10, 20);', "fillText"],
    ['ctx.strokeText("Ship", 10, 20);', "strokeText"],
    ["const g = new TextGeometry(word, { font });", "TextGeometry"],
    ["new FontLoader().load(url, (font) => {});", "FontLoader"],
    ["const t = new troika.Text();", "troika"],
  ])
    bad(js(code), new RegExp(`text in a canvas or WebGL ${name}`));
  // a canvas that draws no text, a DOM label and plain text saying the word
  assert.doesNotThrow(() =>
    lint(
      '<canvas class="gl"></canvas><p class="lb">Ship</p>' +
        js("ctx.fillRect(0, 0, 9, 9);"),
    ),
  );
  assert.doesNotThrow(() => lint("<p>fillText draws text</p>"));
});

test("a tween off the scene's timeline is refused, since it runs on wall time", () => {
  for (const [code, name] of [
    ['gsap.to($("div"), { opacity: 0 });', "gsap.to"],
    ['gsap.fromTo($("div"), { x: 0 }, { x: 9 });', "gsap.fromTo"],
    ['gsap.set($("div"), { opacity: 0 });', "gsap.set"],
    ["const t = gsap.timeline();", "gsap.timeline"],
    ['TweenMax.to($("div"), 1, { x: 1 });', "TweenMax"],
    ["new TimelineLite();", "TimelineLite"],
  ])
    bad(js(code), new RegExp(`off the timeline ${name.replace(".", "\\.")}`));
  // the scene's own `tl`, a gsap utility and plain text are not off-timeline
  assert.doesNotThrow(() =>
    lint(
      js('const f = gsap.utils.interpolate(0, 9); tl.to($("a"), { x: 1 });'),
    ),
  );
  assert.doesNotThrow(() => lint("<p>gsap.to is a tween</p>"));
});

test("a CSS animation, a transition, keyframes, a web animation and an SVG animation are refused", () => {
  bad(css(".a { animation: spin 1s; }"), /CSS animation/);
  bad(css(".a { animation-delay: 1s; }"), /CSS animation/);
  bad(css(".a { transition: opacity 1s; }"), /CSS transition/);
  bad(css("@keyframes spin { to { opacity: 1; } }"), /@keyframes/);
  bad(js("el.animate([{ opacity: 0 }], 500);"), /web animation/);
  bad(
    '<svg><circle><animate attributeName="r" /></circle></svg>',
    /SVG animation/,
  );
  bad('<p style="transition: all 1s">x</p>', /CSS transition/);
  // in the script, any key of an object literal, not only its first
  bad(
    js('tl.to($(".a"), { opacity: 1, transition: "all 1s" }, 0);'),
    /CSS transition/,
  );
  bad(js('tl.set($(".a"), { animationName: "spin" });'), /CSS animation/);
});

test("a script that does not parse is refused at compile, and a commented-out block is neither linted nor played", () => {
  bad(js('tl.to($(".a"), { opacity: 1 }, 0'), /script syntax/);
  const commented = `<p>x</p><!-- <script>setTimeout(f, 1)</script><style>.a { color: #fff; }</style> -->`;
  assert.doesNotThrow(() => lint(commented));
  const { script, css } = splitFragment(commented);
  assert.equal(script, "");
  assert.deepEqual(css, []);
});

test("a rule the scoping cannot carry, an at-rule or a nested rule, is refused", () => {
  bad(css("@media (min-width: 1px) { .a { opacity: 1; } }"), /at-rule @media/);
  bad(css(".a { .b { opacity: 1; } }"), /nested rule/);
});

test("a per-letter span is refused in Arabic text, the span or a split into letters", () => {
  const ar = { names: [], arabic: true };
  bad("<p><span>م</span><span>ر</span></p>", /per-letter span/, ar);
  bad("<p><span>a</span><span>b</span></p>", /per-letter span/, ar);
  bad(
    "<p>مرحبا</p><script>const l = text.split('');</script>",
    /per-letter split/,
    ar,
  );
  // whole words are fine, and so are single letters outside an Arabic run
  assert.doesNotThrow(() =>
    lint("<p><span>مرحبا</span> <span>بك</span></p>", ar),
  );
  assert.doesNotThrow(() => lint("<p><span>a</span><span>b</span></p>"));
  // an Arabic letter in a span is refused whatever the run's language
  bad("<p><span>م</span></p>", /per-letter span/);
});

test("a fragment reads its cue times by name, and a name the scene does not declare, or a computed one, is refused", () => {
  assert.doesNotThrow(() => lint(js('tl.to($(".a"), { x: 1 }, cue("land"));')));
  bad(
    js('tl.to($(".a"), { x: 1 }, cue("lift"));'),
    /cue "lift" is not declared \(land\)/,
  );
  bad(
    js('const n = "land"; tl.to($(".a"), { x: 1 }, cue(n));'),
    /cue needs a string literal name/,
  );
  bad(
    js('tl.to($(".a"), { x: 1 }, cue("land" + 1));'),
    /cue needs a string literal name/,
  );
  bad(
    js('tl.to($(".a"), { x: 1 }, cue("any"));'),
    /cue "any" is not declared \(none\)/,
    {
      names: [],
    },
  );
});

test("a script that loads another file is refused, so the fragment stands alone", () => {
  bad('<p>x</p><script src="x.js"></script>', /script src/);
});

test("the techniques a fragment uses are found by their patterns, for the ban checks", () => {
  assert.deepEqual(techniquesIn(CLEAN), []);
  assert.deepEqual(techniquesIn(css(".a { filter: blur(4px); }")), ["blur"]);
  assert.deepEqual(techniquesIn(css(".a { backdrop-filter: blur(4px); }")), [
    "blur",
  ]);
  assert.deepEqual(techniquesIn(css(".a { stroke-dashoffset: 4; }")), ["draw"]);
  assert.deepEqual(
    techniquesIn(js('tl.to($(".a"), { strokeDashoffset: 0 }, 0);')),
    ["draw"],
  );
  assert.deepEqual(techniquesIn(js('const w = text.split(" ");')), ["kinetic"]);
  assert.deepEqual(
    techniquesIn(js('new SplitText($(".a"), { type: "words" });')),
    ["kinetic"],
  );
  assert.deepEqual(techniquesIn(js("tl.to($(), { scale: 1.2 }, 0);")), [
    "camera",
  ]);
  assert.deepEqual(techniquesIn(js('tl.to($(""), { x: -40 }, 0);')), [
    "camera",
  ]);
  // a class the agent names `camera` is its own: custom has no camera layer
  assert.deepEqual(
    techniquesIn(
      '<p class="camera">x</p><style>.camera { opacity: 0; }</style><script>tl.to($(".camera"), { x: 5 }, 0);</script>',
    ),
    [],
  );
  assert.deepEqual(
    techniquesIn(
      js('tl.to($(".a"), { strokeDashoffset: 0, filter: "blur(2px)" }, 0);'),
    ),
    ["draw", "blur"],
  );
});

test("the text a fragment shows is its markup without tags, styles and scripts", () => {
  assert.equal(
    fragmentText(
      '<div class="a">Ship <b>12</b> &amp; more</div><style>.a { content: "99"; }</style><script>const n = 7;</script><!-- 5 -->',
    ),
    "Ship 12 & more",
  );
});

test("the text a fragment shows also holds what its script writes, but not a counter's start at 0", () => {
  assert.equal(
    shownText(
      '<p class="n">0</p><script>tl.set($(".n"), { textContent: 42 }, 0); el.innerHTML = "1,200 files"; x.innerText = \'ok\';</script>',
    ),
    "42 1,200 files ok",
  );
  const counter =
    '<p class="n">0</p><script>tl.fromTo($(".n"), { textContent: 0 }, { textContent: 87, duration: 1 }, 0);</script>';
  assert.equal(shownText(counter), "87");
  // the 0 the markup starts the counter at is no claim either, but a 0 in a
  // fragment whose script writes no text is shown as it is written
  assert.equal(shownText("<p>Failures: <b>0</b></p>"), "Failures: 0");
  assert.equal(shownText('<p class="n">0</p>'), "0");
  // a start that is bare zero says nothing; a written zero in a string too
  assert.equal(
    shownText('<script>tl.set(a, { textContent: "0" }, 0);</script>'),
    "",
  );
  assert.equal(shownText("<p>plain</p><script>const n = 7;</script>"), "plain");
});
