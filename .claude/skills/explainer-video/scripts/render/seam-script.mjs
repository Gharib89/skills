// The script lines a scene's timeline plays for its seam and its push-in,
// written into the scene's composition by compose.mjs.

// A seam's two halves on a scene's `.content`, as `[from, to]` tween vars: the
// exit of the outgoing scene, the entry of the incoming one. Blur is left off
// at 0: a filter of any value, even `blur(0px)`, makes the content a backdrop
// root that the glass surface cannot see through.
const blur = (px) => ({ filter: `blur(${px}px)` });
const SEAMS = {
  // Through the frame: the exit grows to 1.2 and blurs, the entry settles in
  // from 0.75.
  "zoom-through": {
    exit: (b, d) => [
      { scale: 1, opacity: 1, ...(b && blur(0)) },
      {
        scale: 1.2,
        opacity: 0,
        ...(b && blur(b)),
        duration: d,
        ease: "power3.in",
      },
    ],
    entry: (b, d) => [
      { scale: 0.75, opacity: 0, ...(b && blur(b)) },
      {
        scale: 1,
        opacity: 1,
        ...(b && blur(0)),
        duration: d,
        ease: "expo.out",
      },
    ],
  },
  // Along the reading direction: `s` is 1 left to right, -1 right to left.
  "cut-the-curve": {
    exit: (b, d, s) => [
      { xPercent: 0, opacity: 1, ...(b && blur(0)) },
      {
        xPercent: -13 * s,
        opacity: 0,
        ...(b && blur(b)),
        duration: d,
        ease: "power2.in",
      },
    ],
    entry: (b, d, s) => [
      { xPercent: 13 * s, opacity: 0, ...(b && blur(b)) },
      {
        xPercent: 0,
        opacity: 1,
        ...(b && blur(0)),
        duration: d,
        ease: "power4.out",
      },
    ],
  },
};

// The script lines that play a scene's push-in on its `.camera`, a layer inside
// `.content` so the seam, which moves `.content`, never fights it: from `at`
// for `duration`, held at `scale` for the rest of the scene. The
// `camera:start`/`camera:end` labels mark the window for the gates. A stills
// page holds the push settled, as the scene stands at its end.
export function pushScript(scope, at, { scale, duration }) {
  if (at === null) return "";
  return `
        tl.fromTo('${scope} .camera', ${JSON.stringify({ scale: 1 })}, ${JSON.stringify({ scale, duration, ease: "power3.out" })}, ${at});
        if (!window.__stills) tl.addLabel("camera:start", ${at}).addLabel("camera:end", ${+(at + duration).toFixed(6)});`;
}

// The script lines that play a scene's seam: its entry over the first
// `seam.in.duration` seconds, its exit from `end`, the scene's own last
// moment, on into the next scene's start. The `seam:start`/`seam:end` labels
// (`seam:start2`/`seam:end2` for the exit when both run) mark the windows for
// the gates. A stills page runs no seam: it holds each scene settled at its
// end.
export function seamScript(scope, seam, end, rtl) {
  const halves = [
    ["entry", seam.in, 0],
    ["exit", seam.out, end],
  ].filter(([, x]) => x);
  if (!halves.length) return "";
  const lines = halves.map(([half, x, at], k) => {
    const [from, to] = SEAMS[x.move][half](x.blur, x.duration, rtl ? -1 : 1);
    // The entry hides the scene from its first frame and clears what it set,
    // the exit leaves the scene whole until it runs and ends it gone.
    const vars =
      half === "entry"
        ? { ...to, clearProps: "all" }
        : { ...to, immediateRender: false };
    const n = k ? k + 1 : "";
    return `          tl.fromTo('${scope} .content', ${JSON.stringify(from)}, ${JSON.stringify(vars)}, ${at});
          tl.addLabel("seam:start${n}", ${at}).addLabel("seam:end${n}", ${+(at + x.duration).toFixed(6)});`;
  });
  return `
        if (!window.__stills) {
${lines.join("\n")}
        }`;
}
