// The `diagram` component: nodes in columns along the reading direction, the
// links between them drawn as arrows, and packets flowing along a link. The
// composer lays it out from the content box, so the scene file holds no
// coordinates; right to left, the layout mirrors.
import { diagramColumns } from "../lib/diagram.mjs";
import { boxCss, sketchCss, sketched } from "./box.mjs";

// The room between columns (an arrow runs in it) and between a column's nodes,
// and the largest node box.
const GAP = { x: 120, y: 40 };
const MAX = { w: 400, h: 200 };
// A link's arrow stops this far short of each box; opposite links between
// one pair run this far apart, each to its own side.
const CLEAR = 10;
const APART = 14;
// A packet's speed in px a second, and its shortest trip.
const SPEED = 480;
const TRIP = 0.8;
// A link draws in over this long from its cue; its packets leave once drawn.
const DRAW = 0.5;

const r = (n) => +n.toFixed(2);

// The point where the ray from box `b`'s centre along (dx, dy) leaves it.
function edge(b, dx, dy) {
  const t = Math.min(
    dx ? b.w / 2 / Math.abs(dx) : Infinity,
    dy ? b.h / 2 / Math.abs(dy) : Infinity,
  );
  return [b.left + b.w / 2 + t * dx, b.top + b.h / 2 + t * dy];
}

// The diagram in `box` (the content box: its width and height): each node's
// box, `{ left, top, w, h }` from the content box's corner, and each link's
// arrow, the points of one stroke (its head retraced), and the centre to
// centre run its packets take. `rtl` mirrors the layout.
export function diagramLayout(p, box, rtl) {
  const columns = diagramColumns(p);
  const rows = Math.max(...columns.map((c) => c.length));
  const k = columns.length;
  const w = Math.min(MAX.w, Math.floor((box.width - (k - 1) * GAP.x) / k));
  const h = Math.min(
    MAX.h,
    Math.floor((box.height - (rows - 1) * GAP.y) / rows),
  );
  const left0 = Math.round((box.width - k * w - (k - 1) * GAP.x) / 2);
  const nodes = [];
  for (const [c, col] of columns.entries()) {
    const top0 = Math.round(
      (box.height - col.length * h - (col.length - 1) * GAP.y) / 2,
    );
    for (const [j, i] of col.entries()) {
      const left = left0 + c * (w + GAP.x);
      nodes[i] = {
        left: rtl ? box.width - left - w : left,
        top: top0 + j * (h + GAP.y),
        w,
        h,
      };
    }
  }
  const at = new Map(p.nodes.map((n, i) => [n.id, nodes[i]]));
  const links = p.links.map((l) => {
    const a = at.get(l.from);
    const b = at.get(l.to);
    const dx = b.left - a.left + (b.w - a.w) / 2;
    const dy = b.top - a.top + (b.h - a.h) / 2;
    const len = Math.hypot(dx, dy);
    const [ux, uy] = [dx / len, dy / len];
    // to the right of travel, so the reply runs beside the request
    const off = p.links.some((m) => m.from === l.to && m.to === l.from)
      ? APART
      : 0;
    const shift = ([x, y], d = 0) => [
      x - uy * off + ux * d,
      y + ux * off + uy * d,
    ];
    const s = shift(edge(a, ux, uy), CLEAR);
    const e = shift(edge(b, -ux, -uy), -CLEAR);
    const head = (side) => [
      e[0] - ux * 16 + side * uy * 12,
      e[1] - uy * 16 - side * ux * 12,
    ];
    return {
      line: [s, e, head(1), e, head(-1)].map((q) => q.map(r)),
      run: [
        shift([a.left + a.w / 2, a.top + a.h / 2]),
        shift([b.left + b.w / 2, b.top + b.h / 2]),
      ].map((q) => q.map(r)),
    };
  });
  return { nodes, links };
}

