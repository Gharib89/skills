// The `canvas` seams family's map: the whole video on one canvas, each scene at
// its own place and the page's camera travelling from one to the next. The
// scenes keep their starts: the camera sets off at the next scene's start and
// the outgoing scene stays mounted over the travel, exactly as a seam runs.
// compose.mjs mounts the scenes in a `#world` layer at these places and plays
// the travels on the page's timeline.

// Scenes along a row of this many, the next row back the way it came, so a
// scene's neighbour in the video is its neighbour on the map.
const COLUMNS = 4;
// The room left between two scenes, so the travel crosses open canvas.
const GAP = { x: 480, y: 270 };
const EASE = "power3.inOut";

// Each of `n` scenes' top left on the map, `size` the frame's `{ width,
// height }`: the first at the origin, in reading order, mirrored right to left.
export function places(n, size, rtl) {
  return Array.from({ length: n }, (_, i) => {
    const row = Math.floor(i / COLUMNS);
    const col = row % 2 ? COLUMNS - 1 - (i % COLUMNS) : i % COLUMNS;
    return {
      left: (rtl ? -col : col) * (size.width + GAP.x),
      top: row * (size.height + GAP.y),
    };
  });
}

// The script lines that play the camera's travels on the page's timeline `tl`:
// to each later scene's place from its start, over the time the scene before it
// stays mounted past its own end (`slot` less `duration`), a jump where there is
// none. The world moves against the camera, so a scene's place comes to the
// frame's origin.
export function travels(scenes, at) {
  return scenes
    .slice(1)
    .map((s, k) => {
      const from = at[k];
      const to = at[k + 1];
      const run = +(scenes[k].slot - scenes[k].duration).toFixed(6);
      const start = { x: -from.left, y: -from.top };
      const end = { x: -to.left, y: -to.top };
      return run > 0
        ? `tl.fromTo("#world", ${JSON.stringify(start)}, ${JSON.stringify({ ...end, duration: run, ease: EASE, immediateRender: false })}, ${s.start});`
        : `tl.set("#world", ${JSON.stringify(end)}, ${s.start});`;
    })
    .join("\n        ");
}
