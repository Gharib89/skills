// The `excerpt` component: the cited excerpt's own words on a document surface
// (a code excerpt on a code one), a source line naming its locator, and
// numbered chips beside it for further cited excerpts. On its emphasis cue the
// named sentence (a code excerpt's line) is underlined word by word and the
// rest fall to the muted colour. The text is the pack's, resolved at compile;
// the surface is the profile's tokens, never a real site's look.
import { squash, units } from "../lib/excerpt.mjs";
import { wholeWords } from "../lib/terms.mjs";
import { esc, paint } from "./box.mjs";

// Lighting a sentence takes at most this long, however many words it has.
const LIGHT = 0.6;
const STEP = 0.08;

export const excerpt = (p, f, x) => {
  const { text, locator, code } = p.excerpts[p.cite];
  const all = units(text, code, f.rtl ? "ar" : "en");
  const e = p.emphasis;
  const lit = e ? all.indexOf(code ? e.target : squash(e.target)) : -1;
  const tweens = [];
  const sentence = (u, i) => {
    const words = code ? [u] : wholeWords(u, f.rtl);
    const mark = e ? (i === lit ? " lit" : " dim") : "";
    const inner = words
      .map(
        (w, j) =>
          `<span class="xw${i === lit ? ` lw${j}` : ""}">${code ? esc(w) : f.t(w)}</span>`,
      )
      .join(" ");
    if (i === lit) {
      const room = x.end - x.time(e) - 0.35;
      const step = +Math.max(
        0,
        Math.min(STEP, Math.min(LIGHT, room) / words.length),
      ).toFixed(6);
      for (const j of words.keys())
        tweens.push([
          `.lw${j}`,
          { backgroundSize: "0% 4px" },
          {
            backgroundSize: "100% 4px",
            duration: 0.25,
            ease: "power2.out",
            delay: +(j * step).toFixed(6),
          },
          e,
        ]);
    }
    return code
      ? `<div class="xs xs${i}${mark}">${inner}</div>`
      : `<span class="xs xs${i}${mark}">${inner}</span>`;
  };
  if (e)
    tweens.push([
      ".xs.dim",
      { color: x.colors.text },
      { color: x.colors.muted, duration: 0.35, ease: "power2.out" },
      e,
    ]);
  const chips = (p.chips ?? [])
    .map(
      (c, i) =>
        `<div class="xc xc${i}"><span class="xn">${i + 1}</span><span class="xl" dir="ltr">${esc(p.excerpts[c.cite].locator)}</span></div>`,
    )
    .join("");
  return {
    html: `<div class="xr"><div class="xd${code ? ' xcode" dir="ltr' : ""}"><div class="xsrc" dir="ltr">${esc(locator)}</div><div class="xt">${all.map(sentence).join(code ? "" : " ")}</div></div>${chips ? `<div class="xcs">${chips}</div>` : ""}</div>`,
    css: `.xr { position: absolute; inset: 0; display: flex; align-items: center; gap: 80px; }
.xd { flex: 1; min-width: 0; box-sizing: border-box; ${paint(x.surface)} border: 2px solid var(--line); border-radius: 18px; padding: 40px 56px; text-align: start; }
.xsrc { padding-bottom: 20px; margin-bottom: 28px; border-bottom: 1px solid var(--line); text-align: left; overflow-wrap: anywhere; font: 400 var(--size-label) ${f.code}; color: var(--muted); }
.xt { font: 400 var(--size-body)/${f.lh(1.5, "text")} ${f.text}; color: var(--text); }
.xcode .xt { font: 400 var(--size-code)/1.5 ${f.code}; white-space: pre; }
.xcode .xs { min-height: 1.5em; }
.xw { display: inline; background: linear-gradient(var(--accent), var(--accent)) no-repeat 0 100% / 0% 4px; }
[dir="rtl"] .xs.lit .xw { background-position: 100% 100%; }
.xcs { flex: 0 0 360px; display: flex; flex-direction: column; gap: 24px; }
.xc { display: flex; align-items: center; gap: 20px; box-sizing: border-box; padding: 16px 24px; background: var(--chip); border: 2px solid var(--line); border-radius: 18px; }
.xn { flex: none; width: 48px; height: 48px; display: flex; align-items: center; justify-content: center; border-radius: 50%; background: var(--accent); color: var(--bg); font: 600 var(--size-label) ${f.text}; }
.xl { min-width: 0; text-align: left; overflow-wrap: anywhere; font: 400 var(--size-label) ${f.code}; color: var(--text); }`,
    reveals: [
      [".xd", 1],
      ...(p.chips ?? []).map((c, i) => [`.xc${i}`, c, "snap"]),
    ],
    tweens,
  };
};
