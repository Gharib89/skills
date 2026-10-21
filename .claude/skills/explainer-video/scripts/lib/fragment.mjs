// A custom scene's fragment: the agent's own HTML, with a `<style>` of plain
// rules and a `<script>` that adds to the scene's paused timeline. This module
// splits one into its parts and holds the one lint every fragment passes at
// compile; it touches no file. The lint is a guard rail, not a sandbox: the
// determinism gate is the backstop behind it for a time source it misses.
//
// The script runs as `(tl, cue, $, duration)`: the scene's timeline, a lookup
// of a declared cue's time in seconds by name, a selector scoped to the scene
// (`$(".a")`; `$()` alone is the scene's content, so moving it moves the whole
// frame) and the scene's length (render/fragment-script.mjs).
import { fail } from "./props.mjs";

const block = (tag) =>
  new RegExp(`<${tag}\\b([^>]*)>([\\s\\S]*?)</${tag}\\s*>`, "gi");
const COMMENT = /<!--[\s\S]*?-->/g;
const BLOCK_COMMENT = /\/\*[\s\S]*?\*\//g;

// The fragment's markup with its blocks cut out, its style as written, its
// plain rules one to a line (the composer scopes a line at a time), its script
// and whether a script tag loads a file.
export function splitFragment(whole) {
  // A commented-out block is neither linted nor played.
  const src = whole.replace(COMMENT, "");
  const style = [...src.matchAll(block("style"))].map((m) => m[2]).join("\n");
  const scripts = [...src.matchAll(block("script"))];
  const markup = src
    .replace(block("style"), "")
    .replace(block("script"), "")
    .trim();
  const css = style
    .replace(BLOCK_COMMENT, "")
    .replace(/\s+/g, " ")
    .split("}")
    .map((r) => r.trim())
    .filter(Boolean)
    .map((r) => `${r} }`);
  return {
    markup,
    style,
    css,
    script: scripts.map((m) => m[2]).join("\n"),
    scriptSrc: scripts.some((m) => /\bsrc\s*=/i.test(m[1])),
  };
}

// The text a viewer reads in the fragment: the markup without tags, styles,
// scripts and comments.
export const fragmentText = (src) =>
  src
    .replace(COMMENT, "")
    .replace(block("style"), "")
    .replace(block("script"), "")
    .replace(/<[^>]*>/g, " ")
    .replaceAll("&nbsp;", " ")
    .replaceAll("&lt;", "<")
    .replaceAll("&gt;", ">")
    .replaceAll("&quot;", '"')
    .replaceAll("&#39;", "'")
    .replaceAll("&amp;", "&")
    .replace(/\s+/g, " ")
    .trim();

