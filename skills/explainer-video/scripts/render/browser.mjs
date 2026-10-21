// The `browser` component: a generic page in a window, its elements stacked at
// the reading start, and a cursor that plays the scripted actions on the
// scene's paused timeline. Everything is drawn from the profile's tokens, never
// a real product's look. The page runs in the scene's direction and its URL
// stays left to right.
import { COLUMN, KINDS, PAGE } from "../lib/browser.mjs";
import { wholeWords } from "../lib/terms.mjs";
import { esc, paint } from "./box.mjs";

// A cursor move takes this long and a click rings out for CLICK; typed text
// follows the move, a whole word every STEP.
const MOVE = 0.7;
const CLICK = 0.5;
const STEP = 0.25;
// A button is a button's width, not the column's.
const WIDTH = { button: 360 };

const r = (n) => +n.toFixed(2);

// Each element's box in the window, `{ left, top, w, h }`, stacked under the bar
// and standing at the reading start, which mirrors right to left.
export function pageLayout(elements, rtl) {
  let top = PAGE.bar + PAGE.pad;
  return elements.map((e) => {
    const w = WIDTH[e.kind] ?? COLUMN.width;
    const box = {
      left: rtl ? PAGE.width - COLUMN.inset - w : COLUMN.inset,
      top,
      w,
      h: KINDS[e.kind],
    };
    top += box.h + PAGE.gap;
    return box;
  });
}

const CLASS = {
  heading: "heading",
  text: "txt",
  button: "btn",
  field: "fld",
  link: "lnk",
};

export const browser = (p, f, x) => {
  const boxes = pageLayout(p.elements, f.rtl);
  const at = new Map(p.elements.map((e, i) => [e.id, i]));
  // The cursor comes in from the reading end, low in the window, and each move
  // runs from where the last left it, in px from that start.
  const start = [f.rtl ? 140 : PAGE.width - 140, PAGE.height - 90];
  const centre = ({ left, top, w, h }) => [left + w / 2, top + h / 2];
  const rel = ([cx, cy]) => ({ x: r(cx - start[0]), y: r(cy - start[1]) });
  const tweens = [];
  const typed = new Map();
  let word = 0;
  let from = rel(start);
  for (const [i, a] of p.actions.entries()) {
    const box = boxes[at.get(a.target)];
    const to = rel(centre(box));
    // The timeline alone moves the cursor, and a later move must not repaint
    // an earlier one's from state, so none renders its from at build.
    tweens.push([
      ".cur",
      from,
      { ...to, duration: MOVE, ease: "power2.inOut", immediateRender: false },
      a,
    ]);
    from = to;
    if (a.act === "click")
      tweens.push([
        `.rp${i}`,
        { scale: 0.3, opacity: 0.9 },
        {
          scale: 2.4,
          opacity: 0,
          duration: CLICK,
          ease: "power2.out",
          delay: MOVE,
          immediateRender: false,
        },
        a,
      ]);
    if (a.act === "type") {
      const e = at.get(a.target);
      // The field's own label gives way once, as the first words arrive.
      if (!typed.has(e))
        tweens.push([
          `.ph${e}`,
          { opacity: 1 },
          { opacity: 0, duration: 0.2, delay: MOVE },
          a,
        ]);
      const words = wholeWords(a.text, f.rtl).map((w) => ({ k: word++, w }));
      typed.set(e, [...(typed.get(e) ?? []), ...words]);
      for (const [j, { k }] of words.entries())
        tweens.push([
          `.tw${k}`,
          { opacity: 0 },
          {
            opacity: 1,
            duration: 0.2,
            ease: "power2.out",
            delay: r(MOVE + j * STEP),
          },
          a,
        ]);
    }
  }
  const el = (e, i) => {
    const { left, top, w, h } = boxes[i];
    const inner =
      e.kind === "field"
        ? `<span class="ph ph${i}">${f.t(e.text)}</span><span class="ty">${(
            typed.get(i) ?? []
          )
            .map(({ k, w }) => `<span class="tw tw${k}">${f.t(w)}</span>`)
            .join("")}</span>`
        : f.tt(e.text);
    return `<div class="el e${i} ${CLASS[e.kind]}" style="left: ${left}px; top: ${top}px; width: ${w}px; height: ${h}px;">${inner}</div>`;
  };
  const ripples = p.actions
    .map((a, i) => [a, i])
    .filter(([a]) => a.act === "click")
    .map(([a, i]) => {
      const [cx, cy] = centre(boxes[at.get(a.target)]);
      return `<div class="rp rp${i}" style="left: ${r(cx)}px; top: ${r(cy)}px;"></div>`;
    });
  return {
    html: `<div class="bw"><div class="bbar"><div class="bdot"></div><div class="bdot"></div><div class="bdot"></div><div class="btab">${f.tt(p.title)}</div><div class="url" dir="ltr">${esc(p.url)}</div></div>${p.elements.map(el).join("")}${ripples.join("")}<svg class="cur" viewBox="0 0 28 28" width="28" height="28"><path d="M2 2 L2 24 L8 18 L13 27 L17 25 L12 16 L21 16 Z"/></svg></div>`,
    css: `.bw { position: absolute; left: ${(x.box.width - PAGE.width) / 2}px; top: ${(x.box.height - PAGE.height) / 2}px; width: ${PAGE.width}px; height: ${PAGE.height}px; box-sizing: border-box; overflow: hidden; ${paint(x.surface)} border: 2px solid var(--line); border-radius: 18px; }
.bbar { position: absolute; left: 0; right: 0; top: 0; height: ${PAGE.bar}px; box-sizing: border-box; display: flex; align-items: center; gap: 20px; padding: 0 28px; border-bottom: 2px solid var(--line); }
.bdot { flex: none; width: 14px; height: 14px; border-radius: 50%; background: var(--line); }
.btab { flex: none; font: 600 var(--size-label) ${f.text}; color: var(--text); white-space: nowrap; }
.url { flex: 1; min-width: 0; box-sizing: border-box; text-align: left; white-space: nowrap; overflow: hidden; padding: 6px 24px; font: 400 var(--size-label) ${f.code}; color: var(--muted); background: var(--bg); border: 2px solid var(--line); border-radius: 999px; }
.el { position: absolute; box-sizing: border-box; display: flex; align-items: center; text-align: start; }
.heading { font: ${f.titleWeight} var(--size-title)/${f.lh(1.1, "title")} ${f.title}; color: var(--text); }
.txt { font: 400 var(--size-body)/${f.lh(1.3, "text")} ${f.text}; color: var(--muted); }
.btn { justify-content: center; font: 600 var(--size-body) ${f.text}; color: var(--bg); background: var(--accent); border-radius: 14px; }
.lnk { font: 600 var(--size-body) ${f.text}; color: var(--accent); text-decoration: underline; }
.fld { padding: 0 24px; font: 400 var(--size-body) ${f.text}; color: var(--text); background: var(--bg); border: 2px solid var(--line); border-radius: 12px; }
.ph { position: absolute; inset-inline-start: 24px; color: var(--faint); }
.ty { display: flex; gap: 0.3em; }
.tw { opacity: 0; }
.rp { position: absolute; box-sizing: border-box; width: 48px; height: 48px; margin: -24px 0 0 -24px; border: 4px solid var(--accent); border-radius: 50%; opacity: 0; }
.cur { position: absolute; left: ${start[0]}px; top: ${start[1]}px; }
.cur path { fill: var(--text); stroke: var(--bg); stroke-width: 2; stroke-linejoin: round; }`,
    reveals: [],
    tweens,
  };
};
