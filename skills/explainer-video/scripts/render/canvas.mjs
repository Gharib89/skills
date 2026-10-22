// The `canvas` component: cards on one map and a camera that travels to each in
// turn, landing on its cue, then pulls back to the overview of the whole map.
// The map is the composer's layout, the scene file holds no coordinates. Only
// the card the camera is on is at full strength: the others sit at DIM, which
// the layout gate reads as not yet readable, so the neighbours that spill past
// the frame are never judged. Each travel is a `camera:start`/`camera:end`
// window, so the gates judge a card's text only once the camera settles. The
// map reads in the page's direction, the first card at the reading start.
import { paintStill, sketchCss, sketched } from "./box.mjs";

const CARD = { w: 720, h: 340 };
const GAP = 120;
// The seconds a travel takes, and the least one that is still a move.
const TRAVEL = 0.7;
const LEAST = 0.2;
// The strength of a card the camera is not on.
const DIM = 0.3;
// The overview holds the map this fraction of the content box at the most; the
// time it waits after the last landing, at the most and at the least; and the
// time it leaves to read the whole map before the scene ends.
const FRAME = 0.96;
const WAIT = { most: 1.5, least: 0.4 };
const READ = 1.2;
const EASE = "power3.inOut";

// A card's own fill: still glass, since a backdrop blur under a moving camera
// re-rasters between two renders.
const fill = (surface) =>
  surface === "sketch"
    ? ""
    : `${paintStill(surface)} border: 2px solid var(--line); border-radius: 18px;`;

export const canvas = async (p, f, x) => {
  const n = p.items.length;
  const rows = n <= 3 ? 1 : 2;
  const cols = Math.ceil(n / rows);
  const map = {
    w: cols * CARD.w + (cols - 1) * GAP,
    h: rows * CARD.h + (rows - 1) * GAP,
  };
  const { width: W, height: H } = x.box;
  // Each card's top left on the map, in reading order: a row from the reading
  // start, the columns mirrored right to left.
  const at = p.items.map((_, i) => {
    const col = i % cols;
    return {
      left: (f.rtl ? cols - 1 - col : col) * (CARD.w + GAP),
      top: Math.floor(i / cols) * (CARD.h + GAP),
    };
  });
  const shapes = await x.sketch(
    p.items.map((_, i) => ({ rect: [CARD.w, CARD.h], key: `card${i}` })),
  );
  // The camera frames `centre` (a point of the map) at `scale` in the middle
  // of the content box.
  const frame = ([cx, cy], scale) => ({
    x: +(W / 2 - scale * cx).toFixed(6),
    y: +(H / 2 - scale * cy).toFixed(6),
    scale,
  });
  const visit = (i) =>
    frame([at[i].left + CARD.w / 2, at[i].top + CARD.h / 2], 1);
  const whole = frame(
    [map.w / 2, map.h / 2],
    +Math.min(1, (W * FRAME) / map.w, (H * FRAME) / map.h).toFixed(6),
  );

  // The travels: to each later card, ending on its cue, as long as the time
  // since the last landing allows; then to the overview.
  const cue = p.items.map((it) => +x.time(it).toFixed(6));
  const moves = [];
  let landed = cue[0];
  for (let i = 1; i < n; i++) {
    const start = Math.max(landed, +(cue[i] - TRAVEL).toFixed(6));
    landed = Math.max(cue[i], +(start + LEAST).toFixed(6));
    moves.push({ start, end: landed, to: visit(i), on: i });
  }
  const start = Math.max(
    +(landed + WAIT.least).toFixed(6),
    Math.min(
      +(landed + WAIT.most).toFixed(6),
      +(x.end - TRAVEL - READ).toFixed(6),
    ),
  );
  moves.push({ start, end: +(start + TRAVEL).toFixed(6), to: whole });

  const lines = [
    `tl.set(${JSON.stringify(`${x.scope} .cv`)}, ${JSON.stringify({ ...visit(0), transformOrigin: "0 0" })}, 0);`,
    `tl.fromTo(${JSON.stringify(`${x.scope} .i0`)}, ${JSON.stringify({ opacity: DIM })}, ${JSON.stringify({ opacity: 1, duration: LEAST, ease: "power2.out" })}, ${cue[0]});`,
  ];
  let from = visit(0);
  moves.forEach((m, k) => {
    const d = +(m.end - m.start).toFixed(6);
    const fade = { duration: d, ease: EASE };
    lines.push(
      `tl.fromTo(${JSON.stringify(`${x.scope} .cv`)}, ${JSON.stringify(from)}, ${JSON.stringify({ ...m.to, ...fade, immediateRender: false })}, ${m.start});`,
    );
    // the card the camera lands on comes up as it arrives and the one it
    // leaves goes down; the overview brings every card up
    const level = (i, a, b) =>
      lines.push(
        `tl.fromTo(${JSON.stringify(`${x.scope} .i${i}`)}, ${JSON.stringify({ opacity: a })}, ${JSON.stringify({ opacity: b, ...fade, immediateRender: false })}, ${m.start});`,
      );
    if (m.on === undefined) {
      for (let i = 0; i < n; i++) level(i, i === n - 1 ? 1 : DIM, 1);
    } else {
      level(m.on - 1, 1, DIM);
      level(m.on, DIM, 1);
    }
    const label = k ? k + 1 : "";
    lines.push(
      `if (!window.__stills) tl.addLabel("camera:start${label}", ${m.start}).addLabel("camera:end${label}", ${m.end});`,
    );
    from = m.to;
  });

  return {
    html: `<div class="cvp"><div class="cv" style="width: ${map.w}px; height: ${map.h}px;">${p.items
      .map(
        (it, i) =>
          `<div class="cvi i${i}" style="left: ${at[i].left}px; top: ${at[i].top}px;">${sketched(x.surface, { w: CARD.w, h: CARD.h, ...shapes[i] })}<div class="ct">${f.tt(it.title)}</div><div class="cb">${f.t(it.body)}</div></div>`,
      )
      .join("")}</div></div>`,
    css: `.cvp { position: absolute; inset: 0; overflow: hidden; }
.cv { position: absolute; left: 0; top: 0; transform-origin: 0 0; }
.cvi { position: absolute; box-sizing: border-box; width: ${CARD.w}px; height: ${CARD.h}px; padding: 40px; opacity: ${DIM}; ${fill(x.surface)} text-align: start; }
.ct { position: relative; font: ${f.titleWeight} var(--size-heading)/${f.lh(1.15, "title")} ${f.title}; color: var(--text); }
.cb { position: relative; margin-top: 16px; font: 400 var(--size-body)/${f.lh(1.35, "text")} ${f.text}; color: var(--muted); }
${sketchCss(x.surface)}`,
    reveals: [],
    script: lines.map((l) => `        ${l}`).join("\n"),
  };
};
