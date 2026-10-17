// The `spring` motion: the closed-form response of a damped spring, a pure
// function of the time since a change started. No state steps from frame to
// frame, so HyperFrames seeking to any frame in any order renders the same one.
// `step` and `settleTime` are also written into each scene's script as source
// (compose.mjs), so they stay self-contained: no imports, no outer names but
// each other.

// One rule per class of element: how stiff (omega, rad/s) and how damped
// (zeta), plus the scale a reveal starts from (1 is none). Overshoot is
// exp(-pi * zeta / sqrt(1 - zeta^2)) of the travel.
export const SPRING = {
  // list items, flow arrows, terminal lines: overshoot 0.2 percent
  snap: { zeta: 0.9, omega: 34, scale: 1 },
  // panels, cards, frames, flow nodes: one soft overshoot, 6.8 percent
  settle: { zeta: 0.65, omega: 24, scale: 0.97 },
  // headlines: one visible overshoot, 16 percent, then still
  land: { zeta: 0.5, omega: 20, scale: 0.96 },
};

// A reveal starts from this far below its place.
export const RISE_PX = 20;

// Seconds until the response is within a thousandth of the travel of its
// target, from where on `step` is exactly 1.
export function settleTime(rule) {
  return (
    Math.log(1 / (0.001 * Math.sqrt(1 - rule.zeta * rule.zeta))) /
    (rule.zeta * rule.omega)
  );
}

// The unit step response `tau` seconds after a change: 0 at its start, 1 from
// the settle time on.
export function step(rule, tau) {
  if (tau <= 0) return 0;
  if (tau >= settleTime(rule)) return 1;
  const z = rule.zeta;
  const d = rule.omega * Math.sqrt(1 - z * z);
  return (
    1 -
    Math.exp(-z * rule.omega * tau) *
      (Math.cos(d * tau) + ((z * rule.omega) / d) * Math.sin(d * tau))
  );
}

// A property's value at time t: its start value plus each change's delta
// through its own response, so a change made mid-move continues from where the
// value is, with no jump. `changes` is [[start time, delta]...].
export function springAt(rule, from, changes, t) {
  return changes.reduce(
    (v, [at, delta]) => v + delta * step(rule, t - at),
    from,
  );
}
