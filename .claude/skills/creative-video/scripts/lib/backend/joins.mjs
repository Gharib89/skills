// The backend's joins measure, shaped runs (#976): at a sample frame each scene's
// text is set again at rest, cut into words, each word split where the browser
// shapes alone, and each piece shaped with HarfBuzz in the face Chrome drew it
// in, then compared with the word shaped whole. gates/joins.mjs judges it.
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { sfnt } from "../sfnt.mjs";
import { fromCache } from "./common.mjs";

// Runs in the page: each shown scene host's text, copied beside it with its
// motion stripped and every element's `display` kept, since a box that is not
// `inline` is where the browser shapes alone. A word ends at white space, or
// where two boxes stand more than a tenth of the face's size apart or on
// different lines. Each box a word is split across is marked
// `data-hf-joins="<k>"` on the original, whose face CDP reports. Returns the
// words worth shaping: an Arabic word split across boxes, and a Latin or digit
// run split across boxes whose last character sits left of its first, which
// an RTL line has reversed.
function restingWords() {
  // lib/rtl.mjs's ARABIC_LETTER, written here since this runs in the page.
  const ARABIC = /(?=\p{Script=Arabic})\p{L}/u;
  const SKIP = "script, style, [data-layout-ignore]";
  const texts = (root) => {
    const out = [];
    const walk = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
    for (let n = walk.nextNode(); n; n = walk.nextNode()) out.push(n);
    return out;
  };
  const boxOf = (n, top) => {
    for (let el = n.parentElement; el && el !== top; el = el.parentElement)
      if (!["inline", "contents"].includes(getComputedStyle(el).display))
        return el;
    return top;
  };
  const apart = (a, b) =>
    Math.max(a.rect.left - b.rect.right, b.rect.left - a.rect.right) >
      b.size / 10 ||
    Math.min(a.rect.bottom, b.rect.bottom) - Math.max(a.rect.top, b.rect.top) <
      Math.min(a.rect.height, b.rect.height) / 2;
  const keys = new Map();
  const out = [];
  for (const host of document.querySelectorAll("[data-composition-src]")) {
    if (!host.checkVisibility()) continue;
    const nodes = texts(host);
    const copy = host.cloneNode(true);
    copy.removeAttribute("id");
    copy.removeAttribute("data-composition-src");
    for (const el of [copy, ...copy.querySelectorAll("*")]) {
      const s = el.style;
      if (!s) continue;
      for (const p of [
        "transform",
        "translate",
        "rotate",
        "scale",
        "filter",
        "animation",
        "transition",
      ])
        s.setProperty(p, "none", "important");
      s.setProperty("opacity", "1", "important");
      s.setProperty("visibility", "visible", "important");
    }
    host.after(copy);
    const twins = texts(copy);
    const chars = [];
    nodes.forEach((n, i) => {
      if (n.parentElement?.closest(SKIP)) return;
      const box = boxOf(n, host);
      if (!box.checkVisibility()) return;
      const twin = twins[i];
      const size = parseFloat(getComputedStyle(twin.parentElement).fontSize);
      for (let o = 0; o < n.data.length; o++) {
        const range = document.createRange();
        range.setStart(twin, o);
        range.setEnd(twin, o + 1);
        const rect = range.getBoundingClientRect();
        chars.push({ c: n.data[o], box, twin: boxOf(twin, copy), rect, size });
      }
    });
    const words = [];
    let cur = null;
    let prev = null;
    for (const ch of chars) {
      if (/\s/.test(ch.c)) {
        cur = null;
        continue;
      }
      if (cur && prev.twin !== ch.twin && apart(prev, ch)) cur = null;
      if (!cur) words.push((cur = []));
      cur.push(ch);
      prev = ch;
    }
    copy.remove();
    const found = [];
    for (const w of words) {
      const runs = [];
      for (const ch of w) {
        if (runs.at(-1)?.box !== ch.box) runs.push({ box: ch.box, text: "" });
        runs.at(-1).text += ch.c;
      }
      if (runs.length < 2) continue;
      const text = w.map((ch) => ch.c).join("");
      const arabic = ARABIC.test(text);
      const reversed =
        !arabic &&
        /^[\p{L}\p{N}]+$/u.test(text) &&
        w[0].rect.left > w.at(-1).rect.left + 1;
      if (!arabic && !reversed) continue;
      for (const r of runs)
        if (!keys.has(r.box)) {
          keys.set(r.box, keys.size);
          r.box.setAttribute("data-hf-joins", keys.get(r.box));
        }
      found.push({
        text: text.replaceAll("\u200d", ""),
        runs: runs.map((r) => ({ text: r.text, k: keys.get(r.box) })),
        reversed,
      });
    }
    out.push({ scene: host.id, words: found });
  }
  return out;
}

