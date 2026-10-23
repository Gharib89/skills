// Kept terms: the English words an Arabic run leaves in Latin letters. One
// rule finds them everywhere (captions, screen text, the board's list, an edit
// to one), so a term reads the same in speech, on screen and in captions.

// A Latin run: Latin words, digits among them, joined by single spaces, ending
// on a letter, a digit, `#` or `+` (so `C++` and `C#` hold together and a
// sentence's full stop stays outside).
const RUN =
  /[A-Za-z0-9](?:[A-Za-z0-9#+._/-]*(?: [A-Za-z0-9#+._/-]+)*[A-Za-z0-9#+])?/g;

export const latinRuns = (text) => text.match(RUN) ?? [];

// The text cut around its Latin runs: the runs at odd indexes.
export const splitLatin = (text) => text.split(new RegExp(`(${RUN.source})`));

// The words of `text`, each moved whole. Right to left, a Latin run (an English
// term) is one word however many it holds, and Arabic letters glued to it stay
// in that word, so its order survives the reading direction.
export function wholeWords(text, rtl) {
  const glued = rtl
    ? splitLatin(String(text))
        .map((p, i) => (i % 2 ? p.replace(/\s+/g, "\0") : p))
        .join("")
    : String(text);
  return glued
    .split(/\s+/)
    .filter(Boolean)
    .map((w) => w.replaceAll("\0", " "));
}

export const ARABIC_SCRIPT = /\p{Script=Arabic}/u;

// An Arabic letter: Arabic-Indic digits are in the script but are no letter.
export const ARABIC_LETTER = /(?=\p{Script=Arabic})\p{L}/u;

// A narration's `{written|spoken}` pair: the term as captioned, then as said.
export const BRACES = /\{([^|}]*)\|([^}]*)\}/g;

// A written caption token of Latin letters and no Arabic ones.
export const isLatin = (token) =>
  /[A-Za-z]/.test(token) && !ARABIC_SCRIPT.test(token);

// Whether a written token ends in a Latin run holding a letter (`pull`,
// `وpull`), so a Latin token after it continues the same term.
const LAST_RUN = new RegExp(`(?:${RUN.source})$`);
export const endsLatin = (token) =>
  /[A-Za-z]/.test(token.match(LAST_RUN)?.[0] ?? "");

// A visual with each screen string passed through `fn`. Code frames and
// terminal lines are code, kept as written, so they hold no kept term; nor
// does an excerpt, which holds the pack's own words, its ids and its locators,
// none of which a rewrite may change; nor do the keys a component reads as
// values (`component`, `lang`).
export function mapScreen(visual, fn) {
  if (["code", "codediff", "excerpt"].includes(visual.component)) return visual;
  const walk = (v, key) => {
    if (typeof v === "string")
      return key === "text" && visual.component === "terminal" ? v : fn(v);
    if (Array.isArray(v)) return v.map((x) => walk(x, key));
    if (v && typeof v === "object")
      return Object.fromEntries(
        Object.entries(v).map(([k, x]) => [
          k,
          ["component", "lang"].includes(k) ? x : walk(x, k),
        ]),
      );
    return v;
  };
  return walk(visual);
}

// A compiled script's kept terms, in order of first use in the scenes, then
// the title's.
export function keptTerms(script) {
  const seen = new Set();
  const add = (text) => {
    for (const run of latinRuns(text)) if (/[A-Za-z]/.test(run)) seen.add(run);
    return text;
  };
  for (const s of script.scenes) {
    s.captions.flat().forEach((c) => add(c.text));
    mapScreen(s.visual, add);
  }
  add(script.title);
  return [...seen];
}

// Each Latin run that is a key of `spellings` (a Map of kept term to its new
// spelling) replaced by its value, all in one pass, so two terms can swap. A
// longer run holding one (`CI/CD`, `pull request review`) is a kept term of its
// own, left as it is.
export const rename = (text, spellings) =>
  splitLatin(text)
    .map((p, i) => (i % 2 && spellings.has(p) ? spellings.get(p) : p))
    .join("");

// A narration line renamed as `rename` does, its terms read as written: a
// braced `{written|spoken}` inside a respelt term (`{pull|بول} request`) loses
// its spoken form, which spelt out the old term, so the new one is said as
// written. Every other brace stays.
export function respell(text, spellings) {
  const spans = [];
  let shift = 0;
  const written = text.replace(BRACES, (m, w, _s, at) => {
    spans.push([at - shift, at - shift + w.length]);
    shift += m.length - w.length;
    return w;
  });
  const hit = [];
  let at = 0;
  splitLatin(written).forEach((p, i) => {
    if (i % 2 && spellings.has(p)) hit.push([at, at + p.length]);
    at += p.length;
  });
  let n = 0;
  const unbraced = text.replace(BRACES, (m, w) => {
    const [a, b] = spans[n++];
    return hit.some(([x, y]) => a < y && x < b) ? w : m;
  });
  return rename(unbraced, spellings);
}
