// The `timeline` and `compare` components: items in reading order, each
// revealed on its own cue. The direction is the page's: each flex row starts at
// the reading start, so in Arabic the first event and the first side sit at
// the right.
import { boxCss, sketchCss, sketched } from "./box.mjs";

// Events along an axis that draws in from the reading start as the scene
// opens, each its `when` over a dot on the axis, then its label and note. A
// `when` is display text: escaped, never parsed.
export const timeline = (p, f) => ({
  html: `<div class="tl"><div class="events"><div class="axis"></div>${p.items
    .map(
      (x, i) =>
        `<div class="ev r${i}"><div class="wbox"><div class="when">${f.tt(x.when)}</div></div><div class="dot"></div><div class="lab">${f.t(x.label)}</div>${x.note ? `<div class="note">${f.t(x.note)}</div>` : ""}</div>`,
    )
    .join("")}</div></div>`,
  css: `.tl { position: absolute; inset: 0; display: flex; align-items: center; }
.events { position: relative; display: flex; width: 100%; }
.axis { position: absolute; left: 0; right: 0; top: 124px; height: 4px; background: var(--rule); transform-origin: left center; }
[dir="rtl"] .axis { transform-origin: right center; }
.ev { position: relative; flex: 1 1 0; min-width: 0; display: flex; flex-direction: column; align-items: center; text-align: center; padding: 0 20px; }
.wbox { height: 96px; display: flex; align-items: flex-end; }
.when { font: ${f.titleWeight} var(--size-heading)/${f.lh(1.1, "title")} ${f.title}; color: var(--accent); }
.dot { flex: none; width: 32px; height: 32px; margin-top: 14px; border-radius: 50%; background: var(--accent); }
.lab { margin-top: 26px; font: 600 var(--size-body)/${f.lh(1.25, "text")} ${f.text}; color: var(--text); }
.note { margin-top: 12px; font: 400 var(--size-small) ${f.note}; color: var(--muted); }`,
  reveals: p.items.map((x, i) => [`.r${i}`, x]),
  tweens: [
    [
      ".axis",
      { scaleX: 0 },
      { scaleX: 1, duration: 0.6, ease: "power2.inOut" },
      1,
    ],
  ],
});

// Two boxes side by side, each its title over its items. The boxes frame the
// scene from its start; a side's title arrives with its first item, and each
// item on its own cue (compile holds every item to cue no earlier than the
// first). Title and items reveal as siblings, so no reveal moves inside
// another's.
export const compare = async (p, f, x) => {
  const box = { w: 800, h: 560 };
  const shapes = await x.sketch(
    p.sides.map((_, i) => ({ rect: [box.w, box.h], key: `side${i}` })),
  );
  return {
    html: `<div class="cmp">${p.sides
      .map(
        (s, i) =>
          `<div class="side s${i}">${sketched(x.surface, { ...box, ...shapes[i] })}<div class="stitle">${f.tt(s.title)}</div><div class="sitems">${s.items
            .map((it, j) => `<div class="ci i${j}">${f.t(it.text)}</div>`)
            .join("")}</div></div>`,
      )
      .join("")}</div>`,
    css: `.cmp { position: absolute; inset: 0; display: flex; align-items: center; gap: 80px; }
.side { ${boxCss(x.surface)} box-sizing: border-box; width: ${box.w}px; height: ${box.h}px; padding: 48px; text-align: start; }
.stitle { position: relative; font: ${f.titleWeight} var(--size-title)/${f.lh(1.15, "title")} ${f.title}; color: var(--text); }
.sitems { position: relative; margin-top: 32px; display: flex; flex-direction: column; gap: 22px; }
.ci { position: relative; padding-inline-start: 36px; font: 400 var(--size-body)/${f.lh(1.35, "text")} ${f.text}; color: var(--text); }
.ci::before { content: ""; position: absolute; inset-inline-start: 0; top: calc(${f.lh(1.35, "text") / 2}em - 7px); width: 14px; height: 14px; border-radius: 50%; background: var(--accent); }
${sketchCss(x.surface)}`,
    reveals: p.sides.flatMap((s, i) => [
      [`.s${i} .stitle`, s.items[0]],
      ...s.items.map((it, j) => [`.s${i} .i${j}`, it]),
    ]),
  };
};
