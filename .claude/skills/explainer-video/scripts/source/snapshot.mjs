// The source stage's first half: each source read into a verbatim snapshot.
//
//   node snapshot.mjs <run-folder> [--minutes <n>] <source>...
//
// A source is a git repo folder, a web page URL, or a .pdf, .md, .txt, .html,
// .docx or .pptx file. A repo snapshot is a copy of the files git lists as
// tracked or untracked and not ignored, less `.env*` files and any file whose
// name or text matches a secret pattern. A page, and an HTML file, render in
// HyperFrames' Chrome first; HTML and DOCX end as Markdown, a PDF as one block
// per page, a PPTX as one per slide and one per slide's notes, each after a
// `<!-- page <n> -->` or `<!-- slide <n>[ notes] -->` marker line. Markdown
// and text are copied as they are.
// stdout: `source <id>: <kind> · <n> <unit> · <source>` per source,
//         `withheld <id>/<path>: <why>` per repo file left out, then
//         `budget: <b> excerpts (...); shares <id> <n>, ...`
// writes: <run>/snapshots/ (replaced whole), its sources.json, and
//         explainers/.gitignore
// exit:   0 read · 1 a source refused or unreadable, `source <source>: <why>`
//         on stderr, and no sources.json · 2 usage
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { writeIgnore } from "../lib/runfolder.mjs";
import { catalogue, dest, hyperframesEnv, loadBackend } from "../lib/tools.mjs";
import { marker, sections } from "./locators.mjs";

const args = process.argv.slice(2);
const run = args.shift();
let minutes = 2;
const given = [];
while (args.length) {
  const a = args.shift();
  if (a === "--minutes") minutes = Number(args.shift());
  else given.push(a);
}
if (!run || !given.length || !(minutes > 0)) {
  console.error(
    "usage: node snapshot.mjs <run-folder> [--minutes <n>] <source>...",
  );
  process.exit(2);
}

const EXT = {
  ".pdf": "pdf",
  ".md": "md",
  ".markdown": "md",
  ".txt": "txt",
  ".html": "html",
  ".htm": "html",
  ".docx": "docx",
  ".pptx": "pptx",
};
const UNIT = {
  pdf: "page(s)",
  pptx: "slide(s)",
  md: "section(s)",
  html: "section(s)",
  docx: "section(s)",
  page: "section(s)",
  txt: "line(s)",
  repo: "file(s)",
};
// The rows a kind reads with: the npm install for every converter, Chrome for
// what renders.
const NEEDS = {
  pdf: ["npm"],
  docx: ["npm"],
  pptx: ["npm"],
  html: ["npm", "chrome"],
  page: ["npm", "chrome"],
};

// A repo file left out, by name or by text. A match withholds the whole file.
const SECRET_NAMES = [
  /^\.env/,
  /\.(pem|key|p12|pfx|jks|keystore|kdbx|ovpn)$/i,
  /^id_(rsa|dsa|ecdsa|ed25519)/,
  /^(\.npmrc|\.pypirc|\.netrc|\.git-credentials|\.htpasswd)$/,
  /^credentials(\.json)?$/i,
];
const SECRET_TEXT = [
  /-----BEGIN [A-Z ]*PRIVATE KEY( BLOCK)?-----/,
  /\bAKIA[0-9A-Z]{16}\b/,
  /\bgh[pousr]_[A-Za-z0-9]{36,}/,
  /\bgithub_pat_[A-Za-z0-9_]{22,}/,
  /\bglpat-[A-Za-z0-9_-]{20,}/,
  /\bxox[abprs]-[A-Za-z0-9-]{10,}/,
  /\bAIza[0-9A-Za-z_-]{35}\b/,
  /\bsk-(ant-|proj-)?[A-Za-z0-9_-]{32,}/,
  /\bnpm_[A-Za-z0-9]{36}\b/,
  /\b(api[_-]?key|secret|token|passw(or)?d)\b["']?\s*[:=]\s*["'][A-Za-z0-9/+_=-]{16,}["']/i,
];

const errors = [];
const refuse = (source, why) => errors.push(`source ${source}: ${why}`);

