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

// The layers behind (`back`) and over (`front`) the scenes, and their CSS.
// Over the scenes and under the captions: the page gives the captions the
// higher z-index.
export function texture({ overlays, grain, fieldBlur }) {
  const on = (o) => overlays.includes(o);
  const blob = (cls) => `<i class="${cls}"></i>`;
  return {
    css: `.field { position: absolute; inset: 0; overflow: hidden; }
.field i { position: absolute; border-radius: 50%; filter: blur(${fieldBlur}px); opacity: 0.16; }
.field .a { left: -6%; top: -22%; width: 760px; height: 760px; background: var(--accent); }
.field .b { right: -8%; bottom: -28%; width: 940px; height: 940px; background: var(--rule); }
.field .c { left: 38%; top: 34%; width: 620px; height: 620px; background: var(--line); opacity: 0.5; }
.grain { position: absolute; inset: 0; z-index: 20; opacity: ${grain}; pointer-events: none; }
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
