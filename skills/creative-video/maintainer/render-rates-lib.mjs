// The arithmetic of calibrate-render-rates.mjs, apart from it so a test can read
// it: the render stage reads only the table these numbers end up in.

// The lower median of `xs`.
export const median = (xs) =>
  [...xs].sort((a, b) => a - b)[(xs.length - 1) >> 1];

// The rates from the calibrator's timings of a video of `video` seconds: `cold`
// the seconds of renders with no chapter cached, `cached` the seconds of renders
// with every chapter cached, which pay the audio pass alone. The chapters' cost
// is the cold median less the cached one, and a delta under zero is noise
// between runs, not a render that costs less.
export function ratesFrom({ cold, cached }, video) {
  const audio = median(cached);
  return {
    render: Math.max(0, median(cold) - audio) / video,
    audio: audio / video,
  };
}
