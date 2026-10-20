// The texture a page draws around its scenes, as the profile's grammar names
// it: a blurred colour field behind them, and grain and a vignette over them.
// Every layer is static (the grain's noise has a fixed seed), so a frame
// renders the same whenever HyperFrames seeks to it. The glass surface and the
// depth blur are the scenes' own (components.mjs, compose.mjs).

// The glass a box is drawn in: the panel colour half see-through over the
// field, blurred behind it.
export const GLASS =
  "background: color-mix(in srgb, var(--panel) 62%, transparent); backdrop-filter: blur(26px) saturate(1.15);";

const GRAIN_SEED = 7;

// erf by Abramowitz and Stegun 7.1.26, within 1.5e-7.
const erf = (x) => {
  const t = 1 / (1 + 0.3275911 * Math.abs(x));
  const poly =
    t *
    (0.254829592 +
      t *
        (-0.284496736 +
          t * (1.421413741 + t * (-1.453152027 + t * 1.061405429))));
  return Math.sign(x) * (1 - poly * Math.exp(-x * x));
};

// The share of a disc of radius r that a Gaussian blur of deviation s (a CSS
// blur radius) leaves at d from its centre: along x, the blur of the share of
// each chord it keeps, by Simpson's rule.
const blurred = (r, s, d) => {
  const n = 200;
  const h = (2 * r) / n;
  let sum = 0;
  for (let k = 0; k <= n; k++) {
    const x = -r + k * h;
    const chord = erf(Math.sqrt(Math.max(0, r * r - x * x)) / (s * Math.SQRT2));
    sum +=
      (k % n ? 2 + (k % 2) * 2 : 1) *
      Math.exp(-((d - x) ** 2) / (2 * s * s)) *
      chord;
  }
  return (sum * h) / 3 / (s * Math.sqrt(2 * Math.PI));
};

// A disc of radius r in color, blurred at s, as a radial gradient: stops from
// three blurs inside its edge to three past it, where the blur has spent itself.
const STOPS = 32;
const disc = (r, s, color) => {
  if (!s)
    return `radial-gradient(circle ${r}px, ${color} ${r}px, transparent ${r}px)`;
  const [from, to] = [Math.max(0, r - 3 * s), r + 3 * s];
  const at = [
    ...(from ? [0] : []),
    ...Array.from(
      { length: STOPS + 1 },
      (_, k) => from + ((to - from) * k) / STOPS,
    ),
  ];
  const stops = at.map(
    (d) =>
      `color-mix(in srgb, ${color} ${(100 * blurred(r, s, d)).toFixed(2)}%, transparent) ${+d.toFixed(2)}px`,
  );
  return `radial-gradient(circle ${to}px, ${stops.join(", ")})`;
};

// The layers behind (`back`) and over (`front`) the scenes, and their CSS.
// Over the scenes and under the captions: the page gives the captions the
// higher z-index.
export function texture({ overlays, grain, fieldBlur }) {
  const on = (o) => overlays.includes(o);
  const blob = (cls) => `<i class="${cls}"></i>`;
  // The field's blur is drawn as gradients, not a `filter: blur`: Chrome
  // re-rasters a filter inside each frame's damage rect only, and those pixels
  // depend on which rects were redrawn before, so two renders of one
  // composition differed under load (#905). A gradient's pixel depends on its
  // position alone. The box grows three blurs a side to hold the spread.
  const spread = 3 * fieldBlur;
  return {
    css: `.field { position: absolute; inset: 0; overflow: hidden; }
.field i { position: absolute; margin: -${spread}px; padding: ${spread}px; opacity: 0.16; }
.field .a { left: -6%; top: -22%; width: 760px; height: 760px; background: ${disc(380, fieldBlur, "var(--accent)")}; }
.field .b { right: -8%; bottom: -28%; width: 940px; height: 940px; background: ${disc(470, fieldBlur, "var(--rule)")}; }
.field .c { left: 38%; top: 34%; width: 620px; height: 620px; background: ${disc(310, fieldBlur, "var(--line)")}; opacity: 0.5; }
.grain { position: absolute; inset: 0; width: 100%; height: 100%; z-index: 20; opacity: ${grain}; pointer-events: none; }
.vignette { position: absolute; inset: 0; z-index: 20; pointer-events: none; background: radial-gradient(ellipse at center, transparent 58%, color-mix(in srgb, var(--text) 16%, transparent) 100%); }`,
    back: on("field")
      ? `      <div class="field">${["a", "b", "c"].map(blob).join("")}</div>\n`
      : "",
    front: [
      on("grain")
        ? `      <svg class="grain"><filter id="grain" x="0" y="0" width="100%" height="100%"><feTurbulence type="fractalNoise" baseFrequency="0.8" numOctaves="2" seed="${GRAIN_SEED}" stitchTiles="stitch"/><feColorMatrix type="saturate" values="0"/></filter><rect width="100%" height="100%" filter="url(#grain)"/></svg>\n`
        : "",
      on("vignette") ? `      <div class="vignette"></div>\n` : "",
    ].join(""),
  };
}