function kindOf(s) {
  if (/^https?:\/\//i.test(s)) return "page";
  const st = fs.statSync(s, { throwIfNoEntry: false });
  if (!st) return refuse(s, "no such file or folder");
  if (st.isDirectory()) return "repo";
  return (
    EXT[path.extname(s).toLowerCase()] ??
    refuse(
      s,
      `cannot read ${path.extname(s) || "a file with no extension"}: give a git repo folder, a web page URL, or a .pdf, .md, .txt, .html, .docx or .pptx file`,
    )
  );
}

const kinds = given.map(kindOf);
const rows = catalogue();
for (const k of new Set(kinds.flatMap((k) => NEEDS[k] ?? [])))
  for (const r of rows.filter((r) => r.kind === k))
    if (!fs.existsSync(path.join(dest(r), ".stamp")))
      errors.push(
        `source: ${r.id} is not installed: run /explainer-video setup`,
      );
if (errors.length) stop();

function stop() {
  for (const e of errors) console.error(e);
  fs.rmSync(path.join(run, "snapshots", "sources.json"), { force: true });
  process.exit(1);
}

// Ids from each source's name, kebab-case, a repeat numbered.
const ids = new Set();
function idOf(s, kind) {
  const base =
    kind === "page"
      ? new URL(s).hostname.replace(/^www\./, "") +
        "-" +
        (new URL(s).pathname.split("/").filter(Boolean).pop() ?? "")
      : path.basename(path.resolve(s), kind === "repo" ? "" : path.extname(s));
  const slug =
    base
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, "-")
      .replace(/^-|-$/g, "") || "source";
  let id = slug;
  for (let n = 2; ids.has(id); n++) id = `${slug}-${n}`;
  ids.add(id);
  return id;
}

const XML_ENT = { amp: "&", lt: "<", gt: ">", quot: '"', apos: "'" };
const xmlText = (s) =>
  s.replace(/&(#x[0-9a-f]+|#\d+|\w+);/gi, (m, e) =>
    e[0] === "#"
      ? String.fromCodePoint(
          e[1].toLowerCase() === "x"
            ? parseInt(e.slice(2), 16)
            : Number(e.slice(1)),
        )
      : (XML_ENT[e] ?? m),
  );
// A shape tree's text, one line per paragraph, runs joined.
const paragraphs = (xml) =>
  [...xml.matchAll(/<a:p[ >][\s\S]*?<\/a:p>/g)]
    .map((p) =>
      [...p[0].matchAll(/<a:t>([^<]*)<\/a:t>/g)]
        .map((t) => xmlText(t[1]))
        .join(""),
    )
    .filter((t) => t.trim())
    .join("\n");
const rels = (xml = "") =>
  Object.fromEntries(
    [...xml.matchAll(/<Relationship [^>]*>/g)].map((r) => [
      r[0].match(/Id="([^"]+)"/)[1],
      {
        type: r[0].match(/Type="([^"]+)"/)[1],
        target: r[0].match(/Target="([^"]+)"/)[1],
      },
    ]),
  );
const partOf = (from, target) =>
  path.posix.normalize(path.posix.join(path.posix.dirname(from), target));
const relsOf = (part) =>
  path.posix.join(
    path.posix.dirname(part),
    "_rels",
    `${path.posix.basename(part)}.rels`,
  );

// Slides in the order the deck shows them (presentation.xml's list), each
// with its notes: the notes page's body placeholder, not its slide number.
function pptx(parts) {
  const deck = "ppt/presentation.xml";
  const deckRels = rels(parts[relsOf(deck)]);
  return [...(parts[deck] ?? "").matchAll(/<p:sldId [^>]*r:id="([^"]+)"/g)].map(
    (m) => {
      const slide = partOf(deck, deckRels[m[1]].target);
      const notesRel = Object.values(rels(parts[relsOf(slide)])).find((r) =>
        r.type.endsWith("/notesSlide"),
      );
      const notesXml = notesRel
        ? (parts[partOf(slide, notesRel.target)] ?? "")
        : "";
      const body = [...notesXml.matchAll(/<p:sp>[\s\S]*?<\/p:sp>/g)]
        .map((s) => s[0])
        .filter((s) => /<p:ph [^>]*type="body"/.test(s));
      return {
        text: paragraphs(parts[slide] ?? ""),
        notes: body.map(paragraphs).join("\n"),
      };
    },
  );
}