// Each node and link rises on its cue, a link's arrow stroked on as it does,
// and each packet runs its link's centre to centre run over and over, under
// the nodes (it leaves its first node and enters the second unseen), from once
// the arrow is drawn to the scene's end: `repeat: -1`, which the composer
// turns into the repeats that reach the scene's end, so a packet's place is a
// function of the timeline's time.
export const diagram = async (p, f, x) => {
  const { nodes, links } = diagramLayout(p, x.box, f.rtl);
  const shapes = await x.sketch([
    ...nodes.map((n, i) => ({ rect: [n.w, n.h], key: `node${i}` })),
    ...links.map((l, i) => ({ line: l.line, key: `link${i}` })),
  ]);
  const stroke = (l, i) =>
    shapes[nodes.length + i]?.stroke ??
    `M${l.line.map((q) => q.join(" ")).join(" L")}`;
  const trips = links.map(({ run: [[x0, y0], [x1, y1]] }) =>
    r(Math.max(TRIP, Math.hypot(x1 - x0, y1 - y0) / SPEED)),
  );
  return {
    html: `<div class="dg"><svg class="links" viewBox="0 0 ${x.box.width} ${x.box.height}" width="${x.box.width}" height="${x.box.height}">${links
      .map(
        (l, i) =>
          `<path class="l${i}" d="${stroke(l, i)}" pathLength="1" stroke-dasharray="1"/>`,
      )
      .join("")}</svg>${p.links
      .map((l, i) =>
        l.packets
          ? `<div class="pks p${i}">${Array.from(
              { length: l.packets },
              (_, j) => `<div class="pk k${i}-${j}"></div>`,
            ).join("")}</div>`
          : "",
      )
      .join("")}${p.nodes
      .map(
        (n, i) =>
          `<div class="node n${i}" style="left: ${nodes[i].left}px; top: ${nodes[i].top}px; width: ${nodes[i].w}px; height: ${nodes[i].h}px;">${sketched(x.surface, { ...nodes[i], ...shapes[i] })}<div class="label">${f.tt(n.label)}</div>${n.note ? `<div class="note">${f.t(n.note)}</div>` : ""}</div>`,
      )
      .join("")}</div>`,
    css: `.dg { position: absolute; inset: 0; }
.links { position: absolute; left: 0; top: 0; overflow: visible; }
.links path { fill: none; stroke: var(--rule); stroke-width: 4; stroke-linecap: round; stroke-linejoin: round; }
.pks { position: absolute; left: 0; top: 0; }
.pk { position: absolute; left: -9px; top: -9px; width: 18px; height: 18px; border-radius: 50%; background: var(--accent); }
.node { position: absolute; ${boxCss(x.surface)} box-sizing: border-box; padding: 20px; display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 8px; text-align: center; }
.label { position: relative; font: ${f.titleWeight} var(--size-body)/${f.lh(1.15, "title")} ${f.title}; color: var(--text); }
.note { position: relative; font: 400 var(--size-small) ${f.note}; color: var(--muted); }
${sketchCss(x.surface)}`,
    reveals: [
      ...p.nodes.map((n, i) => [`.n${i}`, n]),
      ...p.links.map((l, i) => [`.l${i}`, l, "snap"]),
      ...p.links.flatMap((l, i) => (l.packets ? [[`.p${i}`, l, "snap"]] : [])),
    ],
    tweens: [
      ...p.links.map((l, i) => [
        `.l${i}`,
        { strokeDashoffset: 1 },
        { strokeDashoffset: 0, duration: DRAW, ease: "power1.inOut" },
        l,
      ]),
      ...p.links.flatMap((l, i) =>
        Array.from({ length: l.packets ?? 0 }, (_, j) => {
          const [[x0, y0], [x1, y1]] = links[i].run;
          return [
            `.k${i}-${j}`,
            { x: x0, y: y0 },
            {
              x: x1,
              y: y1,
              duration: trips[i],
              ease: "none",
              repeat: -1,
              delay: r(DRAW + (j * trips[i]) / l.packets),
            },
            l,
          ];
        }),
      ),
    ],
  };
};
