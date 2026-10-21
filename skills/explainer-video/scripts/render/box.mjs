// A component box's fill and outline under the profile's surface, shared by
// every component that draws one.
import { GLASS } from "./texture.mjs";

export const esc = (s) =>
  String(s)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");

// A box's fill: glass over the page's colour field, else the panel colour.
export const paint = (surface) =>
  surface === "glass" ? GLASS : "background: var(--panel);";

// A sketch surface draws each box's outline with rough.js, at the box's own
// seed; a flat or glass one draws it in CSS.
export const sketched = (surface, d) =>
  surface === "sketch"
    ? `<svg class="sk" viewBox="0 0 ${d.w} ${d.h}" preserveAspectRatio="none"><path class="f" d="${d.fill}"/><path class="s" d="${d.stroke}"/></svg>`
    : "";
export const sketchCss = (surface) =>
  surface === "sketch"
    ? `.sk { position: absolute; inset: 0; width: 100%; height: 100%; }
.sk .f { fill: var(--panel); }
.sk .s { fill: none; stroke: var(--rule); stroke-width: 2.5; }`
    : "";
export const boxCss = (surface) =>
  surface === "sketch"
    ? "position: relative;"
    : `position: relative; ${paint(surface)} border: 2px solid var(--line); border-radius: 18px;`;
