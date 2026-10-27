// Canned source readers: fixture PDF, PPTX and DOCX files and rendered pages.
import fs from "node:fs";
import { log } from "./fake-backend-log.mjs";

// The source readers. A fixture .pdf holds `{"pages": [...]}` and a .pptx
// `{"parts": {path: xml}}`, both JSON; a .docx holds the HTML mammoth would
// give. renderPage answers a URL from the JSON map in
// $CREATIVE_VIDEO_FAKE_PAGES ({url: {title, html}}), a file: URL from the
// file, as the page Chrome would hand Readability once its scripts ran; its
// text is the HTML without its tags.
export async function renderPage(url) {
  log({ call: "renderPage", url });
  const text = (html) => html.replace(/<[^>]+>/g, "");
  if (url.startsWith("file:")) {
    const file = fs.readFileSync(new URL(url), "utf8");
    const html = file.replace(/^[\s\S]*<body>|<\/body>[\s\S]*$/g, "");
    return {
      title: file.match(/<title>([^<]*)<\/title>/)?.[1] ?? "",
      html,
      text: text(html),
    };
  }
  const page = JSON.parse(process.env.CREATIVE_VIDEO_FAKE_PAGES ?? "{}")[url];
  if (!page) throw new Error(`net::ERR_NAME_NOT_RESOLVED at ${url}`);
  return { ...page, text: text(page.html) };
}

// Headings to `#` lines, each block its own paragraph, other tags dropped.
export async function toMarkdown(html) {
  return html
    .replace(
      /<h([1-6])>([\s\S]*?)<\/h\1>/g,
      (_, n, t) => `\n\n${"#".repeat(n)} ${t}\n\n`,
    )
    .replace(/<\/(p|li|div)>/g, "\n\n")
    .replace(/<[^>]+>/g, "")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}

export async function pdfPages(file) {
  log({ call: "pdfPages", file });
  return JSON.parse(fs.readFileSync(file, "utf8")).pages;
}

export async function docxHtml(file) {
  return fs.readFileSync(file, "utf8");
}

export async function unzip(file) {
  return JSON.parse(fs.readFileSync(file, "utf8")).parts;
}