const titled = (title, md) => (/^#\s/.test(md) ? md : `# ${title}\n\n${md}`);

function listRepo(dir) {
  const r = spawnSync(
    "git",
    ["ls-files", "-z", "--cached", "--others", "--exclude-standard"],
    { cwd: dir, encoding: "utf8", maxBuffer: 1 << 28 },
  );
  return r.status === 0
    ? [...new Set(r.stdout.split("\0").filter(Boolean))]
    : null;
}

const snaps = path.join(run, "snapshots");
fs.rmSync(snaps, { recursive: true, force: true });
fs.mkdirSync(snaps, { recursive: true });
const backend = await loadBackend();
const sources = [];
const lines = [];

for (const [i, s] of given.entries()) {
  const kind = kinds[i];
  const id = idOf(s, kind);
  const name = path.basename(s);
  let title = name;
  let text;
  let count;
  const withheld = [];
  const before = errors.length;
  try {
    if (kind === "repo") {
      const files = listRepo(s);
      if (!files)
        refuse(
          s,
          "not inside a git repository: a folder is read as a repo, so git can say which files are ignored",
        );
      else {
        count = 0;
        title = path.basename(path.resolve(s));
        for (const f of files) {
          const from = path.join(s, f);
          const st = fs.lstatSync(from, { throwIfNoEntry: false });
          if (!st?.isFile()) continue;
          const buf = fs.readFileSync(from);
          if (buf.subarray(0, 8192).includes(0)) continue;
          const body = buf.toString("utf8");
          const why = SECRET_NAMES.some((p) => p.test(path.basename(f)))
            ? path.basename(f).startsWith(".env")
              ? ".env file"
              : "secret file name"
            : SECRET_TEXT.some((p) => p.test(body))
              ? "secret pattern"
              : null;
          if (why) {
            withheld.push(`withheld ${id}/${f}: ${why}`);
            continue;
          }
          const to = path.join(snaps, id, f);
          fs.mkdirSync(path.dirname(to), { recursive: true });
          fs.writeFileSync(to, body);
          count++;
        }
      }
    } else if (kind === "md" || kind === "txt") {
      text = fs.readFileSync(s, "utf8");
      if (kind === "md") title = text.match(/^#\s+(.+)$/m)?.[1].trim() ?? name;
      count = kind === "md" ? sections(text).length : text.split("\n").length;
    } else if (kind === "pdf") {
      const pages = await backend.pdfPages(s);
      if (!pages.some((p) => p.trim()))
        refuse(
          s,
          "a scanned PDF with no text layer, so there is nothing to read: give a PDF with selectable text, or the document as Markdown or text",
        );
      text = pages.map((p, n) => `${marker(`page ${n + 1}`)}\n${p}`).join("\n");
      count = pages.length;
    } else if (kind === "pptx") {
      const slides = pptx(await backend.unzip(s));
      text = slides
        .map(
          (sl, n) =>
            `${marker(`slide ${n + 1}`)}\n${sl.text}` +
            (sl.notes
              ? `\n${marker(`slide ${n + 1} notes`)}\n${sl.notes}`
              : ""),
        )
        .join("\n");
      count = slides.length;
    } else if (kind === "docx") {
      text = titled(name, await backend.toMarkdown(await backend.docxHtml(s)));
    } else {
      const url = kind === "page" ? s : pathToFileURL(path.resolve(s)).href;
      const page = await backend.renderPage(url, { env: hyperframesEnv() });
      title = page.title?.trim() || (kind === "page" ? s : name);
      text = titled(title, await backend.toMarkdown(page.html));
    }
  } catch (e) {
    refuse(s, `could not read it: ${e.message}`);
  }
  if (errors.length > before) continue;
  const snapshot = kind === "repo" ? id : `${id}.md`;
  if (text !== undefined) fs.writeFileSync(path.join(snaps, snapshot), text);
  count ??= sections(text).length;
  sources.push({ id, kind, source: s, title, snapshot });
  lines.push(
    `source ${id}: ${kind} · ${count} ${UNIT[kind]} · ${s}`,
    ...withheld,
  );
}
if (errors.length) stop();

// The excerpt budget, split as evenly as it goes, the first sources taking
// what is left over.
const budget = Math.max(12, Math.ceil(8 * minutes));
sources.forEach((src, i) => {
  src.share =
    Math.floor(budget / sources.length) + (i < budget % sources.length ? 1 : 0);
});
fs.writeFileSync(
  path.join(snaps, "sources.json"),
  JSON.stringify({ minutes, budget, sources }, null, 2) + "\n",
);
writeIgnore(run);
for (const l of lines) console.log(l);
console.log(
  `budget: ${budget} excerpts (${minutes} min at 8 per minute, at least 12); shares ${sources.map((s) => `${s.id} ${s.share}`).join(", ")}`,
);
