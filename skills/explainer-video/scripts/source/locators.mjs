// A locator names where in its snapshot an excerpt sits, in the grammar of
// its source's kind; `segment` turns one back into that stretch of text.
import fs from "node:fs";
import path from "node:path";

// The locator forms each kind takes, as the reader writes them.
export const FORMS = {
  pdf: "page <n>",
  pptx: "slide <n> or slide <n> notes",
  md: "§ <heading>, line <n> or lines <a>-<b>",
  txt: "line <n> or lines <a>-<b>",
  html: "§ <heading>",
  docx: "§ <heading>",
  page: "§ <heading>",
  repo: "<path>:<n> or <path>:<a>-<b>",
};

const MARKER = /^<!-- (page \d+|slide \d+(?: notes)?) -->$/;
export const marker = (locator) => `<!-- ${locator} -->`;

// A Markdown snapshot's sections: each ATX heading outside a fence, with the
// lines up to the next heading of any level, the heading line included.
export function sections(text) {
  const out = [];
  let fence = null;
  for (const line of text.split("\n")) {
    const f = line.match(/^ {0,3}(`{3,}|~{3,})/);
    if (f && (!fence || f[1][0] === fence[0])) fence = fence ? null : f[1];
    const h = !fence && !f && line.match(/^ {0,3}#{1,6}\s+(.*?)(?:\s+#+)?\s*$/);
    if (h) out.push({ heading: plain(h[1]), lines: [line] });
    else out.at(-1)?.lines.push(line);
  }
  return out.map((s) => ({ heading: s.heading, text: s.lines.join("\n") }));
}

// Pages and slides: the lines after each marker, up to the next one.
function byMarker(text) {
  const out = new Map();
  let at = null;
  for (const line of text.split("\n")) {
    const m = line.match(MARKER);
    if (m) out.set((at = m[1]), []);
    else if (at) out.get(at).push(line);
  }
  return new Map([...out].map(([k, v]) => [k, v.join("\n")]));
}

function lines(text, a, b) {
  const all = text.split("\n");
  if (a < 1 || b < a || b > all.length) return null;
  return all.slice(a - 1, b).join("\n");
}

// Whitespace runs as one space: word for word, not byte for byte.
export const squash = (s) => s.replace(/\s+/g, " ").trim();

// A heading as read: a Markdown link or image reads as its text, so a page
// heading carrying its anchor (`[Validation](#validation)`) is `Validation`,
// and a linked badge (`[![CI](badge)](runs)`) is `CI`. Innermost first, until
// none is left, so reading a heading twice reads it the same.
export function plain(s) {
  for (let t; (t = s.replace(/!?\[([^[\]]*)\]\([^)]*\)/g, "$1")) !== s;) s = t;
  return squash(s);
}

// The stretches a locator names in a source's snapshot, one per section for a
// heading used twice, or `{error}` saying why there are none.
export function segment(run, source, locator) {
  const snap = path.join(run, "snapshots", source.snapshot);
  const read = () => fs.readFileSync(snap, "utf8");
  const range = (m) => [Number(m[1]), Number(m[2] ?? m[1])];
  let m;
  if (source.kind === "repo") {
    m = locator.match(/^(.+):(\d+)(?:-(\d+))?$/);
    if (!m) return { error: `not a repo locator (want ${FORMS.repo})` };
    const file = path.join(snap, m[1]);
    if (
      !file.startsWith(snap + path.sep) ||
      !fs.statSync(file, { throwIfNoEntry: false })?.isFile()
    )
      return { error: `no file ${m[1]} in the snapshot` };
    const [a, b] = range(m.slice(1));
    const text = lines(fs.readFileSync(file, "utf8"), a, b);
    return text === null
      ? { error: `no lines ${a}-${b} in ${m[1]}` }
      : { texts: [text] };
  }
  if (["md", "txt"].includes(source.kind)) {
    m = locator.match(/^lines? (\d+)(?:-(\d+))?$/);
    if (m) {
      const [a, b] = range(m);
      const text = lines(read(), a, b);
      return text === null
        ? { error: `no lines ${a}-${b}` }
        : { texts: [text] };
    }
  }
  if (["md", "html", "docx", "page"].includes(source.kind)) {
    m = locator.match(/^§ (.+)$/);
    if (m) {
      const hits = sections(read()).filter((s) => s.heading === plain(m[1]));
      return hits.length
        ? { texts: hits.map((s) => s.text) }
        : { error: `no section "${m[1]}"` };
    }
  }
  if (["pdf", "pptx"].includes(source.kind)) {
    const want = source.kind === "pdf" ? /^page \d+$/ : /^slide \d+( notes)?$/;
    if (want.test(locator)) {
      const text = byMarker(read()).get(locator);
      return text === undefined
        ? { error: `no ${locator}` }
        : { texts: [text] };
    }
  }
  return {
    error: `not a ${source.kind} locator (want ${FORMS[source.kind]})`,
  };
}