// Runs in the page: every URL an @font-face rule's src names.
function faceUrls() {
  const urls = new Set();
  const walk = (rules, base) => {
    for (const r of rules)
      if (r instanceof CSSFontFaceRule)
        for (const m of r.style
          .getPropertyValue("src")
          .matchAll(/url\(\s*["']?([^"')]+)["']?\s*\)/g))
          urls.add(new URL(m[1], base).href);
      else if (r.cssRules) walk(r.cssRules, base);
  };
  for (const s of document.styleSheets)
    try {
      walk(s.cssRules, s.href ?? document.baseURI);
    } catch {
      // A cross-origin sheet's rules cannot be read; its faces stay unresolved.
    }
  return [...urls];
}

// The bytes a face URL serves from the project folder `root`, a data: URL's
// own, or null for anything else.
export function urlBytes(href, origin, root) {
  const u = new URL(href);
  if (u.protocol === "data:") {
    // Split as Fetch's data: URL processor splits it: the fragment dropped,
    // the body everything after the first comma, raw commas included,
    // percent-decoded byte by byte (a face is binary, not UTF-8 text), then
    // base64-decoded where the head ends `;base64`, in any case and spacing.
    const url = href.split("#")[0];
    const comma = url.indexOf(",");
    if (comma < 0) return null;
    const body = url
      .slice(comma + 1)
      .replace(/%([0-9a-f]{2})/gi, (_, h) =>
        String.fromCharCode(parseInt(h, 16)),
      );
    const base64 = /; *base64 *$/i.test(url.slice("data:".length, comma));
    return Buffer.from(body, base64 ? "base64" : "latin1");
  }
  if (u.origin !== origin) return null;
  const file = path.join(root, decodeURIComponent(u.pathname));
  return file.startsWith(root + path.sep) && fs.existsSync(file)
    ? fs.readFileSync(file)
    : null;
}

// An installed face's file by its PostScript name, through fontconfig.
function systemFace(ps) {
  const r = spawnSync(
    "fc-list",
    [`:postscriptname=${ps.replace(/[\\:,-]/g, "\\$&")}`, "file"],
    { encoding: "utf8" },
  );
  const file = r.status === 0 && r.stdout.split("\n")[0].replace(/:\s*$/, "");
  return file && fs.existsSync(file) ? fs.readFileSync(file) : null;
}

