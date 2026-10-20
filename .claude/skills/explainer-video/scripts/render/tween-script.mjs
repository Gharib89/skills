// The lines of a scene's script that put its tweens and its counts on the
// scene's paused timeline, and the rise a reveal plays.
import { countText, plain } from "../lib/count.mjs";
import { RISE_PX, SPRING, settleTime, step } from "../lib/spring.mjs";

export const RISE = [
  { opacity: 0, y: RISE_PX },
  { opacity: 1, y: 0, duration: 0.35, ease: "power2.out" },
];

// The script lines that play a scene's tweens on its timeline. A tween naming a
// spring class evaluates `SPRING[class]` (written into the script with the
// functions that read it) in place of a GSAP ease: opacity rises on its own
// ease, never past 1, and position and scale follow the spring.
export const play = (scope, tweens) =>
  tweens.some((x) => x[4])
    ? `        const SPRING = ${JSON.stringify(SPRING)};
        ${settleTime}
        ${step}
        for (const [sel, from, to, t, cls] of tweens) {
          if (!cls) {
            tl.fromTo('${scope} ' + sel, from, to, t);
            continue;
          }
          const { opacity: o0, ...move } = from;
          const { opacity: o1, duration, ...end } = to;
          tl.fromTo('${scope} ' + sel, { opacity: o0 }, { opacity: o1, duration: ${RISE[1].duration}, ease: "${RISE[1].ease}" }, t);
          tl.fromTo('${scope} ' + sel, move, { ...end, duration, ease: (p) => p >= 1 ? 1 : step(SPRING[cls], p * duration) }, t);
        }`
    : `        for (const [sel, from, to, t] of tweens)
          tl.fromTo('${scope} ' + sel, from, to, t);`;

// The script lines that count a scene's numbers up, `[selector, written, time]`
// each: a tween of the element's text from 0 to 1 whose modifier turns the
// progress into text, so the text is a function of the timeline's time alone.
// `countText` is written into the script as source.
export const countScript = (scope, counts) =>
  counts.length
    ? `
        const counts = ${JSON.stringify(counts)};
        ${plain}
        ${countText}
        for (const [sel, written, t, d] of counts)
          tl.fromTo('${scope} ' + sel, { textContent: 0 }, { textContent: 1, duration: d, ease: "power2.out", modifiers: { textContent: (p) => countText(written, p) } }, t);`
    : "";
