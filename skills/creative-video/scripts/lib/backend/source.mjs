// The backend's source readers.
import fs from "node:fs";
import { pathToFileURL } from "node:url";
import { toolPaths } from "../tools.mjs";
import { findChrome } from "./browser.mjs";
import { fromCache } from "./common.mjs";

// The source stage's readers, each one format to text or HTML; the stage turns
// HTML to Markdown through toMarkdown and splits each snapshot by locator.

// A web page (or a local HTML file, by its file: URL) as it reads once its
// scripts have run: loaded in HyperFrames' Chrome until the network is idle,
// then Readability, run inside the page, keeps the article. A page Readability
// finds no article in keeps its whole body.
export async function renderPage(url, { env }) {
  const req = fromCache(toolPaths().node);
  const browser = await sandboxed(env);
  try {
    const page = await browser.newPage();
    // The page's own CSP would block the injected Readability script.
    await page.setBypassCSP(true);
    // A page that never goes idle (a poll, a stream) is read as it stands.
    const res = await page
      .goto(url, { waitUntil: "networkidle0", timeout: 30000 })
      .catch((e) => {
        if (e.name !== "TimeoutError") throw e;
      });
    if (res && !res.ok()) throw new Error(`HTTP ${res.status()} at ${url}`);
    await page.addScriptTag({
      path: req.resolve("@mozilla/readability/Readability.js"),
    });
    return await page.evaluate(() => {
      const a = new window.Readability(document.cloneNode(true)).parse();
      return a?.content
        ? {
            title: a.title || document.title,
            html: a.content,
            text: a.textContent,
          }
        : {
            title: document.title,
            html: document.body?.innerHTML ?? "",
            text: document.body?.innerText ?? "",
          };
    });
  } finally {
    await browser.close();
  }
}

// A page from the internet, or a file the user hands in, gets Chrome's sandbox
// where it starts; it does not where the kernel bars unprivileged user
// namespaces (Ubuntu's AppArmor default) or as root, and there it runs
// unsandboxed.
export function sandboxed(env) {
  const launch = (args) =>
    fromCache(toolPaths().node)("puppeteer-core").launch({
      headless: true,
      executablePath: findChrome(env.HOME),
      args,
    });
  return launch([]).catch(() => launch(["--no-sandbox"]));
}

// HTML to Markdown, headings as `#` lines, with Turndown's Markdown escaping
// off: a snapshot is read and quoted word for word, never rendered.
export async function toMarkdown(html) {
  const Turndown = fromCache(toolPaths().node)("turndown");
  const td = new Turndown({
    headingStyle: "atx",
    codeBlockStyle: "fenced",
    bulletListMarker: "-",
  });
  td.escape = (s) => s;
  return td.turndown(html);
}

// A PDF's text, one string per page, a line break where pdf.js marks one.
export async function pdfPages(file) {
  const entry = fromCache(toolPaths().node).resolve(
    "pdfjs-dist/legacy/build/pdf.mjs",
  );
  const pdfjs = await import(pathToFileURL(entry).href);
  const task = pdfjs.getDocument({
    data: new Uint8Array(fs.readFileSync(file)),
    isEvalSupported: false,
    verbosity: 0,
  });
  const doc = await task.promise;
  const pages = [];
  for (let n = 1; n <= doc.numPages; n++) {
    const { items } = await (await doc.getPage(n)).getTextContent();
    pages.push(items.map((i) => i.str + (i.hasEOL ? "\n" : "")).join(""));
  }
  await task.destroy();
  return pages;
}

// A DOCX as HTML, Word's heading styles as h1 to h6.
export async function docxHtml(file) {
  const mammoth = fromCache(toolPaths().node)("mammoth");
  return (await mammoth.convertToHtml({ path: file })).value;
}

// A zip's XML parts and their .rels by path, as text; a PPTX's media stays
// unread.
export async function unzip(file) {
  const JSZip = fromCache(toolPaths().node)("jszip");
  const zip = await JSZip.loadAsync(fs.readFileSync(file));
  const out = {};
  for (const f of Object.values(zip.files))
    if (!f.dir && /\.(xml|rels)$/.test(f.name))
      out[f.name] = await f.async("string");
  return out;
}