// A measure for one page served from `root`: `at()` measures the frame the page
// is seeked to and answers `{ checked, broken: [{ scene, word, face }], asks:
// [{ scene, what }] }`, `checked` the words it shaped. An ask is what shaping
// cannot see, for the critic's `rtl` kind: a word whose face resolves to no
// file, and a reversed Latin or digit run.
export async function joinsMeasure(page, root, nodeDir) {
  const require = fromCache(nodeDir);
  const hb = await import(pathToFileURL(require.resolve("harfbuzzjs")).href);
  const cdp = await page.createCDPSession();
  await cdp.send("DOM.enable");
  await cdp.send("CSS.enable");
  const origin = new URL(page.url()).origin;

  // Each face as HarfBuzz shapes it, by PostScript name: a custom face from
  // the files the page's @font-face rules serve, an installed one from
  // fontconfig. `glyphs(text)` is the text's glyph ids and offsets in visual
  // order, ZWJ's own glyph dropped; null where the face lacks a glyph.
  let served = null;
  const fonts = new Map();
  const shaper = (bytes, name) => {
    const font = bytes && sfnt(bytes, name);
    if (!font) return null;
    const hbFace = new hb.Face(new hb.Blob(new Uint8Array(font)));
    const hbFont = new hb.Font(hbFace);
    const run = (text) => {
      const buf = new hb.Buffer();
      buf.addText(text);
      buf.guessSegmentProperties();
      buf.setDirection(hb.Direction.RTL);
      hb.shape(hbFont, buf);
      const pos = buf.getGlyphPositions();
      const out = buf.getGlyphInfos().map((g, i) => ({
        g: g.codepoint,
        ax: pos[i].xAdvance,
        id: `${g.codepoint}@${pos[i].xOffset},${pos[i].yOffset}`,
      }));
      buf.destroy?.();
      return out;
    };
    const zwj = new Set(run("\u200d").map((x) => x.g));
    return {
      ps: hbFace.getName(6, "en"),
      glyphs: (text) => {
        const got = run(text).filter((x) => !(zwj.has(x.g) && x.ax === 0));
        return got.some((x) => x.g === 0)
          ? null
          : got.map((x) => x.id).reverse();
      },
    };
  };
  const face = async ({ postScriptName: ps, isCustomFont }) => {
    if (fonts.has(ps)) return fonts.get(ps);
    let found = null;
    if (isCustomFont) {
      served ??= (await page.evaluate(faceUrls))
        .map((href) =>
          shaper(
            urlBytes(href, origin, root),
            href.startsWith("data:") ? "a face in a data: URL" : href,
          ),
        )
        .filter(Boolean);
      found = served.find((s) => s.ps === ps) ?? null;
    } else found = shaper(systemFace(ps), ps);
    fonts.set(ps, found);
    return found;
  };

  return {
    async at() {
      const scenes = await page.evaluate(restingWords);
      const { root: doc } = await cdp.send("DOM.getDocument", { depth: 0 });
      const { nodeIds } = await cdp.send("DOM.querySelectorAll", {
        nodeId: doc.nodeId,
        selector: "[data-hf-joins]",
      });
      const drawn = new Map();
      for (const nodeId of nodeIds) {
        const { attributes } = await cdp.send("DOM.getAttributes", { nodeId });
        const k = +attributes[attributes.indexOf("data-hf-joins") + 1];
        drawn.set(
          k,
          (await cdp.send("CSS.getPlatformFontsForNode", { nodeId })).fonts,
        );
      }
      await page.evaluate(() =>
        document
          .querySelectorAll("[data-hf-joins]")
          .forEach((el) => el.removeAttribute("data-hf-joins")),
      );
      const out = { checked: 0, broken: [], asks: [] };
      for (const { scene, words } of scenes)
        for (const w of words) {
          if (w.reversed) {
            out.asks.push({
              scene,
              what: `"${w.text}": a Latin or digit run split into boxes, read right to left`,
            });
            continue;
          }
          // Each piece in the first face of its box that has all its glyphs.
          const pieces = [];
          for (const r of w.runs) {
            let got = null;
            for (const f of drawn.get(r.k) ?? []) {
              const s = await face(f);
              const glyphs = s?.glyphs(r.text);
              if (glyphs) {
                got = { s, glyphs, family: f.familyName };
                break;
              }
            }
            pieces.push(got);
          }
          if (pieces.some((p) => !p)) {
            const names = [
              ...new Set(
                w.runs.flatMap((r) =>
                  (drawn.get(r.k) ?? []).map((f) => f.familyName),
                ),
              ),
            ];
            out.asks.push({
              scene,
              what: `"${w.text}": its face${names.length ? ` (${names.join(", ")})` : ""} did not resolve to a file to shape it in`,
            });
            continue;
          }
          out.checked++;
          const split = pieces.flatMap((p) => p.glyphs).join(" ");
          const whole = pieces[0].s.glyphs(w.text)?.join(" ");
          if (pieces.some((p) => p.s !== pieces[0].s) || split !== whole)
            out.broken.push({ scene, word: w.text, face: pieces[0].family });
        }
      return out;
    },
  };
}
