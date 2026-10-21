// The `excerpt` component's props at compile, and the pack it reads: the scene
// file names an excerpt by id and never restates it, so compile resolves each
// cited id to the pack's own text and locator and keeps them in script.json,
// for a later stage to play what was checked.
import { CUE, cue, fail, known, named, object, place } from "./props.mjs";
import { ARABIC_SCRIPT } from "./terms.mjs";

// A repo source holds code unless the file it names is prose.
const PROSE_FILE = /\.(?:md|mdx|markdown|txt|rst|adoc)(?::[\d-]+)?$/i;
const EMPHASIS = ["target", ...CUE];
export const squash = (s) => s.replace(/\s+/g, " ").trim();

// The language an excerpt reads in, by its own script and not the run's: an
// English README quoted in an Arabic run is still left to right.
export const tongue = (text, code) =>
  !code && ARABIC_SCRIPT.test(text) ? "ar" : "en";

// The units an emphasis names: a code excerpt's lines as written, any other
// excerpt's sentences, whitespace squashed, as its own language's rules cut
// them (Arabic's `؟` ends one).
export function units(text, code) {
  if (code) return text.split("\n");
  return [
    ...new Intl.Segmenter(tongue(text, code), {
      granularity: "sentence",
    }).segment(text),
  ]
    .map((s) => squash(s.segment))
    .filter(Boolean);
}

// The indexes of the units a `target` names, so compile and render agree on
// which unit lights: one index is a match.
export function matching(text, code, target) {
  const want = code ? target : squash(String(target));
  return units(text, code).flatMap((u, i) => (u === want ? [i] : []));
}

// The pack's excerpts by id, each `{ text, locator, code }`.
function load(read) {
  let pack;
  try {
    pack = JSON.parse(read("excerpts.json"));
  } catch (e) {
    fail(
      e.code === "ENOENT"
        ? "excerpt needs excerpts.json beside the scene file: run the source stage first"
        : `excerpts.json cannot be read: ${e.message}`,
    );
  }
  if (!Array.isArray(pack?.sources) || !Array.isArray(pack?.excerpts))
    fail("excerpts.json must hold a sources list and an excerpts list");
  pack.sources.forEach((s, i) =>
    named(`excerpts.json source ${i + 1}`, s?.id, "an id"),
  );
  const kind = new Map(pack.sources.map((s) => [s.id, s.kind]));
  pack.excerpts.forEach((x, i) => {
    const at = `excerpts.json excerpt ${i + 1}`;
    named(at, x?.id, "an id");
    named(at, x?.text, "text");
    named(at, x?.locator, "a locator");
    // an absent source would read a repo's code as prose
    if (!kind.has(x.source))
      fail(`${at} needs a source its sources list holds`);
  });
  return new Map(
    pack.excerpts.map((x) => [
      x.id,
      {
        text: x.text,
        locator: x.locator,
        code: kind.get(x.source) === "repo" && !PROSE_FILE.test(x.locator),
      },
    ]),
  );
}

// The cites of the props, the main one first, each with the prop naming it.
const cites = (p) => [
  ["excerpt cite", p.cite],
  ...(p.chips ?? []).map((c) => ["excerpt chip cite", c.cite]),
];

// The excerpts the props cite, by id. A cite the pack lacks is refused.
export function resolveExcerpts(p, read) {
  const pack = load(read);
  const out = {};
  for (const [what, id] of cites(p)) {
    if (!pack.has(id))
      fail(
        `${what} "${id}" is not in excerpts.json; cite an id it holds, or run the source stage again`,
      );
    out[id] = pack.get(id);
  }
  return out;
}

// Throws the first reason the props `p` are not an excerpt scene for the
// scene's sentences in spoken form, `said`. `ctx.cites` holds the ids the
// scene's narration cites.
export function checkExcerpt(p, said, ctx = {}) {
  named("excerpt", p.cite, "a cite");
  if (p.chips !== undefined && !Array.isArray(p.chips))
    fail("excerpt chips needs a list of chips");
  for (const c of p.chips ?? []) {
    object(c, "an excerpt chip");
    named("excerpt chip", c.cite, "a cite");
  }
  const got = resolveExcerpts(p, ctx.read);
  const spoken = ctx.cites ?? [];
  for (const [what, id] of cites(p))
    if (!spoken.includes(id))
      fail(
        `${what} "${id}" is not cited by the scene's narration (${spoken.join(", ") || "none"})`,
      );
  let last;
  const shown = new Set([p.cite]);
  for (const [i, c] of (p.chips ?? []).entries()) {
    if (c.cite === p.cite)
      fail(
        `excerpt chip ${i + 1} cites ${c.cite}, the excerpt shown; a chip is a further excerpt`,
      );
    if (shown.has(c.cite))
      fail(
        `excerpt chip ${i + 1} cites ${c.cite} again; each chip names a different excerpt`,
      );
    shown.add(c.cite);
    cue(c, said);
    known("an excerpt chip", c, [...CUE, "cite"]);
    // Chips are numbered as they appear, so one never cues before another.
    if (last && place(c, said) < place(last, said))
      fail(`excerpt chip ${i + 1} cues before chip ${i}`);
    last = c;
  }
  const e = p.emphasis;
  if (e === undefined) return;
  object(e, "excerpt emphasis");
  cue(e, said);
  known("excerpt emphasis", e, EMPHASIS);
  const { text, code } = got[p.cite];
  const noun = code ? "line" : "sentence";
  const hits = matching(text, code, e.target).length;
  if (hits !== 1)
    fail(
      hits
        ? `excerpt emphasis target "${e.target}" matches ${hits} ${noun}s of ${p.cite}; name one`
        : `excerpt emphasis target "${e.target}" is no ${noun} of ${p.cite}`,
    );
}
