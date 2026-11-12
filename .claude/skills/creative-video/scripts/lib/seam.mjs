// The loop seam of a sound, as the sound stage judges an Openverse bed: the render repeats the file end to start, so a bed is clean only
// where that join is inaudible. Two measures over the file's mono samples:
// the jump from its last sample to its first no larger than its 99th-percentile
// sample-to-sample step (no click), and the last and first SPAN seconds within
// LEVEL dB RMS (no fade the loop would swell or drop at).
export const SPAN = 0.05;
export const LEVEL = 3;

const rms = (a) => Math.sqrt(a.reduce((s, v) => s + v * v, 0) / a.length);

// `{ clean, jump, step, level }`: the join's jump, the 99th-percentile step,
// and the dB between the last and first span's RMS, null where both are silent.
// A file shorter than two spans has no seam to measure and is not clean.
export function seam(samples, rate) {
  const n = Math.round(SPAN * rate);
  if (samples.length < 2 * n || n < 1)
    return { clean: false, jump: null, step: null, level: null };
  const steps = Float32Array.from({ length: samples.length - 1 }, (_, i) =>
    Math.abs(samples[i + 1] - samples[i]),
  ).sort();
  const step = steps[Math.floor(steps.length * 0.99)];
  const jump = Math.abs(samples[0] - samples.at(-1));
  const [head, tail] = [rms(samples.subarray(0, n)), rms(samples.subarray(-n))];
  const level =
    head === 0 && tail === 0 ? null : Math.abs(20 * Math.log10(tail / head));
  return {
    clean: jump <= step && (level === null || level <= LEVEL),
    jump,
    step,
    level,
  };
}
