// The live build: the video's one composition, the files Render draws, made
// into one document the storyboard plays in a frame that may run scripts and
// nothing else (no origin, so no fetch): the scenes' markup inline where
// HyperFrames would mount them, GSAP inline, the fonts apart (the page hands
// them in as bytes), the narration left to the page, and live-frame.js last to
// seek it. `liveScript` is that document as a `.js` asset the page loads by
// <script src>, which works the same from a published page and from `file:`.
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const frameJs = fs.readFileSync(
  path.join(path.dirname(fileURLToPath(import.meta.url)), "live-frame.js"),
  "utf8",
);

// The page's `@font-face` rules as compose.mjs writes them, one per face.
const FACE =
  /@font-face \{ font-family: "([^"]+)"; src: url\("fonts\/([^"]+)"\); font-weight: (\d+); font-style: (\w+); font-display: block; \}\n?/g;
// A scene's host in index.html, which names the file HyperFrames mounts into it.
const HOST =
  /(<div id="scene-[^"]+" class="clip" data-composition-id="([^"]+)") data-composition-src="[^"]*"([^>]*)><\/div>/g;

// Source text placed inside an inline <script>.
const inline = (js) => js.replaceAll("</script", "<\\/script");

export function liveScript(comp) {
  const read = (...p) => fs.readFileSync(path.join(comp, ...p), "utf8");
  const index = read("index.html");
  const fonts = [...index.matchAll(FACE)].map(
    ([, family, file, weight, style]) => ({
      family,
      weight: +weight,
      style,
      data: fs.readFileSync(path.join(comp, "fonts", file)).toString("base64"),
    }),
  );
  const html = index
    .replace(FACE, "")
    .replace(
      '<script src="gsap.min.js"></script>',
      () => `<script>${inline(read("gsap.min.js"))}</script>`,
    )
    .replace(/ *<audio[^>]*><\/audio>\n?/g, "")
    .replace(HOST, (_, open, id, rest) => {
      const inner = read("scenes", `${id}.html`).match(
        /<template[^>]*>([\s\S]*)<\/template>/,
      );
      if (!inner) throw new Error(`scenes/${id}.html holds no <template>`);
      return `${open}${rest}>${inner[1]}</div>`;
    })
    .replace("</body>", () => `<script>${inline(frameJs)}</script>\n  </body>`);
  return `window.__build = ${JSON.stringify({ html, fonts })};\n`;
}