// A value the script writes into an element's text.
const WRITTEN =
  /\b(?:textContent|innerText|innerHTML)\s*[:=]\s*(?:(["'`])((?:(?!\1).)*)\1|(-?[\d.]+))/g;

// What a viewer reads: the fragment's text, and the values its script writes
// into an element, as a counter does. A bare 0 is a counter's start, not a
// claim: the value the script writes, and the element a script that writes
// text starts at 0 in its markup.
export function shownText(src) {
  const written = [...splitFragment(src).script.matchAll(WRITTEN)].map((m) =>
    (m[2] ?? m[3]).replace(/<[^>]*>/g, " "),
  );
  const markup = written.length ? src.replace(/>\s*0\s*</g, "><") : src;
  return [fragmentText(markup), ...written.filter((v) => v !== "0")]
    .join(" ")
    .trim();
}

const NAMED = new Set(
  `aliceblue antiquewhite aqua aquamarine azure beige bisque black blanchedalmond blue blueviolet brown burlywood cadetblue chartreuse chocolate coral cornflowerblue cornsilk crimson cyan darkblue darkcyan darkgoldenrod darkgray darkgreen darkgrey darkkhaki darkmagenta darkolivegreen darkorange darkorchid darkred darksalmon darkseagreen darkslateblue darkslategray darkslategrey darkturquoise darkviolet deeppink deepskyblue dimgray dimgrey dodgerblue firebrick floralwhite forestgreen fuchsia gainsboro ghostwhite gold goldenrod gray green greenyellow grey honeydew hotpink indianred indigo ivory khaki lavender lavenderblush lawngreen lemonchiffon lightblue lightcoral lightcyan lightgoldenrodyellow lightgray lightgreen lightgrey lightpink lightsalmon lightseagreen lightskyblue lightslategray lightslategrey lightsteelblue lightyellow lime limegreen linen magenta maroon mediumaquamarine mediumblue mediumorchid mediumpurple mediumseagreen mediumslateblue mediumspringgreen mediumturquoise mediumvioletred midnightblue mintcream mistyrose moccasin navajowhite navy oldlace olive olivedrab orange orangered orchid palegoldenrod palegreen paleturquoise palevioletred papayawhip peachpuff peru pink plum powderblue purple rebeccapurple red rosybrown royalblue saddlebrown salmon sandybrown seagreen seashell sienna silver skyblue slateblue slategray slategrey snow springgreen steelblue tan teal thistle tomato turquoise violet wheat white whitesmoke yellow yellowgreen`.split(
    " ",
  ),
);
const HEX = /#(?:[0-9a-f]{8}|[0-9a-f]{6}|[0-9a-f]{3,4})\b/i;
const COLOUR_FN = /\b(?:rgba?|hsla?|hwb|lab|lch|oklab|oklch|color)\(/i;
// The properties whose value may name a colour by its keyword.
const COLOURED =
  /color|background|border|outline|fill|stroke|shadow|decoration/i;
const PX =
  /(?<![\w.-])\d*\.?\d+(?:px|pt|pc|in|cm|mm|rem|vw|vh|vmin|vmax|ch|ex)\b/;
const SIZE_WORD =
  /(?<![\w-])(?:x{1,3}-)?(?:small|large)(?![\w-])|(?<![\w-])(?:medium|smaller|larger)(?![\w-])/;

// The first literal colour a value holds, or undefined: a hex, a colour
// function or, when `keywords`, a colour name. A `var()` holds a token's name
// and a `url()` a file's.
function colourIn(value, keywords) {
  const v = value.replace(/(?:var|url)\([^)]*\)/g, "");
  return (
    v.match(HEX)?.[0] ??
    v.match(COLOUR_FN)?.[0] ??
    (keywords
      ? v.split(/[^a-z]+/i).find((w) => NAMED.has(w.toLowerCase()))
      : undefined)
  );
}

const declarations = (css) =>
  [...css.matchAll(/([a-z-]+)\s*:\s*([^;{}]+)/gi)].map((m) => [
    m[1].toLowerCase(),
    m[2],
  ]);

// Inline `style` attributes, as the CSS they hold.
const inlineStyle = (markup) =>
  [...markup.matchAll(/\bstyle\s*=\s*(?:"([^"]*)"|'([^']*)')/gi)]
    .map((m) => m[1] ?? m[2])
    .join(";");
// The colour-bearing presentation attributes of a tag, as declarations.
const colourAttrs = (markup) =>
  [
    ...markup.matchAll(
      /\b(fill|stroke|stop-color|flood-color|lighting-color|color|bgcolor)\s*=\s*(?:"([^"]*)"|'([^']*)')/gi,
    ),
  ].map((m) => `${m[1]}: ${m[2] ?? m[3]};`);

const TIME = [
  ["Math.random", /\bMath\s*\.\s*random\b/],
  ["Date.now", /\bDate\s*\.\s*now\b/],
  ["new Date", /\bnew\s+Date\b/],
  ["performance.now", /\bperformance\s*\.\s*now\b/],
  ["setTimeout", /\bsetTimeout\b/],
  ["setInterval", /\bsetInterval\b/],
  ["requestAnimationFrame", /\brequestAnimationFrame\b/],
  ["gsap.ticker", /\bgsap\s*\.\s*ticker\b/],
];
const STRING = /(["'`])((?:(?!\1)[^\\]|\\.)*)\1/g;
// A colour-bearing property of a tween or style object, with a string value.
const COLOURED_PROP =
  /\b([A-Za-z]*(?:[cC]olor|fill|stroke|background\w*|border\w*|[sS]hadow|outline\w*))\s*:\s*(["'`])((?:(?!\2).)*)\2/g;

// Throws why `src` is not a fragment a scene may use, naming the pattern.
// `names` are the cues the scene declares; `arabic` is an Arabic run, where a
// letter on its own in a span is refused too.
export function lintFragment(src, { names = [], arabic = false } = {}) {
  const { markup, style, script, scriptSrc } = splitFragment(src);
  if (scriptSrc)
    fail("script src: the fragment stands alone, so inline the file's text");
  const code = script
    .replace(BLOCK_COMMENT, "")
    .replace(/(^|[^:"'\w])\/\/.*$/gm, "$1");
  const css = [style, inlineStyle(markup), ...colourAttrs(markup)].join("\n");

  for (const [name, re] of TIME)
    if (re.test(code))
      fail(
        `time source ${name}: a frame is a function of the timeline's time alone`,
      );
  // A tween made on `gsap` or a legacy class runs on wall time, outside the
  // paused `tl` the render seeks.
  const loose = code.match(
    /\bgsap\s*\.\s*(?!utils\b|registerPlugin\b)[A-Za-z]\w*|\b(?:TweenMax|TweenLite|TimelineMax|TimelineLite)\b/,
  );
  if (loose)
    fail(
      `off the timeline ${loose[0].replace(/\s+/g, "")}: add the tween to the timeline \`tl\``,
    );
  if (/\.animate\s*\(/.test(code))
    fail("web animation .animate(): add the tween to the timeline `tl`");
  if (/<animate(?:Transform|Motion)?\b|<set\b/i.test(markup))
    fail(
      `SVG animation element ${markup.match(/<(animate\w*|set)\b/i)[0]}>: add the tween to the timeline \`tl\``,
    );
  if (/@(?:-webkit-)?keyframes\b/i.test(css))
    fail("CSS animation @keyframes: add the tween to the timeline `tl`");
  // In the script, every key of an object literal: `{ opacity: 1, transition: 0 }`.
  const keys = [
    ...code.matchAll(
      /["']?\b(animation|transition)(?:-[a-z-]+|[A-Z]\w*)?["']?\s*:/g,
    ),
  ].map((m) => m[0].replace(/["':\s]/g, ""));
  for (const prop of [...declarations(css).map(([p]) => p), ...keys]) {
    if (/^animation(?:-|[A-Z]|$)/.test(prop))
      fail(`CSS animation ${prop}: add the tween to the timeline \`tl\``);
    if (/^transition(?:-|[A-Z]|$)/.test(prop))
      fail(`CSS transition ${prop}: add the tween to the timeline \`tl\``);
  }
  if (/\.style\s*\.\s*(?:animation|transition)\w*\s*=/.test(code))
    fail(
      "CSS animation or transition set from the script: add the tween to `tl`",
    );

  const at = css.match(/(?:^|[;{}\s])(@[a-z-]+)/i)?.[1];
  if (at)
    fail(
      `at-rule ${at}: write plain rules, the composer scopes each to the scene`,
    );
  let depth = 0;
  for (const c of style.replace(BLOCK_COMMENT, ""))
    if (c === "{" && ++depth > 1)
      fail(
        "nested rule: write plain rules, the composer scopes each to the scene",
      );
    else if (c === "}") depth--;

  const colour = (value, keywords) => {
    const c = colourIn(value, keywords);
    if (c)
      fail(
        `literal colour ${c}: name a profile token, var(--accent) or var(--text)`,
      );
  };
  for (const [prop, value] of declarations(css)) {
    colour(value, COLOURED.test(prop));
    const size =
      (prop === "font-size" || prop === "font") &&
      (value.replace(/var\([^)]*\)/g, "").match(PX) ?? value.match(SIZE_WORD));
    if (size)
      fail(
        `literal size ${size[0]}: size text from a type token, var(--size-body) and its steps`,
      );
  }
  // In the script a colour is a property's string value, or a colour function
  // in any string; a hex alone in a string may be a selector (`#add`).
  for (const [, , , value] of code.matchAll(COLOURED_PROP)) colour(value, true);
  for (const [, , value] of code.matchAll(STRING))
    colour(value.replace(HEX, ""));
  // A script's `fontSize` is a token or a relative size, as in a rule: a bare
  // number is pixels to GSAP, and any other unit is as literal as in a rule.
  for (const [, , quoted, bare] of code.matchAll(
    /\bfontSize\s*[:=]\s*(?:(["'`])((?:(?!\1).)*)\1|([^\s,;})]+))/g,
  ))
    if (!/^\s*var\(|^[\d.]+(?:em|%)$/.test(quoted ?? bare))
      fail(
        `literal size fontSize ${quoted ?? bare}: size text from a type token, var(--size-body) and its steps`,
      );

  const inArabic = arabic || /\p{Script=Arabic}/u.test(markup);
  for (const [span, letter] of markup.matchAll(
    /<span\b[^>]*>\s*(\p{L}\p{M}*)\s*<\/span>/gu,
  ))
    if (arabic || /\p{Script=Arabic}/u.test(letter))
      fail(
        `per-letter span ${span} in Arabic text: Arabic moves by whole words, never letters`,
      );
  if (inArabic && /\.split\(\s*(?:""|''|``|\/\(\?:\)\/u?)\s*\)/.test(code))
    fail(
      "per-letter split in Arabic text: Arabic moves by whole words, never letters",
    );

  // A script that does not parse would break the whole scene's timeline at
  // render, so it fails here, not there. `Function` compiles the body only.
  try {
    new Function("tl", "cue", "$", "duration", script);
  } catch (e) {
    fail(`script syntax: ${e.message}`);
  }

  const calls = code.match(/\bcue\s*\(/g)?.length ?? 0;
  const named = [
    ...code.matchAll(/\bcue\s*\(\s*(["'`])((?:(?!\1).)*)\1\s*\)/g),
  ].map((m) => m[2]);
  if (named.length < calls)
    fail(
      'cue needs a string literal name, as cue("land"), so the lint can read it',
    );
  for (const n of named)
    if (!names.includes(n))
      fail(
        `cue "${n}" is not declared (${names.join(", ") || "none"}): add it to the scene's cues`,
      );
}

// What each technique a style profile may ban looks like in a fragment: the
// ban checks read these where a component's name would say it.
const USES = {
  draw: /stroke-?dash(?:offset|array)|drawSVG/i,
  blur: /\bblur\s*\(|backdrop-?filter|feGaussianBlur/i,
  kinetic: /SplitText|\.split\(\s*(?:(["'`])\s\1|\/\\s\+?\/[a-z]*)\s*\)/,
  camera: /\$\(\s*(?:(["'`])\s*\1)?\s*\)|\.camera\b/,
};

// The techniques `src` uses, in the order of USES.
export function techniquesIn(src) {
  const { style, script } = splitFragment(src);
  const code = [style, script, src.match(/<[^>]*>/g)?.join("") ?? ""].join(
    "\n",
  );
  return Object.keys(USES).filter((t) => USES[t].test(code));
}
