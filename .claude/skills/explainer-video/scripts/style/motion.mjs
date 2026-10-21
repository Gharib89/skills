// What a reference video's frames measure: how sharp its edges are, how much
// grain its flat areas carry, and the motion summary measure.mjs writes to
// candidates.json from them. Every function reads decoded PPM frames
// (`{ w, h, px }`), so the same sums run on a real video's frames and a test's
// synthetic ones.

// A binary PPM's size and its RGB bytes.
export function decodePpm(buf) {
  const m = buf
    .subarray(0, 64)
    .toString("latin1")
    .match(/^P6\s+(\d+)\s+(\d+)\s+255\s/);
  if (!m) throw new Error("not a binary PPM");
  return { w: +m[1], h: +m[2], px: buf.subarray(m[0].length) };
}

// The luma noise (RMS, 0 to 255) a flat area carries at a grain of 1: film
// grain reads clearly from about a third of it.
export const GRAIN_FULL = 12;
// A 3x3 neighbourhood whose luma range stays under this is a flat area: an
// edge or a texture is not grain.
const FLAT = 32;

const luma = ({ w, h, px }) => {
  const out = new Float32Array(w * h);
  for (let i = 0; i < w * h; i++)
    out[i] = 0.299 * px[i * 3] + 0.587 * px[i * 3 + 1] + 0.114 * px[i * 3 + 2];
  return out;
};

// The 3x3 box mean of a luma plane, its border pixels clamped.
function box(L, w, h) {
  const out = new Float32Array(w * h);
  for (let y = 0; y < h; y++)
    for (let x = 0; x < w; x++) {
      let sum = 0;
      for (let dy = -1; dy <= 1; dy++)
        for (let dx = -1; dx <= 1; dx++)
          sum +=
            L[
              Math.min(h - 1, Math.max(0, y + dy)) * w +
                Math.min(w - 1, Math.max(0, x + dx))
            ];
      out[y * w + x] = sum / 9;
    }
  return out;
}

// The steepest edges a frame holds: the mean of the top 0.5% of the gradient of
// its smoothed luma, so grain does not read as sharpness and a blur lowers it.
export function sharpness(img) {
  const { w, h } = img;
  const S = box(luma(img), w, h);
  const mags = [];
  for (let y = 1; y < h - 1; y++)
    for (let x = 1; x < w - 1; x++)
      mags.push(
        Math.hypot(
          S[y * w + x + 1] - S[y * w + x - 1],
          S[(y + 1) * w + x] - S[(y - 1) * w + x],
        ),
      );
  mags.sort((a, b) => a - b);
  const top = mags.slice(
    Math.min(mags.length - 1, Math.floor(mags.length * 0.995)),
  );
  return top.length ? top.reduce((a, b) => a + b, 0) / top.length : 0;
}

// The grain of a frame: the RMS of each flat pixel's difference from its 3x3
// mean, 0 where the frame has no flat area.
export function noise(img) {
  const { w, h } = img;
  const L = luma(img);
  const M = box(L, w, h);
  let sum = 0;
  let n = 0;
  for (let y = 1; y < h - 1; y++)
    for (let x = 1; x < w - 1; x++) {
      let lo = Infinity;
      let hi = -Infinity;
      for (let dy = -1; dy <= 1; dy++)
        for (let dx = -1; dx <= 1; dx++) {
          const v = L[(y + dy) * w + x + dx];
          lo = Math.min(lo, v);
          hi = Math.max(hi, v);
        }
      if (hi - lo > FLAT) continue;
      sum += (L[y * w + x] - M[y * w + x]) ** 2;
      n++;
    }
  return n ? Math.sqrt(sum / n) : 0;
}

const unit = (v) => Math.min(1, Math.max(0, v));
const round = (v, d) => Math.round(v * 10 ** d) / 10 ** d;

// The motion summary of one video: cuts a minute; the blur at cuts, 0 to 1,
// how much sharper each shot's steady frame is than its frame just before the
// cut that ends it; and the grain, 0 to 1, of the steady frames. `shots` holds
// one `{ before?, steady }` pair of decoded frames per shot measured. A steady
// frame with no edge to blur is left out of the blur.
export function measureMotion({ duration, cuts, shots }) {
  const cutsPerMinute = round((cuts.length / duration) * 60, 1);
  const blurs = shots
    .filter((s) => s.before)
    .map((s) => [sharpness(s.before), sharpness(s.steady)])
    .filter(([, steady]) => steady >= 1)
    .map(([before, steady]) => unit(1 - before / steady));
  const grains = shots.map((s) => noise(s.steady));
  const mean = (a) => (a.length ? a.reduce((x, y) => x + y, 0) / a.length : 0);
  return {
    cutsPerMinute,
    blurAtCuts: round(mean(blurs), 3),
    grain: round(unit(mean(grains) / GRAIN_FULL), 3),
  };
}

// Seconds either side of a cut that its before and after frames sit.
const AROUND = 0.08;
// The most shots measured and cuts kept as reference strips.
const SHOTS = 6;
const STRIPS = 2;
// `max` of `n` indices spread from the first to the last.
const spread = (n, max) =>
  n <= max
    ? [...Array(n).keys()]
    : [...Array(max).keys()].map((i) => Math.round((i * (n - 1)) / (max - 1)));

// The frames to cut from a video: `times`, and indices into it for each shot
// measured (`steady`, its middle, and `before`, the frame just before the cut
// that ends it) and each cut kept as a reference strip (`cut`, its number from
// 1, and the frames `before`, `at` and `after` it). A time stays inside the
// video.
export function planStills({ duration, cuts }) {
  const times = [];
  const at = (t) =>
    times.push(+Math.min(duration - 0.05, Math.max(0, t)).toFixed(3)) - 1;
  const bounds = [0, ...cuts, duration];
  const shots = spread(cuts.length + 1, SHOTS).map((j) => ({
    steady: at((bounds[j] + bounds[j + 1]) / 2),
    ...(j < cuts.length && {
      before: at(Math.max(bounds[j], cuts[j] - AROUND)),
    }),
  }));
  const strips = spread(cuts.length, STRIPS).map((j) => ({
    cut: j + 1,
    before: at(cuts[j] - AROUND),
    at: at(cuts[j]),
    after: at(cuts[j] + AROUND),
  }));
  return { times, shots, strips };
}
