// The layout and contrast verdicts on a composition's sampled frames, shared by
// the gates stage and the style card: HyperFrames' check findings, then the
// house probe's text elements judged against the run's floors (text size,
// overflow, clip, the safe margin, overlap, and contrast by text size), and
// right to left text against its reading rules (below). Each defect is handed
// to `add(gate, time, what)`, `gate` `layout` or `contrast`.
import { H, W } from "../render/compose.mjs";
import { contrast } from "./style.mjs";
import { ARABIC_SCRIPT, isLatin } from "./terms.mjs";

const ISOLATED = ["isolate", "isolate-override", "plaintext"];

// Right to left (with `dir` on the text boxes, never a page root, which judge
// checks per frame): Arabic text reads right to left with no Latin run left in
// it; a Latin run in it is isolated and on one line, so a term keeps its word
// order; and Arabic text's line height is at least the ink Arabic's letters
// span in its face and weight, as the probe measures it once per face and
// weight. Text in a box marked `dir="ltr"` is exempt: a code frame or terminal,
// which reads left to right as written whatever script it holds, and every
// text box of an English run, whose content, header and cues are marked so.
function rtl(e, bad) {
  if (e.within === "ltr") return;
  if (ARABIC_SCRIPT.test(e.text)) {
    if (e.dir !== "rtl") bad(`Arabic reads ${e.dir}`);
    if (/[A-Za-z]/.test(e.text)) bad("Latin run not isolated in");
    if (e.lineH !== null && e.lineH < e.ink)
      bad(`line height ${e.lineH} under the ink ${e.ink} of ${e.face}`);
  } else if (e.within === "rtl" && isLatin(e.text)) {
    if (!ISOLATED.includes(e.bidi)) bad("Latin run not isolated");
    if (e.wrap !== "nowrap") bad("Latin run wraps");
  }
}

export function judge(checked, frames, floor, add) {
  const { textPx, margin } = floor.layout;
  for (const f of checked.layout.findings)
    if (f.severity === "error") add("layout", f.time, `${f.code} "${f.text}"`);
  for (const f of checked.contrast.findings)
    if (f.severity === "error")
      add(
        "contrast",
        f.time,
        `${f.code} "${f.text}" ${f.ratio}:1 under ${f.requiredRatio}:1`,
      );
  const safe = {
    left: margin * W,
    top: margin * H,
    right: W * (1 - margin),
    bottom: H * (1 - margin),
  };
  const outside = (r, c, by) =>
    r.left < c.left - by ||
    r.top < c.top - by ||
    r.right > c.right + by ||
    r.bottom > c.bottom + by;
  const overlap = (a, b) =>
    Math.min(a.right, b.right) - Math.max(a.left, b.left) > 1 &&
    Math.min(a.bottom, b.bottom) - Math.max(a.top, b.top) > 1 &&
    outside(a, b, 0) &&
    outside(b, a, 0);
  for (const { t, elements, rootDir } of frames) {
    // Mid-reveal text is judged once it settles.
    const shown = elements.filter((e) => e.opacity >= 0.99);
    for (const r of rootDir ?? [])
      add("layout", t, `dir on the page root ${r}`);
    shown.forEach((e, i) => {
      const bad = (what) => add("layout", t, `${what} "${e.text}"`);
      if (e.fontPx < textPx - 0.5) bad(`small ${e.fontPx} px`);
      if (
        !e.inline &&
        (e.scrollW > e.clientW + 1 || e.scrollH > e.clientH + e.fontPx / 4)
      )
        bad(`overflow ${e.scrollW}x${e.scrollH} in ${e.clientW}x${e.clientH}`);
      if (e.clip && outside(e.rect, e.clip, 1)) bad("clipped");
      if (outside(e.rect, safe, 0)) bad("outside the safe margin");
      rtl(e, bad);
      for (const o of shown.slice(i + 1))
        if (overlap(e.rect, o.rect))
          add("layout", t, `"${e.text}" overlaps "${o.text}"`);
      const large = e.fontPx >= 24 || (e.fontPx >= 18.66 && e.weight >= 700);
      const need = floor.contrast[large ? "large" : "body"];
      const ratio = contrast(e.color, e.bg);
      if (ratio < need)
        add(
          "contrast",
          t,
          `"${e.text}" ${e.color} on ${e.bg} ${ratio.toFixed(2)}:1 under ${need}:1`,
        );
    });
  }
}
