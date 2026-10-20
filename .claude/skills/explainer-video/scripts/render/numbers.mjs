// The `chart` and `stat` components: numbers that count up on their cues. A
// number is its own element, `.num`, holding the final text in the markup (a
// stills page and a frame page show it settled) while the scene's script
// counts it up. An item is one reading box, `data-line` `c<n>`, its number and
// label. The direction is the page's: the flex row and the line's points start
// at the reading start, so Arabic runs right to left.
import { COUNT_SECONDS, plain } from "../lib/count.mjs";

// A number as its own element, so the scene's script can count its text up; the
// value is digits and separators (the compile stage checks), so it needs no
// escaping. `<bdi>` isolates it right to left.
const num = (v) => `<bdi class="num lat ti">${v}</bdi>`;
// Each item's number counts up on the item's own cue: [selector, written, cue].
const counts = (items) => items.map((x, i) => [`.r${i} .num`, x.value, x]);
// Each number's share of the largest, 0 to 1, whatever digits it is written in.
const share = (items) => {
  const v = items.map((x) => parseFloat(plain(x.value).replaceAll(",", "")));
  const max = Math.max(...v);
  return v.map((x) => (max > 0 ? +(x / max).toFixed(4) : 0));
};

export const chart = (p, f) => {
  const n = p.items.length;
  const unit = p.unit ? `<span class="unit">${f.t(p.unit)}</span>` : "";
  const val = (x) => `<div class="val">${num(x.value)}${unit}</div>`;
  const part = share(p.items);
  const css = `.val { font: ${f.titleWeight} var(--size-title)/1 ${f.title}; color: var(--text); white-space: nowrap; }
.unit { margin-inline-start: 10px; font: 400 var(--size-label) ${f.text}; color: var(--muted); }
.lab { font: 600 var(--size-label) ${f.text}; color: var(--muted); letter-spacing: ${f.ls("0.06em")}; text-transform: uppercase; text-align: center; }`;
  if (p.kind === "bar")
    return {
      html: `<div class="chart">${p.items
        .map(
          (x, i) =>
            `<div class="bar r${i}" data-line="c${i}" style="--p:${part[i]}"><div class="track">${val(x)}<div class="fill"></div></div><div class="lab">${f.t(x.label)}</div></div>`,
        )
        .join("")}</div>`,
      css: `.chart { position: absolute; inset: 0; display: flex; gap: 40px; }
.bar { flex: 1 1 0; min-width: 0; display: flex; flex-direction: column; }
.track { position: relative; flex: 1; min-height: 0; }
.fill { position: absolute; bottom: 0; left: 18%; right: 18%; height: calc(var(--p) * (100% - 96px)); background: var(--accent); border-radius: 14px 14px 0 0; transform-origin: bottom; }
.track .val { position: absolute; left: 0; right: 0; bottom: calc(var(--p) * (100% - 96px) + 14px); text-align: center; }
.bar .lab { margin-top: 22px; }
${css}`,
      reveals: p.items.map((x, i) => [`.r${i}`, x]),
      tweens: p.items.map((x, i) => [
        `.r${i} .fill`,
        { scaleY: 0 },
        { scaleY: 1, duration: COUNT_SECONDS, ease: "power2.out" },
        x,
      ]),
      counts: counts(p.items),
    };
  // A line: each point at its share of the height, a segment drawn in to each
  // point after the first, as that point's item arrives.
  const at = (i) => +((f.rtl ? n - 1 - i : i) * (100 / (n - 1))).toFixed(2);
  const top = (i) => +(100 - part[i] * 100).toFixed(2);
  return {
    html: `<div class="plot"><svg class="lines" viewBox="0 0 100 100" preserveAspectRatio="none">${p.items
      .slice(1)
      .map(
        (_, i) =>
          `<path class="seg s${i + 1}" d="M${at(i)} ${top(i)} L${at(i + 1)} ${top(i + 1)}"/>`,
      )
      .join("")}</svg>${p.items
      .map(
        (x, i) =>
          `<div class="pt r${i}" data-line="c${i}" style="left:${at(i)}%;top:${top(i)}%"><div class="dot"></div>${val(x)}</div><div class="lab r${i}" data-line="c${i}" style="left:${at(i)}%">${f.t(x.label)}</div>`,
      )
      .join("")}</div>`,
    css: `.plot { position: absolute; left: 140px; right: 140px; top: 90px; bottom: 110px; }
.lines { position: absolute; inset: 0; width: 100%; height: 100%; overflow: visible; }
.seg { fill: none; stroke: var(--accent); stroke-width: 6; stroke-linecap: round; vector-effect: non-scaling-stroke; }
.pt { position: absolute; width: 0; height: 0; }
.dot { position: absolute; width: 28px; height: 28px; margin: -14px 0 0 -14px; border-radius: 50%; background: var(--accent); }
.pt .val { position: absolute; bottom: 26px; left: 0; transform: translateX(-50%); }
.plot .lab { position: absolute; top: calc(100% + 30px); width: 280px; margin-left: -140px; }
${css}`,
    reveals: p.items.map((x, i) => [`.r${i}`, x]),
    tweens: p.items
      .slice(1)
      .map((x, i) => [
        `.s${i + 1}`,
        { opacity: 0 },
        { opacity: 1, duration: 0.5, ease: "power1.inOut" },
        x,
      ]),
    counts: counts(p.items),
  };
};

// One to a few big numbers side by side, each over its label.
export const stat = (p, f) => ({
  html: `<div class="stats">${p.items
    .map(
      (x, i) =>
        `<div class="stat r${i}" data-line="c${i}"><div class="snum">${num(x.value)}</div><div class="slabel">${f.t(x.label)}</div></div>`,
    )
    .join("")}</div>`,
  css: `.stats { position: absolute; inset: 0; display: flex; align-items: center; justify-content: center; gap: 96px; }
.stat { min-width: 0; text-align: center; }
.snum { font: ${f.titleWeight} var(--size-display)/1 ${f.title}; color: var(--accent); white-space: nowrap; }
.slabel { margin-top: 28px; font: 400 var(--size-body)/${f.lh(1.3, "text")} ${f.text}; color: var(--muted); }`,
  reveals: p.items.map((x, i) => [`.r${i}`, x]),
  counts: counts(p.items),
});
